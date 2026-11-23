/// 形象自己的情绪。rawValue 即 M2 标签协议中的 `<emo:...>` 值，每个值对应一个 `ExpressionPreset`。
public enum EmotionTag: String, CaseIterable, Codable, Sendable {
    case happy
    case gentle
    case sad
    case surprised
    case shy
    case playful
    case concerned
    case neutral
}
