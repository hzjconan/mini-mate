import Foundation
import FoundationModels

/// V1: whether the on-device Foundation Models can be used at all.
public struct FoundationModelsProbe: CapabilityProbe {
    public let id = CapabilityID.foundationModels

    public init() {}

    public func run() async throws -> CapabilityResult {
        let status: CapabilityStatus
        switch SystemLanguageModel.default.availability {
        case .available:
            status = .available
        case .unavailable(let reason):
            status = .unavailable(reason: reason.chineseDescription)
        }
        return CapabilityResult(id: id, status: status, detail: nil, duration: .zero)
    }
}

/// V1 中文支持：模型可用时检查支持语言列表是否包含中文。
public struct FoundationModelsChineseProbe: CapabilityProbe {
    public let id = CapabilityID.foundationModelsChinese

    public init() {}

    public func run() async throws -> CapabilityResult {
        guard case .available = SystemLanguageModel.default.availability else {
            return CapabilityResult(
                id: id,
                status: .unavailable(reason: "Foundation Models 不可用"),
                detail: nil,
                duration: .zero
            )
        }
        let languages = SystemLanguageModel.default.supportedLanguages
        let supported = languages.contains { $0.minimalIdentifier.hasPrefix("zh") }
        return CapabilityResult(
            id: id,
            status: supported ? .available : .unavailable(reason: "中文不在支持语言列表中"),
            detail: languages.map(\.minimalIdentifier).joined(separator: ", "),
            duration: .zero
        )
    }
}

extension SystemLanguageModel.Availability.UnavailableReason {
    var chineseDescription: String {
        switch self {
        case .appleIntelligenceNotEnabled: "Apple Intelligence 未开启"
        case .deviceNotEligible: "设备不支持 Apple Intelligence"
        case .modelNotReady: "模型资源尚未就绪（可能仍在下载）"
        default: "未知不可用原因"
        }
    }
}
