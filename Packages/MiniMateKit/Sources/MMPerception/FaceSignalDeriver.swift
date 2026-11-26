import Foundation

/// 从 52 路 ARKit 原始面部系数推导语义信号（D5 公式 + 1€ 平滑 + 阈值滞回 + 最短持续时间）。
public struct FaceSignalDeriver: Sendable, Equatable {
    public struct ThresholdConfig: Sendable, Equatable {
        public var enter: Float
        public var exit: Float
        public var minDuration: TimeInterval

        public init(enter: Float, exit: Float, minDuration: TimeInterval) {
            let clampedEnter = FaceSignalDeriver.clampFinite(enter, min: 0.01, max: 1.0, fallback: 0.5)
            self.enter = clampedEnter
            self.exit = FaceSignalDeriver.clampFinite(exit, min: 0.0, max: clampedEnter, fallback: clampedEnter * 0.6)
            self.minDuration = FaceSignalDeriver.clampFinite(minDuration, min: 0.0, max: 60.0, fallback: 0.3)
        }
    }

    public struct Config: Sendable, Equatable {
        public var smile: ThresholdConfig
        public var frown: ThresholdConfig
        public var surprise: ThresholdConfig
        public var filterMinCutoff: Double
        public var filterBeta: Double
        public var filterDCutoff: Double

        public init(
            smile: ThresholdConfig = ThresholdConfig(enter: 0.50, exit: 0.30, minDuration: 0.40),
            frown: ThresholdConfig = ThresholdConfig(enter: 0.38, exit: 0.22, minDuration: 0.50),
            surprise: ThresholdConfig = ThresholdConfig(enter: 0.38, exit: 0.22, minDuration: 0.30),
            filterMinCutoff: Double = 1.5,
            filterBeta: Double = 0.5,
            filterDCutoff: Double = 1.0
        ) {
            self.smile = smile
            self.frown = frown
            self.surprise = surprise
            self.filterMinCutoff = filterMinCutoff
            self.filterBeta = filterBeta
            self.filterDCutoff = filterDCutoff
        }

        public static let defaults = Config()
    }

    public let config: Config
    public private(set) var lastSignals: FaceSignals = FaceSignals()

    private var smileFilter: OneEuroFilter
    private var frownFilter: OneEuroFilter
    private var surpriseFilter: OneEuroFilter

    private var smileCandidateStartedAt: TimeInterval?
    private var frownCandidateStartedAt: TimeInterval?
    private var surpriseCandidateStartedAt: TimeInterval?
    private var activeExpression: UserExpression?

    public init(config: Config = .defaults) {
        self.config = config
        self.smileFilter = OneEuroFilter(
            minCutoff: config.filterMinCutoff,
            beta: config.filterBeta,
            dCutoff: config.filterDCutoff
        )
        self.frownFilter = OneEuroFilter(
            minCutoff: config.filterMinCutoff,
            beta: config.filterBeta,
            dCutoff: config.filterDCutoff
        )
        self.surpriseFilter = OneEuroFilter(
            minCutoff: config.filterMinCutoff,
            beta: config.filterBeta,
            dCutoff: config.filterDCutoff
        )
    }

    /// 纯公式计算（不含平滑与滞回），严格遵循 research.md D5：
    /// - smile    = (mouthSmileLeft + mouthSmileRight) / 2
    /// - frown    = max(browDownLeft, browDownRight) * 0.6 + (mouthFrownLeft + mouthFrownRight) / 2 * 0.4
    /// - surprise = browInnerUp * 0.5 + jawOpen * 0.3 + (eyeWideLeft + eyeWideRight) / 2 * 0.2
    /// 缺失键按 0 处理，非有限值按 0 处理，每个输入系数先夹紧至 [0, 1]。
    public static func rawSignals(from blendShapes: [String: Float]) -> (smile: Float, frown: Float, surprise: Float) {
        func value(_ canonicalKey: String, legacyKey: String? = nil) -> Float {
            let raw = blendShapes[canonicalKey] ?? legacyKey.flatMap { blendShapes[$0] }
            guard let raw, raw.isFinite else { return 0 }
            return min(max(raw, 0), 1)
        }

        let smile = (
            value("mouthSmileLeft", legacyKey: "mouthSmile_L")
            + value("mouthSmileRight", legacyKey: "mouthSmile_R")
        ) * 0.5
        let frown = max(
            value("browDownLeft", legacyKey: "browDown_L"),
            value("browDownRight", legacyKey: "browDown_R")
        ) * 0.6 + ((
            value("mouthFrownLeft", legacyKey: "mouthFrown_L")
            + value("mouthFrownRight", legacyKey: "mouthFrown_R")
        ) * 0.5) * 0.4
        let surprise = value("browInnerUp") * 0.5
            + value("jawOpen") * 0.3
            + ((
                value("eyeWideLeft", legacyKey: "eyeWide_L")
                + value("eyeWideRight", legacyKey: "eyeWide_R")
            ) * 0.5) * 0.2

        return (
            smile: min(max(smile, 0), 1),
            frown: min(max(frown, 0), 1),
            surprise: min(max(surprise, 0), 1)
        )
    }

    /// 输入单帧原始系数与时间戳（秒），执行 1€ 平滑 + 滞回 + 最短持续判定。
    public mutating func update(blendShapes: [String: Float], at timestamp: TimeInterval) -> FaceSignals {
        guard timestamp.isFinite else {
            return lastSignals
        }

        let raw = Self.rawSignals(from: blendShapes)
        let smile = Self.clamp01(Float(smileFilter.filter(Double(raw.smile), at: timestamp)))
        let frown = Self.clamp01(Float(frownFilter.filter(Double(raw.frown), at: timestamp)))
        let surprise = Self.clamp01(Float(surpriseFilter.filter(Double(raw.surprise), at: timestamp)))

        let smileQualified = updateCandidate(
            value: smile,
            threshold: config.smile,
            startedAt: &smileCandidateStartedAt,
            at: timestamp
        )
        let frownQualified = updateCandidate(
            value: frown,
            threshold: config.frown,
            startedAt: &frownCandidateStartedAt,
            at: timestamp
        )
        let surpriseQualified = updateCandidate(
            value: surprise,
            threshold: config.surprise,
            startedAt: &surpriseCandidateStartedAt,
            at: timestamp
        )

        func signalValue(for expr: UserExpression) -> Float {
            switch expr {
            case .smiling: smile
            case .frowning: frown
            case .surprised: surprise
            }
        }

        func thresholdConfig(for expr: UserExpression) -> ThresholdConfig {
            switch expr {
            case .smiling: config.smile
            case .frowning: config.frown
            case .surprised: config.surprise
            }
        }

        func isQualified(_ expr: UserExpression) -> Bool {
            switch expr {
            case .smiling: smileQualified
            case .frowning: frownQualified
            case .surprised: surpriseQualified
            }
        }

        // 1. 若当前激活表情跌破退出阈值，退出激活
        if let current = activeExpression,
           signalValue(for: current) < thresholdConfig(for: current).exit
        {
            activeExpression = nil
        }

        // 固定优先级（超出进入阈值余量相等时）：.surprised > .frowning > .smiling
        let priorityOrder: [UserExpression] = [.surprised, .frowning, .smiling]

        // 2. 若当前无激活表情，从全部 qualified 中选择余量 (value - enter) 最大者
        if activeExpression == nil {
            activeExpression = selectBestQualified(
                from: priorityOrder,
                isQualified: isQualified,
                valueOf: signalValue,
                thresholdOf: thresholdConfig
            )
        } else if let current = activeExpression,
                  signalValue(for: current) < thresholdConfig(for: current).enter
        {
            // 3. 当前处于滞回维持带 [exit, enter)，允许其他更强的已达标表情接管
            let currentValue = signalValue(for: current)
            let contenders = priorityOrder.filter { expr in
                expr != current && isQualified(expr) && signalValue(for: expr) > currentValue
            }
            if let takeover = selectBestQualified(
                from: contenders,
                isQualified: isQualified,
                valueOf: signalValue,
                thresholdOf: thresholdConfig
            ) {
                activeExpression = takeover
            }
        }

        let signals = FaceSignals(
            smile: smile,
            frown: frown,
            surprise: surprise,
            activeExpression: activeExpression
        )
        lastSignals = signals
        return signals
    }

    /// 重置滤波器、候选计时器与当前 activeExpression。
    public mutating func reset() {
        smileFilter.reset()
        frownFilter.reset()
        surpriseFilter.reset()
        smileCandidateStartedAt = nil
        frownCandidateStartedAt = nil
        surpriseCandidateStartedAt = nil
        activeExpression = nil
        lastSignals = FaceSignals()
    }

    private func updateCandidate(
        value: Float,
        threshold: ThresholdConfig,
        startedAt: inout TimeInterval?,
        at timestamp: TimeInterval
    ) -> Bool {
        if value >= threshold.enter {
            if let started = startedAt, timestamp >= started {
                return (timestamp - started) + 1e-9 >= threshold.minDuration
            } else {
                startedAt = timestamp
                return threshold.minDuration <= 1e-9
            }
        } else {
            startedAt = nil
            return false
        }
    }

    private func selectBestQualified(
        from candidates: [UserExpression],
        isQualified: (UserExpression) -> Bool,
        valueOf: (UserExpression) -> Float,
        thresholdOf: (UserExpression) -> ThresholdConfig
    ) -> UserExpression? {
        var best: UserExpression?
        var bestMargin: Float = -.infinity
        for expr in candidates where isQualified(expr) {
            let margin = valueOf(expr) - thresholdOf(expr).enter
            if best == nil || margin > bestMargin {
                best = expr
                bestMargin = margin
            }
        }
        return best
    }

    private static func clamp01(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func clampFinite(_ value: Float, min lower: Float, max upper: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, lower), upper)
    }

    private static func clampFinite(_ value: Double, min lower: Double, max upper: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, lower), upper)
    }
}
