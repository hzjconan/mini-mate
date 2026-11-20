import Foundation
import NaturalLanguage

/// Whether a zh sentence embedding exists, plus a sanity check on distances.
public struct NLEmbeddingProbe: CapabilityProbe {
    public let id = CapabilityID.nlEmbeddingChinese

    public init() {}

    public func run() async throws -> CapabilityResult {
        guard let (embedding, note) = Self.loadSentenceEmbedding(for: .simplifiedChinese) else {
            return CapabilityResult(
                id: id,
                status: .unavailable(reason: "无简体中文句向量（含重试与按 revision 加载）"),
                detail: nil,
                duration: .zero
            )
        }
        let smoke = EmbeddingSmokeTest.run { embedding.distance(between: $0, and: $1) }
        return CapabilityResult(
            id: id,
            status: .available,
            detail: [note, smoke.detail].compactMap { $0 }.joined(separator: "；"),
            duration: .zero
        )
    }

    /// On iOS 27 the first `sentenceEmbedding(for:)` call in a process returns nil
    /// even when the asset is installed (001 research.md); retry, then load by revision.
    static func loadSentenceEmbedding(for language: NLLanguage) -> (NLEmbedding, note: String?)? {
        if let embedding = NLEmbedding.sentenceEmbedding(for: language) {
            return (embedding, nil)
        }
        if let embedding = NLEmbedding.sentenceEmbedding(for: language) {
            return (embedding, "首次调用返回 nil，重试成功")
        }
        let revision = NLEmbedding.currentSentenceEmbeddingRevision(for: language)
        if revision > 0, let embedding = NLEmbedding.sentenceEmbedding(for: language, revision: revision) {
            return (embedding, "前两次返回 nil，按 revision \(revision) 加载成功")
        }
        return nil
    }
}

/// Whether the zh contextual embedding model is installed and usable (mean-pooled token vectors).
public struct NLContextualEmbeddingProbe: CapabilityProbe {
    public let id = CapabilityID.nlContextualEmbeddingChinese

    public init() {}

    public func run() async throws -> CapabilityResult {
        let language = NLLanguage.simplifiedChinese
        // Early in a process the first attempt reports no assets and load() fails even though the
        // model is installed; an immediate retry also fails, one ~300 ms later succeeds (001 research.md).
        var notes: [String] = []
        var loaded: NLContextualEmbedding?
        let start = ContinuousClock.now
        for attempt in 1...4 {
            if attempt > 1 { try await Task.sleep(for: .milliseconds(300)) }
            guard let candidate = NLContextualEmbedding(language: language) else {
                return CapabilityResult(
                    id: id,
                    status: .unavailable(reason: "无简体中文上下文嵌入模型"),
                    detail: nil,
                    duration: .zero
                )
            }
            let assetsFlag = candidate.hasAvailableAssets
            do {
                try candidate.load()
                loaded = candidate
                if attempt > 1 {
                    notes.append("第 \(attempt) 次加载成功（hasAvailableAssets=\(assetsFlag)，距首次 \(start.duration(to: .now).formatted(.units(allowed: [.milliseconds])))）")
                }
                break
            } catch {
                notes.append("第 \(attempt) 次 hasAvailableAssets=\(assetsFlag)，load 失败：\(error.localizedDescription)")
            }
        }
        guard let embedding = loaded else {
            return CapabilityResult(
                id: id,
                status: .unavailable(reason: "加载失败：资源未下载，或进程内过早调用（见 001 research.md）"),
                detail: notes.joined(separator: "；"),
                duration: .zero
            )
        }
        defer { embedding.unload() }
        let smoke = try EmbeddingSmokeTest.run { a, b in
            try Self.cosineDistance(
                Self.meanVector(embedding, a, language),
                Self.meanVector(embedding, b, language)
            )
        }
        return CapabilityResult(
            id: id,
            status: .available,
            detail: (notes + ["维度 \(embedding.dimension)", smoke.detail]).joined(separator: "；"),
            duration: .zero
        )
    }

    private static func meanVector(_ embedding: NLContextualEmbedding, _ text: String, _ language: NLLanguage) throws -> [Double] {
        let result = try embedding.embeddingResult(for: text, language: language)
        var sum = [Double](repeating: 0, count: embedding.dimension)
        var count = 0.0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            for i in vector.indices { sum[i] += vector[i] }
            count += 1
            return true
        }
        return count > 0 ? sum.map { $0 / count } : sum
    }

    private static func cosineDistance(_ a: [Double], _ b: [Double]) -> Double {
        let dot = zip(a, b).map(*).reduce(0, +)
        let norms = sqrt(a.map { $0 * $0 }.reduce(0, +)) * sqrt(b.map { $0 * $0 }.reduce(0, +))
        return norms > 0 ? 1 - dot / norms : .nan
    }
}
