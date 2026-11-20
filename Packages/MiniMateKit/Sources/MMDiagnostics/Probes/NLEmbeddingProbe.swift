import Foundation
import NaturalLanguage

/// Whether a zh sentence embedding exists, plus a sanity check on distances.
public struct NLEmbeddingProbe: CapabilityProbe {
    public let id = CapabilityID.nlEmbeddingChinese

    public init() {}

    public func run() async throws -> CapabilityResult {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese) else {
            return CapabilityResult(
                id: id,
                status: .unavailable(reason: "无简体中文句向量"),
                detail: nil,
                duration: .zero
            )
        }
        let near = embedding.distance(between: "今天天气很好", and: "今天天气不错")
        let far = embedding.distance(between: "今天天气很好", and: "我昨天睡得很晚")
        let detail = String(format: "近义句距离 %.3f，远义句距离 %.3f", near, far)
        guard near < far else {
            return CapabilityResult(
                id: id,
                status: .error(message: "近义句距离不小于远义句"),
                detail: detail,
                duration: .zero
            )
        }
        return CapabilityResult(id: id, status: .available, detail: detail, duration: .zero)
    }
}
