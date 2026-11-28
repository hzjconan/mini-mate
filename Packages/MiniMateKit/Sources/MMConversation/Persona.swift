import Foundation
import MMCore

/// `Persona` 加载或解析错误。
public enum PersonaError: Error, Sendable, Equatable {
    case resourceNotFound
    case invalidFormat(String)
}

/// 助手人格设定与标签协议指令拼装。
public struct Persona: Sendable, Equatable {
    public let name: String
    public let description: String
    public let addressUserAs: String
    public let rules: [String]

    public init(name: String, description: String, addressUserAs: String, rules: [String]) {
        self.name = name
        self.description = description
        self.addressUserAs = addressUserAs
        self.rules = rules
    }

    /// 解析固定结构 Markdown；缺失 `# 名字`、`- 称呼用户：...`、`## 性格与说话风格` 正文或 `## 规则` 任一必填项时抛 `PersonaError.invalidFormat`。
    public static func parse(markdown: String) throws -> Persona {
        enum Section {
            case none
            case style
            case rules
        }

        var parsedName: String?
        var parsedAddress: String?
        var styleLines: [String] = []
        var parsedRules: [String] = []
        var currentSection: Section = .none

        for rawLine in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("# ") && !line.hasPrefix("## ") {
                let candidate = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty {
                    parsedName = candidate
                }
                currentSection = .none
            } else if line.hasPrefix("## ") {
                let heading = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if heading == "性格与说话风格" {
                    currentSection = .style
                } else if heading == "规则" {
                    currentSection = .rules
                } else {
                    currentSection = .none
                }
            } else if currentSection == .none && (line.hasPrefix("- 称呼用户：") || line.hasPrefix("- 称呼用户:")) {
                let prefixLen = "- 称呼用户：".count
                let candidate = line.dropFirst(prefixLen).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty {
                    parsedAddress = candidate
                }
            } else if currentSection == .style {
                styleLines.append(line)
            } else if currentSection == .rules {
                if line.hasPrefix("- ") {
                    let rule = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                    if !rule.isEmpty {
                        parsedRules.append(rule)
                    }
                }
            }
        }

        guard let name = parsedName, !name.isEmpty else {
            throw PersonaError.invalidFormat("缺失一级标题 `# 名字`")
        }
        guard let address = parsedAddress, !address.isEmpty else {
            throw PersonaError.invalidFormat("缺失 `- 称呼用户：...`")
        }
        let description = styleLines.joined(separator: "\n")
        guard !description.isEmpty else {
            throw PersonaError.invalidFormat("缺失 `## 性格与说话风格` 正文")
        }
        guard !parsedRules.isEmpty else {
            throw PersonaError.invalidFormat("缺失 `## 规则` 列表项")
        }

        return Persona(name: name, description: description, addressUserAs: address, rules: parsedRules)
    }

    /// 从 `Bundle.module` 根目录加载内置 `persona.md`（SwiftPM `.process("Resources")` 扁平化，不传 `subdirectory:`）。
    public static func loadBundled() throws -> Persona {
        guard let url = Bundle.module.url(forResource: "persona", withExtension: "md") else {
            throw PersonaError.resourceNotFound
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(markdown: content)
    }

    /// 标签协议说明（逐字对齐 `contracts/tag-protocol.md:60-79`；枚举列表从 `MMCore` `allCases` 动态拼接防漂移）。
    public static func tagProtocolInstructions(includeCommandInstructions: Bool = true) -> String {
        let userEmotions = UserEmotion.allCases.map(\.rawValue).joined(separator: ", ")
        let emotions = EmotionTag.allCases.map(\.rawValue).joined(separator: ", ")
        let actions = ActionTag.allCases.map(\.rawValue).joined(separator: ", ")

        var lines: [String] = [
            "你在每次回答时必须遵守以下输出格式：",
            "1. 回答最前面用 <user:情绪> 标注你从用户的语气（不只是文字）中听出的情绪，",
            "   取值只能是：\(userEmotions)。",
            "2. 每句话前用 <emo:情绪> 标注你说这句话时的情绪，",
            "   取值只能是：\(emotions)。",
            "3. 需要做动作时，在对应位置插入 <act:动作>，",
            "   取值只能是：\(actions)。",
            "   用户让你做动作（如\"转个圈\"\"笑一个\"）时，必须插入对应动作。",
            "4. 标签不会被念出来，不要解释标签。",
            "5. 当用户的语气和文字含义不一致时（例如低落地说\"我没事\"），以语气为准来回应。",
        ]

        if includeCommandInstructions {
            lines.append(contentsOf: [
                "6. 只有当用户明确要求你\"现在\"给他拍照时（例如\"给我拍张照\"\"帮我拍一张\"\"来张自拍\"），",
                "   在回答末尾插入 <cmd:photo>，回答只说一句很短的话（如\"好呀～\"），不要问用户是否准备好。",
                "   用户只是聊到照片或拍照（例如\"我昨天拍了好多照片\"）时，绝对不要插入。",
                "   插入 <cmd:photo> 之后，App 会用你的声音问用户\"准备好了吗\"（这句你听不到），然后：",
                "   - 用户表示准备好了（\"好了\"\"可以了\"\"拍吧\"\"来吧\"），插入 <cmd:photoReady>，只说两三个字或不说；",
                "   - 用户表示还没好（\"还没\"\"等一下\"\"稍等\"），不插入任何指令，简短回应（如\"好，不急～\"）；",
                "   - 用户表示不拍了（\"不拍了\"\"算了\"\"不要了\"），插入 <cmd:photoCancel>，并且一定要说一句简短的确认（如\"好，不拍啦\"）。",
                "   拍照由 App 完成，你看不到照片，不要描述或评价照片内容。",
            ])
        }

        return lines.joined(separator: "\n")
    }

    /// 拼装完整会话 instructions：人格设定 + 标签协议说明（默认含 1–6 条）+ 可选 `extraInstructions`（004 记忆扩展；纯空白时省略）。
    public func makeInstructions(
        extraInstructions: String? = nil,
        includeCommandInstructions: Bool = true
    ) -> String {
        var sections: [String] = []

        var personaLines: [String] = [
            "你的名字是「\(name)」，称呼用户为「\(addressUserAs)」。",
            description,
            "对话规则：",
        ]
        for rule in rules {
            personaLines.append("- \(rule)")
        }
        sections.append(personaLines.joined(separator: "\n"))
        sections.append(Self.tagProtocolInstructions(includeCommandInstructions: includeCommandInstructions))

        if let extra = extraInstructions?.trimmingCharacters(in: .whitespacesAndNewlines), !extra.isEmpty {
            sections.append(extra)
        }

        return sections.joined(separator: "\n\n")
    }
}
