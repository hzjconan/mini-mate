import Foundation

/// Identifier for each probed capability; declaration order defines report row order.
public enum CapabilityID: String, CaseIterable, Sendable {
    case foundationModels
    case foundationModelsChinese
    case speechTranscriberChinese
    case speechDetector
    case nlEmbeddingChinese
    case arFaceTracking

    /// Row label in the exported report; mirrors `research.md` 的实测结果表.
    public var title: String {
        switch self {
        case .foundationModels: "V1 Foundation Models"
        case .foundationModelsChinese: "V1 中文支持"
        case .speechTranscriberChinese: "V2 SpeechTranscriber zh-CN"
        case .speechDetector: "V3 SpeechDetector"
        case .nlEmbeddingChinese: "NLEmbedding 中文"
        case .arFaceTracking: "ARKit 人脸追踪"
        }
    }
}

public enum CapabilityStatus: Sendable, Equatable {
    case available
    case unavailable(reason: String)
    case error(message: String)

    /// Cell text for the 结果 column.
    public var label: String {
        switch self {
        case .available: "可用"
        case .unavailable: "不可用"
        case .error: "出错"
        }
    }

    /// The reason or message carried by unavailable/error statuses.
    public var reason: String? {
        switch self {
        case .available: nil
        case .unavailable(let reason), .error(let reason): reason
        }
    }
}

public struct CapabilityResult: Sendable, Equatable, Identifiable {
    public let id: CapabilityID
    public let status: CapabilityStatus
    public let detail: String?
    public let duration: Duration

    public init(id: CapabilityID, status: CapabilityStatus, detail: String?, duration: Duration) {
        self.id = id
        self.status = status
        self.detail = detail
        self.duration = duration
    }
}

/// Device context for a report; on iOS `model` is the machine identifier (e.g. iPhone17,2).
public struct DeviceInfo: Sendable {
    public let model: String
    public let systemVersion: String

    public init(model: String, systemVersion: String) {
        self.model = model
        self.systemVersion = systemVersion
    }

    public static var current: DeviceInfo {
        var uts = utsname()
        uname(&uts)
        let model = withUnsafePointer(to: &uts.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceInfo(
            model: model,
            systemVersion: "\(version.majorVersion).\(version.minorVersion)"
        )
    }
}

/// One diagnostics run: device context plus per-capability results.
public struct CapabilityReport: Sendable {
    public let deviceModel: String
    public let systemVersion: String
    public let createdAt: Date
    public let results: [CapabilityResult]

    public init(deviceModel: String, systemVersion: String, createdAt: Date, results: [CapabilityResult]) {
        self.deviceModel = deviceModel
        self.systemVersion = systemVersion
        self.createdAt = createdAt
        self.results = results
    }

    /// Markdown table suitable for pasting into `research.md`.
    public func markdown() -> String {
        var lines = [
            "- 设备：\(deviceModel)",
            "- 系统：\(systemVersion)",
            "- 时间：\(createdAt.formatted(.iso8601))",
            "",
            "| 项 | 结果 | 原因 | 耗时 |",
            "| --- | --- | --- | --- |",
        ]
        for result in sortedResults {
            lines.append("| \(result.id.title) | \(result.status.label) | \(reasonCell(result)) | \(durationCell(result)) |")
        }
        return lines.joined(separator: "\n")
    }

    /// Results in CapabilityID declaration order, regardless of completion order.
    private var sortedResults: [CapabilityResult] {
        let order = Dictionary(uniqueKeysWithValues: CapabilityID.allCases.enumerated().map { ($1, $0) })
        return results.sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    }

    private func reasonCell(_ result: CapabilityResult) -> String {
        let text = [result.status.reason, result.detail]
            .compactMap { $0 }
            .joined(separator: "；")
        return escaped(text.isEmpty ? "—" : text)
    }

    private func durationCell(_ result: CapabilityResult) -> String {
        let seconds = Double(result.duration.components.seconds)
            + Double(result.duration.components.attoseconds) / 1e18
        return String(format: "%.2f s", seconds)
    }

    private func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
