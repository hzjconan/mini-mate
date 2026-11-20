---
description: "M3 记忆、离线与预置短句的任务列表"
---

# Tasks: M3 记忆、离线与预置短句

**Input**: Design documents from `/specs/004-m3-memory-offline/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md；003 已完成

**Tests**: 纯逻辑模块测试先行（宪章 V）。

## Format: `[ID] [P?] [Story] Description`

`Kit/` 为 `Packages/MiniMateKit/` 的简写。

## Phase 1: Setup

- [ ] T001 `Kit/Package.swift` 新增 target `MMMemory` 与 `MMMemoryTests`；`MMConversation` 增加资源 `preset-phrases.json`、`offline-intents.json`
- [ ] T002 [P] `App/MiniMate/Info.plist` 增加 `NSSpeechRecognitionUsageDescription`（端侧转写）
- [ ] T003 [P] 在 `AppComposition` 中创建 SwiftData `ModelContainer`

---

## Phase 2: Foundational

### Tests（先写）

- [ ] T004 [P] `Kit/Tests/MMMemoryTests/TokenEstimatorTests.swift`：中文 / ASCII / 混合，10% 余量
- [ ] T005 [P] `Kit/Tests/MMMemoryTests/MemoryStoreTests.swift`：内存容器下的增删查、级联删除、清空

### Implementation

- [ ] T006 [P] `Kit/Sources/MMMemory/Models/*.swift`：`ConversationSession`、`Turn`、`SessionSummary`、`MemoryFact`（data-model.md）
- [ ] T007 [P] `Kit/Sources/MMMemory/TokenEstimator.swift`
- [ ] T008 `Kit/Sources/MMMemory/MemoryStore.swift`
- [ ] T009 `Kit/Sources/MMMemory/TurnRecorder.swift`：订阅 `ConversationEvent`，每轮结束落盘；冷启动补齐 `endedAt`

**Checkpoint**：对话轮次可持久化

---

## Phase 3: User Story 1 - 它记得我 (P1) 🎯

**Goal**：跨会话记忆、事实更新、情绪趋势、会话重建。

**Independent Test**：quickstart 第二节。

### Tests（先写）

- [ ] T010 [P] [US1] `Kit/Tests/MMMemoryTests/SessionContextBuilderTests.swift`：contracts/session-context.md C-1–C-6 与预算边界
- [ ] T011 [P] [US1] `Kit/Tests/MMMemoryTests/FactMergerTests.swift`：data-model.md 合并规则四种情况
- [ ] T012 [P] [US1] `Kit/Tests/MMMemoryTests/MoodTrendTests.swift`
- [ ] T013 [P] [US1] `Kit/Tests/MMMemoryTests/MemoryMaintenanceTests.swift`：用假 `TextLLMProvider` 验证 M-1–M-5（重试、未知类别、触发时机、rolling 不抽取、skip 轮次）

### Implementation

- [ ] T014 [P] [US1] `Kit/Sources/MMMemory/SessionContextBuilder.swift`
- [ ] T015 [P] [US1] `Kit/Sources/MMMemory/FactMerger.swift`
- [ ] T016 [P] [US1] `Kit/Sources/MMMemory/MoodTrend.swift`
- [ ] T017 [US1] `Kit/Sources/MMConversation/Text/TextLLMProvider.swift` + 选定厂商实现
- [ ] T018 [US1] `Kit/Sources/MMMemory/MemoryMaintenance.swift`：contracts/memory-extraction.md 的请求组装、解析、重试、触发时机
- [ ] T019 [US1] 对话引擎接入：建立会话时调用 `SessionContextBuilder`；会话内 ≥ 20 轮与断线重连时做 rolling 摘要并重建（contracts/session-context.md "会话重建"）
- [ ] T020 [US1] 若 003 V7 结论为实时接口不提供用户转写：接入端侧 `LocalTranscriber` 并行转写写入 `Turn.userText`
- [ ] T021 [US1] 真机执行 quickstart 第二节，记录 SC-001、SC-002

**Checkpoint**：SC-001–SC-003 达成

---

## Phase 4: User Story 2 - 断网不傻 (P1)

**Goal**：离线引擎、意图匹配、在线 / 离线自动切换。

**Independent Test**：quickstart 第四节。

### Tests（先写）

- [ ] T022 [P] [US2] `Kit/Tests/MMConversationTests/IntentMatcherTests.swift`：关键词层全部初版意图 × 2 种说法；I-3 预处理；负样本 → `fallback`
- [ ] T023 [P] [US2] `Kit/Tests/MMConversationTests/EngineSwitcherTests.swift`：切换表全部转换、SW-2、SW-3（假时钟）
- [ ] T024 [P] [US2] `Kit/Tests/MMConversationTests/OfflineEngineTests.swift`：事件顺序、O-1、O-3 回退

### Implementation

- [ ] T025 [P] [US2] `Kit/Sources/MMConversation/Resources/offline-intents.json`（contracts/offline-intents.md 初版意图）
- [ ] T026 [US2] `Kit/Sources/MMConversation/Offline/IntentMatcher.swift`：关键词层 + `NLEmbedding` 层（依 001 结论）
- [ ] T027 [US2] `Kit/Sources/MMConversation/Offline/LocalTranscriber.swift`：`SpeechTranscriber` 或 `SFSpeechRecognizer`（research.md D5）
- [ ] T028 [P] [US2] `Kit/Sources/MMConversation/TTS/SystemTTSProvider.swift`（`AVSpeechSynthesizer`，输出到同一 `AudioIO`）
- [ ] T029 [US2] `Kit/Sources/MMConversation/OfflineConversationEngine.swift`
- [ ] T030 [US2] `Kit/Sources/MMConversation/EngineSwitcher.swift` + `NWPathMonitor` 适配；`AppComposition` 改为经由切换器提供引擎
- [ ] T031 [US2] 真机调参 `NLEmbedding` 阈值（research.md 待实测项），写回 `IntentMatcher` 默认值
- [ ] T032 [US2] 真机执行 quickstart 第四节，记录 SC-004、SC-005

**Checkpoint**：SC-004、SC-005 达成

---

## Phase 5: User Story 3 - 预置短句与垫场 (P2)

**Goal**：同音色预合成、低延迟播放、按阈值垫场。

**Independent Test**：quickstart 第一、五节。

### Tests（先写）

- [ ] T033 [P] [US3] `Kit/Tests/MMConversationTests/FillerPolicyTests.swift`：F-1、F-2
- [ ] T034 [P] [US3] `Kit/Tests/MMConversationTests/PresetCacheTests.swift`：manifest 失效判定（P-3）、原子替换（P-2，临时目录）
- [ ] T035 [P] [US3] `RealtimeTextEngineTests` 增加：垫场后实质回答排队（F-3）

### Implementation

- [ ] T036 [P] [US3] `Kit/Sources/MMConversation/Resources/preset-phrases.json`（contracts/preset-phrases.md 初版清单）
- [ ] T037 [US3] `Kit/Sources/MMConversation/Presets/PresetCatalog.swift`、`PresetSynthesizer.swift`、`PresetPlayer.swift`
- [ ] T038 [US3] `Kit/Sources/MMConversation/Filler/FillerPolicy.swift`；在线引擎接入垫场
- [ ] T039 [US3] `App/MiniMate/Screens/Settings/PresetPhrasesView.swift`：状态、生成进度、试听；`.stale` 时在首页提示
- [ ] T040 [US3] 真机执行 quickstart 第一、五节，记录 SC-006、SC-007；按 003 首个文字耗时分布调整阈值

**Checkpoint**：SC-006、SC-007 达成

---

## Phase 6: User Story 4 - 记忆管理 (P2)

**Goal**：查看、删除、清空。

**Independent Test**：quickstart 第三节。

- [ ] T041 [US4] `App/MiniMate/Screens/Settings/MemoryView.swift`：按类别列出事实（含过时标记与来源时间）、滑动删除、"清空全部"二次确认
- [ ] T042 [US4] 真机执行 quickstart 第三节，记录 SC-008

---

## Phase 7: User Story 5 - 本地快速指令 (P3，可选)

**Goal**：在线时闭集指令 < 500 ms。

**Independent Test**：quickstart 第六节。

- [ ] T043 [P] [US5] `Kit/Tests/MMConversationTests/QuickCommandDedupTests.swift`：本地已执行动作后，同轮云端 `<act>` 去重
- [ ] T044 [US5] 在线引擎并行运行 `LocalTranscriber` + `IntentMatcher`（仅关键词层，避免误触发），命中即发出 `assistantAction`；本轮去重
- [ ] T045 [US5] 设置中增加开关；真机执行 quickstart 第六节，记录 SC-009

---

## Phase 8: Polish

- [ ] T046 [P] 冷启动补摘要、App 被杀后数据完整性测试（手动：对话中强杀 App）
- [ ] T047 [P] 实测结论写入 `research.md`；若推翻 tech-selection 假设，同步修订 `docs/tech-selection.md`
- [ ] T048 根据 003 与本 feature 的 M_answer 数据，在 `docs/tech-selection.md` 中给出 M4 是否启动的结论

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → US1、US2、US3 可并行（均依赖 Phase 2 与 003）
- US2 的离线话术依赖 US3 的预合成短句；US3 未完成时 US2 使用 `SystemTTSProvider` 兜底
- US4 依赖 US1 的数据
- US5 依赖 US2 的 `LocalTranscriber` 与 `IntentMatcher`

## Implementation Strategy

1. 先 Phase 2 + US1（陪伴连续性收益最大）
2. US3 与 US2 并行（US3 简单，可先给 US2 提供短句）
3. US4 随 US1 一起收尾
4. US5 视 003 中闭集指令的体感延迟决定是否实施
