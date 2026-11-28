import Foundation
import Testing
import MMCore
@testable import MMConversation

private struct SplitterSeededRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int((state >> 16) % span)
    }
}

private let splitterSeeds: [UInt64] = (1...12).map { UInt64($0 * 104729) }

@Suite("SentenceSplitter 流式分句（S-1–S-7）")
struct SentenceSplitterTests {

    @Test("S-1：中英文句末标点与跨块连续标点合并")
    func sentenceEndAndConsecutivePunctuation() {
        let turnID = UUID()
        var splitter = SentenceSplitter(turnID: turnID)

        var sentences: [Sentence] = []
        sentences.append(contentsOf: splitter.feed(.text("真的吗！")))
        sentences.append(contentsOf: splitter.feed(.text("？先歇会儿。嗯……好吧！Hi... ok~!")))
        sentences.append(contentsOf: splitter.finish())

        #expect(sentences.map(\.text) == ["真的吗！？", "先歇会儿。", "嗯……", "好吧！", "Hi...", "ok~!"])
        #expect(sentences.map(\.index) == [0, 1, 2, 3, 4, 5])
        #expect(sentences.allSatisfy { $0.turnID == turnID })
    }

    @Test("S-2：首句达 6 字遇逗号提速切分，第二句逗号不切")
    func firstSentenceCommaSpeedup() {
        let turnID = UUID()
        var splitter = SentenceSplitter(turnID: turnID)

        let sentences = splitter.feed(.text("嗨，今天天气真好，去散步吧。先歇会儿，我陪着你。")) + splitter.finish()

        #expect(sentences.map(\.text) == [
            "嗨，今天天气真好，",
            "去散步吧。",
            "先歇会儿，我陪着你。",
        ])
        #expect(sentences.map(\.index) == [0, 1, 2])
    }

    @Test("S-3：超过 40 字无标点强切、优先在逗号处切分并迁移 <act> 偏移、40 字 + 句号保持单句")
    func maxLengthForceSplit() {
        // 1. 45 字无标点 → 40 + 5
        var s1 = SentenceSplitter(turnID: UUID())
        let fortyFive = String(repeating: "啊", count: 45)
        let out1 = s1.feed(.text(fortyFive)) + s1.finish()
        #expect(out1.map(\.text) == [String(repeating: "啊", count: 40), String(repeating: "啊", count: 5)])

        // 2. 45 字且第 20 字（索引 20）为逗号、第 25 字处有 <act:nod>（放在第 2 句以避开 S-2 首句逗号提速）
        var s2 = SentenceSplitter(turnID: UUID())
        let prefixOut = s2.feed(.text("好。"))
        let beforeComma = String(repeating: "甲", count: 20) // 0..<20
        let afterCommaBeforeAct = String(repeating: "乙", count: 4) // 21..<25
        let afterAct = String(repeating: "丙", count: 20) // 25..<45
        let out2 = prefixOut + s2.feed([
            .text(beforeComma + "，" + afterCommaBeforeAct),
            .action(.nod),
            .text(afterAct),
        ]) + s2.finish()
        #expect(out2.count == 3)
        #expect(out2[0].text == "好。")
        #expect(out2[1].text == beforeComma + "，")
        #expect(out2[1].actions.isEmpty)
        #expect(out2[2].text == afterCommaBeforeAct + afterAct)
        #expect(out2[2].actions == [SentenceAction(action: .nod, charOffset: 4)])

        // 3. 40 字 + 句号 → 保持单句 41 字
        var s3 = SentenceSplitter(turnID: UUID())
        let fortyAndDot = String(repeating: "测", count: 40) + "。"
        let out3 = s3.feed(.text(fortyAndDot)) + s3.finish()
        #expect(out3.count == 1)
        #expect(out3[0].text == fortyAndDot)
    }

    @Test("S-4：沿用上一个 <emo>、句中切新 <emo> 强切、同 <emo> 不切、连续 <emo> 与末尾动作归属")
    func emotionInheritanceAndChangeSplits() {
        var splitter = SentenceSplitter(turnID: UUID())
        let segments: [TaggedSegment] = [
            .emotion(.happy),
            .emotion(.gentle),
            .text("你好"),
            .emotion(.gentle),
            .text("呀"),
            .action(.nod),
            .emotion(.playful),
            .text("再见。"),
            .text("明天见。"),
        ]
        let out = splitter.feed(segments) + splitter.finish()

        #expect(out.count == 3)
        #expect(out[0].text == "你好呀")
        #expect(out[0].emotion == .gentle)
        #expect(out[0].actions.isEmpty)

        #expect(out[1].text == "再见。")
        #expect(out[1].emotion == .playful)
        #expect(out[1].actions == [SentenceAction(action: .nod, charOffset: 0)])

        #expect(out[2].text == "明天见。")
        #expect(out[2].emotion == .playful)
    }

    @Test("S-5 / S-6 / S-7：动作偏移、纯标点与波浪号过滤、<cmd> 零影响、尾动作与 finish 幂等")
    func actionsFilteringCommandsAndTrailingActions() {
        var splitter = SentenceSplitter(turnID: UUID())
        let segments: [TaggedSegment] = [
            .text("   。。。~~~～～～！！！"),
            .emotion(.gentle),
            .action(.notice),
            .text("你好"),
            .command(.photo),
            .action(.nod),
            .text("世界！"),
            .command(.photoReady),
            .text("拜拜！"),
            .action(.wave),
        ]
        let out = splitter.feed(segments) + splitter.finish()

        #expect(out.count == 2)
        #expect(out[0].index == 0)
        #expect(out[0].text == "你好世界！")
        #expect(out[0].emotion == .gentle)
        #expect(out[0].actions == [
            SentenceAction(action: .notice, charOffset: 0),
            SentenceAction(action: .nod, charOffset: 2),
        ])

        #expect(out[1].index == 1)
        #expect(out[1].text == "拜拜！")
        #expect(out[1].actions.isEmpty)

        #expect(splitter.trailingActions == [.wave])
        // finish 幂等
        #expect(splitter.finish().isEmpty)
        #expect(splitter.trailingActions == [.wave])
    }

    @Test("参数化随机切分一致性：TagParser + SentenceSplitter 串联在任意切分下与整段输入 100% 相等", arguments: splitterSeeds)
    func endToEndStreamingEquivalence(seed: UInt64) {
        let samples = [
            "<user:tired><emo:gentle>今天累坏了吧？<act:nod>先歇会儿，我陪着你。",
            "<user:happy><emo:happy>哇，真的吗！<act:spin>那我给你转个圈庆祝一下～<cmd:photo>",
            "<emo:playful>你猜？<emo:shy>其实<act:shyCover>我早就准备好了！<act:wave>",
        ]

        let turnID = UUID()
        for sample in samples {
            var refParser = TagParser()
            var refSplitter = SentenceSplitter(turnID: turnID)
            let expected = refSplitter.feed(refParser.feed(sample) + refParser.finish()) + refSplitter.finish()

            var rng = SplitterSeededRNG(seed: seed)
            let chars = Array(sample)
            var parser = TagParser()
            var splitter = SentenceSplitter(turnID: turnID)
            var actual: [Sentence] = []
            var idx = 0
            while idx < chars.count {
                let len = rng.nextInt(in: 1...5)
                let end = min(idx + len, chars.count)
                let delta = String(chars[idx..<end])
                actual.append(contentsOf: splitter.feed(parser.feed(delta)))
                idx = end
            }
            actual.append(contentsOf: splitter.feed(parser.finish()))
            actual.append(contentsOf: splitter.finish())

            #expect(actual == expected)
            #expect(splitter.trailingActions == refSplitter.trailingActions)
        }
    }
}
