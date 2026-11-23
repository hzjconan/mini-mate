/// 用户语气。M1 由调试面板注入，M2 起由模型给出。
public enum UserEmotion: String, CaseIterable, Codable, Sendable {
    case happy
    case calm
    case sad
    case tired
    case angry
    case anxious
}
