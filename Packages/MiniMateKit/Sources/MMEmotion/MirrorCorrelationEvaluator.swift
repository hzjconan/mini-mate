import Foundation

public struct MirrorChannelCorrelation: Sendable, Equatable {
    public let name: String
    public let correlation: Double
    public var absCorrelation: Double { abs(correlation) }

    public init(name: String, correlation: Double) {
        self.name = name
        self.correlation = correlation
    }
}

public struct MirrorCorrelationReport: Sendable, Equatable {
    public let sampleCount: Int
    public let duration: TimeInterval
    public let threshold: Double
    public let perChannel: [String: Double]
    public let maxAbsCorrelation: Double
    public let maxChannelName: String?
    public let meanAbsCorrelation: Double
    public let topChannels: [MirrorChannelCorrelation]

    public var passed: Bool { sampleCount >= 2 && maxAbsCorrelation < threshold }

    public init(
        sampleCount: Int,
        duration: TimeInterval,
        threshold: Double = 0.3,
        perChannel: [String: Double],
        maxAbsCorrelation: Double,
        maxChannelName: String?,
        meanAbsCorrelation: Double,
        topChannels: [MirrorChannelCorrelation]
    ) {
        self.sampleCount = sampleCount
        self.duration = duration
        self.threshold = threshold
        self.perChannel = perChannel
        self.maxAbsCorrelation = maxAbsCorrelation
        self.maxChannelName = maxChannelName
        self.meanAbsCorrelation = meanAbsCorrelation
        self.topChannels = topChannels
    }

    public func summaryText() -> String {
        let status = passed ? "PASS" : "FAIL"
        var lines: [String] = [
            "Mirror Correlation Report (SC-004): \(status)",
            String(format: "samples=%d duration=%.1fs threshold=%.2f", sampleCount, duration, threshold),
            String(
                format: "maxAbsR=%.4f (%@) meanAbsR=%.4f",
                maxAbsCorrelation,
                maxChannelName ?? "none",
                meanAbsCorrelation
            ),
        ]
        if !topChannels.isEmpty {
            lines.append("topChannels:")
            for item in topChannels {
                lines.append(String(format: "  - %@: r=%.4f (|r|=%.4f)", item.name, item.correlation, item.absCorrelation))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public enum MirrorCorrelationEvaluator: Sendable {
    /// 宪章 I / FR-014 豁免的 8 个视线通道，不纳入镜像检测。
    public static let gazeBlendShapeNames: Set<String> = [
        "eyeLookDownLeft", "eyeLookDownRight",
        "eyeLookInLeft", "eyeLookInRight",
        "eyeLookOutLeft", "eyeLookOutRight",
        "eyeLookUpLeft", "eyeLookUpRight",
    ]

    /// 单通道双精度 Pearson 相关系数；长度 < 2 或任一序列方差 < 1e-12 返回 0.0（杜绝 NaN）。
    public static func pearson(_ xs: [Double], _ ys: [Double]) -> Double {
        let n = min(xs.count, ys.count)
        guard n >= 2 else { return 0.0 }

        var sumX = 0.0
        var sumY = 0.0
        for i in 0..<n {
            let x = xs[i].isFinite ? xs[i] : 0.0
            let y = ys[i].isFinite ? ys[i] : 0.0
            sumX += x
            sumY += y
        }
        let meanX = sumX / Double(n)
        let meanY = sumY / Double(n)

        var cov = 0.0
        var varX = 0.0
        var varY = 0.0
        for i in 0..<n {
            let x = xs[i].isFinite ? xs[i] : 0.0
            let y = ys[i].isFinite ? ys[i] : 0.0
            let dx = x - meanX
            let dy = y - meanY
            cov += dx * dy
            varX += dx * dx
            varY += dy * dy
        }

        guard varX >= 1e-12, varY >= 1e-12 else {
            return 0.0
        }
        let denom = (varX * varY).squareRoot()
        guard denom.isFinite, denom > 0 else {
            return 0.0
        }
        let r = cov / denom
        guard r.isFinite else { return 0.0 }
        return min(max(r, -1.0), 1.0)
    }

    /// 评估逐帧配对的用户 rawBlendShapes 与形象 expressionWeights。
    public static func evaluate(
        pairs: [(user: [String: Float], avatar: [String: Float])],
        duration: TimeInterval,
        channels: [String]? = nil,
        threshold: Double = 0.3
    ) -> MirrorCorrelationReport {
        let sampleCount = pairs.count
        let safeDuration = duration.isFinite ? max(duration, 0) : 0
        let safeThreshold = threshold.isFinite ? threshold : 0.3

        var candidateSet: Set<String>
        if let channels {
            candidateSet = Set(channels)
        } else {
            candidateSet = []
            for pair in pairs {
                for key in pair.user.keys { candidateSet.insert(key) }
                for key in pair.avatar.keys { candidateSet.insert(key) }
            }
        }
        candidateSet.subtract(gazeBlendShapeNames)
        let evaluatedChannels = candidateSet.sorted()

        guard sampleCount >= 2 else {
            return MirrorCorrelationReport(
                sampleCount: sampleCount,
                duration: safeDuration,
                threshold: safeThreshold,
                perChannel: [:],
                maxAbsCorrelation: 0.0,
                maxChannelName: nil,
                meanAbsCorrelation: 0.0,
                topChannels: []
            )
        }

        var perChannel: [String: Double] = [:]
        perChannel.reserveCapacity(evaluatedChannels.count)

        var items: [MirrorChannelCorrelation] = []
        items.reserveCapacity(evaluatedChannels.count)

        var xs = [Double](repeating: 0, count: sampleCount)
        var ys = [Double](repeating: 0, count: sampleCount)

        for name in evaluatedChannels {
            for i in 0..<sampleCount {
                let ux = pairs[i].user[name] ?? 0
                let ay = pairs[i].avatar[name] ?? 0
                xs[i] = ux.isFinite ? Double(ux) : 0.0
                ys[i] = ay.isFinite ? Double(ay) : 0.0
            }
            let r = pearson(xs, ys)
            perChannel[name] = r
            items.append(MirrorChannelCorrelation(name: name, correlation: r))
        }

        items.sort { lhs, rhs in
            if lhs.absCorrelation != rhs.absCorrelation {
                return lhs.absCorrelation > rhs.absCorrelation
            }
            return lhs.name < rhs.name
        }

        let maxItem = items.first
        let meanAbs: Double
        if items.isEmpty {
            meanAbs = 0.0
        } else {
            meanAbs = items.reduce(0.0) { $0 + $1.absCorrelation } / Double(items.count)
        }

        return MirrorCorrelationReport(
            sampleCount: sampleCount,
            duration: safeDuration,
            threshold: safeThreshold,
            perChannel: perChannel,
            maxAbsCorrelation: maxItem?.absCorrelation ?? 0.0,
            maxChannelName: maxItem?.name,
            meanAbsCorrelation: meanAbs,
            topChannels: Array(items.prefix(5))
        )
    }
}
