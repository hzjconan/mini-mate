---
description: "语音拍照的任务列表"
---

# Tasks: 语音拍照

**Input**: Design documents from `/specs/005-voice-photo/`（2026-11-26 按两轮外部评审修订）

**Prerequisites**:

- Phase 0（契约同步）在 005 计划定稿后、任何代码开工前完成。
- Phase 1–3 只依赖已完成的 002 US1–US4，可立即开工。
- Phase 4 起依赖 **002 US5**（情绪状态机接入对话事件，含 `assistantCue`）与 **003**（含本 feature 的契约增补）。

**Tests**: 纯逻辑模块测试先行（宪章 V）。

## Format: `[ID] [P?] [Story] Description`

`Kit/` 为 `Packages/MiniMateKit/` 的简写。

## Phase 0: 契约同步（定稿后、开工前）

- [ ] T000 按 plan.md"对既有契约的修改"更新 002 `data-model.md`、`contracts/emotion-state-machine.md`（EM-1–EM-5）、`contracts/perception-source.md`（P-6）、`tasks.md`（US5 增加 `assistantCue` 的测试与实现）；003 `contracts/tag-protocol.md`、`conversation-engine.md`（C-1–C-4、RH-1–RH-5）、`audio-gating.md`（AF-1–AF-4）；004 `contracts/preset-phrases.md`（PP-4、PP-5、`photo.*`）

---

## Phase 1: Setup

- [ ] T001 `Kit/Package.swift` 新增 target `MMPhoto`（依赖 `MMCore`、`MMPerception`）与 `MMPhotoTests`；App target 链接 `MMPhoto`
- [ ] T002 [P] App 构建设置（Debug 与 Release）新增 `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription`；修改 `INFOPLIST_KEY_NSCameraUsageDescription` 为"只在你让它拍照时保存照片到相册，画面不会上传"（FR-020）
- [ ] T003 [P] 程序生成快门音效 `App/MiniMate/Resources/shutter.caf`（research D10）
- [ ] T004 [P] `Kit/Sources/MMPerception/ARKitPerceptionSource.swift`：`state`、`sessionQueue`、`gestureQueue` 由 `private` 改为 `internal`（行为不变，现有测试全部通过）

---

## Phase 2: Foundational（纯逻辑与协议，不依赖 003）

### Tests（先写）

- [ ] T005 [P] `Kit/Tests/MMPhotoTests/CornerPlacementTests.swift`：photo-output.md CP-1–CP-6（含竖屏 3:4 / 9:16、多人）
- [ ] T006 [P] `Kit/Tests/MMPhotoTests/PhotoCompositorTests.swift`：合成区域像素、HEIC 可解码、回退 JPEG 且 `uti` 正确
- [ ] T007 [P] `Kit/Tests/MMPhotoTests/SpeakingMotionDetectorTests.swift`：两路独立参数；反复开合 → 说话；持续张嘴 / 闭嘴 → 不说话；样本不足（含 Vision 8 Hz 下 0.5 s 窗口的边界）；任一通道任一张脸为真即为真；`trackID` 丢失与重现
- [ ] T008 [P] `Kit/Tests/MMPerceptionTests/FaceTrackAssociatorTests.swift`、`InnerLipOpennessTests.swift`：photo-capture.md 测试要求

### Implementation

- [ ] T009 [P] `Kit/Sources/MMCore/AssistantCommand.swift`、`AvatarCue.swift`；`ConversationEvent` 新增 `assistantCommand`、`assistantCue`、`assistantCueEnded`
- [ ] T010 [P] `Kit/Sources/MMPerception/PhotoCapture.swift`：`PhotoCaptureSource`、`MouthActivitySource` 协议与值类型；`ScriptedPhotoCaptureSource`、`ScriptedMouthActivitySource`
- [ ] T011 [P] `Kit/Sources/MMPerception/FaceTrackAssociator.swift`、`InnerLipOpenness.swift`
- [ ] T012 [P] `Kit/Sources/MMPhoto/PhotoFlowTypes.swift`、`Protocols.swift`：data-model.md 中 MMPhoto 的全部类型；`AvatarSnapshotter`、`PhotoLibraryWriter`、`CountdownVoice`、`PhotoAudioFeedback`、`GestureSuspending`、`ReplyHolding`
- [ ] T013 [P] `Kit/Sources/MMPhoto/CornerPlacement.swift`
- [ ] T014 [P] `Kit/Sources/MMPhoto/PhotoCompositor.swift`（只做合成与编码）
- [ ] T015 [P] `Kit/Sources/MMPhoto/SpeakingMotionDetector.swift`
- [ ] T016 [P] `Kit/Sources/MMPhoto/Fakes/`、`SilentCountdownVoice.swift`（按标称时长等待）

**Checkpoint**：`swift test --filter "MMPhotoTests|MMPerceptionTests"` 通过

---

## Phase 3: User Story 1 - 技术路径验证 (P1)

**Goal**：确定取帧方式（D1）、形象快照方式（D3）、是否需要 Vision 兜底判断"人在画面中"（D12 / R11），并验证口型检测的可行性与负载。不依赖 002 US5 与 003。

**Independent Test**：quickstart 第一、二节。

- [ ] T017 [US1] `Kit/Sources/MMPerception/ARKitPerceptionSource+PhotoCapture.swift`：PC-1–PC-9，运行时探测方式 A / B，方向转换（D7），照片人脸框（PC-5），取景预览流
- [ ] T018 [US1] `Kit/Sources/MMPerception/ARKitPerceptionSource+MouthActivity.swift`：MA-1–MA-6
- [ ] T019 [US1] `Kit/Sources/MMAvatar/AvatarFraming.swift`：把相机与构图参数从 `AvatarScreen.swift` 抽出，`AvatarScreen` 改为使用它（行为不变）
- [ ] T020 [US1] `Kit/Sources/MMAvatar/AvatarOffscreenSnapshotter.swift`：影子克隆实体 + 快门时同步骨骼 / 形态键 / `HeartEffect`（AS-2、AS-3）；先在调试面板验证 R4
- [ ] T021 [US1] 调试面板"拍照"页：取帧方式、视频格式列表、测试拍照、取景预览开关与帧率、测试形象快照、口型检测开关（两路开合度曲线与"在说话"判定）、`isFaceTracked` 丢失统计、耗时与追踪中断统计、导出
- [ ] T022 [US1] 真机执行 quickstart 第一、二节：填写 research.md R1–R5、R10、R11 与 R9 冒烟（单人 0.5 m、1–1.5 m 每类 5 次；有条件时 2 人各 5 次），给出 D1 / D3 / D12 兜底结论（SC-001）；若 R4 失败，加入 `avatar-sticker.png` 与 `StickerAvatarSnapshotter`

**Checkpoint**：D1、D3、D12 兜底已定；口型检测在单人 1–1.5 m 可行

---

## Phase 4: User Story 2 - 语音拍自拍主流程 (P1) 🎯 MVP

**Goal**：说一句话 → 问"准备好了吗" → 确认 → 倒数 → 拍照 → 存相册（真实版）→ 反应 + 缩略图。

**Prerequisites**：002 US5（含 `assistantCue`）、003 完成。

**Independent Test**：quickstart 第三、四、八节。

### Tests（先写）

- [ ] T023 [P] [US2] `Kit/Tests/MMConversationTests/TagParserTests.swift` 增加 command-tag.md T-8–T-10，`<cmd>` 纳入随机切分参数化测试
- [ ] T024 [P] [US2] `Kit/Tests/MMConversationTests/RealtimeTextEngineTests.swift` 增加 C-1–C-3、RH-1–RH-5
- [ ] T025 [P] [US2] `MMAudio` 播放队列测试：AF-1–AF-3（`flush()` 只清可打断缓冲；`cancel(turnID:)` 清除指定 turn）
- [ ] T026 [P] [US2] `Kit/Tests/MMPhotoTests/PhotoFlowControllerTests.swift`：photo-flow.md 状态转换表主流程各行（idle → awaitingReplyEnd → checkingPermission（含 `notDetermined` → 授权）→ 问一次 → ready → 倒数 → cheese → capturing → saving → presenting → idle）；PF-1、PF-3（含无声降级）、PF-6、PF-8；`replyTimeout`；`muted` / `interrupted`
- [ ] T027 [P] [US2] `Kit/Tests/MMPhotoTests/PhotoFlowRunnerTests.swift`（Fakes）：副作用执行顺序；RN-2（`.stopped` 不送 `phraseFinished`）、RN-6（`.inactive` 不算中断）；快门音效调用；`captureFailed` / `saveFailed` 路径；`avatarCue` 转为 `ConversationEvent.assistantCue`；指标 M_photoStart、\|M_shutter\|

### Implementation

- [ ] T028 [US2] `MMConversation`：`TagParser` 支持 `<cmd>`；引擎按 C-1–C-3 发出 `assistantCommand`；instructions 追加第 6 条
- [ ] T029 [US2] `MMConversation`：引擎 `holdReplies()` / `releaseReplies(discardingTurnsStartedBefore:)`（RH-1–RH-5）
- [ ] T030 [US2] `MMAudio`：`enqueue(_:turnID:interruptible:)`、`flush()` 只清可打断缓冲、`cancel(turnID:)`（AF-1–AF-4）
- [ ] T031 [US2] `Kit/Sources/MMPhoto/CountdownScript.swift`、`PhotoFlowController.swift`
- [ ] T032 [US2] `Kit/Sources/MMPhoto/PhotoFlowRunner.swift`、`PhotoAttemptMetrics.swift`（RN-1–RN-7）
- [ ] T033 [US2] `Kit/Sources/MMPhoto/PhotosLibraryWriter.swift`：PL-1–PL-4，含 `requestAuthorization`；本阶段只写原图
- [ ] T034 [US2] `App/MiniMate/Resources/photo-phrases.json`；`CountdownVoiceCache`（004 未完成时）或 `PresetCountdownVoice`（004 US3 完成后）（research D5）
- [ ] T035 [US2] App 组合根与适配：`AudioFeedbackAdapter`、`GestureSuspendAdapter`、`ReplyHoldingAdapter`；`AppComposition` 组装 Runner，把 Runner 的 `cueEvents` 与 `ConversationEngine.events` 合流后送入情绪状态机；静音开关与 `scenePhase` / 音频中断接入 `PhotoControlEvent`
- [ ] T036 [US2] App UI：`PhotoUIState`、`PhotoPreviewOverlay`（镜像小窗 + 文字提示 / 倒数数字 + 闪白）、`PhotoThumbnailView`、`PhotoViewer`（本阶段只有真实版）
- [ ] T037 [US2] 调试面板"模拟拍照指令" / "模拟准备好了" / "模拟取消"按钮（注入对应 `assistantCommand` + `assistantSpeechEnded`）
- [ ] T038 [US2] 真机执行 quickstart 第三、四、八节：记录 SC-002、SC-003、SC-004、SC-005、SC-009、SC-010、SC-011（"准备好了"部分）；按 R8 调整 `CountdownScript`

**Checkpoint**：MVP 可用

---

## Phase 5: User Story 3 - 没准备好时等我、倒数时能喊停 (P1)

**Goal**：确认环节的再问 / 放弃 / 取消；倒数中"人声 + 口型"停止；"茄子"阶段不可打断；倒数期间暂缓回应。

**Independent Test**：quickstart 第五节。

- [ ] T039 [P] [US3] `PhotoFlowControllerTests` 增加：确认环节各行；PF-2、PF-4、PF-5、PF-9–PF-14；photo-flow.md 测试要求中的全部竞态与组合场景
- [ ] T040 [US3] `PhotoFlowController` / Runner 实现确认环节与倒数停止（research D6、D11）；Runner 接入 `MouthActivitySource` + `SpeakingMotionDetector`（RN-5）、`GestureSuspending`、`ReplyHolding`
- [ ] T041 [US3] 真机执行 quickstart 第五节：记录 SC-006、SC-011（"还没好"部分）、SC-012、SC-013 与 R7；单人 R9 精调，阈值写回 `SpeakingMotionParams` 默认值

---

## Phase 6: User Story 4 - 合影版 (P2)

**Goal**：每次另存一张小瓜在角落的合影。

**Independent Test**：quickstart 第六节。

- [ ] T042 [P] [US4] `PhotoFlowRunnerTests` 增加：快照超时 / 失败时只写原图；成功时两张同一事务写入，格式随数据传递
- [ ] T043 [US4] App `AvatarSnapshotAdapter`；Runner 在 `capture` 时并行快照（RN-3），`saving` 中合成并写入两张；`PhotoViewer` 支持真实 / 合影切换
- [ ] T044 [US4] 真机执行 quickstart 第六节，记录 SC-007

---

## Phase 7: User Story 5 - 不在画面与权限被拒 (P2)

**Goal**：等人脸、权限被拒的提示与引导。

**Independent Test**：quickstart 第七节。

- [ ] T045 [P] [US5] `PhotoFlowControllerTests` 增加：`waitingForFace(confirmed: false / true)` 的进入、超时、取消、恢复；倒数中人脸丢失（`faceLostTolerance`）；权限拒绝
- [ ] T046 [US5] App `PhotoPermissionBanner`（`UIApplication.openSettingsURLString`）
- [ ] T047 [US5] 若 R11 结论为需要兜底：Runner 在 `waitingForFace` 期间用 Vision 人脸数合成 `facePresence`（RN-4，同时让出手势）
- [ ] T048 [US5] 真机执行 quickstart 第七节，记录 SC-008

---

## Phase 8: User Story 6 - 多人 (P2)

**Goal**：多人时"人在画面"、任意人确认、画面内任意人喊停、合影避开所有人脸。

**Independent Test**：quickstart 第九节。

- [ ] T049 [P] [US6] `PhotoFlowRunnerTests` 增加：多人时一人离开不停止、全部离开超过 0.5 s 停止；多张人脸的 `faceRects` 传入 `CornerPlacement`
- [ ] T050 [US6] 真机 2–3 人执行 quickstart 第九节：记录 SC-014 与多人场景下的 SC-013；多人 R9 精调

---

## Phase 9: Polish

- [ ] T051 [P] 边界情况手测：热状态 `serious` / `critical` 下小窗与口型检测降频；倒数中断网；授权弹窗期间流程不被取消
- [ ] T052 [P] 日志检查：不含图像数据（FR-019、RN-7）
- [ ] T053 实测结论写入 `research.md`；`docs/tech-selection.md` 4.12 注明前置自拍不属于"看图"，并回写取帧方式结论

---

## Dependencies & Execution Order

- Phase 0 → Phase 1 → Phase 2 → Phase 3（US1）：只依赖 002 US1–US4，现在即可开始
- Phase 4（US2）依赖 Phase 3 的 D1 / D3 结论、002 US5 与 003；其中 T026、T027、T031、T032、T037 不依赖 003，可提前进行（Runner 用 Fakes 与调试注入驱动；在真机上走通无声流程需要 002 US5）
- US3、US5 依赖 US2 的 Runner；US4 依赖 US2 与 T020 / T022；US6 依赖 US3、US4、US5
- T034 在 004 US3 完成前后的实现不同（research D5）

## Implementation Strategy

1. 先做 Phase 0–3：契约对齐后，US1 的"需确认"项决定后面的实现方式，且现在就能做。
2. 并行推进 002 US5 与 003；同时把 `PhotoFlowController` / Runner 与调试注入做完。
3. 002 US5 与 003 完成后接入 `<cmd>`、回应暂缓与倒数语音，完成 MVP（US2），紧接着做 US3（喊停是 P1）。
4. US4、US5、US6 随后收尾。
