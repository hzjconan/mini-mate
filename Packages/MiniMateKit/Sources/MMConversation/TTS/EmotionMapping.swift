import Foundation
import MMCore

/// Emotion parameter JSON scalar value.
public enum JSONScalar: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Decode in Bool -> Double -> String order so booleans are not misread as numbers.
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

/// Driver-specific parameter bag for a single emotion (encoded as flat JSON object `{ ... }`).
public struct EmotionParameterSet: Sendable, Equatable, Codable {
    public let parameters: [String: JSONScalar]
    public static let empty = EmotionParameterSet([:])

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

/// Loading and validation errors for `TTSEmotionMapping`.
public enum TTSEmotionMappingError: Error, Sendable, Equatable {
    case resourceNotFound(String)
    case emptyDriverID
    case emptyVoice
    case unknownEmotionKey(String)
    case missingNeutralMapping
}

/// Voice and per-emotion parameter mapping table for a TTS driver (contracts/tts-provider.md).
public struct TTSEmotionMapping: Sendable, Equatable, Codable {
    public let driverID: String
    public let voice: String
    public let map: [EmotionTag: EmotionParameterSet]

    private enum CodingKeys: String, CodingKey {
        case driverID
        case voice
        case map
    }

    public init(driverID: String, voice: String, map: [EmotionTag: EmotionParameterSet]) {
        self.driverID = driverID
        self.voice = voice
        self.map = map
    }

    /// TTS-2: returns parameters for `emotion`, falling back to `.neutral` or `.empty`.
    public func params(for emotion: EmotionTag) -> EmotionParameterSet {
        map[emotion] ?? map[.neutral] ?? .empty
    }

    /// Decodes JSON and validates non-empty `driverID`, non-empty `voice` (TTS-1),
    /// valid `EmotionTag` keys, and required `.neutral` entry.
    public static func load(from data: Data) throws -> TTSEmotionMapping {
        let mapping = try JSONDecoder().decode(TTSEmotionMapping.self, from: data)
        guard !mapping.driverID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TTSEmotionMappingError.emptyDriverID
        }
        guard !mapping.voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TTSEmotionMappingError.emptyVoice
        }
        guard mapping.map[.neutral] != nil else {
            throw TTSEmotionMappingError.missingNeutralMapping
        }
        return mapping
    }

    /// Loads and validates a mapping JSON file from disk.
    public static func load(fromFile url: URL) throws -> TTSEmotionMapping {
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    /// Loads `tts-emotion-<driverID>.json` from `Bundle.module` root; throws `.resourceNotFound(driverID)` if absent.
    public static func loadBundled(for driverID: String) throws -> TTSEmotionMapping {
        let trimmed = driverID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TTSEmotionMappingError.emptyDriverID
        }
        let resourceName = "tts-emotion-\(trimmed)"
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw TTSEmotionMappingError.resourceNotFound(trimmed)
        }
        return try load(fromFile: url)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.driverID = try container.decode(String.self, forKey: .driverID)
        self.voice = try container.decode(String.self, forKey: .voice)

        // Decode via [String: EmotionParameterSet] so JSON objects are used instead of alternating arrays.
        let rawMap = try container.decode([String: EmotionParameterSet].self, forKey: .map)
        var parsedMap: [EmotionTag: EmotionParameterSet] = [:]
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
        try container.encode(driverID, forKey: .driverID)
        try container.encode(voice, forKey: .voice)

        var rawMap: [String: EmotionParameterSet] = [:]
        rawMap.reserveCapacity(map.count)
        for (emotion, params) in map {
            rawMap[emotion.rawValue] = params
        }
        try container.encode(rawMap, forKey: .map)
    }
}
