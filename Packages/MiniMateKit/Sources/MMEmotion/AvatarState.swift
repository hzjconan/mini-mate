import Foundation
import MMCore

/// 形象自身的状态。`reacting` 携带反应内容，结束后回到 `returnTo`。
public indirect enum AvatarStateKind: Sendable, Equatable {
    case idle
    case attending
    case listening
    case thinking
    case speaking(EmotionTag)
    case reacting(Reaction)
}

/// 一次由感知触发或事件指定的回应。
public struct Reaction: Sendable, Equatable {
    public let expression: EmotionTag
    public let action: ActionTag?
    public let duration: Duration
    public let returnTo: AvatarStateKind
    /// 是否来自 `assistantCue`（EM-1–EM-5）：为 true 时不可被感知反应打断，且不写入感知冷却。
    public let isCue: Bool
    /// 提示是否保持到下一个 `assistantCue` 或 `assistantCueEnded`（EM-4）。
    public let holdsUntilEnded: Bool

    public init(
        expression: EmotionTag,
        action: ActionTag? = nil,
        duration: Duration = .milliseconds(1500),
        returnTo: AvatarStateKind,
        isCue: Bool = false,
        holdsUntilEnded: Bool = false
    ) {
        self.expression = expression
        self.action = action
        self.duration = duration
        self.returnTo = returnTo
        self.isCue = isCue
        self.holdsUntilEnded = holdsUntilEnded
    }
}

/// 计划在未来某时刻触发的反应，用于实现随机延迟。
public struct ScheduledReaction: Sendable, Equatable {
    public let key: ReactionKey
    public let reaction: Reaction
    public let triggerAt: TimeInterval

    public init(key: ReactionKey, reaction: Reaction, triggerAt: TimeInterval) {
        self.key = key
        self.reaction = reaction
        self.triggerAt = triggerAt
    }
}

public struct AvatarState: Sendable, Equatable {
    public let kind: AvatarStateKind
    public let enteredAt: TimeInterval
    /// 底色情绪，如收到 `userEmotion(.sad)` 后为 `concerned`。
    public let baseEmotion: EmotionTag
    /// 各类反应的冷却到期时间。
    public let cooldowns: [ReactionKey: TimeInterval]
    public let scheduled: [ScheduledReaction]
    public let lastFaceSeenAt: TimeInterval?
    /// 当前保持中（或对话期间暂存待恢复）的形象提示（EM-2、EM-4、EM-5）。
    public let heldCue: AvatarCue?

    public init(
        kind: AvatarStateKind = .idle,
        enteredAt: TimeInterval = 0,
        baseEmotion: EmotionTag = .neutral,
        cooldowns: [ReactionKey: TimeInterval] = [:],
        scheduled: [ScheduledReaction] = [],
        lastFaceSeenAt: TimeInterval? = nil,
        heldCue: AvatarCue? = nil
    ) {
        self.kind = kind
        self.enteredAt = enteredAt
        self.baseEmotion = baseEmotion
        self.cooldowns = cooldowns
        self.scheduled = scheduled
        self.lastFaceSeenAt = lastFaceSeenAt
        self.heldCue = heldCue
    }
}
