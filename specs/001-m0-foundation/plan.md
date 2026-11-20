# Implementation Plan: M0 工程基座与能力探测

**Branch**: `001-m0-foundation` | **Date**: 2026-11-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-m0-foundation/spec.md`

## Summary

建立后续所有里程碑共用的工程结构：一个 SwiftUI iOS App 作为组合根，一个本地 Swift Package `MiniMateKit` 承载全部业务模块（纯逻辑模块可在 macOS 测试）。在此基础上交付三件事：开发者账号签名真机安装与重签流程、一次性能力探测页（验证 V1–V3）、Keychain 密钥存储。

## Technical Context

**Language/Version**：Swift 6（严格并发检查）

**Primary Dependencies**：SwiftUI、Security（Keychain）、FoundationModels、Speech、NaturalLanguage、ARKit；无第三方依赖

**Storage**：Keychain（密钥）；探测报告不持久化，导出为文本

**Testing**：Swift Testing（`swift test` 于 macOS）；真机部分按 quickstart 手动验收

**Target Platform**：iOS 26+（App）；Package 同时声明 macOS 26 以支持本机测试

**Project Type**：mobile-app（iOS App + 本地 Swift Package）

**Performance Goals**：能力探测全部完成 < 5 s

**Constraints**：不声明任何付费账号独有的 capability；不联网

**Scale/Scope**：单用户、单设备；本阶段 3 个页面（首页、能力探测、设置）

## Constitution Check

| 原则 | 结论 |
|---|---|
| I. 陪伴而非镜像 | 不涉及 |
| II. 感知在本地 | 不涉及 |
| III. 度量先于假设 | ✅ 本 feature 的核心目的就是把 V1–V3 从"需确认"变成实测结论 |
| IV. 可替换边界 | ✅ 建立模块划分；密钥访问收敛在 `CredentialStore` |
| V. 纯逻辑可测 | ✅ `CapabilityReport` 导出逻辑在 macOS 可测；探测器本身依赖系统框架，按 quickstart 真机验证 |
| VI. 简单优先 | ✅ 无第三方依赖；不引入 XcodeGen 等工具 |
| VII. 隐私与密钥 | ✅ Keychain 存储、仅显示末 4 位、`.gitignore` |

无违反项。

## Project Structure

### Documentation (this feature)

```text
specs/001-m0-foundation/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── tasks.md
```

### Source Code (repository root)

本结构为全项目共用，后续 feature 只在其中增加文件。

```text
App/
├── MiniMate.xcodeproj
└── MiniMate/
    ├── MiniMateApp.swift            # 入口
    ├── AppComposition.swift         # 组合根：创建并注入各模块实现
    ├── Screens/
    │   ├── HomeView.swift
    │   ├── DiagnosticsView.swift    # 能力探测页
    │   └── SettingsView.swift       # 密钥设置
    └── Info.plist

Packages/MiniMateKit/
├── Package.swift                    # platforms: iOS 26, macOS 26
├── Sources/
│   ├── MMCore/                      # 共享值类型、标签枚举、时钟、指标记录
│   ├── MMDiagnostics/               # CapabilityProbe、CapabilityReport
│   ├── MMSecurity/                  # CredentialStore（Keychain）
│   ├── MMPerception/                # (M1) ARKit 感知
│   ├── MMEmotion/                   # (M1) 情绪状态机，纯逻辑
│   ├── MMAvatar/                    # (M1) RealityKit 渲染
│   ├── MMAudio/                     # (M2) 音频会话、收音闸门
│   ├── MMConversation/              # (M2) 对话引擎、标签解析、分句、厂商适配
│   └── MMMemory/                    # (M3) 会话记忆
├── Tests/
│   ├── MMCoreTests/
│   ├── MMDiagnosticsTests/
│   └── ...                          # 每个纯逻辑模块一个测试 target
└── Tools/                           # (M2a) macOS 命令行验证工具

.specify/memory/constitution.md
specs/
docs/tech-selection.md
```

**Structure Decision**：单 App + 单本地 Package、多 target。模块按 tech-selection 第 3 章的四块架构划分；依赖 ARKit / RealityKit / AVAudioSession 的代码用 `#if os(iOS)` 隔离或放在仅 iOS 的 target 中，保证纯逻辑 target 可在 macOS 测试。Xcode 工程在 Xcode 中手动创建（一次性操作），不引入工程生成工具。

### 关键设计

- **能力探测**：`CapabilityProbe` 协议，每项一个实现；`DiagnosticsRunner` 并发执行（`withTaskGroup`），单项超时 3 s，异常转为 `.error(reason)`。
- **Foundation Models 探测**：读取 `SystemLanguageModel.default.availability`，把 `.unavailable(reason)` 的各分支映射为中文原因；可用时再用 `supportsLocale` 检查中文（API 名称以 Xcode 26 SDK 为准）。
- **Speech 探测**：`SpeechTranscriber.supportedLocales` / `installedLocales` 是否含 zh-CN；`SpeechDetector` 能否构造并加入 `SpeechAnalyzer`。
- **NLEmbedding 探测**：`NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)` 是否非 nil，并对两句近义句计算距离作冒烟测试。
- **ARKit 探测**：`ARFaceTrackingConfiguration.isSupported`。
- **CredentialStore**：`kSecClassGenericPassword`，service 固定为 `ai.minimate.credentials`，account 为厂商标识；`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`。

## Complexity Tracking

无。
