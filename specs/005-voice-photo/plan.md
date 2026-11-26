# Implementation Plan: 语音拍照

**Branch**: `005-voice-photo` | **Date**: 2026-11-26（按两轮外部评审修订，2026-11-26 定稿；既有契约已同步） | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-voice-photo/spec.md`

## Summary

模型在回答中输出 `<cmd:photo>`，由 003 的 `TagParser` 解析为 `ConversationEvent.assistantCommand(.photo)`。新模块 `MMPhoto` 中的纯逻辑状态机 `PhotoFlowController` 驱动整个流程，`PhotoFlowRunner` 负责执行副作用：

1. 等回应播完 → 检查相册权限 → 等人脸出现。
2. 显示取景小窗并问"准备好了吗"（App 预置短句；用户的回答由模型理解为 `<cmd:photoReady>` / `<cmd:photoCancel>`；没确认则每 5 秒再问，最多 5 次）。
3. 四拍倒数：预合成短句 + 经情绪状态机的专用提示事件 `assistantCue`；"3、2、1"时人声闸门打开期间检测到画面内有人做说话口型才停止，否则视为环境声；倒数期间暂缓模型回应的播放。
4. 快门：从同一 `ARSession` 抓帧，不中断 ARKit；同时用离屏影子实体渲染形象快照。
5. 生成真实版与合影版，以"仅添加"权限写入系统相册，显示缩略图。

多人时用 Vision 检测全部人脸（口型、合影避让），ARKit 配置不变。US1（技术验证）只依赖已完成的 002 US1–US4，现在即可开始。

## Technical Context

**Language/Version**：Swift 6（严格并发）

**Primary Dependencies**：ARKit（`captureHighResolutionFrame`、`capturedImage`、`jawOpen` / `mouthClose`）、Vision（`VNDetectFaceLandmarksRequest`、`VNDetectFaceRectanglesRequest`）、CoreImage（合成、HEIC / JPEG 编码）、Photos（add-only）、RealityKit（`RealityRenderer` 离屏渲染，依 R4）、002 的 `MMEmotion`（US5）、003 的 `MMConversation` / `MMAudio`；可选使用 004 的 `PresetPlayer`

**Storage**：不持久化照片，只写系统相册。`PhotoAttempt` 指标在内存中，可从调试面板导出（与 003 `TurnMetrics` 相同）

**Testing**：Swift Testing——`PhotoFlowController` 全部状态转换与竞态场景（假时钟）、`PhotoFlowRunner`（Fakes）、`<cmd>` 标签解析、`SpeakingMotionDetector`、`FaceTrackAssociator`、内唇开合比、`CornerPlacement`、`PhotoCompositor`；设备相关部分按 quickstart 真机验收

**Target Platform**：iOS 26+（App）；`MMPhoto` 全部可在 macOS 26 编译与测试（`PhotosLibraryWriter` 为 `#if os(iOS)`）

**Project Type**：mobile-app

**Performance Goals**：\|M_shutter\| p50 < 150 ms；M_photoStart p50 < 300 ms；追踪中断 ≤ 500 ms；取景小窗 ≥ 15 fps 且感知帧率不明显下降

**Constraints**：图像不出设备、不进模型；不新增第三方依赖；不新增 `AVCaptureSession`

**Scale/Scope**：单用户（画面中可多人）；每次拍照 2 张图片

## Constitution Check

| 原则 | 结论 |
|---|---|
| I. 陪伴而非镜像 | ✅ 形象表现经专用提示事件 `assistantCue` 送入情绪状态机，不直接驱动渲染器；口型开合度只作为拍照流程的输入，不进入状态机、不驱动形象 |
| II. 感知在本地 | ✅ 照片、取景画面、人脸与口型检测都在端侧完成，不上传、不进模型（FR-019、FR-026）；模型只收到用户语音并输出文字标签。宪章 II 中的"看图"指上传图片，本 feature 不涉及 |
| III. 度量先于假设 | ✅ 高分辨率抓帧、离屏快照、Vision 关键点负载、远距追踪稳定性、口型可行性放在 US1 先验证（R1–R5、R9 冒烟、R10、R11），之后才实施依赖它们的任务；指标以 p50/p90 验收 |
| IV. 可替换边界 | ✅ 摄像头能力以 `MMPerception` 中的协议暴露；形象快照、相册、短句语音、回应暂缓、手势让出、音效均以 `MMPhoto` 协议注入，App 组合根做适配；每个协议都有真机实现与测试实现 |
| V. 纯逻辑可测 | ✅ 流程状态机、口型判定、人脸关联、内唇开合比、角落选择、合成均在 Package 中，先写测试 |
| VI. 简单优先 | ✅ 无第三方依赖；不建 App 内相册；不新增动画片段；不新增 `AvatarStateKind` |
| VII. 隐私与密钥 | ✅ 相册只申请"仅添加"；摄像头权限文案如实更新；收音沿用 003 的闸门与静音 |

无违反项。需同步修改的既有契约见"对既有契约的修改"，在 005 计划定稿后、任何代码开工前完成。

## Project Structure

### Documentation (this feature)

```text
specs/005-voice-photo/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── command-tag.md        # <cmd> 标签、AssistantCommand（对 003 的扩展）
│   ├── photo-flow.md         # PhotoFlowController、PhotoFlowRunner、CountdownVoice；对 002 / 003 / 004 的契约增补
│   ├── photo-capture.md      # PhotoCaptureSource、MouthActivitySource（MMPerception）
│   └── photo-output.md       # AvatarSnapshotter、CornerPlacement、PhotoCompositor、PhotoLibraryWriter
└── tasks.md
```

### 模块依赖

```text
MMCore ◀── MMPerception ◀── MMPhoto
  ▲            ▲   (只用协议与值类型)
  │            │
  ├── MMEmotion ◀── MMAvatar
  │
App ──▶ MMPhoto、MMPerception、MMAvatar、MMEmotion、MMConversation / MMAudio（003）
        └─ Photo/Adapters：把 MMAvatar 快照、003 AudioIO / ConversationEngine、004 PresetPlayer、
           手势频率控制适配为 MMPhoto 协议
```

- `MMPhoto` 只依赖 `MMCore` 与 `MMPerception`（后者只用其中的协议与值类型，ARKit 实现在 `#if os(iOS)` 内）。`MMPerception`、`MMAvatar` 不依赖 `MMPhoto`，不形成反向或循环依赖。
- 依赖 003 / 004 的实现（`CountdownVoiceCache`、`PresetCountdownVoice`、AudioIO 与回应暂缓适配）放在 App，003 完成前不参与编译。

### Source Code

```text
Packages/MiniMateKit/Sources/
├── MMCore/
│   ├── AssistantCommand.swift              # 新增
│   ├── AvatarCue.swift                     # 新增（research D13）
│   ├── PlaybackResult.swift                # 新增：completed / stopped（MMPhoto 与 004 共用）
│   └── ConversationEvent.swift             # 新增 assistantCommand / assistantCue / assistantCueEnded
├── MMPerception/
│   ├── PhotoCapture.swift                  # 协议 PhotoCaptureSource、MouthActivitySource 与值类型
│   ├── FaceTrackAssociator.swift           # 跨帧人脸关联（纯逻辑）
│   ├── InnerLipOpenness.swift              # 内唇开合比（纯逻辑）
│   ├── ARKitPerceptionSource.swift         # state / sessionQueue / gestureQueue 由 private 改为 internal
│   ├── ARKitPerceptionSource+PhotoCapture.swift   # 抓帧（含方向转换）+ 取景预览 + 照片人脸框
│   ├── ARKitPerceptionSource+MouthActivity.swift  # Vision 关键点 + ARKit 系数 → 两路开合度
│   └── ScriptedPhotoCaptureSource.swift / ScriptedMouthActivitySource.swift  # 测试与调试
├── MMEmotion/
│   └── RuleBasedEmotionStateMachine.swift  # 002 US5：assistantCue 规则（research D13）
├── MMAvatar/
│   ├── AvatarFraming.swift                 # 从 AvatarScreen 抽出的相机与构图参数
│   └── AvatarOffscreenSnapshotter.swift    # 离屏影子实体快照（依 R4），返回 CGImage
├── MMConversation/                         # 003
│   ├── TagParser.swift                     # 支持 <cmd:…>
│   └── （引擎）                             # holdReplies / releaseReplies（research D14）
├── MMAudio/                                # 003
│   └── AudioIO.swift                       # interruptible、cancel(turnID:)（research D15）
└── MMPhoto/                                # 新 target，依赖 MMCore、MMPerception
    ├── PhotoFlowTypes.swift                # 状态、输入、副作用、原因
    ├── PhotoFlowController.swift           # 纯逻辑状态机
    ├── PhotoFlowRunner.swift               # actor：事件订阅、计时器、副作用执行、指标
    ├── CountdownScript.swift
    ├── SpeakingMotionDetector.swift        # 两路口型判定（纯逻辑）
    ├── CornerPlacement.swift
    ├── PhotoCompositor.swift               # 只做合成与编码
    ├── PhotoAttemptMetrics.swift
    ├── Protocols.swift                     # AvatarSnapshotter、PhotoLibraryWriter、CountdownVoice、
    │                                       # PhotoAudioFeedback、GestureSuspending、ReplyHolding
    ├── SilentCountdownVoice.swift          # 无声降级（按标称时长等待）
    ├── PhotosLibraryWriter.swift           # #if os(iOS)
    └── Fakes/                              # FakeAvatarSnapshotter、InMemoryLibraryWriter、FakeReplyHolding、
                                            # FakeGestureSuspending、FakeAudioFeedback …

App/MiniMate/
├── AppComposition.swift                    # 组装 Runner；合并 ConversationEngine 事件与 Runner 提示事件后送入状态机
├── Photo/
│   ├── PhotoUIState.swift                  # @Observable @MainActor
│   └── Adapters/
│       ├── AvatarSnapshotAdapter.swift     # AvatarOffscreenSnapshotter → AvatarSnapshotter
│       ├── GestureSuspendAdapter.swift     # 记住原手势频率，设为 0 / 恢复
│       ├── AudioFeedbackAdapter.swift      # 快门音效 → AudioIO（003 后）
│       ├── ReplyHoldingAdapter.swift       # ConversationEngine.holdReplies / releaseReplies（003 后）
│       ├── CountdownVoiceCache.swift       # 003 TTSProvider 合成 + 内存缓存（004 未完成时）
│       └── PresetCountdownVoice.swift      # 004 PresetPlayer（004 US3 后）
├── Resources/
│   ├── photo-phrases.json                  # photo.* 文本清单（research D5）
│   ├── shutter.caf                         # 程序生成
│   └── avatar-sticker.png                  # 仅 R4 失败时加入
├── Screens/Photo/
│   ├── PhotoPreviewOverlay.swift           # 取景小窗 + 文字提示 / 倒数数字 + 闪白
│   ├── PhotoThumbnailView.swift
│   ├── PhotoViewer.swift                   # 大图，真实 / 合影切换
│   └── PhotoPermissionBanner.swift         # "去设置"
└── Screens/Debug/AvatarDebugPanel.swift    # 拍照页：测试拍照 / 测试形象快照 / 口型曲线 / 模拟指令 / 指标
```

### 关键设计

**事件流**

```
ConversationEngine.events ──┬────────────────────────────▶ 合流 ─▶ EmotionStateMachine
                            └─▶ PhotoFlowRunner ─┬─ avatarCue ─▶ 合流
PerceptionSource.features（isFaceTracked）──▶ Runner │
MouthActivitySource ─▶ SpeakingMotionDetector ─▶ Runner（仅确认环节与倒数期间）
Runner: PhotoFlowController.handle(input, now) ─▶ [Effect] ─▶ 执行：
  playPhrase / stopPhrase ─▶ CountdownVoice ─▶ AudioIO（每条短句独立 turnID，不可打断项用 cancel(turnID:) 停止）
  holdReplies / releaseReplies ─▶ ReplyHolding ─▶ ConversationEngine
  suspendGestures / resumeGestures ─▶ GestureSuspending
  mouthDetection(on/off)、preview(on/off) ─▶ MMPerception
  capture ─▶ PhotoCaptureSource ∥ AvatarSnapshotter
  composeAndSave ─▶ CornerPlacement + PhotoCompositor ─▶ PhotoLibraryWriter
  shutterFeedback ─▶ PhotoAudioFeedback + PhotoUIState（闪白）
  UI effects ─▶ PhotoUIState ─▶ SwiftUI 叠加层
```

**形象时间线（默认值，`CountdownScript` 可调）**

| 阶段 | 声音 | `AvatarCue` | 用户开口时 |
|---|---|---|---|
| 确认环节（问句） | "准备好了吗？" | `playful` + `lookAround`，hold | 正常对话；模型回应期间形象处于 Speaking，说完回到提示 |
| 倒数 0.0 s | "3" | `happy` + `notice`，hold | 闸门打开期间有口型 → 停止，回到确认环节；无口型 → 忽略 |
| 1.0 s | "2" | `happy` + `nod`，hold | 同上 |
| 2.0 s | "1" | `happy` + `nod`，hold | 同上 |
| 3.0 s | "茄子" | `happy` + `heart`，hold | 不受影响 |
| "茄子"播完 | 快门音效 + 闪白 | — | 不受影响 |
| 保存成功 | — | `happy` + `spin`，不 hold；随后 `assistantCueEnded` | — |

## 对既有契约的修改

在 005 计划定稿后、任何代码开工前完成（包括 US1）。

| 文档 | 修改 |
|---|---|
| 002 `data-model.md` | `ConversationEvent` 新增 `assistantCommand`、`assistantCue`、`assistantCueEnded`；新增 `AssistantCommand`、`AvatarCue`、`PlaybackResult` |
| 002 `contracts/emotion-state-machine.md` | 转换表新增 `assistantCue` / `assistantCueEnded` 行与"不可被感知反应打断、保持、Speaking 结束后回到提示"规则（photo-flow.md EM-1–EM-5） |
| 002 `contracts/perception-source.md` | P-6 放开：感知流不保存图像，`PhotoCaptureSource` 在用户指令下取单帧；新增 `MouthActivitySource` 的边界说明 |
| 002 `tasks.md` | US5 增加 `assistantCue` 的测试与实现 |
| 003 `contracts/tag-protocol.md` | 语法新增 `cmd_tag`；T-8、T-9；给模型的说明第 6 条（command-tag.md） |
| 003 `contracts/conversation-engine.md` | `assistantCommand` 事件顺序 C-1–C-4；`holdReplies()` / `releaseReplies(discardingTurnsStartedBefore:)`（photo-flow.md RH-1–RH-5） |
| 003 `contracts/audio-gating.md` | `enqueue(_:turnID:interruptible:)`、`flush()` 只清可打断缓冲、`cancel(turnID:)`（photo-flow.md AF-1–AF-3） |
| 004 `contracts/preset-phrases.md` | `PresetPlayer.play` 增加 `interruptible`、`emitsEmotion` 参数，返回 `PresetPlayback`（条目 + 播放结果）；新增 `stop(turnID:)`；新增 `photo.*` 类别（来源为 005 的 `photo-phrases.json`） |
| `docs/tech-selection.md` 4.12 | 注明前置自拍不属于"看图"；取帧方式以本 feature research 结论为准（实测后回写） |

## Complexity Tracking

无。
