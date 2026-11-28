import Foundation
import MMCore

/// 流式标签解析产出的片段。
public enum TaggedSegment: Sendable, Equatable {
    case userEmotion(UserEmotion)
    case emotion(EmotionTag)
    case action(ActionTag)
    case command(AssistantCommand)
    case text(String)
}

/// 标签解析警告（T-3 / T-9）。
public struct TagParseWarning: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case unknownTagType(String)
        case unknownUserEmotion(String)
        case unknownEmotion(String)
        case unknownAction(String)
        case unknownCommand(String)
    }

    public let rawTag: String
    public let reason: Reason

    public init(rawTag: String, reason: Reason) {
        self.rawTag = rawTag
        self.reason = reason
    }
}

/// 流式标签解析器（contracts/tag-protocol.md T-1–T-10）。
public struct TagParser: Sendable {
    public static let maxTagLength = 24

    public private(set) var warnings: [TagParseWarning] = []

    private var tagBuffer: String = ""
    private var hasEmittedUserEmotion: Bool = false
    private var hasSeenNonWhitespaceText: Bool = false
    private var hasSeenBodyTag: Bool = false

    public init() {}

    /// 喂入一段流式文字增量，返回可确定的已解析片段（相邻纯文本段在同次返回中自动合并，不产出空 `.text("")`）。
    public mutating func feed(_ delta: String) -> [TaggedSegment] {
        guard !delta.isEmpty else { return [] }

        var output: [TaggedSegment] = []
        var textAccumulator = ""

        func flushTextAccumulator() {
            guard !textAccumulator.isEmpty else { return }
            appendSegment(.text(textAccumulator), to: &output)
            textAccumulator.removeAll(keepingCapacity: true)
        }

        func appendPlainText(_ string: String) {
            guard !string.isEmpty else { return }
            if !hasSeenNonWhitespaceText && string.contains(where: { !$0.isWhitespace && !$0.isNewline }) {
                hasSeenNonWhitespaceText = true
            }
            textAccumulator.append(string)
        }

        for ch in delta {
            if tagBuffer.isEmpty {
                if ch == "<" {
                    tagBuffer = "<"
                } else {
                    appendPlainText(String(ch))
                }
            } else {
                if ch == "<" {
                    // 未闭合 `<` 后遇到新 `<`（例如 "1<2<emo:happy>"），将旧缓存按普通文字刷出并开启新缓冲
                    appendPlainText(tagBuffer)
                    tagBuffer = "<"
                } else if ch == ">" {
                    tagBuffer.append(">")
                    let rawTag = tagBuffer
                    tagBuffer.removeAll(keepingCapacity: true)

                    if let parsed = parseTagShape(rawTag) {
                        switch parsed.kind {
                        case "user":
                            if let emotion = UserEmotion(rawValue: parsed.value) {
                                // T-4 / T-5：仅允许出现在回答最前面（首个非空白文字与任何正文标签之前）且最多一次
                                if !hasEmittedUserEmotion && !hasSeenNonWhitespaceText && !hasSeenBodyTag {
                                    flushTextAccumulator()
                                    hasEmittedUserEmotion = true
                                    appendSegment(.userEmotion(emotion), to: &output)
                                }
                            } else {
                                warnings.append(TagParseWarning(rawTag: rawTag, reason: .unknownUserEmotion(parsed.value)))
                            }
                        case "emo":
                            if let emotion = EmotionTag(rawValue: parsed.value) {
                                flushTextAccumulator()
                                hasSeenBodyTag = true
                                appendSegment(.emotion(emotion), to: &output)
                            } else {
                                warnings.append(TagParseWarning(rawTag: rawTag, reason: .unknownEmotion(parsed.value)))
                            }
                        case "act":
                            if let action = ActionTag(rawValue: parsed.value) {
                                flushTextAccumulator()
                                hasSeenBodyTag = true
                                appendSegment(.action(action), to: &output)
                            } else {
                                warnings.append(TagParseWarning(rawTag: rawTag, reason: .unknownAction(parsed.value)))
                            }
                        case "cmd":
                            if let command = AssistantCommand(rawValue: parsed.value) {
                                flushTextAccumulator()
                                hasSeenBodyTag = true
                                appendSegment(.command(command), to: &output)
                            } else {
                                warnings.append(TagParseWarning(rawTag: rawTag, reason: .unknownCommand(parsed.value)))
                            }
                        default:
                            warnings.append(TagParseWarning(rawTag: rawTag, reason: .unknownTagType(parsed.kind)))
                        }
                    } else {
                        // T-6：不构成标签外形（如 "<2 and 3>"、"<你好>"、"<>"），作为普通文字输出
                        appendPlainText(rawTag)
                    }
                } else {
                    tagBuffer.append(ch)
                    // T-2：超过 24 字符仍未闭合，立即作为普通文字刷出
                    if tagBuffer.count > Self.maxTagLength {
                        appendPlainText(tagBuffer)
                        tagBuffer.removeAll(keepingCapacity: true)
                    }
                }
            }
        }

        flushTextAccumulator()
        return output
    }

    /// 回答结束时按 T-7 刷出未闭合缓存（幂等：重复调用返回 `[]`）。
    public mutating func finish() -> [TaggedSegment] {
        guard !tagBuffer.isEmpty else { return [] }
        let trailing = tagBuffer
        tagBuffer.removeAll(keepingCapacity: false)
        if !hasSeenNonWhitespaceText && trailing.contains(where: { !$0.isWhitespace && !$0.isNewline }) {
            hasSeenNonWhitespaceText = true
        }
        return [.text(trailing)]
    }

    /// 重置状态以复用解析器（清空缓存、标记位与 `warnings`）。
    public mutating func reset() {
        warnings.removeAll(keepingCapacity: false)
        tagBuffer.removeAll(keepingCapacity: false)
        hasEmittedUserEmotion = false
        hasSeenNonWhitespaceText = false
        hasSeenBodyTag = false
    }

    private func appendSegment(_ segment: TaggedSegment, to output: inout [TaggedSegment]) {
        if case .text(let rhs) = segment {
            guard !rhs.isEmpty else { return }
            if case .text(let lhs) = output.last {
                output[output.count - 1] = .text(lhs + rhs)
                return
            }
        }
        output.append(segment)
    }

    /// 校验标签外形：`<kind:value>`，恰含 1 个 `:`，`kind` 非空且全 ASCII 字母，`value` 全 ASCII 字母/数字/`_`/`-`（可为空）。
    private func parseTagShape(_ rawTag: String) -> (kind: String, value: String)? {
        guard rawTag.count >= 3, rawTag.first == "<", rawTag.last == ">" else { return nil }
        let inner = rawTag.dropFirst().dropLast()
        guard let colonIndex = inner.firstIndex(of: ":") else { return nil }
        let afterColon = inner.index(after: colonIndex)
        // 若存在第二个冒号则不构成标签外形
        if inner[afterColon...].contains(":") {
            return nil
        }

        let kindSub = inner[..<colonIndex]
        let valueSub = inner[afterColon...]
        guard !kindSub.isEmpty else { return nil }
        guard kindSub.allSatisfy(Self.isASCIILetter) else { return nil }
        guard valueSub.allSatisfy(Self.isTagValueChar) else { return nil }
        return (String(kindSub), String(valueSub))
    }

    private static func isASCIILetter(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return false }
        return (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
    }

    private static func isTagValueChar(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return false }
        let v = scalar.value
        return (v >= 65 && v <= 90)
            || (v >= 97 && v <= 122)
            || (v >= 48 && v <= 57)
            || v == 95 // "_"
            || v == 45 // "-"
    }
}
