import Foundation
import MMCore

/// 句内动作及其字符偏移（contracts/tag-protocol.md S-5）。
public struct SentenceAction: Sendable, Equatable, Codable {
    public let action: ActionTag
    public let charOffset: Int

    public init(action: ActionTag, charOffset: Int) {
        self.action = action
        self.charOffset = charOffset
    }
}

/// 分句器产出的一句可送入 TTS 的文本单元。
public struct Sentence: Sendable, Equatable {
    public let turnID: UUID
    public let index: Int
    public let text: String
    public let emotion: EmotionTag
    public let actions: [SentenceAction]

    public init(
        turnID: UUID,
        index: Int,
        text: String,
        emotion: EmotionTag,
        actions: [SentenceAction] = []
    ) {
        self.turnID = turnID
        self.index = index
        self.text = text
        self.emotion = emotion
        self.actions = actions
    }
}

/// 流式分句器（contracts/tag-protocol.md S-1–S-7）。
public struct SentenceSplitter: Sendable {
    public let turnID: UUID
    public let firstSentenceCommaMinLength: Int
    public let maxSentenceLength: Int

    /// `finish()` 后若有紧跟句末/无后续可播文字的孤立 `<act>`，按出现顺序记录在此（不产出空句）。
    public private(set) var trailingActions: [ActionTag] = []

    private static let sentenceEndPunctuation: Set<Character> = ["。", "！", "？", "…", "~", "～", ".", "!", "?"]
    private static let commaPunctuation: Set<Character> = ["，", "、", ","]

    private var buffer: [Character] = []
    private var pendingActions: [SentenceAction] = []
    private var currentEmotion: EmotionTag
    private var sentenceEmotion: EmotionTag
    private var emittedSentenceCount: Int = 0
    private var pendingSentenceEnd: Bool = false

    public init(
        turnID: UUID,
        initialEmotion: EmotionTag = .neutral,
        firstSentenceCommaMinLength: Int = 6,
        maxSentenceLength: Int = 40
    ) {
        self.turnID = turnID
        let minComma = max(1, firstSentenceCommaMinLength)
        self.firstSentenceCommaMinLength = minComma
        self.maxSentenceLength = max(minComma, maxSentenceLength)
        self.currentEmotion = initialEmotion
        self.sentenceEmotion = initialEmotion
    }

    public mutating func feed(_ segments: [TaggedSegment]) -> [Sentence] {
        var result: [Sentence] = []
        for segment in segments {
            result.append(contentsOf: feed(segment))
        }
        return result
    }

    public mutating func feed(_ segment: TaggedSegment) -> [Sentence] {
        var emitted: [Sentence] = []

        switch segment {
        case .userEmotion, .command:
            // 不产出文字、不改变 pendingSentenceEnd、不触发切分（T-8）
            return []

        case .emotion(let newEmotion):
            if pendingSentenceEnd {
                flushBuffer(into: &emitted)
                pendingSentenceEnd = false
            }
            if newEmotion != currentEmotion {
                if hasSpeakableContent(buffer) {
                    // 将紧贴当前末尾（charOffset == buffer.count）的待发动作迁入新句
                    let endOffset = buffer.count
                    var carried: [SentenceAction] = []
                    var remaining: [SentenceAction] = []
                    for act in pendingActions {
                        if act.charOffset >= endOffset {
                            carried.append(SentenceAction(action: act.action, charOffset: 0))
                        } else {
                            remaining.append(act)
                        }
                    }
                    pendingActions = remaining
                    flushBuffer(into: &emitted)
                    pendingActions.append(contentsOf: carried)
                } else {
                    buffer.removeAll(keepingCapacity: true)
                    pendingActions = pendingActions.map { SentenceAction(action: $0.action, charOffset: 0) }
                }
            }
            currentEmotion = newEmotion
            if buffer.isEmpty {
                sentenceEmotion = newEmotion
            }

        case .action(let act):
            if pendingSentenceEnd {
                flushBuffer(into: &emitted)
                pendingSentenceEnd = false
            }
            pendingActions.append(SentenceAction(action: act, charOffset: buffer.count))

        case .text(let str):
            for ch in str {
                if pendingSentenceEnd {
                    if Self.sentenceEndPunctuation.contains(ch) {
                        buffer.append(ch)
                        continue
                    } else {
                        flushBuffer(into: &emitted)
                        pendingSentenceEnd = false
                    }
                }

                if buffer.isEmpty && (ch.isWhitespace || ch.isNewline) {
                    continue
                }

                if Self.sentenceEndPunctuation.contains(ch) {
                    if buffer.isEmpty {
                        sentenceEmotion = currentEmotion
                    }
                    buffer.append(ch)
                    pendingSentenceEnd = true
                } else if Self.commaPunctuation.contains(ch) {
                    if buffer.isEmpty {
                        sentenceEmotion = currentEmotion
                    }
                    buffer.append(ch)
                    if emittedSentenceCount == 0
                        && buffer.count - 1 >= firstSentenceCommaMinLength
                        && hasSpeakableContent(buffer)
                    {
                        flushBuffer(into: &emitted)
                    } else if buffer.count > maxSentenceLength {
                        forceSplitOverMaxLength(into: &emitted)
                    }
                } else {
                    if buffer.isEmpty {
                        sentenceEmotion = currentEmotion
                    }
                    buffer.append(ch)
                    if buffer.count > maxSentenceLength {
                        forceSplitOverMaxLength(into: &emitted)
                    }
                }
            }
        }

        return emitted
    }

    public mutating func finish() -> [Sentence] {
        var emitted: [Sentence] = []
        pendingSentenceEnd = false
        if !buffer.isEmpty {
            flushBuffer(into: &emitted)
        }
        if !pendingActions.isEmpty {
            trailingActions.append(contentsOf: pendingActions.map(\.action))
            pendingActions.removeAll(keepingCapacity: false)
        }
        return emitted
    }

    private func hasSpeakableContent(_ chars: [Character]) -> Bool {
        chars.contains { $0.isLetter || $0.isNumber }
    }

    private func hasSpeakableContent(_ slice: ArraySlice<Character>) -> Bool {
        slice.contains { $0.isLetter || $0.isNumber }
    }

    private mutating func flushBuffer(into emitted: inout [Sentence]) {
        guard !buffer.isEmpty else { return }

        var end = buffer.count
        while end > 0 && (buffer[end - 1].isWhitespace || buffer[end - 1].isNewline) {
            end -= 1
        }
        let trimmedSlice = buffer[0..<end]

        if hasSpeakableContent(trimmedSlice) {
            let trimmedText = String(trimmedSlice)
            let maxOffset = trimmedSlice.count
            let clampedActions = pendingActions.map { act in
                SentenceAction(action: act.action, charOffset: max(0, min(act.charOffset, maxOffset)))
            }
            let sentence = Sentence(
                turnID: turnID,
                index: emittedSentenceCount,
                text: trimmedText,
                emotion: sentenceEmotion,
                actions: clampedActions
            )
            emitted.append(sentence)
            emittedSentenceCount += 1
            pendingActions.removeAll(keepingCapacity: true)
        } else {
            // S-6：纯空白/标点/波浪号句过滤，不递增 index；挂在上面的动作偏移归 0 留待下一句
            if !pendingActions.isEmpty {
                pendingActions = pendingActions.map { SentenceAction(action: $0.action, charOffset: 0) }
            }
        }

        buffer.removeAll(keepingCapacity: true)
        sentenceEmotion = currentEmotion
    }

    private mutating func forceSplitOverMaxLength(into emitted: inout [Sentence]) {
        let searchEnd = min(maxSentenceLength, buffer.count)
        var commaIndex: Int?
        var i = searchEnd - 1
        while i >= 0 {
            if Self.commaPunctuation.contains(buffer[i]) {
                commaIndex = i
                break
            }
            i -= 1
        }

        let splitOffset: Int
        if let idx = commaIndex, hasSpeakableContent(buffer[0...idx]) {
            splitOffset = idx + 1
        } else {
            splitOffset = maxSentenceLength
        }

        let headChars = Array(buffer[0..<splitOffset])
        var tailChars = Array(buffer[splitOffset..<buffer.count])

        var headActions: [SentenceAction] = []
        var tailActions: [SentenceAction] = []
        for act in pendingActions {
            if act.charOffset < splitOffset {
                headActions.append(act)
            } else {
                tailActions.append(SentenceAction(action: act.action, charOffset: act.charOffset - splitOffset))
            }
        }

        // 刷出 head
        buffer = headChars
        pendingActions = headActions
        flushBuffer(into: &emitted)
        let leftoverFromHead = pendingActions

        // 剥离 tail 前导空白并同步修正动作偏移
        var trimmedLead = 0
        while trimmedLead < tailChars.count && (tailChars[trimmedLead].isWhitespace || tailChars[trimmedLead].isNewline) {
            trimmedLead += 1
        }
        if trimmedLead > 0 {
            tailChars.removeFirst(trimmedLead)
        }

        var adjustedTailActions = leftoverFromHead
        for act in tailActions {
            adjustedTailActions.append(SentenceAction(action: act.action, charOffset: max(0, act.charOffset - trimmedLead)))
        }

        buffer = tailChars
        pendingActions = adjustedTailActions
        sentenceEmotion = currentEmotion
    }
}
