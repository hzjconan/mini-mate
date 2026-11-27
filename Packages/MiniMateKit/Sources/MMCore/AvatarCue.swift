/// 非对话轮次的形象提示（如 005 拍照流程的准备/倒数/完成表现），经 `ConversationEvent.assistantCue` 进入情绪状态机。
public struct AvatarCue: Sendable, Equatable, Codable {
    public let emotion: EmotionTag
    public let action: ActionTag?
    public let hold: Bool

    public init(
        emotion: EmotionTag,
        action: ActionTag? = nil,
        hold: Bool = false
    ) {
        self.emotion = emotion
        self.action = action
        self.hold = hold
    }
}
