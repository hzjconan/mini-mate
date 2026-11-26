import Foundation

/// Vision 21 个手部关节点的平台无关枚举标识。
public enum HandJointName: String, CaseIterable, Codable, Sendable, Hashable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

/// Vision 归一化坐标系中的单个关节点：x ∈ [0, 1]（左→右），y ∈ [0, 1]（下→上）。
public struct HandJointPoint: Codable, Sendable, Equatable {
    public let x: Float
    public let y: Float
    public let confidence: Float

    public init(x: Float, y: Float, confidence: Float = 1.0) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

/// 单只手的关节点快照。
public struct HandPoseFrame: Codable, Sendable, Equatable {
    public let joints: [HandJointName: HandJointPoint]

    public init(joints: [HandJointName: HandJointPoint]) {
        self.joints = joints
    }
}

/// 纯逻辑规则手势分类器（支持挥手、双手/单手比心、竖大拇指；尺度无关；严格边沿触发 P-3）。
public struct HandGestureClassifier: Sendable, Equatable {
    public struct Config: Sendable, Equatable {
        /// 有效关节点最低置信度（默认 0.30）。
        public var minJointConfidence: Float
        /// 最小手掌尺度 dist(wrist, middleMCP)（默认 0.03，过滤远景噪声）。
        public var minPalmScale: Float

        // 挥手（wave）
        /// 统计方向翻转的时间窗（默认 1.5 s，对应 plan.md）。
        public var waveWindowDuration: TimeInterval
        /// 窗内最少水平方向翻转次数（默认 2 次 = 确立初始方向 + 2 次翻转，共 3 段有效水平摆动）。
        public var waveMinReversals: Int
        /// 单次有效摆动最小水平位移（归一化坐标下限，默认 0.030）。
        public var waveMinNormalizedAmplitude: Float
        /// 单次有效摆动相对手掌尺度的最小比例（默认 0.25）。
        public var waveMinPalmScaleRatio: Float
        /// 摆动水平/垂直分量比下限 |dx| / max(|dy|, ε)（默认 0.60，容忍弧线扇动并过滤竖直抬手）。
        public var waveMinHorizontalRatio: Float
        /// 张开手掌中断超过此时长后重置挥手轨迹（默认 0.45 s，容忍快速挥手运动模糊丢帧）。
        public var waveGapResetDuration: TimeInterval
        /// 挥手触发后需静默/收手达到此时长才允许再次触发（默认 0.45 s）。
        public var waveReleaseDuration: TimeInterval

        // 比心（heart：支持双手比心与单手韩式手指比心）
        /// 双手比心需持续保持的最短时长（默认 0.50 s，对应 spec.md）。
        public var heartHoldDuration: TimeInterval
        /// 两手拇指尖/食指尖间距相对平均手掌尺度的上限（默认 0.75）。
        public var heartTipMaxDistanceRatio: Float
        /// 食指尖中点高于拇指尖中点的最小比例（默认 0.25，过滤双手平合/拍手）。
        public var heartVerticalSeparationRatio: Float
        /// 两手腕最小间距相对平均手掌尺度下限（默认 0.60，防单手双检误触）。
        public var heartMinWristSeparationRatio: Float
        /// 两手腕最大间距相对平均手掌尺度上限（默认 4.50）。
        public var heartMaxWristSeparationRatio: Float
        /// 单手比心（韩式手指比心）拇指尖与食指尖最大间距比例（默认 1.25，兼容交叉后顶部 V 字开口）。
        public var singleHeartMaxTipDistanceRatio: Float
        /// 单手比心拇指上段与食指上段最小线段距离比例（默认 0.35，交叉相交时距离为 0）。
        public var singleHeartMaxCrossDistanceRatio: Float

        // 点赞（thumbsUp）
        /// 点赞需持续保持的最短时长（默认 0.50 s，对应 spec.md）。
        public var thumbsUpHoldDuration: TimeInterval
        /// 拇指方向向量 y 分量占比下限（默认 0.75，约 ±41° 朝上锥角）。
        public var thumbsUpMinUpwardCosine: Float

        // 通用防抖与边沿释放
        /// 静态保持期间允许的短时丢帧容忍窗口（默认 0.22 s，约 2 帧 12 Hz Vision 抖动）。
        public var holdDropoutTolerance: TimeInterval
        /// 静态手势结束后需持续不匹配此时长才释放边沿锁存（默认 0.25 s）。
        public var holdReleaseDuration: TimeInterval

        public init(
            minJointConfidence: Float = 0.30,
            minPalmScale: Float = 0.03,
            waveWindowDuration: TimeInterval = 1.5,
            waveMinReversals: Int = 2,
            waveMinNormalizedAmplitude: Float = 0.030,
            waveMinPalmScaleRatio: Float = 0.25,
            waveMinHorizontalRatio: Float = 0.60,
            waveGapResetDuration: TimeInterval = 0.45,
            waveReleaseDuration: TimeInterval = 0.45,
            heartHoldDuration: TimeInterval = 0.50,
            heartTipMaxDistanceRatio: Float = 0.75,
            heartVerticalSeparationRatio: Float = 0.25,
            heartMinWristSeparationRatio: Float = 0.60,
            heartMaxWristSeparationRatio: Float = 4.50,
            singleHeartMaxTipDistanceRatio: Float = 1.25,
            singleHeartMaxCrossDistanceRatio: Float = 0.35,
            thumbsUpHoldDuration: TimeInterval = 0.50,
            thumbsUpMinUpwardCosine: Float = 0.75,
            holdDropoutTolerance: TimeInterval = 0.22,
            holdReleaseDuration: TimeInterval = 0.25
        ) {
            self.minJointConfidence = min(max(minJointConfidence.isFinite ? minJointConfidence : 0.30, 0), 1)
            self.minPalmScale = max(minPalmScale.isFinite ? minPalmScale : 0.03, 0.001)
            self.waveWindowDuration = max(waveWindowDuration.isFinite ? waveWindowDuration : 1.5, 0.1)
            self.waveMinReversals = max(waveMinReversals, 1)
            self.waveMinNormalizedAmplitude = max(waveMinNormalizedAmplitude.isFinite ? waveMinNormalizedAmplitude : 0.030, 0)
            self.waveMinPalmScaleRatio = max(waveMinPalmScaleRatio.isFinite ? waveMinPalmScaleRatio : 0.25, 0)
            self.waveMinHorizontalRatio = max(waveMinHorizontalRatio.isFinite ? waveMinHorizontalRatio : 0.60, 0)
            self.waveGapResetDuration = max(waveGapResetDuration.isFinite ? waveGapResetDuration : 0.45, 0)
            self.waveReleaseDuration = max(waveReleaseDuration.isFinite ? waveReleaseDuration : 0.45, 0)
            self.heartHoldDuration = max(heartHoldDuration.isFinite ? heartHoldDuration : 0.50, 0)
            self.heartTipMaxDistanceRatio = max(heartTipMaxDistanceRatio.isFinite ? heartTipMaxDistanceRatio : 0.75, 0.05)
            self.heartVerticalSeparationRatio = max(heartVerticalSeparationRatio.isFinite ? heartVerticalSeparationRatio : 0.25, 0)
            self.heartMinWristSeparationRatio = max(heartMinWristSeparationRatio.isFinite ? heartMinWristSeparationRatio : 0.60, 0)
            self.heartMaxWristSeparationRatio = max(
                heartMaxWristSeparationRatio.isFinite ? heartMaxWristSeparationRatio : 4.50,
                self.heartMinWristSeparationRatio
            )
            self.singleHeartMaxTipDistanceRatio = max(singleHeartMaxTipDistanceRatio.isFinite ? singleHeartMaxTipDistanceRatio : 1.25, 0.05)
            self.singleHeartMaxCrossDistanceRatio = max(singleHeartMaxCrossDistanceRatio.isFinite ? singleHeartMaxCrossDistanceRatio : 0.35, 0.05)
            self.thumbsUpHoldDuration = max(thumbsUpHoldDuration.isFinite ? thumbsUpHoldDuration : 0.50, 0)
            self.thumbsUpMinUpwardCosine = min(max(thumbsUpMinUpwardCosine.isFinite ? thumbsUpMinUpwardCosine : 0.75, 0), 1)
            self.holdDropoutTolerance = max(holdDropoutTolerance.isFinite ? holdDropoutTolerance : 0.22, 0)
            self.holdReleaseDuration = max(holdReleaseDuration.isFinite ? holdReleaseDuration : 0.25, 0)
        }

        public static let defaults = Config()
    }

    private struct ValidHand: Sendable, Equatable {
        let joints: [HandJointName: HandJointPoint]
        let wrist: HandJointPoint
        let palmScale: Float
    }

    private struct FingerDescriptor {
        let mcp: HandJointName
        let pip: HandJointName
        let tip: HandJointName
    }

    private static let fourFingers: [FingerDescriptor] = [
        FingerDescriptor(mcp: .indexMCP, pip: .indexPIP, tip: .indexTip),
        FingerDescriptor(mcp: .middleMCP, pip: .middlePIP, tip: .middleTip),
        FingerDescriptor(mcp: .ringMCP, pip: .ringPIP, tip: .ringTip),
        FingerDescriptor(mcp: .littleMCP, pip: .littlePIP, tip: .littleTip),
    ]

    /// 只读实时诊断快照（仅含纯数值摘要，供真机调试面板排查手势阈值，不含任何图像数据）。
    public struct DebugSnapshot: Sendable, Equatable {
        public let validHandCount: Int
        public let openPalmCount: Int
        public let maxExtendedFingers: Int
        public let palmScale: Float
        public let tipDeltaX: Float
        public let tipDeltaY: Float
        public let waveDirection: Int
        public let waveReversalCount: Int
        public let latchedGesture: GestureKind?

        public static let empty = DebugSnapshot(
            validHandCount: 0,
            openPalmCount: 0,
            maxExtendedFingers: 0,
            palmScale: 0,
            tipDeltaX: 0,
            tipDeltaY: 0,
            waveDirection: 0,
            waveReversalCount: 0,
            latchedGesture: nil
        )
    }

    public let config: Config
    /// 当前处于边沿锁存中的手势（手势未结束前保持非 nil，供诊断/单测观察）。
    public private(set) var latchedGesture: GestureKind?
    /// 最近一次有手（或清空）的纯数值诊断快照，供调试面板观察。
    public private(set) var lastDiagnostics: DebugSnapshot = .empty

    private var lastTimestamp: TimeInterval?

    // 静态保持计时器：heart
    private var heartStartedAt: TimeInterval?
    private var heartLastMatchedAt: TimeInterval?

    // 静态保持计时器：thumbsUp
    private var thumbsUpStartedAt: TimeInterval?
    private var thumbsUpLastMatchedAt: TimeInterval?

    // 挥手轨迹状态
    private var waveAnchorPoint: HandJointPoint?
    private var waveDirection: Int = 0
    private var waveReversalTimestamps: [TimeInterval] = []
    private var lastOpenPalmAt: TimeInterval?
    private var lastOpenPalmWrist: HandJointPoint?
    private var lastWaveActivityAt: TimeInterval?

    public init(config: Config = .defaults) {
        self.config = config
    }

    /// 输入单帧检测到的 0–2 只手关节点与时间戳（秒）；仅在新手势首次成立时返回一次 `GestureEvent`（P-3）。
    public mutating func update(hands: [HandPoseFrame], at timestamp: TimeInterval) -> GestureEvent? {
        guard timestamp.isFinite else { return nil }
        if let last = lastTimestamp, timestamp < last {
            return nil
        }
        lastTimestamp = timestamp

        // 1. 过滤有效关节点并计算手掌尺度
        let validHands = hands.compactMap(extractValidHand)

        // 2. 单帧几何匹配：heart > thumbsUp > wave
        let heartConfidence = matchHeart(validHands)
        let thumbsUpConfidence: Float? = (heartConfidence == nil) ? matchThumbsUp(validHands) : nil
        let waveResult = updateWave(validHands, at: timestamp)

        // 3. 更新静态保持计时器（带短丢帧容忍）
        let heartReady = updateHoldTimer(
            matched: heartConfidence != nil,
            startedAt: &heartStartedAt,
            lastMatchedAt: &heartLastMatchedAt,
            holdDuration: config.heartHoldDuration,
            at: timestamp
        )
        let thumbsUpReady = updateHoldTimer(
            matched: thumbsUpConfidence != nil,
            startedAt: &thumbsUpStartedAt,
            lastMatchedAt: &thumbsUpLastMatchedAt,
            holdDuration: config.thumbsUpHoldDuration,
            at: timestamp
        )

        // 4. 边沿锁存释放检查
        if let latched = latchedGesture {
            switch latched {
            case .heart:
                if heartConfidence == nil {
                    let silentSince = heartLastMatchedAt ?? timestamp
                    if heartLastMatchedAt == nil || timestamp - silentSince + 1e-9 >= config.holdReleaseDuration {
                        latchedGesture = nil
                        heartStartedAt = nil
                    }
                }
            case .thumbsUp:
                if thumbsUpConfidence == nil {
                    let silentSince = thumbsUpLastMatchedAt ?? timestamp
                    if thumbsUpLastMatchedAt == nil || timestamp - silentSince + 1e-9 >= config.holdReleaseDuration {
                        latchedGesture = nil
                        thumbsUpStartedAt = nil
                    }
                }
            case .wave:
                if let lastActivity = lastWaveActivityAt {
                    if timestamp - lastActivity + 1e-9 >= config.waveReleaseDuration {
                        latchedGesture = nil
                    }
                } else {
                    latchedGesture = nil
                }
            }
        }

        // 5. 同帧优先级裁决：heart > thumbsUp > wave
        let candidate: (kind: GestureKind, confidence: Float)?
        if heartReady, let conf = heartConfidence {
            candidate = (.heart, conf)
        } else if thumbsUpReady, let conf = thumbsUpConfidence {
            candidate = (.thumbsUp, conf)
        } else if let waveConf = waveResult.triggeredConfidence {
            candidate = (.wave, waveConf)
        } else {
            candidate = nil
        }

        // 更新最近一次有手帧的诊断快照（无手时不覆盖最近有手数据，方便截屏观察）
        if !validHands.isEmpty {
            lastDiagnostics = DebugSnapshot(
                validHandCount: validHands.count,
                openPalmCount: waveResult.openPalmCount,
                maxExtendedFingers: waveResult.maxExtendedFingers,
                palmScale: waveResult.bestPalmScale,
                tipDeltaX: waveResult.bestTipDeltaX,
                tipDeltaY: waveResult.bestTipDeltaY,
                waveDirection: waveDirection,
                waveReversalCount: waveReversalTimestamps.count,
                latchedGesture: latchedGesture
            )
        }

        guard let selected = candidate else {
            return nil
        }

        // 若挥手达成，立即重置翻转窗口防止重复触发
        if selected.kind == .wave {
            waveReversalTimestamps.removeAll()
            waveDirection = 0
            if let wrist = waveResult.activeWrist {
                waveAnchorPoint = wrist
            }
            lastWaveActivityAt = timestamp
        }

        // 边沿锁存：同手势不重复触发，不同手势允许立即切换触发
        if latchedGesture == selected.kind {
            return nil
        }

        latchedGesture = selected.kind
        lastDiagnostics = DebugSnapshot(
            validHandCount: validHands.count,
            openPalmCount: waveResult.openPalmCount,
            maxExtendedFingers: waveResult.maxExtendedFingers,
            palmScale: waveResult.bestPalmScale,
            tipDeltaX: waveResult.bestTipDeltaX,
            tipDeltaY: waveResult.bestTipDeltaY,
            waveDirection: waveDirection,
            waveReversalCount: waveReversalTimestamps.count,
            latchedGesture: latchedGesture
        )
        return GestureEvent(
            kind: selected.kind,
            confidence: Self.clamp01(selected.confidence),
            timestamp: timestamp
        )
    }

    /// 清空全部保持计时器、挥手轨迹与边沿锁存状态。
    public mutating func reset() {
        latchedGesture = nil
        lastDiagnostics = .empty
        lastTimestamp = nil
        heartStartedAt = nil
        heartLastMatchedAt = nil
        thumbsUpStartedAt = nil
        thumbsUpLastMatchedAt = nil
        waveAnchorPoint = nil
        waveDirection = 0
        waveReversalTimestamps.removeAll()
        lastOpenPalmAt = nil
        lastOpenPalmWrist = nil
        lastWaveActivityAt = nil
    }

    // MARK: - 关节点过滤与基础几何

    private func extractValidHand(_ frame: HandPoseFrame) -> ValidHand? {
        var filtered: [HandJointName: HandJointPoint] = [:]
        filtered.reserveCapacity(frame.joints.count)
        for (name, pt) in frame.joints {
            guard pt.x.isFinite, pt.y.isFinite, pt.confidence.isFinite,
                  pt.confidence >= config.minJointConfidence
            else {
                continue
            }
            filtered[name] = pt
        }

        let mcpNames: [HandJointName] = [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
        let validMCPs = mcpNames.compactMap { filtered[$0] }

        // 当手靠近镜头底边时，wrist 偶发被裁剪或置信度跌破 0.30，但上方掌指关节置信度很高；
        // 在至少有 2 个有效 MCP 关节的前提下，允许用低置信度 wrist(>=0.10) 或由 MCP 推算虚拟 wrist 兜底。
        let wrist: HandJointPoint
        let palmScale: Float
        if let directWrist = filtered[.wrist] {
            wrist = directWrist
            if let middleMCP = filtered[.middleMCP] {
                palmScale = Self.distance(wrist, middleMCP)
            } else {
                let dists = validMCPs.map { Self.distance(wrist, $0) }
                guard !dists.isEmpty else { return nil }
                palmScale = dists.reduce(0, +) / Float(dists.count)
            }
        } else {
            guard validMCPs.count >= 2 else { return nil }
            var maxMcpSpan: Float = 0
            for i in 0..<(validMCPs.count - 1) {
                for j in (i + 1)..<validMCPs.count {
                    maxMcpSpan = max(maxMcpSpan, Self.distance(validMCPs[i], validMCPs[j]))
                }
            }
            let estimatedScale = maxMcpSpan / 0.85
            if let rawWrist = frame.joints[.wrist],
               rawWrist.x.isFinite, rawWrist.y.isFinite, rawWrist.confidence.isFinite,
               rawWrist.confidence >= 0.10 {
                wrist = rawWrist
                let dists = validMCPs.map { Self.distance(wrist, $0) }
                palmScale = max(dists.reduce(0, +) / Float(dists.count), estimatedScale * 0.5)
            } else {
                guard estimatedScale >= config.minPalmScale else { return nil }
                let centerX = validMCPs.reduce(Float(0)) { $0 + $1.x } / Float(validMCPs.count)
                let centerY = validMCPs.reduce(Float(0)) { $0 + $1.y } / Float(validMCPs.count)
                let avgConf = validMCPs.reduce(Float(0)) { $0 + $1.confidence } / Float(validMCPs.count)
                wrist = HandJointPoint(x: centerX, y: centerY - estimatedScale, confidence: avgConf)
                palmScale = estimatedScale
            }
        }

        guard palmScale.isFinite, palmScale >= config.minPalmScale else {
            return nil
        }
        return ValidHand(joints: filtered, wrist: wrist, palmScale: palmScale)
    }

    private func fingerStates(in hand: ValidHand) -> [(extended: Bool, curled: Bool, tip: HandJointPoint, confidence: Float)] {
        var results: [(extended: Bool, curled: Bool, tip: HandJointPoint, confidence: Float)] = []
        results.reserveCapacity(4)

        for finger in Self.fourFingers {
            guard let mcp = hand.joints[finger.mcp],
                  let pip = hand.joints[finger.pip],
                  let tip = hand.joints[finger.tip]
            else {
                continue
            }
            let distTipWrist = Self.distance(tip, hand.wrist)
            let distPipWrist = Self.distance(pip, hand.wrist)
            let distTipMcp = Self.distance(tip, mcp)
            let cosVal = Self.cosAngle(
                ax: pip.x - mcp.x, ay: pip.y - mcp.y,
                bx: tip.x - pip.x, by: tip.y - pip.y
            )

            let extended = distTipWrist >= distPipWrist * 1.08
                && distTipMcp >= hand.palmScale * 0.45
                && cosVal >= 0.30

            let curled = !extended
                && (distTipWrist <= distPipWrist * 1.05 || distTipMcp <= hand.palmScale * 0.72)
                && distTipMcp <= hand.palmScale * 0.95

            let conf = (mcp.confidence + pip.confidence + tip.confidence) / 3.0
            results.append((extended, curled, tip, conf))
        }
        return results
    }

    // MARK: - 比心（heart：双手比心 + 单手手指比心，左右手对称）

    private func matchHeart(_ hands: [ValidHand]) -> Float? {
        if let twoHandConf = matchTwoHandHeart(hands) {
            return twoHandConf
        }
        return matchSingleHandHeart(hands)
    }

    private func matchTwoHandHeart(_ hands: [ValidHand]) -> Float? {
        guard hands.count >= 2 else { return nil }
        var bestConfidence: Float?

        for i in 0..<(hands.count - 1) {
            for j in (i + 1)..<hands.count {
                let a = hands[i]
                let b = hands[j]
                guard let thumbTipA = a.joints[.thumbTip],
                      let indexTipA = a.joints[.indexTip],
                      let indexMcpA = a.joints[.indexMCP],
                      let thumbTipB = b.joints[.thumbTip],
                      let indexTipB = b.joints[.indexTip],
                      let indexMcpB = b.joints[.indexMCP]
                else {
                    continue
                }

                let avgScale = (a.palmScale + b.palmScale) * 0.5
                guard avgScale >= config.minPalmScale else { continue }

                let thumbTipDist = Self.distance(thumbTipA, thumbTipB)
                guard thumbTipDist <= avgScale * config.heartTipMaxDistanceRatio else { continue }

                let indexTipDist = Self.distance(indexTipA, indexTipB)
                guard indexTipDist <= avgScale * config.heartTipMaxDistanceRatio else { continue }

                let indexMidY = (indexTipA.y + indexTipB.y) * 0.5
                let thumbMidY = (thumbTipA.y + thumbTipB.y) * 0.5
                guard indexMidY - thumbMidY >= avgScale * config.heartVerticalSeparationRatio else { continue }

                let wristDist = Self.distance(a.wrist, b.wrist)
                guard wristDist >= avgScale * config.heartMinWristSeparationRatio,
                      wristDist <= avgScale * config.heartMaxWristSeparationRatio
                else {
                    continue
                }

                let indexMcpDist = Self.distance(indexMcpA, indexMcpB)
                guard indexMcpDist > indexTipDist else { continue }

                let conf = (
                    a.wrist.confidence + thumbTipA.confidence + indexTipA.confidence + indexMcpA.confidence +
                    b.wrist.confidence + thumbTipB.confidence + indexTipB.confidence + indexMcpB.confidence
                ) / 8.0
                if bestConfidence == nil || conf > bestConfidence! {
                    bestConfidence = Self.clamp01(conf)
                }
            }
        }
        return bestConfidence
    }

    /// 单手比心（韩式拇指与食指交叉比心，左右手对称、抗手腕倾斜 ±40°、抗手背局部遮挡）：
    /// 拇指与食指在手腕上方伸出并在中上段交叉或贴合（兼容顶部 V 字开口与指尖捏合），中指/无名指/小指无一伸直且至少 1 根弯曲（排除 OK、L 字手势、剪刀手、张手、握拳与点赞）。
    private func matchSingleHandHeart(_ hands: [ValidHand]) -> Float? {
        let lowerFingers: [FingerDescriptor] = [
            FingerDescriptor(mcp: .middleMCP, pip: .middlePIP, tip: .middleTip),
            FingerDescriptor(mcp: .ringMCP, pip: .ringPIP, tip: .ringTip),
            FingerDescriptor(mcp: .littleMCP, pip: .littlePIP, tip: .littleTip),
        ]

        var bestConfidence: Float?
        for hand in hands {
            guard let thumbTip = hand.joints[.thumbTip],
                  let indexTip = hand.joints[.indexTip]
            else {
                continue
            }
            // 允许手背遮挡 thumbMP 或 indexMCP 时回退至邻近关节，至少各需 1 个中段/根部参考点
            guard hand.joints[.thumbIP] != nil || hand.joints[.thumbMP] != nil,
                  hand.joints[.indexPIP] != nil || hand.joints[.indexMCP] != nil
            else {
                continue
            }
            let thumbBase = hand.joints[.thumbMP] ?? hand.joints[.thumbCMC] ?? hand.wrist
            let thumbMid = hand.joints[.thumbIP] ?? thumbBase
            let indexBase = hand.joints[.indexMCP] ?? hand.wrist
            let indexMid = hand.joints[.indexPIP] ?? indexBase

            let thumbWristDist = Self.distance(thumbTip, hand.wrist)
            let indexWristDist = Self.distance(indexTip, hand.wrist)
            // 单手比心时手背常对镜头微倾，wrist->middleMCP 在 2D 投影下可能透视缩短至 0.06–0.09；
            // 用手腕到拇指/食指尖的半长兜底还原真实手掌尺度，避免比例阈值被透视压扁误杀。
            let scale = max(hand.palmScale, max(thumbWristDist, indexWristDist) * 0.50)

            // 1. 拇指与食指在手腕上方伸出（兼容手腕倾斜 ±40° 歪手比心，同时排除握拳、垂手与点赞）
            let meanTipY = (thumbTip.y + indexTip.y) * 0.5
            let indexBaseWristDist = Self.distance(indexBase, hand.wrist)
            guard meanTipY >= hand.wrist.y + scale * 0.45,
                  min(thumbTip.y, indexTip.y) >= hand.wrist.y + scale * 0.25,
                  thumbWristDist >= scale * 0.85,
                  indexWristDist >= scale * 0.85,
                  max(thumbWristDist, indexWristDist) >= indexBaseWristDist + scale * 0.08,
                  abs(thumbTip.y - indexTip.y) <= scale * 0.85
            else {
                continue
            }
            if let thumbCMC = hand.joints[.thumbCMC],
               Self.distance(thumbTip, thumbCMC) < scale * 0.45 {
                continue
            }

            // 2. 拇指与食指交叉或上段贴近（相交时线段距为 0；兼容张开 V 字小爱心与指尖捏合，同时排除 L 字手势与点赞）
            let tipDist = Self.distance(thumbTip, indexTip)
            guard tipDist <= scale * config.singleHeartMaxTipDistanceRatio else { continue }

            // 仅在两根部参考点不重合（避免共享回退 wrist 导致共端点退化恒相交）时判定含 base 的交叉；
            // 上段 (thumbMid->thumbTip) 与 (indexMid->indexTip) 始终参与相交与最小距离判定。
            let hasDistinctBases = Self.distance(thumbBase, indexBase) > 1e-4
            let crosses: Bool = if hasDistinctBases {
                Self.segmentsIntersect(thumbBase, thumbTip, indexBase, indexTip)
                    || Self.segmentsIntersect(thumbBase, thumbMid, indexBase, indexMid)
                    || Self.segmentsIntersect(thumbMid, thumbTip, indexBase, indexTip)
                    || Self.segmentsIntersect(thumbMid, thumbTip, indexMid, indexTip)
            } else {
                Self.segmentsIntersect(thumbMid, thumbTip, indexMid, indexTip)
            }
            let upperSegDist = Self.segmentDistance(thumbMid, thumbTip, indexMid, indexTip)
            guard crosses || upperSegDist <= scale * config.singleHeartMaxCrossDistanceRatio else {
                continue
            }

            // 3. 中指、无名指、小指无一伸直且至少 1 根明确弯曲（容忍小指微翘或手背遮挡，同时严格排除 OK、剪刀手与张手）
            var visibleLower = 0
            var curledLower = 0
            var extendedLower = 0
            var sumConf = hand.wrist.confidence + thumbBase.confidence + thumbMid.confidence + thumbTip.confidence
                + indexBase.confidence + indexMid.confidence + indexTip.confidence
            var countConf = 7

            for finger in lowerFingers {
                guard let mcp = hand.joints[finger.mcp],
                      let pip = hand.joints[finger.pip],
                      let tip = hand.joints[finger.tip]
                else {
                    continue
                }
                visibleLower += 1
                let distTipWrist = Self.distance(tip, hand.wrist)
                let distPipWrist = Self.distance(pip, hand.wrist)
                let distTipMcp = Self.distance(tip, mcp)
                let cosVal = Self.cosAngle(
                    ax: pip.x - mcp.x, ay: pip.y - mcp.y,
                    bx: tip.x - pip.x, by: tip.y - pip.y
                )
                let extended = distTipWrist >= distPipWrist * 1.08
                    && distTipMcp >= scale * 0.45
                    && cosVal >= 0.30
                let curled = !extended
                    && (distTipWrist <= distPipWrist * 1.05 || distTipMcp <= scale * 0.72)
                    && distTipMcp <= scale * 0.95
                if extended {
                    extendedLower += 1
                }
                if curled {
                    curledLower += 1
                }
                sumConf += mcp.confidence + pip.confidence + tip.confidence
                countConf += 3
            }

            guard visibleLower >= 1, extendedLower == 0, curledLower >= 1 else { continue }

            let conf = Self.clamp01(sumConf / Float(countConf))
            if bestConfidence == nil || conf > bestConfidence! {
                bestConfidence = conf
            }
        }
        return bestConfidence
    }

    // MARK: - 点赞（thumbsUp）

    private func matchThumbsUp(_ hands: [ValidHand]) -> Float? {
        var bestConfidence: Float?

        for hand in hands {
            guard let thumbCMC = hand.joints[.thumbCMC],
                  let thumbMP = hand.joints[.thumbMP],
                  let thumbIP = hand.joints[.thumbIP],
                  let thumbTip = hand.joints[.thumbTip],
                  let indexMCP = hand.joints[.indexMCP]
            else {
                continue
            }

            let scale = hand.palmScale
            // 拇指伸直
            guard Self.distance(thumbTip, thumbCMC) >= scale * 0.65,
                  Self.distance(thumbTip, thumbMP) >= scale * 0.35,
                  Self.distance(thumbTip, hand.wrist) > Self.distance(thumbIP, hand.wrist),
                  Self.distance(thumbTip, indexMCP) >= scale * 0.55
            else {
                continue
            }

            // 拇指朝上
            let vx = thumbTip.x - thumbMP.x
            let vy = thumbTip.y - thumbMP.y
            let vLen = hypot(vx, vy)
            guard vy > 0, vLen > 1e-6, (vy / vLen) >= config.thumbsUpMinUpwardCosine else {
                continue
            }
            guard thumbTip.y > thumbCMC.y else { continue }

            let visibleMcpYs = Self.fourFingers.compactMap { hand.joints[$0.mcp]?.y }
            guard let maxVisibleMcpY = visibleMcpYs.max(),
                  thumbTip.y >= maxVisibleMcpY + scale * 0.15
            else {
                continue
            }

            // 其余四指弯曲
            let states = fingerStates(in: hand)
            guard states.count >= 3,
                  states.allSatisfy({ $0.curled && !$0.extended })
            else {
                continue
            }

            var sumConf = hand.wrist.confidence + thumbCMC.confidence + thumbMP.confidence + thumbIP.confidence + thumbTip.confidence
            var countConf = 5
            for finger in Self.fourFingers {
                if let mcp = hand.joints[finger.mcp],
                   let pip = hand.joints[finger.pip],
                   let tip = hand.joints[finger.tip] {
                    sumConf += mcp.confidence + pip.confidence + tip.confidence
                    countConf += 3
                }
            }
            let conf = Self.clamp01(sumConf / Float(countConf))
            if bestConfidence == nil || conf > bestConfidence! {
                bestConfidence = conf
            }
        }
        return bestConfidence
    }

    // MARK: - 挥手（wave）

    private mutating func updateWave(
        _ hands: [ValidHand],
        at timestamp: TimeInterval
    ) -> (
        triggeredConfidence: Float?,
        activeWrist: HandJointPoint?,
        openPalmCount: Int,
        maxExtendedFingers: Int,
        bestPalmScale: Float,
        bestTipDeltaX: Float,
        bestTipDeltaY: Float
    ) {
        // 寻找张开手掌（至少 2 根手指伸直且弯曲手指 <= 1 根；
        // 仅排除明显朝下倒垂的手 tipDeltaY < -0.25 * palmScale，避免挥手歪到左右极限拐点时 ΔY≈0 被误拒；
        // 跟踪点取手腕与伸直指尖加权重心 0.35*wrist + 0.65*meanTip）
        var openPalms: [(trackPoint: HandJointPoint, palmScale: Float, confidence: Float, tipDeltaX: Float, tipDeltaY: Float)] = []
        var maxExtended = 0
        var fallbackPalmScale: Float = 0
        var fallbackTipDeltaX: Float = 0
        var fallbackTipDeltaY: Float = 0

        for hand in hands {
            let states = fingerStates(in: hand)
            let extendedFingers = states.filter(\.extended)
            let curledFingers = states.filter(\.curled)
            if extendedFingers.count >= maxExtended {
                maxExtended = extendedFingers.count
                fallbackPalmScale = hand.palmScale
                if !extendedFingers.isEmpty {
                    let meanX = extendedFingers.reduce(Float(0)) { $0 + $1.tip.x } / Float(extendedFingers.count)
                    let meanY = extendedFingers.reduce(Float(0)) { $0 + $1.tip.y } / Float(extendedFingers.count)
                    fallbackTipDeltaX = meanX - hand.wrist.x
                    fallbackTipDeltaY = meanY - hand.wrist.y
                } else if !states.isEmpty {
                    let meanX = states.reduce(Float(0)) { $0 + $1.tip.x } / Float(states.count)
                    let meanY = states.reduce(Float(0)) { $0 + $1.tip.y } / Float(states.count)
                    fallbackTipDeltaX = meanX - hand.wrist.x
                    fallbackTipDeltaY = meanY - hand.wrist.y
                }
            }
            guard extendedFingers.count >= 2, curledFingers.count <= 1 else { continue }
            let meanTipX = extendedFingers.reduce(Float(0)) { $0 + $1.tip.x } / Float(extendedFingers.count)
            let meanTipY = extendedFingers.reduce(Float(0)) { $0 + $1.tip.y } / Float(extendedFingers.count)
            let tipDeltaX = meanTipX - hand.wrist.x
            let tipDeltaY = meanTipY - hand.wrist.y
            guard tipDeltaY >= -hand.palmScale * 0.25 else { continue }

            let fingerConf = extendedFingers.reduce(Float(0)) { $0 + $1.confidence } / Float(extendedFingers.count)
            let conf = Self.clamp01((hand.wrist.confidence + fingerConf) * 0.5)
            let trackPoint = HandJointPoint(
                x: hand.wrist.x * 0.35 + meanTipX * 0.65,
                y: hand.wrist.y * 0.35 + meanTipY * 0.65,
                confidence: conf
            )
            openPalms.append((trackPoint, hand.palmScale, conf, tipDeltaX, tipDeltaY))
        }

        guard !openPalms.isEmpty else {
            if let lastSeen = lastOpenPalmAt, timestamp - lastSeen > config.waveGapResetDuration {
                waveAnchorPoint = nil
                waveDirection = 0
                waveReversalTimestamps.removeAll()
                lastOpenPalmWrist = nil
            }
            return (nil, nil, 0, maxExtended, fallbackPalmScale, fallbackTipDeltaX, fallbackTipDeltaY)
        }

        // 多只张开手掌时选与上次记录跟踪点距离最近的一只
        let chosen: (trackPoint: HandJointPoint, palmScale: Float, confidence: Float, tipDeltaX: Float, tipDeltaY: Float)
        if let prevTrack = lastOpenPalmWrist {
            chosen = openPalms.min(by: {
                Self.distance($0.trackPoint, prevTrack) < Self.distance($1.trackPoint, prevTrack)
            })!
        } else {
            chosen = openPalms.max(by: { $0.confidence < $1.confidence })!
        }

        let wrist = chosen.trackPoint
        let palmScale = chosen.palmScale
        lastOpenPalmAt = timestamp
        lastOpenPalmWrist = wrist

        // 淘汰时间窗外的旧翻转；若长时间无有效翻转，重置方向与锚点防旧 anchor.y 死锁
        waveReversalTimestamps.removeAll { timestamp - $0 > config.waveWindowDuration }
        if waveDirection != 0,
           let lastAct = lastWaveActivityAt,
           timestamp - lastAct > config.waveWindowDuration {
            waveDirection = 0
            waveAnchorPoint = wrist
        }

        guard let anchor = waveAnchorPoint else {
            waveAnchorPoint = wrist
            waveDirection = 0
            return (nil, wrist, openPalms.count, maxExtended, palmScale, chosen.tipDeltaX, chosen.tipDeltaY)
        }

        let minSwing = max(config.waveMinNormalizedAmplitude, palmScale * config.waveMinPalmScaleRatio)
        let dx = wrist.x - anchor.x
        let dy = wrist.y - anchor.y
        let absDx = abs(dx)
        let absDy = abs(dy)

        switch waveDirection {
        case 0:
            if absDx >= minSwing && absDx >= absDy * config.waveMinHorizontalRatio {
                waveDirection = dx > 0 ? 1 : -1
                waveAnchorPoint = wrist
                lastWaveActivityAt = timestamp
            } else if absDy >= minSwing && absDx < absDy * config.waveMinHorizontalRatio {
                // 大幅竖直移动主导：平移锚点，避免抬手后再微横移误计数
                waveAnchorPoint = wrist
            }

        case 1:
            if wrist.x > anchor.x {
                waveAnchorPoint = wrist
            } else {
                let backDx = anchor.x - wrist.x
                if backDx >= minSwing && backDx >= absDy * config.waveMinHorizontalRatio {
                    waveReversalTimestamps.append(timestamp)
                    waveDirection = -1
                    waveAnchorPoint = wrist
                    lastWaveActivityAt = timestamp
                } else if absDy >= minSwing && backDx < absDy * config.waveMinHorizontalRatio {
                    // 手竖直移动至新高度：解锁旧 anchor.y 防止后续水平挥手被永久拒判
                    waveDirection = 0
                    waveAnchorPoint = wrist
                }
            }

        case -1:
            if wrist.x < anchor.x {
                waveAnchorPoint = wrist
            } else {
                let backDx = wrist.x - anchor.x
                if backDx >= minSwing && backDx >= absDy * config.waveMinHorizontalRatio {
                    waveReversalTimestamps.append(timestamp)
                    waveDirection = 1
                    waveAnchorPoint = wrist
                    lastWaveActivityAt = timestamp
                } else if absDy >= minSwing && backDx < absDy * config.waveMinHorizontalRatio {
                    waveDirection = 0
                    waveAnchorPoint = wrist
                }
            }

        default:
            waveDirection = 0
            waveAnchorPoint = wrist
        }

        if waveReversalTimestamps.count >= config.waveMinReversals {
            return (chosen.confidence, wrist, openPalms.count, maxExtended, palmScale, chosen.tipDeltaX, chosen.tipDeltaY)
        }
        return (nil, wrist, openPalms.count, maxExtended, palmScale, chosen.tipDeltaX, chosen.tipDeltaY)
    }

    // MARK: - 静态保持与工具函数

    private func updateHoldTimer(
        matched: Bool,
        startedAt: inout TimeInterval?,
        lastMatchedAt: inout TimeInterval?,
        holdDuration: TimeInterval,
        at timestamp: TimeInterval
    ) -> Bool {
        if matched {
            if startedAt == nil {
                startedAt = timestamp
            }
            lastMatchedAt = timestamp
            if let started = startedAt, timestamp - started + 1e-9 >= holdDuration {
                return true
            }
            return false
        } else {
            if let last = lastMatchedAt, timestamp - last <= config.holdDropoutTolerance {
                // 短时丢帧容忍窗口内保留 startedAt
                return false
            }
            startedAt = nil
            return false
        }
    }

    private static func distance(_ a: HandJointPoint, _ b: HandJointPoint) -> Float {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func cross2D(_ o: HandJointPoint, _ a: HandJointPoint, _ b: HandJointPoint) -> Float {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    private static func onSegment(_ p: HandJointPoint, _ a: HandJointPoint, _ b: HandJointPoint) -> Bool {
        let eps: Float = 1e-6
        return p.x >= min(a.x, b.x) - eps && p.x <= max(a.x, b.x) + eps
            && p.y >= min(a.y, b.y) - eps && p.y <= max(a.y, b.y) + eps
    }

    /// 2D 线段相交判定（对水平镜像完全对称不变）。
    private static func segmentsIntersect(
        _ a: HandJointPoint, _ b: HandJointPoint,
        _ c: HandJointPoint, _ d: HandJointPoint
    ) -> Bool {
        let d1 = cross2D(c, d, a)
        let d2 = cross2D(c, d, b)
        let d3 = cross2D(a, b, c)
        let d4 = cross2D(a, b, d)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }
        let eps: Float = 1e-6
        if abs(d1) <= eps && onSegment(a, c, d) { return true }
        if abs(d2) <= eps && onSegment(b, c, d) { return true }
        if abs(d3) <= eps && onSegment(c, a, b) { return true }
        if abs(d4) <= eps && onSegment(d, a, b) { return true }
        return false
    }

    private static func pointToSegmentDistance(_ p: HandJointPoint, _ a: HandJointPoint, _ b: HandJointPoint) -> Float {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lenSq = abx * abx + aby * aby
        guard lenSq > 1e-12 else { return distance(p, a) }
        let t = min(max(((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq, 0), 1)
        let proj = HandJointPoint(x: a.x + t * abx, y: a.y + t * aby)
        return distance(p, proj)
    }

    private static func segmentDistance(
        _ a: HandJointPoint, _ b: HandJointPoint,
        _ c: HandJointPoint, _ d: HandJointPoint
    ) -> Float {
        if segmentsIntersect(a, b, c, d) {
            return 0
        }
        return min(
            min(pointToSegmentDistance(a, c, d), pointToSegmentDistance(b, c, d)),
            min(pointToSegmentDistance(c, a, b), pointToSegmentDistance(d, a, b))
        )
    }

    private static func cosAngle(ax: Float, ay: Float, bx: Float, by: Float) -> Float {
        let lenA = hypot(ax, ay)
        let lenB = hypot(bx, by)
        guard lenA > 1e-6, lenB > 1e-6 else { return -1 }
        return (ax * bx + ay * by) / (lenA * lenB)
    }

    private static func clamp01(_ v: Float) -> Float {
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }
}
