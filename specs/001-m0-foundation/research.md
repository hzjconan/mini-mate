# Research: M0 工程基座与能力探测

**Feature**: `001-m0-foundation` | **Date**: 2026-11-20

本文件记录本 feature 的技术决策与实测结果。"实测结果"一节在真机探测后填写。

## 决策

### D1. 工程结构：App + 本地 Swift Package

- **Decision**：一个 iOS App target 作为组合根；业务代码全部在 `Packages/MiniMateKit` 的多个 target 中。
- **Rationale**：宪章 V 要求纯逻辑可在 macOS 上 `swift test`；Package target 天然隔离模块依赖，避免循环引用。
- **Alternatives considered**：全部放在 App target（无法在 macOS 测试）；XcodeGen / Tuist 生成工程（新增工具依赖，单人项目收益低）。

### D2. 签名：开发者账号（2026-11-20 修订）

- **Decision**：付费个人开发者账号签名；App 不声明 Push、iCloud、App Groups 等 capability。
- **Rationale**：原计划用免费 Apple ID；真机安装当天遇到"设备注册名额已满"（免费账号的 iPhone 名额是跨项目共享的硬上限，且无法在线删除），购入个人付费会员。付费签名约一年有效，每周重签的负担消除。
- **Alternatives considered**：免费 Apple ID（7 天签名、无付费能力）——仍可用作回退路径；本 App 不依赖任何付费 capability，换免费账号只需重新签名安装。

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
| 重签耗时（SC-001） | ✅ ~30 s | ⌘R 原地重签（付费账号 Xcode Managed Profile），@AppStorage 计数器保留（5→5） | 达标（≤5 min）|

> 注（2026-11-20 实测）：付费账号下"签名到期、App 打不开"的状态无法模拟——iOS 设置无描述文件管理入口（付费证书在信任链内，不像免费账号有信任条目）；Xcode 27 的 Window 菜单也已移除设备描述文件管理；吊销 Apple Development 证书后 App 仍可正常启动，说明 iOS 启动校验是本地的（内嵌 profile + 签名链），不做吊销检查。真正的到期→重签全链路只能等 11 个月后自然到期或换回免费账号时验证。
