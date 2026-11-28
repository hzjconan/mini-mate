import Foundation
import MMCore
import MMSecurity

public enum ProbeArgumentError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingSubcommand
    case unknownSubcommand(String)
    case missingValue(String)
    case missingRequiredOption(String)
    case invalidValue(option: String, value: String, reason: String)
    case unknownOption(String)
    case conflictingOptions(String)

    public var description: String {
        switch self {
        case .missingSubcommand:
            "Missing subcommand. Run `mm-probe --help` for usage."
        case .unknownSubcommand(let name):
            "Unknown subcommand '\(name)'. Run `mm-probe --help` for usage."
        case .missingValue(let option):
            "Missing value for option '\(option)'."
        case .missingRequiredOption(let option):
            "Missing required option '\(option)'."
        case .invalidValue(let option, let value, let reason):
            "Invalid value '\(value)' for option '\(option)': \(reason)"
        case .unknownOption(let option):
            "Unknown option '\(option)'."
        case .conflictingOptions(let message):
            message
        }
    }
}

public struct RealtimeProbeOptions: Sendable, Equatable {
    public let driverID: String
    public let inputPath: String
    public let endpoint: String?
    public let model: String?
    public let keyEnv: String
    public let secondaryEnv: String?
    public let chunkMs: Int
    public let silenceMs: Int
    public let pace: Double
    public let timeoutSeconds: Double
}

public struct ToneSuiteOptions: Sendable, Equatable {
    public let driverID: String
    public let samplesDir: String?
    public let endpoint: String?
    public let model: String?
    public let keyEnv: String
    public let secondaryEnv: String?
    public let chunkMs: Int
    public let silenceMs: Int
    public let pace: Double
    public let timeoutSeconds: Double
    public let allowPartial: Bool
}

public struct TTSProbeOptions: Sendable, Equatable {
    public let driverID: String
    public let text: String
    public let emotions: [EmotionTag]
    public let outputDir: String
    public let voice: String?
    public let endpoint: String?
    public let model: String?
    public let mappingPath: String?
    public let keyEnv: String
    public let secondaryEnv: String?
}

public struct RecordFixtureOptions: Sendable, Equatable {
    public let driverID: String
    public let inputPath: String
    public let outputPath: String
    public let endpoint: String?
    public let model: String?
    public let keyEnv: String
    public let secondaryEnv: String?
    public let chunkMs: Int
    public let silenceMs: Int
    public let pace: Double
    public let timeoutSeconds: Double
}

public enum ProbeCommand: Sendable, Equatable {
    case help
    case listDrivers(role: ProviderRole?)
    case realtime(RealtimeProbeOptions)
    case toneSuite(ToneSuiteOptions)
    case tts(TTSProbeOptions)
    case recordFixture(RecordFixtureOptions)
}

public enum ProbeArguments {
    public static let usageText: String = """
    Usage:
      mm-probe --help | -h
      mm-probe list-drivers [--role <realtime|tts>]
      mm-probe realtime --driver <id> --input <path.wav> [--endpoint <url>] [--model <id>] [--key-env <VAR>] [--secondary-env <VAR>] [--chunk-ms <100>] [--silence-ms <1200>] [--pace <1.0>] [--timeout-s <30>]
      mm-probe tone-suite --driver <id> [--samples-dir <dir>] [--endpoint <url>] [--model <id>] [--key-env <VAR>] [--secondary-env <VAR>] [--chunk-ms <100>] [--silence-ms <1200>] [--pace <1.0>] [--timeout-s <30>] [--allow-partial]
      mm-probe tts --driver <id> --text <string> (--all-emotions | --emotion <tag>) --out <dir> [--voice <id>] [--endpoint <url>] [--model <id>] [--mapping <json>] [--key-env <VAR>] [--secondary-env <VAR>]
      mm-probe record-fixture --driver <id> --input <path.wav> --out <path.jsonl> [--endpoint <url>] [--model <id>] [--key-env <VAR>] [--secondary-env <VAR>] [--chunk-ms <100>] [--silence-ms <1200>] [--pace <1.0>] [--timeout-s <30>]

    Default credential environment variables:
      Realtime / tone-suite / record-fixture: MM_REALTIME_KEY (optional: MM_REALTIME_SECONDARY_SECRET)
      TTS:                                    MM_TTS_KEY      (optional: MM_TTS_SECONDARY_SECRET)
    """

    public static func parse(_ arguments: [String]) throws -> ProbeCommand {
        guard let first = arguments.first else {
            throw ProbeArgumentError.missingSubcommand
        }
        if first == "--help" || first == "-h" {
            return .help
        }

        let rest = Array(arguments.dropFirst())

        switch first {
        case "list-drivers":
            return try parseListDrivers(rest)
        case "realtime":
            return try parseRealtime(rest)
        case "tone-suite":
            return try parseToneSuite(rest)
        case "tts":
            return try parseTTS(rest)
        case "record-fixture":
            return try parseRecordFixture(rest)
        default:
            throw ProbeArgumentError.unknownSubcommand(first)
        }
    }

    // MARK: - Subcommand Parsers

    private static func parseListDrivers(_ args: [String]) throws -> ProbeCommand {
        var role: ProviderRole?
        var index = 0
        while index < args.count {
            let token = args[index]
            switch token {
            case "--help", "-h":
                return .help
            case "--role":
                let value = try nextValue(for: token, in: args, index: &index)
                switch value.lowercased() {
                case "realtime", "realtime_brain":
                    role = .realtimeBrain
                case "tts", "emotional_tts":
                    role = .emotionalTTS
                default:
                    throw ProbeArgumentError.invalidValue(option: token, value: value, reason: "expected 'realtime' or 'tts'")
                }
            default:
                throw ProbeArgumentError.unknownOption(token)
            }
            index += 1
        }
        return .listDrivers(role: role)
    }

    private static func parseRealtime(_ args: [String]) throws -> ProbeCommand {
        var driverID: String?
        var inputPath: String?
        var endpoint: String?
        var model: String?
        var keyEnv = "MM_REALTIME_KEY"
        var secondaryEnv: String? = "MM_REALTIME_SECONDARY_SECRET"
        var chunkMs = 100
        var silenceMs = 1200
        var pace = 1.0
        var timeoutSeconds = 30.0

        var index = 0
        while index < args.count {
            let token = args[index]
            switch token {
            case "--help", "-h":
                return .help
            case "--driver":
                driverID = try nextValue(for: token, in: args, index: &index)
            case "--input":
                inputPath = try nextValue(for: token, in: args, index: &index)
            case "--endpoint":
                endpoint = try nextValue(for: token, in: args, index: &index)
            case "--model":
                model = try nextValue(for: token, in: args, index: &index)
            case "--key-env":
                keyEnv = try nextValue(for: token, in: args, index: &index)
            case "--secondary-env":
                secondaryEnv = try nextValue(for: token, in: args, index: &index)
            case "--chunk-ms":
                chunkMs = try parsePositiveInt(for: token, in: args, index: &index)
            case "--silence-ms":
                silenceMs = try parseNonNegativeInt(for: token, in: args, index: &index)
            case "--pace":
                pace = try parseNonNegativeDouble(for: token, in: args, index: &index)
            case "--timeout-s":
                timeoutSeconds = try parsePositiveDouble(for: token, in: args, index: &index)
            default:
                throw ProbeArgumentError.unknownOption(token)
            }
            index += 1
        }

        guard let driverID, !driverID.isEmpty else {
            throw ProbeArgumentError.missingRequiredOption("--driver")
        }
        guard let inputPath, !inputPath.isEmpty else {
            throw ProbeArgumentError.missingRequiredOption("--input")
        }

        return .realtime(RealtimeProbeOptions(
            driverID: driverID,
            inputPath: inputPath,
            endpoint: endpoint,
            model: model,
            keyEnv: keyEnv,
            secondaryEnv: secondaryEnv,
            chunkMs: chunkMs,
            silenceMs: silenceMs,
            pace: pace,
            timeoutSeconds: timeoutSeconds
        ))
    }

    private static func parseToneSuite(_ args: [String]) throws -> ProbeCommand {
        var driverID: String?
        var samplesDir: String?
        var endpoint: String?
        var model: String?
        var keyEnv = "MM_REALTIME_KEY"
        var secondaryEnv: String? = "MM_REALTIME_SECONDARY_SECRET"
        var chunkMs = 100
        var silenceMs = 1200
        var pace = 1.0
        var timeoutSeconds = 30.0
        var allowPartial = false

        var index = 0
        while index < args.count {
            let token = args[index]
            switch token {
            case "--help", "-h":
                return .help
            case "--driver":
                driverID = try nextValue(for: token, in: args, index: &index)
            case "--samples-dir":
                samplesDir = try nextValue(for: token, in: args, index: &index)
            case "--endpoint":
                endpoint = try nextValue(for: token, in: args, index: &index)
            case "--model":
                model = try nextValue(for: token, in: args, index: &index)
            case "--key-env":
                keyEnv = try nextValue(for: token, in: args, index: &index)
            case "--secondary-env":
                secondaryEnv = try nextValue(for: token, in: args, index: &index)
            case "--chunk-ms":
                chunkMs = try parsePositiveInt(for: token, in: args, index: &index)
            case "--silence-ms":
                silenceMs = try parseNonNegativeInt(for: token, in: args, index: &index)
            case "--pace":
                pace = try parseNonNegativeDouble(for: token, in: args, index: &index)
            case "--timeout-s":
                timeoutSeconds = try parsePositiveDouble(for: token, in: args, index: &index)
            case "--allow-partial":
                allowPartial = true
            default:
                throw ProbeArgumentError.unknownOption(token)
            }
            index += 1
        }

        guard let driverID, !driverID.isEmpty else {
            throw ProbeArgumentError.missingRequiredOption("--driver")
        }

        return .toneSuite(ToneSuiteOptions(
            driverID: driverID,
            samplesDir: samplesDir,
            endpoint: endpoint,
            model: model,
            keyEnv: keyEnv,
            secondaryEnv: secondaryEnv,
            chunkMs: chunkMs,
            silenceMs: silenceMs,
            pace: pace,
            timeoutSeconds: timeoutSeconds,
            allowPartial: allowPartial
        ))
    }

    private static func parseTTS(_ args: [String]) throws -> ProbeCommand {
        var driverID: String?
        var text: String?
        var allEmotions = false
        var singleEmotion: EmotionTag?
        var outputDir: String?
        var voice: String?
        var endpoint: String?
        var model: String?
        var mappingPath: String?
        var keyEnv = "MM_TTS_KEY"
        var secondaryEnv: String? = "MM_TTS_SECONDARY_SECRET"

        var index = 0
        while index < args.count {
            let token = args[index]
            switch token {
            case "--help", "-h":
                return .help
            case "--driver":
                driverID = try nextValue(for: token, in: args, index: &index)
            case "--text":
                text = try nextValue(for: token, in: args, index: &index)
            case "--all-emotions":
                allEmotions = true
            case "--emotion":
                let raw = try nextValue(for: token, in: args, index: &index)
                guard let parsed = EmotionTag(rawValue: raw) else {
                    throw ProbeArgumentError.invalidValue(
                        option: token,
                        value: raw,
                        reason: "expected one of \(EmotionTag.allCases.map(\.rawValue).joined(separator: ", "))"
                    )
                }
                singleEmotion = parsed
            case "--out":
                outputDir = try nextValue(for: token, in: args, index: &index)
            case "--voice":
                voice = try nextValue(for: token, in: args, index: &index)
            case "--endpoint":
                endpoint = try nextValue(for: token, in: args, index: &index)
            case "--model":
                model = try nextValue(for: token, in: args, index: &index)
            case "--mapping":
                mappingPath = try nextValue(for: token, in: args, index: &index)
            case "--key-env":
                keyEnv = try nextValue(for: token, in: args, index: &index)
            case "--secondary-env":
                secondaryEnv = try nextValue(for: token, in: args, index: &index)
            default:
                throw ProbeArgumentError.unknownOption(token)
            }
            index += 1
        }

        guard let driverID, !driverID.isEmpty else {
            throw ProbeArgumentError.missingRequiredOption("--driver")
        }
        guard let text, !text.isEmpty else {
            throw ProbeArgumentError.missingRequiredOption("--text")
        }
        guard let outputDir, !outputDir.isEmpty else {
            throw ProbeArgumentError.missingRequiredOption("--out")
        }
        if allEmotions && singleEmotion != nil {
            throw ProbeArgumentError.conflictingOptions("Cannot pass both --all-emotions and --emotion.")
        }
        let emotions: [EmotionTag]
        if allEmotions {
            emotions = EmotionTag.allCases
        } else if let singleEmotion {
            emotions = [singleEmotion]
        } else {
            throw ProbeArgumentError.missingRequiredOption("--all-emotions or --emotion")
        }

        return .tts(TTSProbeOptions(
            driverID: driverID,
            text: text,
            emotions: emotions,
            outputDir: outputDir,
            voice: voice,
            endpoint: endpoint,
            model: model,
            mappingPath: mappingPath,
            keyEnv: keyEnv,
            secondaryEnv: secondaryEnv
        ))
    }

    private static func parseRecordFixture(_ args: [String]) throws -> ProbeCommand {
        var driverID: String?
        var inputPath: String?
        var outputPath: String?
        var endpoint: String?
        var model: String?
        var keyEnv = "MM_REALTIME_KEY"
        var secondaryEnv: String? = "MM_REALTIME_SECONDARY_SECRET"
        var chunkMs = 100
        var silenceMs = 1200
        var pace = 1.0
        var timeoutSeconds = 30.0

        var index = 0
        while index < args.count {
            let token = args[index]
            switch token {
            case "--help", "-h":
                return .help
            case "--driver":
                driverID = try nextValue(for: token, in: args, index: &index)
            case "--input":
                inputPath = try nextValue(for: token, in: args, index: &index)
            case "--out":
                outputPath = try nextValue(for: token, in: args, index: &index)
            case "--endpoint":
                endpoint = try nextValue(for: token, in: args, index: &index)
            case "--model":
                model = try nextValue(for: token, in: args, index: &index)
            case "--key-env":
                keyEnv = try nextValue(for: token, in: args, index: &index)
            case "--secondary-env":
                secondaryEnv = try nextValue(for: token, in: args, index: &index)
            case "--chunk-ms":
                chunkMs = try parsePositiveInt(for: token, in: args, index: &index)
            case "--silence-ms":
                silenceMs = try parseNonNegativeInt(for: token, in: args, index: &index)
            case "--pace":
                pace = try parseNonNegativeDouble(for: token, in: args, index: &index)
            case "--timeout-s":
                timeoutSeconds = try parsePositiveDouble(for: token, in: args, index: &index)
            default:
                throw ProbeArgumentError.unknownOption(token)
            }
            index += 1
        }

        guard let driverID, !driverID.isEmpty else {
            throw ProbeArgumentError.missingRequiredOption("--driver")
        }
        guard let inputPath, !inputPath.isEmpty else {
            throw ProbeArgumentError.missingRequiredOption("--input")
        }
        guard let outputPath, !outputPath.isEmpty else {
            throw ProbeArgumentError.missingRequiredOption("--out")
        }

        return .recordFixture(RecordFixtureOptions(
            driverID: driverID,
            inputPath: inputPath,
            outputPath: outputPath,
            endpoint: endpoint,
            model: model,
            keyEnv: keyEnv,
            secondaryEnv: secondaryEnv,
            chunkMs: chunkMs,
            silenceMs: silenceMs,
            pace: pace,
            timeoutSeconds: timeoutSeconds
        ))
    }

    // MARK: - Primitive Parsers

    private static func nextValue(for option: String, in args: [String], index: inout Int) throws -> String {
        let nextIndex = index + 1
        guard nextIndex < args.count else {
            throw ProbeArgumentError.missingValue(option)
        }
        index = nextIndex
        return args[nextIndex]
    }

    private static func parsePositiveInt(for option: String, in args: [String], index: inout Int) throws -> Int {
        let raw = try nextValue(for: option, in: args, index: &index)
        guard let value = Int(raw), value > 0 else {
            throw ProbeArgumentError.invalidValue(option: option, value: raw, reason: "expected integer > 0")
        }
        return value
    }

    private static func parseNonNegativeInt(for option: String, in args: [String], index: inout Int) throws -> Int {
        let raw = try nextValue(for: option, in: args, index: &index)
        guard let value = Int(raw), value >= 0 else {
            throw ProbeArgumentError.invalidValue(option: option, value: raw, reason: "expected integer >= 0")
        }
        return value
    }

    private static func parseNonNegativeDouble(for option: String, in args: [String], index: inout Int) throws -> Double {
        let raw = try nextValue(for: option, in: args, index: &index)
        guard let value = Double(raw), value.isFinite, value >= 0 else {
            throw ProbeArgumentError.invalidValue(option: option, value: raw, reason: "expected number >= 0")
        }
        return value
    }

    private static func parsePositiveDouble(for option: String, in args: [String], index: inout Int) throws -> Double {
        let raw = try nextValue(for: option, in: args, index: &index)
        guard let value = Double(raw), value.isFinite, value > 0 else {
            throw ProbeArgumentError.invalidValue(option: option, value: raw, reason: "expected number > 0")
        }
        return value
    }
}
