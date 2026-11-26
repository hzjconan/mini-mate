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
        let rawIn = try container.decodeIfPresent(Double.self, forKey: .blendInMs) ?? 200
        let rawOut = try container.decodeIfPresent(Double.self, forKey: .blendOutMs) ?? 300
        let blendInMs = rawIn.isFinite ? min(max(rawIn, 0), 60_000) : 200
        let blendOutMs = rawOut.isFinite ? min(max(rawOut, 0), 60_000) : 300
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

public enum ExpressionPresetError: Error, Sendable, Equatable {
    case resourceNotFound
    case duplicateEmotion(EmotionTag)
    case missingEmotions([EmotionTag])
    case invalidWeight(emotion: EmotionTag, name: String, value: Float)
}

extension ExpressionPreset {
    /// 从 JSON 数据解码并校验预设字典。
    /// - Parameter requireAllEmotions: 为 true 时强制检查 8 个 `EmotionTag` 齐全，缺项抛 `.missingEmotions`。
    public static func load(
        from data: Data,
        requireAllEmotions: Bool = false
    ) throws -> [EmotionTag: ExpressionPreset] {
        let list = try JSONDecoder().decode([ExpressionPreset].self, from: data)
        var result: [EmotionTag: ExpressionPreset] = [:]
        result.reserveCapacity(list.count)

        for preset in list {
            if result[preset.emotion] != nil {
                throw ExpressionPresetError.duplicateEmotion(preset.emotion)
            }
            for (name, value) in preset.weights {
                guard value.isFinite, value >= 0, value <= 1 else {
                    throw ExpressionPresetError.invalidWeight(emotion: preset.emotion, name: name, value: value)
                }
            }
            result[preset.emotion] = preset
        }

        if requireAllEmotions {
            let missing = EmotionTag.allCases.filter { result[$0] == nil }
            if !missing.isEmpty {
                throw ExpressionPresetError.missingEmotions(missing)
            }
        }

        return result
    }

    /// 从 `Bundle.module` 加载内置 `expression-presets.json`（强制 8 个情绪齐全）。
    public static func loadBundled() throws -> [EmotionTag: ExpressionPreset] {
        guard let url = Bundle.module.url(forResource: "expression-presets", withExtension: "json") else {
            throw ExpressionPresetError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        return try load(from: data, requireAllEmotions: true)
    }

    /// 加载并缓存内置预设；仅在极端资源异常时回退为空字典，供默认参数与 App 启动使用。
    public static let bundledDefaults: [EmotionTag: ExpressionPreset] = (try? loadBundled()) ?? [:]

    /// 按 `EmotionTag.allCases` 顺序编码为格式化 JSON（`[.prettyPrinted, .sortedKeys]`），供调试面板导出。
    public static func encodeJSON(_ presets: [EmotionTag: ExpressionPreset]) throws -> Data {
        let ordered = EmotionTag.allCases.compactMap { presets[$0] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ordered)
    }

    /// 编码单个预设为格式化 JSON，供调试面板单情绪调参导出。
    public static func encodeSingleJSON(_ preset: ExpressionPreset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(preset)
    }
}
