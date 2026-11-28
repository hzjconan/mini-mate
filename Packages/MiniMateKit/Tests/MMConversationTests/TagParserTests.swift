import Foundation
import Testing
import MMCore
@testable import MMConversation

/// 用于比较的相邻 `.text` 合并辅助函数。
private func coalescingText(_ segments: [TaggedSegment]) -> [TaggedSegment] {
    var result: [TaggedSegment] = []
    for seg in segments {
        if case .text(let rhs) = seg, case .text(let lhs) = result.last {
            result[result.count - 1] = .text(lhs + rhs)
        } else {
            result.append(seg)
        }
    }
    return result
}

/// 确定性线性同余伪随机数生成器，用于参数化随机切分。
private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int((state >> 16) % span)
    }
}

enum ChunkStrategy: Sendable, CustomTestStringConvertible {
    case perCharacter
    case fixedStep(Int)
    case randomSeed(UInt64)

    var testDescription: String {
        switch self {
        case .perCharacter: "perCharacter"
        case .fixedStep(let n): "fixedStep(\(n))"
        case .randomSeed(let seed): "randomSeed(\(seed))"
        }
    }

    func split(_ input: String) -> [String] {
        let chars = Array(input)
        switch self {
        case .perCharacter:
            return chars.map { String($0) }
        case .fixedStep(let step):
            var chunks: [String] = []
            var idx = 0
            while idx < chars.count {
                let end = min(idx + step, chars.count)
                chunks.append(String(chars[idx..<end]))
                idx = end
            }
            return chunks
        case .randomSeed(let seed):
            var rng = SeededRNG(seed: seed)
            var chunks: [String] = []
            var idx = 0
            while idx < chars.count {
                let len = rng.nextInt(in: 1...6)
                let end = min(idx + len, chars.count)
                chunks.append(String(chars[idx..<end]))
                idx = end
            }
            return chunks
        }
    }
}

private let randomChunkStrategies: [ChunkStrategy] =
    [.perCharacter, .fixedStep(2), .fixedStep(3), .fixedStep(5), .fixedStep(7)]
    + (1...20).map { ChunkStrategy.randomSeed(UInt64($0 * 7919)) }

@Suite("TagParser 流式标签解析（T-1–T-10）")
struct TagParserTests {

    @Test("正例：完整对话样例精确产出序列且零警告")
    func fullConversationExample() {
        var parser = TagParser()
        let input = "<user:tired><emo:gentle>今天累坏了吧？<act:nod>先歇会儿，我陪着你。<cmd:photo>"
        let output = parser.feed(input) + parser.finish()

        #expect(output == [
            .userEmotion(.tired),
            .emotion(.gentle),
            .text("今天累坏了吧？"),
            .action(.nod),
            .text("先歇会儿，我陪着你。"),
            .command(.photo),
        ])
        #expect(parser.warnings.isEmpty)
    }

    @Test("T-1：标签跨 2/3 个增量切分与整段输入完全一致")
    func splitAcrossDeltas() {
        let full = "<user:happy><emo:happy>哇！<act:spin>好的<cmd:photoCancel>"
        var whole = TagParser()
        let expected = whole.feed(full) + whole.finish()

        var streamed = TagParser()
        let deltas = ["<us", "er:ha", "ppy><em", "o:happy>哇！<a", "ct:sp", "in>好的<cm", "d:photo", "Cancel>"]
        var actual: [TaggedSegment] = []
        for delta in deltas {
            actual.append(contentsOf: streamed.feed(delta))
        }
        actual.append(contentsOf: streamed.finish())

        #expect(coalescingText(actual) == expected)
        #expect(streamed.warnings.isEmpty)
    }

    @Test("T-2 / T-6 / T-7：超长未闭合 <、数学不等号、嵌套 < 与 finish 幂等")
    func unclosedAndNonTagBrackets() {
        // T-2：超过 24 字符未闭合，在 feed 内立即刷出
        var pLong = TagParser()
        let longUnclosed = "<123456789012345678901234" // 25 chars
        let flushed = pLong.feed(longUnclosed)
        #expect(flushed == [.text(longUnclosed)])
        #expect(pLong.finish().isEmpty)
        #expect(pLong.warnings.isEmpty)

        // T-6：数学比较与中文尖括号不构成标签，原样输出且零警告
        var pMath = TagParser()
        let mathOut = pMath.feed("1<2 and 3>2") + pMath.finish()
        #expect(coalescingText(mathOut) == [.text("1<2 and 3>2")])
        #expect(pMath.warnings.isEmpty)

        // T-6 + 嵌套 < 后接合法标签
        var pNested = TagParser()
        let nestedOut = pNested.feed("1<2<emo:happy>你好") + pNested.finish()
        #expect(coalescingText(nestedOut) == [.text("1<2"), .emotion(.happy), .text("你好")])
        #expect(pNested.warnings.isEmpty)

        // T-7：结束时刷出未闭合缓存，二次 finish 返回 []
        var pTail = TagParser()
        #expect(pTail.feed("1<2") == [.text("1")])
        #expect(pTail.finish() == [.text("<2")])
        #expect(pTail.finish().isEmpty)
    }

    @Test("T-3 / T-9：未知标签类型与未知枚举值丢弃且精确记录警告")
    func unknownTagsAndValuesRecordWarnings() {
        var parser = TagParser()
        let input = "<emo:excited><foo:bar><act:jump><user:unknown><cmd:video><cmd:>你好"
        let out = parser.feed(input) + parser.finish()

        #expect(out == [.text("你好")])
        #expect(parser.warnings == [
            TagParseWarning(rawTag: "<emo:excited>", reason: .unknownEmotion("excited")),
            TagParseWarning(rawTag: "<foo:bar>", reason: .unknownTagType("foo")),
            TagParseWarning(rawTag: "<act:jump>", reason: .unknownAction("jump")),
            TagParseWarning(rawTag: "<user:unknown>", reason: .unknownUserEmotion("unknown")),
            TagParseWarning(rawTag: "<cmd:video>", reason: .unknownCommand("video")),
            TagParseWarning(rawTag: "<cmd:>", reason: .unknownCommand("")),
        ])
    }

    @Test("T-4 / T-5：无 <user>、文字后/重复/<emo> 后的 <user> 丢弃、前导换行后 <user> 生效")
    func userTagPositionAndUniqueness() {
        // T-4：无 <user>
        var pNoUser = TagParser()
        #expect(pNoUser.feed("<emo:playful>你猜？") + pNoUser.finish() == [.emotion(.playful), .text("你猜？")])

        // T-5：文字后 <user:sad> 丢弃
        var pAfterText = TagParser()
        #expect(pAfterText.feed("你好<user:sad>呀") + pAfterText.finish() == [.text("你好呀")])
        #expect(pAfterText.warnings.isEmpty)

        // T-5：重复 <user> 仅保留第一个
        var pDup = TagParser()
        #expect(pDup.feed("<user:happy><user:sad>嗨") + pDup.finish() == [.userEmotion(.happy), .text("嗨")])
        #expect(pDup.warnings.isEmpty)

        // T-5：<emo> 之后出现的 <user> 丢弃
        var pAfterEmo = TagParser()
        #expect(pAfterEmo.feed("<emo:happy><user:sad>嗨") + pAfterEmo.finish() == [.emotion(.happy), .text("嗨")])
        #expect(pAfterEmo.warnings.isEmpty)

        // 前导换行/空白后 <user> 正常产出
        var pLeadingWS = TagParser()
        let out = pLeadingWS.feed("\n  <user:tired><emo:gentle>累了吧") + pLeadingWS.finish()
        #expect(out == [.text("\n  "), .userEmotion(.tired), .emotion(.gentle), .text("累了吧")])
        #expect(pLeadingWS.warnings.isEmpty)
    }

    @Test("T-8 / T-10：三种 <cmd> 精确产出且同轮多指令按原序全量保留")
    func commandTagsAndMultiCommandOrder() {
        var pSingle = TagParser()
        #expect(pSingle.feed("<cmd:photo><cmd:photoReady><cmd:photoCancel>") + pSingle.finish() == [
            .command(.photo),
            .command(.photoReady),
            .command(.photoCancel),
        ])
        #expect(pSingle.warnings.isEmpty)

        // T-10：重复与冲突指令按原序全量产出
        var pMulti = TagParser()
        let out = pMulti.feed("好呀<cmd:photo>等一下<cmd:photo><cmd:photoCancel>") + pMulti.finish()
        #expect(out == [
            .text("好呀"),
            .command(.photo),
            .text("等一下"),
            .command(.photo),
            .command(.photoCancel),
        ])
    }

    @Test("reset 清空状态、标记位与 warnings 供复用")
    func resetClearsAllState() {
        var parser = TagParser()
        _ = parser.feed("<user:happy><emo:bad><unclosed")
        #expect(parser.warnings.count == 1)

        parser.reset()
        #expect(parser.warnings.isEmpty)
        let out = parser.feed("<user:calm><emo:gentle>重置成功") + parser.finish()
        #expect(out == [.userEmotion(.calm), .emotion(.gentle), .text("重置成功")])
        #expect(parser.warnings.isEmpty)
    }

    @Test("参数化随机切分一致性：任意切分点产出与单次整段输入 100% 相等", arguments: randomChunkStrategies)
    func randomChunkingEquivalence(strategy: ChunkStrategy) {
        let sample =
            "<user:tired><emo:gentle>今天1<2 and 3>2累坏了吧？<act:nod>"
            + "<emo:excited><user:happy><cmd:photo>先歇会儿<foo:bar>1<2<emo:happy>哇！"
            + "<act:spin><cmd:photoReady><cmd:video>好的<cmd:photoCancel>尾<unclosed"

        var ref = TagParser()
        let expectedSegments = coalescingText(ref.feed(sample) + ref.finish())
        let expectedWarnings = ref.warnings

        var streamed = TagParser()
        var actual: [TaggedSegment] = []
        for piece in strategy.split(sample) {
            actual.append(contentsOf: streamed.feed(piece))
        }
        actual.append(contentsOf: streamed.finish())

        #expect(coalescingText(actual) == expectedSegments)
        #expect(streamed.warnings == expectedWarnings)
    }
}
