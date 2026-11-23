/// 形象的动作。rawValue 必须与 USDZ 中的动画名称逐字一致。
public enum ActionTag: String, CaseIterable, Codable, Sendable {
    case nod
    case wave
    case spin
    case heart
    case shyCover
    case leanBack
    case lookAround
    case notice
}
