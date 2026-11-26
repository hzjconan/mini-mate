# Data Model: 语音拍照

**Feature**: `005-voice-photo`（2026-11-26 按两轮外部评审修订）

除图像载体（`CGImage` 包装为 `@unchecked Sendable`）外均为 `Sendable` 值类型。图像只保存在内存中，生命周期见 photo-output.md。

## MMCore

### AssistantCommand

`photo` · `photoReady` · `photoCancel`

rawValue 即标签值（`<cmd:photo>`）。今后其他 App 指令也在此扩展。

### AvatarCue（research D13）

| 字段 | 类型 | 说明 |
|---|---|---|
| `emotion` | `EmotionTag` | 提示期间的表情 |
| `action` | `ActionTag?` | 可选动作，收到提示时播放一次 |
| `hold` | `Bool` | true：保持到下一个提示或 `assistantCueEnded`；false：按默认反应时长（1.5 s）结束 |

### PlaybackResult

`completed` · `stopped`——放在 `MMCore`，供 `MMPhoto` 的 `CountdownVoice` 与 004 的 `PresetPlayer` 共用。

### ConversationEvent（扩展）

| case | 说明 |
|---|---|
| `assistantCommand(AssistantCommand)` | 模型输出的 App 指令；解析到即发出，保证在同一轮 `assistantSpeechEnded` 之前（command-tag.md） |
| `assistantCue(AvatarCue)` | 非对话轮次的形象提示，由拍照流程发出（photo-flow.md EM-1–EM-5） |
| `assistantCueEnded` | 结束当前保持中的提示 |

## MMPerception

### CaptureMethod

`highResolution` · `currentFrame`

### CapturedPhoto

| 字段 | 类型 | 说明 |
|---|---|---|
| `image` | `CGImage` | 已转为竖屏、不镜像（research D7） |
| `timestamp` | `TimeInterval` | 画面时间戳（与 `Clock` 同一时基） |
| `method` | `CaptureMethod` | |
| `faceRects` | `[CGRect]` | 照片中全部人脸框（Vision），归一化、左上原点 |

### PreviewFrame

| 字段 | 类型 | 说明 |
|---|---|---|
| `image` | `CGImage` | 镜像、竖屏、约 360 px 宽 |
| `timestamp` | `TimeInterval` | |

### MouthActivityFrame（`MouthActivitySource` 输出）

| 字段 | 类型 | 说明 |
|---|---|---|
| `timestamp` | `TimeInterval` | |
| `channel` | `MouthChannel` | `arkit`（60 Hz，只含被追踪的那张脸）/ `vision`（约 12 Hz，全部人脸） |
| `faces` | `[FaceMouthSample]` | |

### FaceMouthSample

| 字段 | 类型 | 说明 |
|---|---|---|
| `trackID` | `Int` | 同一通道内跨帧关联同一张脸（`FaceTrackAssociator`，IoU 最近邻）；ARKit 通道固定为 0 |
| `rect` | `CGRect?` | 归一化人脸框（ARKit 通道为 nil） |
| `openness` | `Float` | 0–1：ARKit 通道为 `jawOpen − mouthClose`（夹紧）；Vision 通道为内唇开合比（`InnerLipOpenness`） |

## MMPhoto

### PhotoFlowState

| case | 说明 |
|---|---|
| `idle` | |
| `awaitingReplyEnd(deadline: TimeInterval)` | 已收到 `<cmd:photo>`，等待该轮回应播完；超过 deadline（`replyEndTimeout`）取消 |
| `checkingPermission` | 等待相册授权结果 |
| `waitingForFace(deadline: TimeInterval, confirmed: Bool)` | 已提示"你在哪呀"；`confirmed` 为 true 表示用户已确认，人脸出现后直接倒数 |
| `awaitingReady(ConfirmState)` | 确认环节 |
| `countingDown(beat: CountdownBeat, beatStartedAt: TimeInterval, audioDone: Bool)` | 倒数中（3 / 2 / 1）；`audioDone` 表示该拍语音已完整播完 |
| `cheese` | "茄子"阶段，不可打断 |
| `capturing` | 等待取帧结果 |
| `saving` | 合成与写入相册 |
| `presenting(until: TimeInterval)` | 显示缩略图（大图由 UI 独立持有，见 photo-output.md） |

### ControllerContext（跨状态维护，research D6 / D11）

| 字段 | 类型 | 说明 |
|---|---|---|
| `isUserSpeaking` | `Bool` | `userSpeechStarted` → true，`userSpeechEnded` → false（即人声闸门是否打开） |
| `userSpeechStartedAt` | `TimeInterval?` | 最近一次语音开始时刻 |
| `isAssistantSpeaking` | `Bool` | `assistantSpeechStarted` → true，`assistantSpeechEnded` → false |
| `lastMouthSpeakingAt` | `TimeInterval?` | 最近一次 `mouthActivity(true)` 的时刻 |
| `faceAbsentSince` | `TimeInterval?` | 人脸最近一次消失的时刻，用于 `faceLostTolerance` |
| `repliesHeld` | `Bool` | 是否处于回应暂缓中 |

### ConfirmState

| 字段 | 类型 | 说明 |
|---|---|---|
| `asks` | `Int` | 已问次数（0…`maxAsks`；倒数被停止回到确认环节时为 0） |
| `nextAskAt` | `TimeInterval?` | 下次再问的时刻；nil 表示计时暂停 |
| `replyDeadline` | `TimeInterval?` | 等待模型回应的上限；到期按"无指令"处理 |
| `readyPending` | `Bool` | 本轮已收到"准备好了"、等回应结束时生效；用户开口时清空（取消则立即生效，不经此字段） |
| `enteredAt` | `TimeInterval` | 统计确认环节时长 |

### PhotoFlowInput

| case | 来源 |
|---|---|
| `command(AssistantCommand)` | `ConversationEvent.assistantCommand` |
| `userSpeechStarted` / `userSpeechEnded` | `ConversationEvent` 同名事件 |
| `assistantSpeechStarted` / `assistantSpeechEnded` | `ConversationEvent` 同名事件（拍照短句不产生这两个事件） |
| `facePresence(Bool)` | Runner 由 `isFaceTracked`（及 R11 决定的 Vision 兜底）合成，只在变化时送入 |
| `mouthActivity(isAnyoneSpeaking: Bool)` | `SpeakingMotionDetector` 判定结果，只在确认环节与倒数期间送入 |
| `permission(PhotoPermission)` | `PhotoLibraryWriter` |
| `phraseFinished(PhotoPhrase)` | `CountdownVoice.play` 返回 `.completed` 时送入；`.stopped` 不送入 |
| `tick` | Runner 计时器（≤ 100 ms 间隔，只在非 `idle` 状态运行） |
| `captured(CapturedPhoto)` / `captureFailed` | `PhotoCaptureSource` |
| `saved(PhotoSaveResult)` / `saveFailed` | 合成 + 写入 |
| `muted` / `interrupted` | 经 `PhotoControlEvent` 送入：静音开关；App 进入后台或音频会话中断（`.inactive` 不算） |

### PhotoFlowEffect

| case | 说明 |
|---|---|
| `requestPermission` | |
| `showPreview(Bool)` | 取景小窗 |
| `showPrompt(String?)` | 小窗上的文字提示 / 倒数数字；nil 清除 |
| `playPhrase(PhotoPhrase, interruptible: Bool)` | |
| `stopPhrase` | 停止正在播放的拍照短句（经 `AudioIO.cancel(turnID:)`） |
| `avatarCue(AvatarCue)` / `endAvatarCue` | Runner 转为 `ConversationEvent.assistantCue` / `assistantCueEnded` 送入合流 |
| `holdReplies` / `releaseReplies(discardingTurnsStartedBefore: TimeInterval)` | 经 `ReplyHolding`（research D14）；`.infinity` 表示全部丢弃 |
| `suspendGestures` / `resumeGestures` | 经 `GestureSuspending` |
| `mouthDetection(Bool)` | 开启 / 关闭 `MouthActivitySource` 订阅 |
| `capture` | 取帧与形象快照并行 |
| `shutterFeedback` | 快门音效 + 闪白 |
| `composeAndSave(CapturedPhoto)` | |
| `showThumbnail(PhotoSaveResult)` / `hideThumbnail` | |
| `showSettingsButton` | 权限被拒 |
| `record(PhotoAttempt)` | 流程结束时写指标 |

### CountdownBeat

`three` · `two` · `one` · `cheese`

### PhotoPhrase（文本清单 `photo-phrases.json`，research D5）

| 类别 | 示例 | 情绪 | 标称时长（无声降级用） |
|---|---|---|---|
| `askReady` | 准备好了吗？/ 姿势摆好了吗？/ 好了就告诉我哦～ / 还要再等等吗？（4–5 条轮换，相邻不重复） | playful | 1.5 s |
| `beat3` / `beat2` / `beat1` | 三 / 二 / 一 | playful | 0.5 s |
| `cheese` | 茄子～ | happy | 0.8 s |
| `whereAreYou` | 你在哪呀？到镜头前来～ | playful | 1.5 s |
| `giveUp` | 那下次再拍吧 | gentle | 1.2 s |
| `noPermission` | 我没法存照片，要去设置里允许一下哦 | concerned | 2.5 s |
| `saveFailed` | 呜，照片没存上 | sad | 1.2 s |

### CountdownScript（可调参数）

| 字段 | 默认值 | 说明 |
|---|---|---|
| `beatInterval` | 1.0 s | 相邻两拍开始时刻的间隔（语音更长时以播完为准） |
| `askCue` / `beatCues` / `doneCue` | 见 plan.md 形象时间线 | |
| `faceWaitTimeout` | 10 s | |
| `faceLostTolerance` | 0.5 s | 倒数中人脸消失超过此值即停止倒数 |
| `reaskInterval` | 5 s | |
| `maxAsks` | 5 | |
| `replyWaitTimeout` | 8 s | 等待模型回应的上限 |
| `replyEndTimeout` | 8 s | 收到 `<cmd:photo>` 后等待该轮回应结束的上限（research D16） |
| `preSpeechMouthWindow` | 0.3 s | 闸门打开前多长时间内的口型也算数（research D11） |
| `thumbnailDuration` | 4 s | |

### SpeakingMotionParams（每通道一组，research D11）

| 字段 | ARKit 默认 | Vision 默认 | 说明 |
|---|---|---|---|
| `window` | 0.4 s | 0.5 s | |
| `minSamples` | 12 | 3 | 不足判为"不在说话" |
| `minStdDev` | 0.04 | 0.03 | |
| `minPeakToPeak` | 0.12 | 0.10 | |

`SpeakingMotionDetector` 对每个通道、每个 `trackID` 维护窗口；任一通道任一张脸满足条件 → `isAnyoneSpeaking = true`。

### PhotoPermission

`authorized` · `notDetermined` · `denied`（含 `restricted`）

### AvatarSnapshot

| 字段 | 类型 | 说明 |
|---|---|---|
| `image` | `CGImage` | 带透明通道 |
| `isLivePose` | `Bool` | false：使用了兜底贴纸 |

### CompositeLayout（`CornerPlacement` 输出）

| 字段 | 类型 | 说明 |
|---|---|---|
| `corner` | `Corner` | `bottomRight` / `bottomLeft` / `topRight` / `topLeft` |
| `rect` | `CGRect` | 形象在照片中的位置（像素，左上原点） |
| `widthRatio` | `Double` | 0.30，四角都重叠时 0.20 |
| `overlapsFace` | `Bool` | 只有四角都重叠时为 true |

### EncodedImage

| 字段 | 类型 | 说明 |
|---|---|---|
| `data` | `Data` | |
| `uti` | `UTType` | `.heic` 或 `.jpeg` |

### PhotoSaveResult

| 字段 | 类型 |
|---|---|
| `original` | `CGImage` |
| `composite` | `CGImage?`（合影失败为 nil） |
| `compositeFailure` | `String?` |

### PhotoAttempt（指标）

| 字段 | 说明 |
|---|---|
| `id`、`startedAt` | |
| `photoStart` | `Duration?`：确认回应的 `assistantSpeechEnded` → 第一拍开始（M_photoStart）；确认后若需等人脸，不计入 |
| `permissionWait`、`faceWait`、`confirmDuration` | `Duration?` |
| `asks` | 问"准备好了吗"的总次数 |
| `shutterSigned` | `Duration?`："茄子"播完 → 画面时间戳（带符号） |
| `shutterAbs` | `Duration?`：上值的绝对值（M_shutter，SC-004 以此统计） |
| `trackingGap` | `Duration?`：快门前后 2 s 内人脸未追踪的最长连续时长 |
| `method`、`resolution` | 取帧方式与像素尺寸 |
| `compositeOK`、`livePose` | |
| `countdownStops` | 倒数因"人声 + 口型"或人脸消失而停止的次数 |
| `ambientVoiceIgnored` | 倒数中闸门打开后又关闭、期间无口型（判为环境声）的次数 |
| `stopLatency` | `[Duration]`：每次"人声 + 口型"停止时，从闸门打开（或口型出现，取较晚者）到 `stopPhrase` 的耗时（R7） |
| `maxFaceCount` | 流程中检测到的最多人脸数 |
| `outcome` | `saved` / `cancelled(CancelReason)` / `failed(FailureReason)` |

### CancelReason / FailureReason

- `CancelReason`：`userCancelled` · `readyTimeout` · `faceTimeout` · `replyTimeout` · `permissionDenied` · `muted` · `interrupted`
- `FailureReason`：`captureFailed` · `saveFailed`

## 状态转换（摘要，完整表见 contracts/photo-flow.md）

```
idle ─cmd photo─▶ awaitingReplyEnd ─回应结束─▶ checkingPermission ─authorized─▶ (face? awaitingReady : waitingForFace)
awaitingReplyEnd ─8 s 无回应结束─▶ idle（replyTimeout）
waitingForFace(confirmed: false) ─face─▶ awaitingReady（问一次）
awaitingReady ─回应结束 + ready─▶ (face? countingDown(3) : waitingForFace(confirmed: true) ─face─▶ countingDown(3))
awaitingReady ─回应结束 + 无指令 / 没回答─▶ 小瓜说完 5 s 后再问（最多 5 次）─问满仍未确认─▶ idle（readyTimeout）
waitingForFace / awaitingReady / countingDown ─cancel─▶ idle
countingDown(3→2→1) ─▶ cheese ─▶ capturing ─▶ saving ─▶ presenting ─4 s─▶ idle
countingDown ─闸门打开期间有口型─▶ awaitingReady（asks = 0）
countingDown ─闸门打开期间无口型─▶ countingDown（环境声）
countingDown ─人脸消失 > 0.5 s─▶ waitingForFace(confirmed: false)
```
