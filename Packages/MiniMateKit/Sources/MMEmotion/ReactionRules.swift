import Foundation

/// 感知反应的类别，同一类别共享冷却。
public enum ReactionKey: String, CaseIterable, Sendable, Codable {
    case smile
    case frown
    case surprise
    case wave
    case heart
    case thumbsUp
}

/// 可调参数，调参结果同步写入 `specs/002-m1-presence/research.md`。
public struct ReactionRules: Sendable, Equatable {
    /// 表情反应的延迟区间，均匀随机；用于 S-3 的 300–800 ms。
    public var reactionDelay: ClosedRange<TimeInterval>
    public var reactionDuration: Duration
    /// 同一 `ReactionKey` 的冷却时间。
    public var cooldown: TimeInterval
    /// 看向屏幕持续多久后进入 Attending。
    public var attendingEnter: TimeInterval
    /// 人脸丢失多久后回到 Idle。
    public var idleAfterFaceLost: TimeInterval
    /// 判定"快速靠近"的时间窗，窗内距离缩短超过 `approachDistance` 即触发。
    public var approachWindow: TimeInterval
    public var approachDistance: Float

    public init(
        reactionDelay: ClosedRange<TimeInterval> = 0.3...0.8,
        reactionDuration: Duration = .milliseconds(1500),
        cooldown: TimeInterval = 8,
        attendingEnter: TimeInterval = 0.2,
        idleAfterFaceLost: TimeInterval = 3,
        approachWindow: TimeInterval = 1,
        approachDistance: Float = 0.10
    ) {
        self.reactionDelay = reactionDelay
        self.reactionDuration = reactionDuration
        self.cooldown = cooldown
        self.attendingEnter = attendingEnter
        self.idleAfterFaceLost = idleAfterFaceLost
        self.approachWindow = approachWindow
        self.approachDistance = approachDistance
    }

    public static let defaults = ReactionRules()
}
