# Contract: 拍照流程

**Module**: `MMPhoto`（`PhotoFlowController`、`PhotoFlowRunner`、`CountdownScript`、`CountdownVoice`） | **Feature**: `005-voice-photo`（2026-11-26 按两轮外部评审修订）

## PhotoFlowController（纯逻辑）

```swift
public struct PhotoFlowController: Sendable {
    public private(set) var state: PhotoFlowState
    public private(set) var context: ControllerContext
    public init(script: CountdownScript = .default)

    /// 处理一个输入，返回需要按顺序执行的副作用。不做 I/O，不读系统时钟。
    public mutating func handle(_ input: PhotoFlowInput, now: TimeInterval) -> [PhotoFlowEffect]
}
```

### 记号

| 记号 | 含义 |
|---|---|
| **更新上下文** | 每个输入先更新 `ControllerContext`（`isUserSpeaking`、`userSpeechStartedAt`、`isAssistantSpeaking`、`lastMouthSpeakingAt`、`faceAbsentSince`），再查下表 |
| **问一次** | `stopPhrase`、`playPhrase(.askReady, interruptible: true)`、`showPrompt("准备好了吗？")`、`avatarCue(askCue)`；`asks += 1`，`nextAskAt = nil`（等问句完整播完才开始计时） |
| **进入确认** | 若尚未开启：`mouthDetection(true)`、`suspendGestures` |
| **离开确认** | `mouthDetection(false)`、`resumeGestures` |
| **开始倒数** | `stopPhrase`、**进入确认**（倒数同样需要口型检测）、`holdReplies`（若未暂缓）、`playPhrase(.beat3, interruptible: false)`、`showPrompt("3")`、`avatarCue(beatCues[.three])`；状态 `countingDown(.three, beatStartedAt: now, audioDone: false)` |
| **停止倒数** | `stopPhrase`、`releaseReplies(discardingTurnsStartedBefore: userSpeechStartedAt)`、`showPrompt("准备好了吗？")`、`avatarCue(askCue)`；状态 `awaitingReady(asks: 0, nextAskAt: nil, replyDeadline: isUserSpeaking ? nil : now + replyWaitTimeout, readyPending: false)` |
| **结束(reason)** | `stopPhrase`、`showPreview(false)`、`showPrompt(nil)`、`endAvatarCue`、**离开确认**（若已开启）、`releaseReplies(…)`（若在暂缓中，参数见各行）、`record(reason)`；状态 `idle` |

### 状态转换表

| 当前状态 | 输入 | 条件 | 新状态 / 副作用 |
|---|---|---|---|
| `idle` | `command(.photo)` | | `awaitingReplyEnd(deadline: now + replyEndTimeout)` |
| `idle` | 其他 | | 不变 |
| `awaitingReplyEnd` | `assistantSpeechEnded` | `!isUserSpeaking` | `checkingPermission`；`requestPermission` |
| `awaitingReplyEnd` | `assistantSpeechEnded` | `isUserSpeaking`（应答被用户插话打断，E-2） | 不变；`deadline = now + replyEndTimeout`，等新一轮回应结束 |
| `awaitingReplyEnd` | `command(.photoCancel)` | | **结束**(userCancelled) |
| `awaitingReplyEnd` | `tick` | `now > deadline` | `playPhrase(.giveUp)`；**结束**(replyTimeout) |
| `checkingPermission` | `permission(.authorized)` | 有人脸 | `awaitingReady`（`asks: 0`）；`showPreview(true)`、**进入确认**、**问一次** |
| `checkingPermission` | `permission(.authorized)` | 无人脸 | `waitingForFace(deadline: now + faceWaitTimeout, confirmed: false)`；`showPreview(true)`、`playPhrase(.whereAreYou, interruptible: true)`、`avatarCue(askCue)` |
| `checkingPermission` | `permission(.denied)` | | `playPhrase(.noPermission)`、`showSettingsButton`；**结束**(permissionDenied) |
| `waitingForFace(confirmed: false)` | `facePresence(true)` | | `awaitingReady`（`asks: 0`）；**进入确认**、**问一次** |
| `waitingForFace(confirmed: true)` | `facePresence(true)` | | **开始倒数** |
| `waitingForFace` | `command(.photoCancel)` | | **结束**(userCancelled) |
| `waitingForFace` | `tick` | `now > deadline` | `playPhrase(.giveUp)`；**结束**(faceTimeout) |
| `awaitingReady` | `phraseFinished(.askReady)` | `!isUserSpeaking && !isAssistantSpeaking` | `nextAskAt = now + reaskInterval` |
| `awaitingReady` | `userSpeechStarted` | | `stopPhrase`；`nextAskAt = nil`、`replyDeadline = nil`、`readyPending = false` |
| `awaitingReady` | `userSpeechEnded` | | `replyDeadline = now + replyWaitTimeout` |
| `awaitingReady` | `assistantSpeechStarted` | | `nextAskAt = nil`、`replyDeadline = nil` |
| `awaitingReady` | `command(.photoReady)` / `command(.photo)` | | `readyPending = true` |
| `awaitingReady` | `command(.photoCancel)` | | **结束**(userCancelled) |
| `awaitingReady` | `assistantSpeechEnded` | `isUserSpeaking` | 不变（被插话打断的旧一轮，PF-4） |
| `awaitingReady` | `assistantSpeechEnded` | `!isUserSpeaking && readyPending`，有人脸 | **开始倒数**；记录 M_photoStart 起点 |
| `awaitingReady` | `assistantSpeechEnded` | `!isUserSpeaking && readyPending`，无人脸 | `waitingForFace(deadline: now + faceWaitTimeout, confirmed: true)`；**离开确认**、`playPhrase(.whereAreYou, interruptible: true)` |
| `awaitingReady` | `assistantSpeechEnded` | `!isUserSpeaking && !readyPending` | `nextAskAt = now + reaskInterval`、`replyDeadline = nil` |
| `awaitingReady` | `tick` | `replyDeadline` 已过 且 `!isAssistantSpeaking` | `nextAskAt = now + reaskInterval`、`replyDeadline = nil` |
| `awaitingReady` | `tick` | `nextAskAt` 已过 且 `asks < maxAsks` | **问一次** |
| `awaitingReady` | `tick` | `nextAskAt` 已过 且 `asks == maxAsks` | `playPhrase(.giveUp)`；**结束**(readyTimeout) |
| `countingDown(b)` | `phraseFinished(b)` | | `audioDone = true` |
| `countingDown(b)` | `tick` / `phraseFinished(b)` | `audioDone && now − beatStartedAt ≥ beatInterval`，`b` 为 three / two | `countingDown(next, beatStartedAt: now, audioDone: false)`；`playPhrase(next, interruptible: false)`、`showPrompt(数字)`、`avatarCue(beatCues[next])` |
| `countingDown(.one)` | 同上 | | `cheese`；`playPhrase(.cheese, interruptible: false)`、`showPrompt("茄子")`、`avatarCue(beatCues[.cheese])` |
| `countingDown` | `userSpeechStarted` | `lastMouthSpeakingAt ≥ now − preSpeechMouthWindow` | **停止倒数** |
| `countingDown` | `mouthActivity(true)` | `isUserSpeaking` | **停止倒数** |
| `countingDown` | `userSpeechEnded` | （未被停止） | 不变；`ambientVoiceIgnored += 1` |
| `countingDown` | `command(.photoCancel)` | | **结束**(userCancelled)，`releaseReplies(discardingTurnsStartedBefore: userSpeechStartedAt ?? now)` |
| `countingDown` | `command(.photo)` / `command(.photoReady)` | | 不变 |
| `countingDown` | `tick` | `faceAbsentSince` 非空且 `now − faceAbsentSince > faceLostTolerance` | `waitingForFace(deadline: now + faceWaitTimeout, confirmed: false)`；`stopPhrase`、`releaseReplies(discardingTurnsStartedBefore: .infinity)`、**离开确认**、`playPhrase(.whereAreYou, interruptible: true)`、`avatarCue(askCue)` |
| `cheese` | 语音、口型、指令、人脸变化 | | 不变（PF-5） |
| `cheese` | `phraseFinished(.cheese)` | | `capturing`；`capture`、`shutterFeedback`、`showPrompt(nil)`、**离开确认** |
| `capturing` | `captured(p)` | | `saving`；`showPreview(false)`、`releaseReplies(discardingTurnsStartedBefore: .infinity)`、`composeAndSave(p)` |
| `capturing` | `captureFailed` | | `playPhrase(.saveFailed)`；**结束**(captureFailed)，`releaseReplies(.infinity)` |
| `saving` | `saved(r)` | | `presenting(until: now + thumbnailDuration)`；`avatarCue(doneCue)`、`showThumbnail(r)` |
| `saving` | `saveFailed` | | `playPhrase(.saveFailed)`；**结束**(saveFailed) |
| `presenting` | `tick` | `now > until` | `hideThumbnail`；**结束**(saved) |
| `presenting` | `command(.photo)` | | 不变（PF-1） |
| 除 `idle` / `saving` / `presenting` 外 | `muted` / `interrupted` | | **结束**(muted / interrupted)，`releaseReplies(.infinity)` |

### 行为约定

| 编号 | 约定 |
|---|---|
| PF-1 | `command(.photo)`：`idle` 中开始流程；`awaitingReady` 中等同 `photoReady`；其他状态忽略 |
| PF-2 | 取消（`<cmd:photoCancel>`）立即生效；取消确认由模型的回应承担（instructions 要求简短回应），App 不再额外播放短句。确认环节的"准备好了"在本轮回应结束时才生效，以便模型的回应（如"好嘞～"）先播完 |
| PF-3 | 倒数推进同时要求"该拍语音完整播完"和"距该拍开始 ≥ `beatInterval`"；无声降级时 `SilentCountdownVoice` 按标称时长等待后返回 `.completed`，推进规则不变 |
| PF-4 | 用户开口时清空 `readyPending`；003 E-2 中旧一轮的 `assistantSpeechEnded` 在 `isUserSpeaking == true` 时到达，不作为结论 |
| PF-5 | `cheese` 与 `capturing` 状态对语音、口型、指令都不做反应（FR-012） |
| PF-6 | 每次流程结束（回到 `idle`）恰好产出一次 `record`，且 **结束** 一定成对关闭已开启的口型检测、手势让出、回应暂缓与形象提示 |
| PF-7 | `avatarCue` 只能经 Runner 转为 `ConversationEvent.assistantCue` 送入情绪状态机（宪章 I）；控制器不读取图像内容 |
| PF-8 | 所有超时都用 `tick` 的 `now` 计算，测试使用假时钟 |
| PF-9 | 倒数被停止后回到确认环节时，用户通常仍在说话，不立即再问；`asks` 归零，下一次问句算第 1 次；若此时用户已不在说话，`replyDeadline` 默认为 `now + replyWaitTimeout`，保证计时不会永远为空 |
| PF-10 | 确认环节中，用户说话期间、等待模型回应期间、小瓜播放问句或回应期间都不会再问；再问间隔总是从小瓜最近一次完整说完话起算（FR-024） |
| PF-11 | `askReady` 多条轮换，相邻两次不重复 |
| PF-12 | 喊停判定（research D11）：闸门打开期间任一 `mouthActivity(true)` 即停，或闸门打开时刻之前 `preSpeechMouthWindow` 内已有口型；`isUserSpeaking` 跨"3→2→1"保持，持续环境声期间画面内的人开口同样能停止 |
| PF-13 | 倒数各拍以 `interruptible: false` 播放，003 的插话判定不会停播；是否停止只由本控制器决定，停止经 `stopPhrase`（`AudioIO.cancel(turnID:)`） |
| PF-14 | 口型检测与手势让出只在确认环节与倒数期间开启（含 `cheese` 之前）；等人脸阶段关闭；两条进入等人脸的路径行为一致 |

## PhotoFlowRunner

```swift
public actor PhotoFlowRunner {
    public init(script: CountdownScript,
                clock: any Clock,
                capture: any PhotoCaptureSource,
                mouth: any MouthActivitySource,
                snapshotter: any AvatarSnapshotter,
                library: any PhotoLibraryWriter,
                voice: any CountdownVoice,
                feedback: any PhotoAudioFeedback,
                gestures: any GestureSuspending,
                replies: any ReplyHolding)
    /// 送往情绪状态机的提示事件（由 App 与 ConversationEngine 事件合流）。
    public var cueEvents: AsyncStream<ConversationEvent> { get }
    public var uiEffects: AsyncStream<PhotoFlowEffect> { get }   // 只含 UI 相关副作用
    public func run(conversation: AsyncStream<ConversationEvent>,
                    perception: AsyncStream<PerceptionFeatures>,
                    controls: AsyncStream<PhotoControlEvent>) async  // muted / interrupted
}
```

| 编号 | 约定 |
|---|---|
| RN-1 | 计时器只在非 `idle` 状态运行，间隔 ≤ 100 ms |
| RN-2 | `playPhrase` 为每条短句生成新 turnID 并异步播放；`PlaybackResult.completed` 时送入 `phraseFinished`，`.stopped` 不送入 |
| RN-3 | `capture` 同时启动取帧与形象快照（AS-1）；快照结果与照片一起进入 `composeAndSave` |
| RN-4 | `facePresence` 由 `PerceptionFeatures.isFaceTracked` 合成，只在变化时送入；R11 决定启用 Vision 兜底时，在 `waitingForFace` 期间额外订阅 Vision 人脸数（同时让出手势） |
| RN-5 | `mouthDetection(true)` 时订阅 `MouthActivitySource`，经 `SpeakingMotionDetector` 后只在判定结果变化时送入 `mouthActivity` |
| RN-6 | App 进入后台或音频会话中断 → `interrupted`；`scenePhase == .inactive`（如系统授权弹窗）不算 |
| RN-7 | 日志与指标中不含图像数据 |

## CountdownVoice

```swift
public protocol CountdownVoice: Sendable {
    func isReady() async -> Bool
    /// 播放一条拍照短句；返回是否完整播完。
    func play(_ phrase: PhotoPhrase, turnID: UUID, interruptible: Bool) async -> PlaybackResult
    func stop(turnID: UUID) async
}
```

| 实现 | 所在 | 说明 |
|---|---|---|
| `PresetCountdownVoice` | App | 004 US3 完成后：包装 `PresetPlayer`（PP-4、PP-5） |
| `CountdownVoiceCache` | App | 004 未完成时：003 `TTSProvider` 合成 `photo-phrases.json`，内存缓存（research D5） |
| `SilentCountdownVoice` | MMPhoto | 降级与测试：按标称时长等待后返回 `.completed`；`stop` 立即返回 `.stopped` |

| 编号 | 约定 |
|---|---|
| CV-1 | 播放走 003 `AudioIO`，与对话语音同一引擎（回声消除生效） |
| CV-2 | 播放时发出 `assistantAudioLevel` 驱动口型；不发出 `assistantEmotion`（表情由 `assistantCue` 负责） |
| CV-3 | 不发出 `assistantSpeechStarted` / `assistantSpeechEnded` |

## 其他注入协议（MMPhoto）

| 协议 | 方法 | App 实现 |
|---|---|---|
| `PhotoAudioFeedback` | `playShutter() async` | `AudioFeedbackAdapter`：`shutter.caf` 经 `AudioIO`，独立 turnID，`interruptible: false` |
| `GestureSuspending` | `suspend()` / `resume()` | `GestureSuspendAdapter`：记住当前配置频率 → `setGestureRate(0)` / 恢复原值 |
| `ReplyHolding` | `hold()` / `release(discardingTurnsStartedBefore:)` | `ReplyHoldingAdapter`：转调 003 `ConversationEngine`（RH-1–RH-5） |

## 对 002 / 003 / 004 契约的增补（2026-11-26 已写入对应文档，以对应文档为准）

### 情绪状态机（002 emotion-state-machine.md）

| 编号 | 约定 |
|---|---|
| EM-1 | 非 Listening / Thinking / Speaking 状态收到 `assistantCue(c)` → 进入 `.reacting`（表情 `c.emotion`），立即播放 `c.action`（若有）；替换当前的提示或感知反应 |
| EM-2 | Listening / Thinking / Speaking 中收到 `assistantCue(c)` → 记为"保持中的提示"，不改变当前状态；`assistantSpeechEnded` 后回到该提示的 `.reacting`，而不是 Attending |
| EM-3 | 提示期间感知反应（表情、手势、快速靠近）一律不触发，也不进入冷却 |
| EM-4 | `c.hold == true` 保持到下一个提示或 `assistantCueEnded`；`false` 按默认反应时长结束后回到原状态 |
| EM-5 | `assistantCueEnded` 清除保持中的提示，回到 Attending（有人脸）/ Idle |

### 对话引擎（003 conversation-engine.md）

| 编号 | 约定 |
|---|---|
| RH-1 | `holdReplies()` 之后，新到达的回应照常解析并发出 `assistantCommand` / `assistantText`，但不播放 TTS、不发出 `assistantSpeech*` / `assistantEmotion` / `assistantAction` / `assistantAudioLevel` |
| RH-2 | `releaseReplies(discardingTurnsStartedBefore: t)`：用户语音开始时刻早于 `t` 的暂缓回应全部丢弃（取消 TTS，不再发出任何事件）；其余按顺序正常播放；之后的回应恢复正常 |
| RH-3 | 被丢弃的回应仍保留在会话历史中 |
| RH-4 | `holdReplies` 不嵌套；未暂缓时调用 `releaseReplies` 无效果 |
| RH-5 | 暂缓期间插话判定照常运行，但只能清除可打断的播放（AF-2） |

### AudioIO（003 audio-gating.md）

| 编号 | 约定 |
|---|---|
| AF-1 | `enqueue(_:turnID:interruptible:)`，`interruptible` 默认 true |
| AF-2 | `flush()`（B-4 对话打断）只清除可打断的缓冲 |
| AF-3 | `cancel(turnID:)` 立即停止并移除该 turn 的全部缓冲，不论是否可打断；50 ms 内无声（同 IO-5） |
| AF-4 | 拍照短句与快门音效播放期间，人声闸门使用"播放期间"的提高阈值（G-3） |

### PresetPlayer（004 preset-phrases.md）

| 编号 | 约定 |
|---|---|
| PP-4 | `play(category:turnID:interruptible:emitsEmotion:) async -> PresetPlayback?`（条目 + `PlaybackResult`）；`emitsEmotion == false` 时不发出 `assistantEmotion`（仍发 `assistantAudioLevel`） |
| PP-5 | `stop(turnID:)`：经 `AudioIO.cancel(turnID:)` 停止，返回 `.stopped` |

## 测试要求

- 状态转换表每一行至少一个用例；PF-1–PF-14、RN-2、RN-6 各至少一个用例。
- 竞态与组合场景：
  - "好了" → 模型说"好嘞～"时用户插话"等一下" → 旧一轮结束不开始倒数（PF-4）。
  - 倒数中短词喊停后 `userSpeechEnded` 很快到达、模型不回应 → `replyDeadline` 到期后 5 s 再问（PF-9）。
  - 问句被用户打断（`.stopped`）→ 不启动再问计时（RN-2）。
  - 持续环境声（闸门一直开着）期间画面内的人开口 → 停止（PF-12）；跨拍保持闸门状态。
  - 口型先于人声 0.2 s → 停止；口型早于人声 0.5 s 且闸门打开期间无口型 → 不停止。
  - 收到 `<cmd:photo>` 后断网 → 8 s 后 `replyTimeout`。
  - 等人脸阶段说"不拍了" → 取消。
  - 无声降级下问句与各拍按标称时长推进，"茄子"不会 0 ms 拍照。
  - 问满 5 次放弃；确认时人不在画面 → 等人脸 → 直接倒数；倒数中人脸丢失 → 恢复 → 重新问；`cheese` 阶段插话仍然拍照。
  - 静音 / 后台中断时成对关闭口型检测、手势让出、回应暂缓与提示（PF-6）。
- Runner（Fakes）：副作用执行顺序、`captureFailed` / `saveFailed` 路径、快门音效调用、指标字段（M_photoStart、\|M_shutter\|、`stopLatency`）。
