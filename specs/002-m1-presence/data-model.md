# Data Model: M1 感知与形象

**Feature**: `002-m1-presence`

所有类型为 `Sendable` 值类型。`MMCore` 中的枚举在 M2 的标签协议中复用，枚举的 rawValue 即标签值（如 `<emo:happy>` 对应 `EmotionTag.happy`）。

## MMCore

### EmotionTag（形象情绪）

`happy` · `gentle` · `sad` · `surprised` · `shy` · `playful` · `concerned` · `neutral`

每个值对应一个 `ExpressionPreset`。

### ActionTag（形象动作）

`nod` · `wave` · `spin` · `heart` · `shyCover` · `leanBack` · `lookAround` · `notice`

每个值对应一个 `ActionClip`。USDZ 内为一条 `SkelAnimation` 时间线，随包清单 `<asset>.actions.json` 用 rawValue 作为 key 声明每个片段的帧区间。

### UserEmotion（用户语气，M2 起由模型给出）

`happy` · `calm` · `sad` · `tired` · `angry` · `anxious`

### AssistantCommand（005 起）

`photo` · `photoReady` · `photoCancel`——模型输出的 App 指令，rawValue 即 `<cmd:…>` 标签值（005 `contracts/command-tag.md`）。

### AvatarCue（005 起）

| 字段 | 类型 | 说明 |
|---|---|---|
| `emotion` | `EmotionTag` | 提示期间的表情 |
| `action` | `ActionTag?` | 可选动作，收到提示时播放一次 |
| `hold` | `Bool` | true：保持到下一个提示或 `assistantCueEnded`；false：按默认反应时长结束 |

### PlaybackResult（005 起）

`completed` · `stopped`——一段 App 主动播放的音频（拍照短句、预置短句）是否完整播完。

### ConversationEvent

| case | 说明 |
|---|---|
| `userSpeechStarted` / `userSpeechEnded` | 用户开始 / 结束说话 |
| `userTranscript(String, isFinal: Bool)` | 用户转写 |
| `userEmotion(UserEmotion)` | 用户语气 |
| `assistantEmotion(EmotionTag)` | 助手情绪（作用于下一句） |
| `assistantAction(ActionTag)` | 助手动作 |
| `assistantText(String)` | 助手文字 |
| `assistantSpeechStarted` / `assistantSpeechEnded` | 助手开始 / 结束发声 |
| `assistantAudioLevel(Float)` | 0–1 音频电平，驱动口型 |
| `assistantCommand(AssistantCommand)` | 005：模型输出的 App 指令，不影响状态机 |
| `assistantCue(AvatarCue)` | 005：非对话轮次的形象提示（emotion-state-machine.md EM-1–EM-5） |
| `assistantCueEnded` | 005：结束当前保持中的提示 |

## MMPerception

### PerceptionFeatures（每帧，60 Hz）

| 字段 | 类型 | 说明 |
|---|---|---|
| `timestamp` | `TimeInterval` | ARFrame 时间戳 |
| `isFaceTracked` | `Bool` | |
| `rawBlendShapes` | `[String: Float]` | 52 个 ARKit 原始系数，键为 ARKit 名称；**只供 `FaceSignalDeriver` 使用，不得传给渲染器** |
| `signals` | `FaceSignals` | 平滑后的语义信号 |
| `facePosition` | `SIMD3<Float>?` | 用户脸在相机坐标系中的位置（米） |
| `isLookingAtScreen` | `Bool` | 经最短持续时间判定 |
| `gesture` | `GestureEvent?` | 本帧新识别出的手势（边沿触发） |

### FaceSignals

| 字段 | 类型 | 说明 |
|---|---|---|
| `smile` / `frown` / `surprise` | `Float` | 0–1，平滑后 |
| `activeExpression` | `UserExpression?` | 经阈值滞回与最短持续判定的当前表情：`smiling` / `frowning` / `surprised` |

### GestureEvent

| 字段 | 类型 |
|---|---|
| `kind` | `GestureKind`（`wave` / `heart` / `thumbsUp`） |
| `confidence` | `Float` |
| `timestamp` | `TimeInterval` |

## MMEmotion

### AvatarStateKind

`idle` · `attending` · `listening` · `thinking` · `speaking(EmotionTag)` · `reacting(Reaction)`

### Reaction

| 字段 | 类型 | 说明 |
|---|---|---|
| `expression` | `EmotionTag` | 形象回应用的表情 |
| `action` | `ActionTag?` | 可选动作 |
| `duration` | `Duration` | 默认 1.5 s |
| `returnTo` | `AvatarStateKind` | 结束后回到的状态 |

### AvatarState

| 字段 | 类型 | 说明 |
|---|---|---|
| `kind` | `AvatarStateKind` | |
| `enteredAt` | `TimeInterval` | |
| `baseEmotion` | `EmotionTag` | 当前底色情绪（如收到 `<user:sad>` 后为 `concerned`） |
| `cooldowns` | `[ReactionKey: TimeInterval]` | 各类反应的冷却到期时间 |
| `scheduled` | `[ScheduledReaction]` | 计划在未来某时刻触发的反应（实现随机延迟） |
| `lastFaceSeenAt` | `TimeInterval?` | |

### AvatarPose（每帧送给渲染器）

| 字段 | 类型 | 说明 |
|---|---|---|
| `expressionWeights` | `[String: Float]` | 形象**自己的**系数（由预设 × 强度 + 待机层 + 口型层合成），键为 ARKit 名称 |
| `headRotation` | `SIMD3<Float>` | 欧拉角（弧度），限幅 ±25° |
| `eyeTarget` | `SIMD2<Float>` | 视线方向（归一化） |
| `action` | `ActionCommand?` | `play(ActionTag)` / `stop`，边沿触发 |

### ExpressionPreset

| 字段 | 类型 | 说明 |
|---|---|---|
| `emotion` | `EmotionTag` | |
| `weights` | `[String: Float]` | 该表情满强度时的系数 |
| `blendIn` / `blendOut` | `Duration` | 过渡时间，默认 200 ms / 300 ms |

预设以 JSON 资源保存在 `Packages/MiniMateKit/Sources/MMEmotion/Resources/expression-presets.json`，便于调参。

调参初值（来自 2D 表情稿，T034 在调试面板里调整后以实际导出为准）：

| `emotion` | `weights` 初值 |
|---|---|
| `happy` | `mouthSmile` 0.8、`jawOpen` 0.2、`cheekSquint` 0.4、`browInnerUp` 0.3 |
| `gentle` | `mouthSmile` 0.5、`eyeSquint` 0.2 |
| `sad` | `mouthFrown` 0.6、`browInnerUp` 0.7、`eyeSquint` 0.3 |
| `surprised` | `jawOpen` 0.5、`eyeWide` 0.6、`browOuterUp` 0.5 |
| `shy` | `mouthSmile` 0.4、`eyeSquint` 0.5（低头由 `AvatarPose` 承担，不写权重） |
| `playful` | `mouthSmile` 0.6、`eyeSquint` 0.3、`tongueOut` 0.5（模型暂无舌头层，实际只表现为张嘴） |
| `concerned` | `mouthFrown` 0.3、`browDown` 0.4、`browInnerUp` 0.4 |
| `neutral` | 空（全部为 0） |

表中的对称键（如 `mouthSmile`）在 JSON 中需写成 ARKit 的左右两项（`mouthSmileLeft` / `mouthSmileRight`）。ARKit 52 个名称里没有“脸红”，腮红不通过权重实现。

### ReactionRules（可调参数）

| 参数 | 初值 |
|---|---|
| `reactionDelay` | 300–800 ms 均匀随机 |
| `reactionDuration` | 1.5 s |
| `cooldown` | 8 s（同一 `ReactionKey`） |
| `attendingEnter` | 看向屏幕持续 200 ms |
| `idleAfterFaceLost` | 3 s |
| `approachThreshold` | 1 s 内距离缩短 > 0.10 m |

## 状态转换

见 [contracts/emotion-state-machine.md](./contracts/emotion-state-machine.md)。
