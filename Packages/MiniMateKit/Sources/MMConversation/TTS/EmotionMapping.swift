import Foundation
import MMCore
import MMSecurity

/// 厂商情感参数 JSON 标量值。
public enum JSONScalar: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // 必须按 Bool → Double → String 顺序解码，避免布尔值被误判为数字
        if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            guard doubleVal.isFinite else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Non-finite number in JSONScalar"
                )
            }
            self = .number(doubleVal)
        } else if let stringVal = try? container.decode(String.self) {
            self = .string(stringVal)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSONScalar value (expected Bool, Double, or String)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }
}

/// 单个情绪对应的厂商参数集合（JSON 中直接编码/解码为平面对象 `{ ... }`）。
public struct VendorEmotionParams: Sendable, Equatable, Codable {
    public let parameters: [String: JSONScalar]
    public static let empty = VendorEmotionParams([:])

    public init(_ parameters: [String: JSONScalar] = [:]) {
        self.parameters = parameters
    }

    public var isEmpty: Bool { parameters.isEmpty }

    public func string(_ key: String) -> String? {
        if case .string(let v) = parameters[key] { return v }
        return nil
    }

    public func number(_ key: String) -> Double? {
        if case .number(let v) = parameters[key] { return v }
        return nil
    }

    public func bool(_ key: String) -> Bool? {
        if case .bool(let v) = parameters[key] { return v }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.parameters = try container.decode([String: JSONScalar].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(parameters)
    }
}

/// `TTSEmotionMapping` 加载与校验错误。
public enum TTSEmotionMappingError: Error, Sendable, Equatable {
    case resourceNotFound(VendorID)
    case emptyVoice
    case unknownEmotionKey(String)
    case missingNeutralMapping
}

/// 厂商 TTS 音色与情绪参数映射表（contracts/tts-provider.md）。
public struct TTSEmotionMapping: Sendable, Equatable, Codable {
    public let vendor: VendorID
    public let voice: String
    public let map: [EmotionTag: VendorEmotionParams]

    private enum CodingKeys: String, CodingKey {
        case vendor
        case voice
        case map
    }

    public init(vendor: VendorID, voice: String, map: [EmotionTag: VendorEmotionParams]) {
        self.vendor = vendor
        self.voice = voice
        self.map = map
    }

    /// TTS-2：返回指定情绪的参数；缺失时回退至 `.neutral`，若手工构造且连 `.neutral` 也缺失则回退 `.empty`。
    public func params(for emotion: EmotionTag) -> VendorEmotionParams {
        map[emotion] ?? map[.neutral] ?? .empty
    }

    /// 解码 JSON 并校验：`voice` 去空白后非空（TTS-1）、`map` 中每个键必须为合法 `EmotionTag.rawValue`、`map[.neutral]` 必存在。
    public static func load(from data: Data) throws -> TTSEmotionMapping {
        let mapping = try JSONDecoder().decode(TTSEmotionMapping.self, from: data)
        guard !mapping.voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TTSEmotionMappingError.emptyVoice
        }
        guard mapping.map[.neutral] != nil else {
            throw TTSEmotionMappingError.missingNeutralMapping
        }
        return mapping
    }

    /// 从 `Bundle.module` 根目录加载 `tts-emotion-<vendor>.json`；不存在抛 `.resourceNotFound(vendor)`。
    public static func loadBundled(for vendor: VendorID) throws -> TTSEmotionMapping {
        let resourceName = "tts-emotion-\(vendor.rawValue)"
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw TTSEmotionMappingError.resourceNotFound(vendor)
        }
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.vendor = try container.decode(VendorID.self, forKey: .vendor)
        self.voice = try container.decode(String.self, forKey: .voice)

        // 手动经 [String: VendorEmotionParams] 解码为 JSON 对象，避免 Swift 默认把枚举键编解码成交替数组
        let rawMap = try container.decode([String: VendorEmotionParams].self, forKey: .map)
        var parsedMap: [EmotionTag: VendorEmotionParams] = [:]
        parsedMap.reserveCapacity(rawMap.count)
        for (key, value) in rawMap {
            guard let emotion = EmotionTag(rawValue: key) else {
                throw TTSEmotionMappingError.unknownEmotionKey(key)
            }
            parsedMap[emotion] = value
        }
        self.map = parsedMap
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vendor, forKey: .vendor)
        try container.encode(voice, forKey: .voice)

        var rawMap: [String: VendorEmotionParams] = [:]
        rawMap.reserveCapacity(map.count)
        for (emotion, params) in map {
            rawMap[emotion.rawValue] = params
        }
        try container.encode(rawMap, forKey: .map)
    }
}
