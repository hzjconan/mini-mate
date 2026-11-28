---
description: "M2 语音对话的任务列表"
---

# Tasks: M2 语音对话

**Input**: Design documents from `/specs/003-m2-voice-conversation/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md；001 完成；002 的状态机与渲染可用（US6 需要）

**Tests**: 纯逻辑模块测试先行（宪章 V）。

## Format: `[ID] [P?] [Story] Description`

`Kit/` 为 `Packages/MiniMateKit/` 的简写。

## Phase 1: Setup

- [x] T001 `Kit/Package.swift` 新增 targets：`MMAudio`、`MMConversation`（资源：`persona.md`、`tts-emotion-*.json`）、executable `mm-probe`（target `MMProbeCLI`，仅 macOS）、测试 `MMAudioTests`、`MMConversationTests`
- [x] T002 [P] `.gitignore` 增加 `Assets/voice-samples/*.wav`
- [x] T003 [P] `App/MiniMate/Info.plist` 增加 `NSMicrophoneUsageDescription`
- [x] T004 [P] `MMSecurity/VendorID.swift` 按候选厂商更新（`aliyun`、`volcengine`、`openai`）
- [x] T005 [P] `Kit/Sources/MMConversation/Resources/persona.md`：写入人格设定：名字"小瓜"，呆萌、俏皮、话不多，称呼用户为"你"，每次回答 1–3 句（spec.md Assumptions）

---

## Phase 2: Foundational

### Tests（先写）

- [x] T006 [P] `Kit/Tests/MMConversationTests/TagParserTests.swift`：tag-protocol.md T-1–T-7；随机切分一致性（参数化）
- [x] T007 [P] `Kit/Tests/MMConversationTests/SentenceSplitterTests.swift`：S-1–S-7

### Implementation

- [x] T008 [P] `Kit/Sources/MMAudio/AudioChunk.swift`、`GateState.swift`；`MMCore/ConversationEvent.swift` 增加 `connectionStateChanged`、`gateStateChanged`
- [x] T009 [P] `Kit/Sources/MMConversation/Realtime/RealtimeTextSession.swift`、`RealtimeOutput`、`RealtimeError`（contracts/realtime-session.md）
- [x] T010 [P] `Kit/Sources/MMConversation/TTS/TTSProvider.swift`、`EmotionMapping.swift`、`FakeTTSProvider.swift`
- [x] T011 [P] `Kit/Sources/MMConversation/TagParser.swift`（使 T006 通过）
- [x] T012 [P] `Kit/Sources/MMConversation/SentenceSplitter.swift`（使 T007 通过）
- [x] T013 [P] `Kit/Sources/MMConversation/Persona.swift`：加载 `persona.md`，与标签协议说明拼成 instructions
- [x] T014 [P] `Kit/Sources/MMAudio/PCMConverter.swift`：重采样到 16 / 24 kHz Int16（macOS 可测，附测试）

**Checkpoint**：解析与分句测试全部通过

---

## Phase 3: User Story 1 - 方案 B 验证与选型 (P1) 🎯

**Goal**：M2a，选定厂商与方案。

**Independent Test**：quickstart 第一节。

- [ ] T015 [US1] 查阅各候选厂商最新文档，填写 `contracts/realtime-session.md` 厂商附录（endpoint、鉴权、只出文字配置、音频格式、VAD、取消、转写事件）
- [ ] T016 [P] [US1] `Kit/Sources/MMConversation/Realtime/QwenOmniRealtimeSession.swift`
- [ ] T017 [P] [US1] `Kit/Sources/MMConversation/Realtime/DoubaoRealtimeSession.swift`
- [ ] T018 [P] [US1] `Kit/Sources/MMConversation/TTS/CosyVoiceTTSProvider.swift`
- [ ] T019 [P] [US1] `Kit/Sources/MMConversation/TTS/DoubaoTTSProvider.swift`
- [ ] T020 [US1] `Kit/Sources/MMProbeCLI/main.swift`：`realtime`、`tone-suite`、`tts`、`record-fixture` 子命令（plan "mm-probe 子命令"）；Key 只从环境变量读取
- [ ] T021 [US1] 录制 9 个语气样本到 `Assets/voice-samples/`
- [ ] T022 [US1] 运行 quickstart 第一节；用 `record-fixture` 为每个适配器录制夹具到 `Kit/Tests/MMConversationTests/Fixtures/`（确认已去除鉴权信息）
- [ ] T023 [P] [US1] `Kit/Tests/MMConversationTests/RealtimeDecodingTests.swift`：用夹具回放验证各适配器的 `RealtimeOutput` 映射（RS-5）
- [ ] T024 [US1] 填写 `research.md` M2a 对比与选型结论；填写 `Resources/tts-emotion-<vendor>.json`
- [ ] T025 [US1] 删除未选中厂商的适配器、夹具与附录（宪章 VI）；若结论为方案 C，跳到 Phase 9

**Checkpoint**：SC-001、SC-002 达成，厂商与方案已定

---

## Phase 4: User Story 2 - 免唤醒对话闭环 (P1)

**Goal**：闸门 → 实时会话 → 解析 → 分句 → TTS → 同引擎播放；回声消除；多轮。

**Independent Test**：quickstart 第三节。

### Tests（先写）

- [ ] T026 [P] [US2] `Kit/Tests/MMAudioTests/EnergyVoiceGateTests.swift`：G-1–G-3（合成正弦 / 噪声 / 静音 PCM）
- [ ] T027 [P] [US2] `Kit/Tests/MMAudioTests/PreRollBufferTests.swift`
- [ ] T028 [P] [US2] `Kit/Tests/MMConversationTests/RealtimeTextEngineTests.swift`：用假 Session + `FakeTTSProvider` + 假 AudioIO 验证 contracts/conversation-engine.md 事件顺序、E-1、E-3；PV-1（闸门关闭时 `send` 调用 0 次）
- [ ] T029 [P] [US2] `Kit/Tests/MMConversationTests/TurnMetricsTests.swift`：各时间点填充与 M_feedback / M_answer 计算

### Implementation

- [ ] T030 [P] [US2] `Kit/Sources/MMAudio/PreRollBuffer.swift`、`VoiceActivityGate.swift`（`EnergyVoiceGate`）
- [ ] T031 [US2] `Kit/Sources/MMAudio/AudioSessionController.swift`、`AudioIO.swift`（iOS）：IO-1–IO-5，输出电平
- [ ] T032 [P] [US2] `Kit/Sources/MMAudio/SpeechDetectorGate.swift`（仅当 001 探测 V3 可用）
- [ ] T033 [US2] `Kit/Sources/MMConversation/TurnCoordinator.swift`：turnID、取消、迟到事件丢弃
- [ ] T034 [US2] `Kit/Sources/MMConversation/RealtimeTextConversationEngine.swift`：组装闸门、会话、解析、分句、TTS 队列（预取 1 句）、播放、事件发出；断线重连（0.5 / 1 / 2 s）
- [ ] T035 [US2] `Kit/Sources/MMConversation/TurnMetrics.swift` 与 `MMCore/Metrics/LatencyRecorder` 对接
- [ ] T036 [US2] `App/MiniMate/AppComposition.swift`：创建引擎，`events` 转发给情绪状态机；`AvatarScreen` 启动 / 停止引擎
- [ ] T037 [US2] `App/MiniMate/Screens/Debug/ConversationDebugPanel.swift`：闸门状态、连接状态、每轮文字与标签、分段耗时、p50/p90、已上传字节数
- [ ] T038 [US2] 真机执行 quickstart 第三节；若自问自答，按 research.md D5 调整（降低音量 / 提高 playback 阈值），记录 V8

**Checkpoint**：SC-003、SC-004、SC-008 达成

---

## Phase 5: User Story 3 - 听得出语气 (P1)

**Goal**：`<user>` 驱动 Thinking 神情；回答以语气为准。

**Independent Test**：quickstart 第四节。

- [ ] T039 [US3] 确认 `persona.md` + 标签协议说明中包含"语气优先"规则（tag-protocol.md 第 5 条）
- [ ] T040 [US3] 引擎在第一个 `assistantSpeechStarted` 之前发出 `userEmotion`（补充 T028 用例）
- [ ] T041 [US3] 真机执行 quickstart 第四节；必要时调整 instructions 措辞，并在 `research.md` 记录

---

## Phase 6: User Story 4 - 打断 (P1)

**Goal**：M_bargein < 300 ms，误打断 0。

**Independent Test**：quickstart 第五节第 1 步。

### Tests（先写）

- [ ] T042 [P] [US4] `Kit/Tests/MMAudioTests/BargeInDetectorTests.swift`：B-1–B-3
- [ ] T043 [P] [US4] `RealtimeTextEngineTests` 增加打断用例：E-2、B-4 调用顺序、旧 turn 的 TTS 音频不再入队（TTS-5）

### Implementation

- [ ] T044 [US4] `Kit/Sources/MMAudio/BargeInDetector.swift`
- [ ] T045 [US4] 引擎接入打断流程（B-4）；记录 M_bargein
- [ ] T046 [US4] 真机执行 quickstart 第五节第 1 步，记录 SC-006

---

## Phase 7: User Story 5 - 视线软闸门与静音 (P2)

**Goal**：电视 / 旁人不误触发；静音一步可达。

**Independent Test**：quickstart 第五节第 2–5 步。

### Tests（先写）

- [ ] T047 [P] [US5] `Kit/Tests/MMAudioTests/GazeGatePolicyTests.swift`：四条规则与时间边界
- [ ] T048 [P] [US5] `RealtimeTextEngineTests` 增加：`paused` / `muted` 不建立会话（PV-2）；恢复后重建会话

### Implementation

- [ ] T049 [US5] `Kit/Sources/MMAudio/GazeGatePolicy.swift`
- [ ] T050 [US5] App：感知结果 → `GazeGatePolicy` → `engine.setGazeDecision`；静音按钮 → `engine.setMuted`
- [ ] T051 [US5] 状态机：`gateStateChanged(.muted)` → 静音姿态（`shyCover` 或专用"捂耳朵"预设）；`paused` → Idle
- [ ] T052 [US5] 真机执行 quickstart 第五节第 2–5 步，记录 SC-007、V9

---

## Phase 8: User Story 6 - 口型、表情、动作联动 (P2)

**Goal**：口型随声音；`<emo>` 同步切换表情与 TTS 语气；`<act>` 按位置触发。

**Independent Test**：quickstart 第六节。

- [ ] T053 [US6] 引擎：按句开始播放时发 `assistantEmotion`；按字符偏移估算 `<act>` 的播放时间点（字数比例 × 句音频时长；有时间戳时用时间戳）
- [ ] T054 [US6] `AudioIO.outputLevel` → `assistantAudioLevel`（≥ 30 Hz）→ 状态机口型层
- [ ] T055 [US6] 真机执行 quickstart 第六节，记录 SC-009

---

## Phase 9: User Story 7 - 方案 C（仅当 T024 结论为 C）(P3)

- [ ] T056 [US7] `Kit/Sources/MMConversation/RealtimeVoiceConversationEngine.swift`：模型直接出语音；从回答转写推断情绪（本地关键词 / `NLEmbedding`）；口型取输出音频电平
- [ ] T057 [US7] 复用 T026–T048 中与方案无关的测试；新增情绪推断测试
- [ ] T058 [US7] 真机重跑 quickstart 第三–六节

---

## Phase 10: Polish

- [ ] T059 晚间高峰时段补测 20 轮（quickstart 第七节），完成 `research.md` M2b 指标表
- [ ] T060 若 M_answer p50 > 1.5 s：按 tech-selection 4.3.2 尝试缩短首句下限、调整服务端 VAD 静音时长，记录前后对比
- [ ] T061 [P] 检查日志与夹具中无 Key（`git grep` + 运行时日志抽查）
- [ ] T062 [P] 实测结论回写 `docs/tech-selection.md`（厂商、方案、指标、V4–V9）

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → US1（阻塞：未选定厂商前不开始 US2）
- US2 → US3、US4、US5（依赖引擎与 AudioIO）
- US6 依赖 US2 与 002 的状态机口型层
- US7 仅在 US1 结论为方案 C 时执行，替代 US2 的引擎实现
- 纯逻辑测试（T006–T007、T026–T029、T042–T043、T047–T048）可在 US1 期间并行编写

## Implementation Strategy

1. 第一周：Phase 1–3（M2a），尽快拿到选型结论
2. 第二周：US2 闭环 + 回声消除（最大风险）
3. 第三周：US3、US4、US5
4. 之后：US6 联动与 Polish
