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
}
