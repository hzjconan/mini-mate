---
description: "M1 感知与形象的任务列表"
---

# Tasks: M1 感知与形象

**Input**: Design documents from `/specs/002-m1-presence/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md；001 已完成

**Tests**: `MMEmotion`、`MMPerception` 中的纯逻辑测试先行（宪章 V）。

## Format: `[ID] [P?] [Story] Description`

路径均相对仓库根；`Kit/` 为 `Packages/MiniMateKit/` 的简写。

## Phase 1: Setup

- [x] T001 在 `Kit/Package.swift` 中新增 targets：`MMPerception`、`MMEmotion`、`MMAvatar` 及测试 targets `MMPerceptionTests`、`MMEmotionTests`；`MMEmotion` 声明资源 `Resources/expression-presets.json`
- [x] T002 [P] 新建 `Assets/avatar/README.md`：记录素材来源、许可、导出步骤（research.md D3）
- [x] T003 [P] 在 `App/MiniMate/Info.plist` 中添加 `NSCameraUsageDescription`

---

## Phase 2: Foundational（共享类型）

- [x] T004 [P] `Kit/Sources/MMCore/EmotionTag.swift`、`ActionTag.swift`、`UserEmotion.swift`（data-model.md）
- [x] T005 [P] `Kit/Sources/MMCore/ConversationEvent.swift`
- [x] T006 [P] `Kit/Tests/MMCoreTests/LatencyRecorderTests.swift`：p50/p90 计算、空样本、导出 CSV（先写）
- [x] T007 `Kit/Sources/MMCore/Metrics/LatencyRecorder.swift`：按指标名记录样本，计算 p50/p90，导出 CSV
- [x] T008 [P] `Kit/Sources/MMPerception/PerceptionFeatures.swift`、`FaceSignals`、`GestureEvent`
- [x] T009 [P] `Kit/Sources/MMEmotion/AvatarState.swift`、`AvatarPose.swift`、`ExpressionPreset.swift`、`ReactionRules.swift`
- [x] T010 [P] 协议：`Kit/Sources/MMPerception/PerceptionSource.swift`、`Kit/Sources/MMEmotion/EmotionStateMachine.swift`、`Kit/Sources/MMAvatar/AvatarRenderer.swift`（contracts/）

**Checkpoint**：`swift build` 通过

---

## Phase 3: User Story 1 - 能被逐个表情驱动的形象 (P1) 🎯 MVP

**Goal**：打通素材管线（V10），形象可渲染、可驱动、可播动作，待机自然。

**Independent Test**：quickstart 第一节。

- [x] T011 [US1] 选定 VRoid Perfect Sync 模型并确认许可；在 Blender 中导入、核对 52 个形态键命名、补齐缺失项（research.md D3）（用 hinzka/52blendshapes-for-VRoid-face 临时模型，52 个名称零缺失）
- [x] T012 [US1] 制作或导入 8 个动作片段，命名与 `ActionTag` 一致；导出 `App/MiniMate/Resources/Avatar/minimate.usdz`（当前为程序化占位动作，14 MB，含 8 条 SkelAnimation；后续由 `Assets/avatar/auto-build/` 重新生成）
- [x] T012a [US1] 修复 auto-build 多动作绑定：8 个动作合并为一条 `SkelAnimation` 时间线 + `actions.json`，运行时按清单裁出片段；修复 `spin` 旋转采样（`docs/avatar-action-binding-issue.md`）
- [x] T013 [US1] `Kit/Sources/MMAvatar/BlendShapeIndex.swift`：加载后建立 ARKit 名称 → 索引映射，报告缺失项
- [x] T014 [US1] `Kit/Sources/MMAvatar/RealityKitAvatarRenderer.swift`：加载 USDZ、`BlendShapeWeightsComponent` 写入权重、动作播放与过渡（contracts/avatar-renderer.md R-1–R-5）
- [x] T015 [P] [US1] `Kit/Tests/MMEmotionTests/IdleMotionLayerTests.swift`：眨眼间隔分布（2–6 s）、呼吸周期、权重范围（先写）
- [x] T016 [US1] `Kit/Sources/MMAvatar/IdleMotionLayer.swift`：呼吸与眨眼（可注入时钟与随机源）
- [x] T017 [US1] `App/MiniMate/Screens/AvatarScreen.swift`：`RealityView` + 固定虚拟相机 + 每帧驱动（当前为占位形象）
- [x] T018 [US1] `App/MiniMate/Screens/Debug/AvatarDebugPanel.swift`：52 个滑杆、动作点播（当前为占位形象）
- [ ] T019 [US1] 真机执行 quickstart 第一节，结果写入 `research.md`；若 V10 失败，停止后续任务并评估自建模型或 Live2D，修订 plan

**Checkpoint**：SC-001 达成

---

## Phase 4: User Story 2 - 它在看我 (P1)

**Goal**：视线跟随、注意/离开/回来/靠近反应。

**Independent Test**：quickstart 第二节。

### Tests（先写）

- [ ] T020 [P] [US2] `Kit/Tests/MMPerceptionTests/OneEuroFilterTests.swift`：静止输入收敛、阶跃响应延迟上限、参数边界
- [ ] T021 [P] [US2] `Kit/Tests/MMPerceptionTests/LookingAtScreenTests.swift`：夹角阈值、最短持续 200 ms、人脸丢失
- [ ] T022 [P] [US2] `Kit/Tests/MMEmotionTests/AttentionTransitionTests.swift`：Idle ↔ Attending、丢失 3 s 回 Idle、回来触发 `notice`、快速靠近触发 `leanBack`（假时钟）

### Implementation

- [ ] T023 [P] [US2] `Kit/Sources/MMPerception/OneEuroFilter.swift`
- [ ] T024 [US2] `Kit/Sources/MMPerception/ARKitPerceptionSource.swift`：独立 `ARSession`、delegate、人脸位置与 `isLookingAtScreen`、后台中断恢复（contracts/perception-source.md P-1、P-5、P-6）
- [ ] T025 [P] [US2] `Kit/Sources/MMPerception/ScriptedPerceptionSource.swift`：JSON Lines 回放
- [ ] T026 [US2] `Kit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift`：Idle / Attending 转换、视线目标计算、姿态合成第 1、5、6 步（contracts/emotion-state-machine.md）
- [ ] T027 [US2] `AvatarScreen` 接入：感知 → 状态机 → 渲染；记录 M_track（用户脸位置变化 → 形象头部朝向变化的时间差）
- [ ] T028 [US2] 调试面板增加"录制感知"导出 JSON Lines，"指标"页显示 p50/p90
- [ ] T029 [US2] 真机执行 quickstart 第二节，记录 SC-002

**Checkpoint**：SC-002 达成，主观"它在看我"

---

## Phase 5: User Story 3 - 用自己的方式回应表情 (P1)

**Goal**：微笑 / 皱眉 / 惊讶 → 形象自己的回应，带延迟与冷却，非镜像。

**Independent Test**：quickstart 第三节；macOS 用录制回放测试。

### Tests（先写）

- [ ] T030 [P] [US3] `Kit/Tests/MMPerceptionTests/FaceSignalDeriverTests.swift`：D5 公式、阈值滞回、最短持续（参数化测试）
- [ ] T031 [P] [US3] `Kit/Tests/MMEmotionTests/ExpressionReactionTests.swift`：S-2（冷却）、S-3（延迟区间，固定随机种子）、皱眉 → `concerned`
- [ ] T032 [P] [US3] `Kit/Tests/MMEmotionTests/NoMirroringTests.swift`：S-1；用 `RecordingAvatarRenderer` 回放录制序列，计算同名 blendShape 相关系数 < 0.3（SC-004）

### Implementation

- [ ] T033 [P] [US3] `Kit/Sources/MMPerception/FaceSignalDeriver.swift`
- [ ] T034 [P] [US3] `Kit/Sources/MMEmotion/Resources/expression-presets.json`：8 个 `EmotionTag` 预设（在调试面板中调出满意的权重后导出）
- [ ] T035 [US3] 状态机：感知反应映射、计划反应队列、冷却、姿态合成第 2、3 步
- [ ] T036 [P] [US3] `Kit/Sources/MMAvatar/RecordingAvatarRenderer.swift`
- [ ] T037 [US3] 调试面板增加"镜像检测"（30 s 相关系数）与 M_reflex 记录
- [ ] T038 [US3] 真机执行 quickstart 第三节，调参后把 D5 阈值写回 `research.md` 与 `ReactionRules` 默认值

**Checkpoint**：SC-003、SC-004 达成

---

## Phase 6: User Story 4 - 回应手势 (P2)

**Goal**：挥手、比心、点赞。

**Independent Test**：quickstart 第四节。

### Tests（先写）

- [ ] T039 [P] [US4] `Kit/Tests/MMPerceptionTests/HandGestureClassifierTests.swift`：用合成关节点序列测试三种手势与若干负样本（抬手、摸脸）；边沿触发（P-3）

### Implementation

- [ ] T040 [US4] `Kit/Sources/MMPerception/HandGestureClassifier.swift`（plan 关键设计中的规则）
- [ ] T041 [US4] `ARKitPerceptionSource` 中按 12 Hz 抽帧执行 `VNDetectHumanHandPoseRequest`（`ARFrame.capturedImage`，注意前置摄像头方向）；`thermalState` 降频（P-4）
- [ ] T042 [US4] 状态机：手势反应映射（contracts 表）
- [ ] T043 [US4] 真机执行 quickstart 第四节，记录 SC-005

**Checkpoint**：SC-005 达成

---

## Phase 7: User Story 5 - 对话阶段状态 (P3)

**Goal**：Listening / Thinking / Speaking 与优先级规则就绪，供 M2 直接使用。

**Independent Test**：quickstart 第五节。

### Tests（先写）

- [ ] T044 [P] [US5] `Kit/Tests/MMEmotionTests/ConversationTransitionTests.swift`：转换表中全部对话相关行；S-4、S-5；打断清空计划反应；口型层覆盖嘴部系数

### Implementation

- [ ] T045 [US5] 状态机：对话事件处理、`userEmotion` → `baseEmotion` 映射、口型层（姿态合成第 4 步）
- [ ] T046 [US5] 调试面板增加"对话事件"注入与状态显示；记录注入场景下的 M_feedback
- [ ] T047 [US5] 真机执行 quickstart 第五节

---

## Phase 8: Polish

- [ ] T048 真机执行 quickstart 第六节（SC-006），必要时优化（降低贴图、减少面数、手势降频）
- [ ] T049 主观验收 SC-007；全部实测数据写入 `research.md`
- [ ] T050 [P] 若实测推翻 tech-selection 中的假设（如素材管线、阈值），同步修订 `docs/tech-selection.md`

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → US1（阻塞：V10 失败则后续 story 需重新规划渲染）
- US2 依赖 US1 的渲染；US3、US4 依赖 US2 的感知源与状态机骨架
- US5 只依赖 Phase 2 与状态机骨架（T026），可与 US3/US4 并行
- 纯逻辑测试与实现（T020–T023、T030–T034、T039–T040、T044）可在素材未就绪时先行

## Implementation Strategy

1. 第一周：Phase 1–3，确认 V10。不通则立即止损改路线
2. 第二周：US2，达到"它在看我"
3. 第三周：US3 + US5 并行，定下"陪伴而非镜像"的手感
4. 之后：US4 与 Polish
