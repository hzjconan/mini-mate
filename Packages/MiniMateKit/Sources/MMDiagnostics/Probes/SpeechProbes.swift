import Foundation
import Speech

/// V2: whether SpeechTranscriber supports zh-CN (simplified) specifically,
/// and whether its assets are installed.
public struct SpeechTranscriberProbe: CapabilityProbe {
    public let id = CapabilityID.speechTranscriberChinese

    public init() {}

    public func run() async throws -> CapabilityResult {
        let supported = await SpeechTranscriber.supportedLocales
        let zhLocales = supported.filter(Self.isChinese).map(\.identifier)
        let simplified = supported.filter(Self.isSimplifiedChinese).map(\.identifier)
        let installed = await SpeechTranscriber.installedLocales.map(\.identifier)
        let installedSimplified = installed.filter(Self.isSimplifiedIdentifier)

        guard !simplified.isEmpty else {
            return CapabilityResult(
                id: id,
                status: .unavailable(reason: "不支持简体中文"),
                detail: detail(supported: zhLocales, installed: installed),
                duration: .zero
            )
        }
        let detailText = detail(
            supported: zhLocales,
            installed: installed,
            note: "简体支持 \(simplified.joined(separator: ", "))"
        )
        if !installedSimplified.isEmpty {
            return CapabilityResult(
                id: id,
                status: .available,
                detail: detailText,
                duration: .zero
            )
        }
        return CapabilityResult(
            id: id,
            status: .unavailable(reason: "支持简体但资源未下载"),
            detail: detailText,
            duration: .zero
        )
    }

    private func detail(supported: [String], installed: [String], note: String? = nil) -> String {
        [
            note,
            "中文支持：\(supported.isEmpty ? "无" : supported.joined(separator: ", "))",
            "已安装：\(installed.isEmpty ? "无" : installed.joined(separator: ", "))",
        ].compactMap { $0 }.joined(separator: "；")
    }

    private static func isChinese(_ locale: Locale) -> Bool {
        normalized(locale.identifier).hasPrefix("zh")
    }

    private static func isSimplifiedChinese(_ locale: Locale) -> Bool {
        isSimplifiedIdentifier(locale.identifier)
    }

    /// Simplified = zh + Hans/CN/SG marker (zh-CN, zh-Hans, zh-Hans-CN, zh-SG, ...).
    private static func isSimplifiedIdentifier(_ identifier: String) -> Bool {
        let id = normalized(identifier)
        guard id.hasPrefix("zh") else { return false }
        return id.contains("hans") || id.contains("-cn") || id.contains("-sg")
    }

    private static func normalized(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

/// V3: whether SpeechDetector can be constructed and added to a SpeechAnalyzer.
public struct SpeechDetectorProbe: CapabilityProbe {
    public let id = CapabilityID.speechDetector

    public init() {}

    public func run() async throws -> CapabilityResult {
        let detector = SpeechDetector()
        _ = SpeechAnalyzer(modules: [detector])
        return CapabilityResult(id: id, status: .available, detail: nil, duration: .zero)
    }
}
