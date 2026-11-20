import Foundation

/// Checks that an embedding ranks a paraphrase closer than an unrelated sentence.
/// Only a smoke test: it reports how many triples are ordered, it does not judge quality.
enum EmbeddingSmokeTest {
    struct Triple: Sendable {
        let anchor: String
        let near: String
        let far: String
    }

    struct Outcome: Sendable, Equatable {
        let ordered: Int
        let total: Int
        /// e.g. "近<远 2/3：0.372<0.443，0.486<0.605，0.469>0.401"
        let detail: String
    }

    static let defaultTriples = [
        Triple(anchor: "今天天气很好", near: "今天天气不错", far: "我昨天睡得很晚"),
        Triple(anchor: "我想听首歌", near: "放点音乐吧", far: "帮我关灯"),
        Triple(anchor: "我有点难过", near: "心情不太好", far: "明天要开会"),
    ]

    static func run(
        _ triples: [Triple] = defaultTriples,
        distance: (String, String) throws -> Double
    ) rethrows -> Outcome {
        var ordered = 0
        var cells: [String] = []
        for triple in triples {
            let near = try distance(triple.anchor, triple.near)
            let far = try distance(triple.anchor, triple.far)
            if near < far { ordered += 1 }
            let sign = near < far ? "<" : (near == far ? "=" : ">")
            cells.append(String(format: "%.3f%@%.3f", near, sign, far))
        }
        return Outcome(
            ordered: ordered,
            total: triples.count,
            detail: "近<远 \(ordered)/\(triples.count)：" + cells.joined(separator: "，")
        )
    }
}
