import Foundation
import Speech

/// V2: whether SpeechTranscriber supports zh-CN and whether assets are installed.
public struct SpeechTranscriberProbe: CapabilityProbe {
    public let id = CapabilityID.speechTranscriberChinese

    public init() {}

    public func run() async throws -> CapabilityResult {
        let supported = await SpeechTranscriber.supportedLocales
        guard let zh = supported.first(where: { $0.identifier.hasPrefix("zh") }) else {
            return CapabilityResult(
                id: id,
                status: .unavailable(reason: "SpeechTranscriber 不支持中文"),
                detail: nil,
                duration: .zero
            )
        }
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier == zh.identifier }) {
            return CapabilityResult(
                id: id,
                status: .available,
                detail: "\(zh.identifier) 资源已安装",
                duration: .zero
            )
        }
        return CapabilityResult(
            id: id,
            status: .unavailable(reason: "支持 \(zh.identifier)，但语言资源尚未下载"),
            detail: "已安装：\(installed.map(\.identifier).joined(separator: ", "))",
            duration: .zero
        )
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
