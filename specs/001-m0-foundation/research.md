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

探测设备：iPhone 16 Pro Max（iPhone17,2，型号 CH/A 国行）、iOS 27.2、2026-11-20。单项均 < 1 s，SC-002 达标。

导出报告原文：

```markdown
- 设备：iPhone17,2
- 系统：27.2
- 时间：2026-11-20T08:12:40Z

| 项 | 结果 | 原因 | 耗时 |
| --- | --- | --- | --- |
| V1 Foundation Models | 不可用 | 设备不支持 Apple Intelligence | 0.56 s |
| V1 中文支持 | 不可用 | Foundation Models 不可用 | 0.56 s |
| V2 SpeechTranscriber zh-CN | 可用 | 简体支持 zh_CN；中文支持：zh_TW, zh_HK, zh_CN；已安装：zh_TW, zh_CN | 0.64 s |
| V3 SpeechDetector | 可用 | — | 0.00 s |
| NLEmbedding 中文 | 不可用 | 无简体中文句向量 | 0.59 s |
| ARKit 人脸追踪 | 可用 | — | 0.00 s |
```

| 项 | 结果 | 原因 / 备注 | 对后续的影响 |
|---|---|---|---|
| 设备 / 系统 | iPhone17,2 / iOS 27.2 | iPhone 16 Pro Max，型号号码 CH/A（国行） | — |
| V1 Foundation Models | ❌ 不可用 | `deviceNotEligible`——国行型号硬屏蔽 Apple Intelligence（A18 Pro 硬件本身支持，与语言/账号设置无关） | M4 若启动只能走 MLX；依赖 FM 的功能（如将来的看图）在本机不可用 |
| V1 中文支持 | ❌ 不可用 | FM 整体不可用，中文支持无从谈起 | 同上 |
| V2 SpeechTranscriber zh-CN | ✅ 可用 | zh_CN 支持且资源已安装（zh_TW/HK/CN 均支持，已装 zh_TW、zh_CN） | 端侧/并行转写可用简体（003 V7、004 离线转写前提成立） |
| V3 SpeechDetector | ✅ 可用 | 可构造并加入 `SpeechAnalyzer` | 人声闸门可用；误开率/效果仍待 003 M2b 实测 |
| NLEmbedding 中文 | ❌ 不可用 | `sentenceEmbedding(.simplifiedChinese)` 返回 nil | 离线意图匹配降级：关键词 + CreateML 分类器（004 的 I-2 embedding 层在本机不生效） |
| ARKit 人脸追踪 | ✅ 可用 | `ARFaceTrackingConfiguration.isSupported = true` | 按预期，TrueDepth 可用 |
| 重签耗时（SC-001） | ✅ ~30 s | ⌘R 原地重签（付费账号 Xcode Managed Profile），@AppStorage 计数器保留（5→5） | 达标（≤5 min）|

> 注（2026-11-20 实测）：付费账号下"签名到期、App 打不开"的状态无法模拟——iOS 设置无描述文件管理入口（付费证书在信任链内，不像免费账号有信任条目）；Xcode 27 的 Window 菜单也已移除设备描述文件管理；吊销 Apple Development 证书后 App 仍可正常启动，说明 iOS 启动校验是本地的（内嵌 profile + 签名链），不做吊销检查。真正的到期→重签全链路只能等 11 个月后自然到期或换回免费账号时验证。
