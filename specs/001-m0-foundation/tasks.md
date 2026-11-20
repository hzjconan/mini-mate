---
description: "M0 工程基座与能力探测的任务列表"
---

# Tasks: M0 工程基座与能力探测

**Input**: Design documents from `/specs/001-m0-foundation/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: 宪章 V 要求纯逻辑模块测试先行；依赖系统框架的探测器按 quickstart 真机验收。

## Format: `[ID] [P?] [Story] Description`

- **[P]**：可并行（不同文件、无依赖）
- **[Story]**：所属 user story（US1、US2、US3）

## Phase 1: Setup

- [x] T001 新建仓库根 `.gitignore`（Xcode `xcuserdata/`、`DerivedData/`、`.build/`、`.swiftpm/`、`*.xcuserstate`、`.env*`、`Secrets*.plist`）
- [x] T002 在 Xcode 26 中创建 iOS App 工程 `App/MiniMate.xcodeproj`（SwiftUI、Swift 6、最低 iOS 26、仅 iPhone、Bundle ID `ai.minimate.app.cucumber`）
- [x] T003 创建本地包 `Packages/MiniMateKit/Package.swift`：platforms iOS 26 / macOS 26；targets `MMCore`、`MMDiagnostics`、`MMSecurity` 及对应测试 target；开启 Swift 6 严格并发
- [x] T004 将 `MiniMateKit` 以本地包形式加入 App 工程，App target 依赖 `MMCore`、`MMDiagnostics`、`MMSecurity`

---

## Phase 2: Foundational

- [x] T005 [P] 在 `Packages/MiniMateKit/Sources/MMCore/MMCore.swift` 建立模块占位与 `Clock` 协议（便于后续测试注入时间）
- [x] T006 `App/MiniMate/AppComposition.swift`：组合根，持有各模块实现；`App/MiniMate/MiniMateApp.swift` 注入
- [x] T007 `App/MiniMate/Screens/HomeView.swift`：首页占位 + 进入设置的入口

**Checkpoint**：App 可在模拟器启动（已验证模拟器编译与 bundle 校验），`swift test` 可运行

---

## Phase 3: User Story 1 - 真机安装与重签 (P1) 🎯 MVP

**Goal**：用免费 Apple ID 在真机安装，并跑通一次重签。

**Independent Test**：quickstart 第一、二节。

- [ ] T008 [US1] 按 quickstart 第一节在真机安装；确认 Signing & Capabilities 中无免费账号不支持的 capability
- [ ] T009 [US1] 在 `HomeView` 中加入一个本地计数器（`@AppStorage`），用于验证重签后数据保留
- [ ] T010 [US1] 等签名到期或在设备上删除描述文件模拟到期，按 quickstart 第二节重签，记录耗时到 `specs/001-m0-foundation/research.md`

**Checkpoint**：SC-001 达成

---

## Phase 4: User Story 2 - 能力探测 (P1)

**Goal**：一次看清 V1–V3 等关键能力。

**Independent Test**：quickstart 第三节。

### Tests（先写，确认失败）

- [x] T011 [P] [US2] `Packages/MiniMateKit/Tests/MMDiagnosticsTests/CapabilityReportTests.swift`：`markdown()` 输出表头、行顺序、`unavailable`/`error` 原因转义（含 `|` 字符）
- [x] T012 [P] [US2] `Packages/MiniMateKit/Tests/MMDiagnosticsTests/DiagnosticsRunnerTests.swift`：用假探测器验证并发执行、单项超时转为 `.error`、单项抛错不影响其他项

### Implementation

- [x] T013 [P] [US2] `Sources/MMDiagnostics/CapabilityModels.swift`：`CapabilityID`、`CapabilityStatus`、`CapabilityResult`、`CapabilityReport`（见 data-model.md）
- [x] T014 [US2] `Sources/MMDiagnostics/DiagnosticsRunner.swift`：`withTaskGroup` 并发、单项 3 s 超时（依赖 T013）
- [ ] T015 [P] [US2] `Sources/MMDiagnostics/Probes/FoundationModelsProbe.swift`：`SystemLanguageModel.default.availability` 各分支映射为中文原因；检查简体中文支持
- [ ] T016 [P] [US2] `Sources/MMDiagnostics/Probes/SpeechProbes.swift`：`SpeechTranscriber` zh-CN（supported / installed）、`SpeechDetector` 可用性
- [ ] T017 [P] [US2] `Sources/MMDiagnostics/Probes/NLEmbeddingProbe.swift`：中文句向量是否非 nil + 近义句距离冒烟测试
- [ ] T018 [P] [US2] `Sources/MMDiagnostics/Probes/ARKitProbe.swift`：`ARFaceTrackingConfiguration.isSupported`（`#if os(iOS)`）
- [ ] T019 [US2] `App/MiniMate/Screens/DiagnosticsView.swift`：开始探测、逐项展示状态与原因、导出（`ShareLink` 分享 Markdown 文本）
- [ ] T020 [US2] 真机运行探测，导出结果写入 `specs/001-m0-foundation/research.md` 并逐项写结论；若结论推翻 tech-selection 中的假设，同步修订 `docs/tech-selection.md`

**Checkpoint**：SC-002、SC-003 达成

---

## Phase 5: User Story 3 - API Key 安全存储 (P2)

**Goal**：Keychain 保存、查看状态、替换、删除。

**Independent Test**：quickstart 第五节 US3。

### Tests（先写，确认失败）

- [x] T021 [P] [US3] `Packages/MiniMateKit/Tests/MMSecurityTests/CredentialStoreTests.swift`：基于内存实现的 `CredentialStore` 协议测试（保存 / 读取末 4 位 / 覆盖 / 删除）；断言 `CredentialStatus` 的 `description` 不含完整 Key

### Implementation

- [x] T022 [US3] `Sources/MMSecurity/CredentialStore.swift`：协议 + `KeychainCredentialStore`（generic password，service `ai.minimate.credentials`，`AfterFirstUnlockThisDeviceOnly`）+ `InMemoryCredentialStore`（测试用）
- [x] T023 [US3] `Sources/MMSecurity/VendorID.swift`：厂商枚举（`aliyun`、`volcengine`、`openai`）
- [ ] T024 [US3] `App/MiniMate/Screens/SettingsView.swift`：每个厂商一行，显示状态、输入（`SecureField`）、保存、删除；入口包含"能力探测"
- [ ] T025 [US3] 真机验证 quickstart US3，并执行 `git grep` 确认无明文

**Checkpoint**：SC-005 达成

---

## Phase 6: Polish

- [ ] T026 [P] 更新 `AGENTS.md` 中的构建与测试命令（若实际命令与文档不同）
- [ ] T027 按 quickstart 第五节完成全部验收勾选，并在 `research.md` 填完实测表

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → 各 User Story
- US1 与 US2、US3 可并行；US2 的 T020 与 US3 的 T025 需要 US1 的真机安装完成
- 每个 story 内：测试 → 模型 → 服务 → 界面 → 真机验证

## Implementation Strategy

1. 完成 Setup + Foundational
2. 先做 US1，确认真机与重签可行（最大的现实门槛）
3. US2 尽早拿到 V1–V3 结论，必要时调整 002/003/004 的 plan
4. US3 在进入 M2 前完成即可
