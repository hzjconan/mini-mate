import Foundation
import MMCore

/// 表情预设：满强度时的 blendShape 权重。
///
/// 以 JSON 资源保存（`Sources/MMEmotion/Resources/expression-presets.json`），
/// 时长字段写作 `blendInMs` / `blendOutMs`（毫秒），便于手动调参：
///
/// ```json
/// { "emotion": "happy", "weights": { "mouthSmileLeft": 0.8 }, "blendInMs": 200, "blendOutMs": 300 }
/// ```
public struct ExpressionPreset: Codable, Sendable, Equatable {
    public let emotion: EmotionTag
    public let weights: [String: Float]
    public let blendIn: Duration
    public let blendOut: Duration

    public init(
        emotion: EmotionTag,
        weights: [String: Float],
        blendIn: Duration = .milliseconds(200),
        blendOut: Duration = .milliseconds(300)
    ) {
        self.emotion = emotion
        self.weights = weights
        self.blendIn = blendIn
        self.blendOut = blendOut
    }

    private enum CodingKeys: String, CodingKey {
        case emotion
        case weights
        case blendInMs
        case blendOutMs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        emotion = try container.decode(EmotionTag.self, forKey: .emotion)
        weights = try container.decode([String: Float].self, forKey: .weights)
        let blendInMs = try container.decodeIfPresent(Double.self, forKey: .blendInMs) ?? 200
        let blendOutMs = try container.decodeIfPresent(Double.self, forKey: .blendOutMs) ?? 300
        blendIn = .milliseconds(Int64(blendInMs.rounded()))
        blendOut = .milliseconds(Int64(blendOutMs.rounded()))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(emotion, forKey: .emotion)
        try container.encode(weights, forKey: .weights)
        try container.encode(Self.milliseconds(blendIn), forKey: .blendInMs)
        try container.encode(Self.milliseconds(blendOut), forKey: .blendOutMs)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
