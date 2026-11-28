/// 对话事件。M1 仅由调试面板注入，M2 由 ConversationEngine 产出。
public enum ConversationEvent: Sendable, Equatable {
    case userSpeechStarted
    case userSpeechEnded
    case userTranscript(String, isFinal: Bool)
    case userEmotion(UserEmotion)
    case assistantEmotion(EmotionTag)
    case assistantAction(ActionTag)
    case assistantText(String)
    case assistantSpeechStarted
    case assistantSpeechEnded
    /// 0–1 音频电平，驱动口型。
    case assistantAudioLevel(Float)
    /// 005：模型输出的 App 指令，情绪状态机忽略。
    case assistantCommand(AssistantCommand)
    /// 005：非对话轮次的形象提示（emotion-state-machine.md EM-1–EM-5）。
    case assistantCue(AvatarCue)
    /// 005：结束当前保持中的提示。
    case assistantCueEnded
    /// 003：实时会话连接状态变化，不属于对话轮次（conversation-engine.md E-4）。
    case connectionStateChanged(ConnectionState)
    /// 003：收音闸门状态变化（驱动静音姿态与调试面板显示，E-4）。
    case gateStateChanged(GateState)
}
