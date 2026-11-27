import Foundation
import MMCore

/// 测量 M_feedback：从 `userSpeechEnded`（Listening 态）到观测到 `.thinking` 状态的时间差（秒）。
public struct FeedbackLatencyTracker: Sendable, Equatable {
    public let timeout: TimeInterval
    private var pendingStartedAt: TimeInterval?

    public init(timeout: TimeInterval = 3.0) {
        self.timeout = timeout.isFinite ? max(timeout, 0.1) : 3.0
    }

    /// 在 `userSpeechEnded` 送入状态机前调用；仅当 `previousState` 为 `.listening`
    /// （或底层状态为 `.listening` 的非提示 `.reacting`）且 `timestamp.isFinite` 时武装。
    public mutating func observeUserSpeechEnded(
        previousState: AvatarStateKind,
        at timestamp: TimeInterval
    ) {
        guard timestamp.isFinite else { return }
        guard Self.canTransitionToThinking(from: previousState) else { return }
        pendingStartedAt = timestamp
    }

    /// 在状态机产出新状态/渲染应用姿态后调用；首次观测到 `.thinking` 且 `0 <= latency < timeout` 时
    /// 返回单次 M_feedback 样本（秒）并解除武装；超时或负值则清零返回 `nil`。
    public mutating func observeAppliedState(
        _ stateKind: AvatarStateKind,
        at timestamp: TimeInterval
    ) -> TimeInterval? {
        guard timestamp.isFinite, let startedAt = pendingStartedAt else {
            return nil
        }

        let latency = timestamp - startedAt
        if latency < 0 || latency >= timeout {
            pendingStartedAt = nil
            return nil
        }

        guard case .thinking = stateKind else {
            return nil
        }

        pendingStartedAt = nil
        return latency
    }

    public mutating func reset() {
        pendingStartedAt = nil
    }

    private static func canTransitionToThinking(from state: AvatarStateKind) -> Bool {
        switch state {
        case .listening:
            return true
        case .reacting(let reaction) where !reaction.isCue:
            var cursor = reaction.returnTo
            while case .reacting(let inner) = cursor {
                if inner.isCue { return false }
                cursor = inner.returnTo
            }
            return cursor == .listening
        default:
            return false
        }
    }
}
