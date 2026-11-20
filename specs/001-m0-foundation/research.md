# Research: M0 工程基座与能力探测

**Feature**: `001-m0-foundation` | **Date**: 2026-11-20

本文件记录本 feature 的技术决策与实测结果。"实测结果"一节在真机探测后填写。

## 决策

### D1. 工程结构：App + 本地 Swift Package

- **Decision**：一个 iOS App target 作为组合根；业务代码全部在 `Packages/MiniMateKit` 的多个 target 中。
- **Rationale**：宪章 V 要求纯逻辑可在 macOS 上 `swift test`；Package target 天然隔离模块依赖，避免循环引用。
- **Alternatives considered**：全部放在 App target（无法在 macOS 测试）；XcodeGen / Tuist 生成工程（新增工具依赖，单人项目收益低）。

### D2. 签名：免费 Apple ID

- **Decision**：Personal Team 签名，每 7 天重签；不声明 Push、iCloud、App Groups 等 capability。
- **Rationale**：用户已决定暂不购买开发者账号（tech-selection 2.2）。
- **Alternatives considered**：付费账号（一年期签名、完整 capability）——记为后续可选项，触发条件是重签频率成为实际负担，或 M4 需要 `increased-memory-limit` 而免费账号不支持。

### D3. 测试框架：Swift Testing

- **Decision**：使用 Swift Testing（`import Testing`、`@Test`、`#expect`）。
- **Rationale**：Xcode 26 默认，语法简洁，支持参数化测试，适合解析器与状态机。
- **Alternatives considered**：XCTest（保留用于未来可能的 UI 测试）。

### D4. 密钥存储

- **Decision**：Keychain generic password，`AfterFirstUnlockThisDeviceOnly`。
- **Rationale**：宪章 VII；不随备份迁移到其他设备。
- **Alternatives considered**：`UserDefaults` / plist（明文，不可接受）。

## 待实测项（对应 tech-selection 第 9.2 节）

| # | 问题 | 探测方式 | 影响 |
|---|---|---|---|
| V1 | Foundation Models 是否可用、是否支持中文 | `SystemLanguageModel.default.availability` + 中文 locale 检查 | 不可用 → M4 走 MLX；离线意图匹配只用 `NLEmbedding` |
| V2 | `SpeechTranscriber` 是否支持 zh-CN | `supportedLocales` / `installedLocales` | 不可用 → 离线识别用 `SFSpeechRecognizer` |
| V3 | `SpeechDetector` 能否用作人声闸门 | 能否构造；效果在 003 中实测 | 不可用 → 能量阈值 + 过零率 |
| — | `NLEmbedding` 中文句向量 | 是否非 nil + 近义句距离 | 不可用 → 关键词 + CreateML 分类器 |
| — | ARKit 人脸追踪 | `ARFaceTrackingConfiguration.isSupported` | 参考设备预期为支持 |

## 实测结果

> 在真机运行能力探测页后，把导出的报告粘贴到这里，并逐项写结论。

| 项 | 结果 | 原因 / 备注 | 对后续的影响 |
|---|---|---|---|
| 设备 / 系统 | 待填 | | |
| V1 Foundation Models | 待填 | | |
| V1 中文支持 | 待填 | | |
| V2 SpeechTranscriber zh-CN | 待填 | | |
| V3 SpeechDetector | 待填 | | |
| NLEmbedding 中文 | 待填 | | |
| ARKit 人脸追踪 | 待填 | | |
| 重签耗时（SC-001） | 待填 | | |
