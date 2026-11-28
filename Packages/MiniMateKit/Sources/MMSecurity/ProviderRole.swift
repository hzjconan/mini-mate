import Foundation

/// Logical role of a user-configured cloud model profile.
public enum ProviderRole: String, CaseIterable, Codable, Sendable, Identifiable {
    case realtimeBrain = "realtime_brain"
    case emotionalTTS = "emotional_tts"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .realtimeBrain:
            "实时语音理解（对话大脑）"
        case .emotionalTTS:
            "情感语音合成（小瓜声音）"
        }
    }

    public var purposeDescription: String {
        switch self {
        case .realtimeBrain:
            "听懂你说的话和语气，决定小瓜要怎么回应（只输出文字与情绪/动作标签）。"
        case .emotionalTTS:
            "把小瓜的话用固定音色和对应情绪念出来。"
        }
    }
}
