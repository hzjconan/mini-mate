/// 模型输出的 App 指令。rawValue 即 `<cmd:...>` 标签值（005 `contracts/command-tag.md`）。
public enum AssistantCommand: String, CaseIterable, Codable, Sendable {
    case photo
    case photoReady
    case photoCancel
}
