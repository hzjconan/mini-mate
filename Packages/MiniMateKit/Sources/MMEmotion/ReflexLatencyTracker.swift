import Foundation
import MMCore
import MMPerception

/// 测量 M_reflex：用户语义表情首次进入（且成功进入状态机计划队列）→ 形象开始应用对应 Reacting 姿态的时间差（秒）。
public struct ReflexLatencyTracker: Sendable, Equatable {
    private struct PendingReflex: Sendable, Equatable {
        let key: ReactionKey
        let expectedEmotion: EmotionTag
        let scheduledTriggerAt: TimeInterval
        let startedAt: TimeInterval
    }

    public let timeout: TimeInterval

    private var previousActiveExpression: UserExpression?
    private var pending: PendingReflex?

    public init(timeout: TimeInterval = 3.0) {
        self.timeout = timeout.isFinite ? max(timeout, 0.1) : 3.0
    }

    /// 在感知帧经状态机 `handle(_:)` 后调用；仅当表情边沿进入且状态机实际为该 key 排程了反应时武装。
    /// 若已追踪同一 `(key, scheduledTriggerAt)` 排程项，保持原 `startedAt` 不覆写。
    public mutating func observePerception(
        activeExpression: UserExpression?,
        state: AvatarState,
        at timestamp: TimeInterval
    ) {
        guard timestamp.isFinite else { return }

        let prev = previousActiveExpression
        previousActiveExpression = activeExpression

        guard activeExpression != prev, let expr = activeExpression else {
            return
        }

        let (key, emotion) = Self.mapping(for: expr)
        guard let scheduledItem = state.scheduled.first(where: { $0.key == key }) else {
            return
        }

        if let existing = pending,
           existing.key == key,
           abs(existing.scheduledTriggerAt - scheduledItem.triggerAt) < 1e-9
        {
            return
        }

        pending = PendingReflex(
            key: key,
            expectedEmotion: emotion,
            scheduledTriggerAt: scheduledItem.triggerAt,
            startedAt: timestamp
        )
    }

    /// 在渲染器应用姿态时调用；当状态首次进入对应 `.reacting`（且无动作，即纯表情反应）时返回单次 M_reflex 样本（秒）。
    public mutating func observeAppliedState(
        _ stateKind: AvatarStateKind,
        at timestamp: TimeInterval
    ) -> TimeInterval? {
        guard timestamp.isFinite, let current = pending else {
            return nil
        }

        let latency = timestamp - current.startedAt
        if latency < 0 || latency >= timeout {
            pending = nil
            return nil
        }

        guard case .reacting(let reaction) = stateKind,
              !reaction.isCue,
              reaction.action == nil,
              reaction.expression == current.expectedEmotion
        else {
            return nil
        }

        pending = nil
        return latency
    }

    public mutating func reset() {
        previousActiveExpression = nil
        pending = nil
    }

    private static func mapping(for expr: UserExpression) -> (ReactionKey, EmotionTag) {
        switch expr {
        case .smiling: (.smile, .happy)
        case .frowning: (.frown, .concerned)
        case .surprised: (.surprise, .surprised)
        }
    }
}
