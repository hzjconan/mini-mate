# Contract: EmotionStateMachine

**Module**: `MMEmotion` | **Feature**: `002-m1-presence`（M2 起接入真实对话事件；005 增补形象提示事件）

## 接口

```swift
public protocol EmotionStateMachine: Sendable {
    func handle(_ features: PerceptionFeatures) async
    func handle(_ event: ConversationEvent) async
    /// 按时间求值：根据当前状态与时间返回插值后的姿态。渲染循环每帧调用。
    func pose(at time: TimeInterval) async -> AvatarPose
    /// 当前状态（调试与测试用）
    var state: AvatarState { get async }
}
```

实现 `RuleBasedEmotionStateMachine(rules:presets:clock:random:)` MUST 允许注入时钟与随机源，以便测试确定性。

## 状态转换表

| 当前状态 | 输入 | 条件 | 新状态 | 附带效果 |
|---|---|---|---|---|
| Idle | 感知 | `isLookingAtScreen` 持续 ≥ 200 ms | Attending | 若距上次见到人脸 > 3 s，先播 `notice` |
| Attending | 感知 | 人脸丢失 ≥ 3 s | Idle | 播 `lookAround`（循环、低频） |
| Idle / Attending | `userSpeechStarted` | — | Listening | |
| Listening | `userSpeechEnded` | — | Thinking | 100 ms 内生效（M_feedback） |
| Thinking | `userEmotion(e)` | — | Thinking | `baseEmotion` 按映射切换（如 `sad` / `tired` / `anxious` → `concerned`，`happy` → `happy`） |
| Thinking / Listening | `assistantSpeechStarted` | — | Speaking(当前情绪) | |
| Speaking | `assistantEmotion(e)` | — | Speaking(e) | 在下一句开始播放时生效（M2 由引擎保证顺序） |
| Speaking | `assistantSpeechEnded` | — | Attending（有人脸）/ Idle | |
| Listening / Thinking / Speaking | `userSpeechStarted`（打断） | — | Listening | 清空计划中的反应 |
| 任意（非 Speaking） | 感知：`activeExpression` 进入 | 不在冷却 | 计划 Reacting | 延迟 300–800 ms 后进入 Reacting，结束回到原状态 |
| 任意（非 Speaking） | 感知：`gesture` | 不在冷却 | Reacting | 立即进入（手势是明确意图），延迟 ≤ 300 ms |
| Attending | 感知：快速靠近 | 1 s 内缩短 > 0.10 m | Reacting(`surprised`, `leanBack`) | |
| 任意 | `assistantAction(a)` | — | 不改变状态 | 播放动作 `a`（优先级高于感知反应） |
| Speaking | 感知反应 | — | 不改变 | 只允许叠加轻量表情（强度 ≤ 0.3），不打断说话表情 |
| 非 Listening / Thinking / Speaking | `assistantCue(c)` | — | Reacting(提示 c) | 立即播放 `c.action`（若有）；替换当前提示或感知反应（EM-1） |
| Listening / Thinking / Speaking | `assistantCue(c)` | — | 不改变 | 记为保持中的提示（EM-2） |
| Speaking | `assistantSpeechEnded` | 有保持中的提示 | Reacting(该提示) | 代替回到 Attending（EM-2） |
| Reacting(提示) | `assistantCueEnded` | — | Attending（有人脸）/ Idle | 清除保持中的提示（EM-5） |
| Reacting(提示) | 感知反应 | — | 不改变 | 不触发、不进入冷却（EM-3） |
| 任意 | `assistantCommand` | — | 不改变 | 状态机忽略 |

## 形象提示（005 增补）

拍照流程等非对话轮次的形象表现经 `assistantCue` 进入状态机，不借用 `assistantEmotion`（后者只在 Speaking 生效）。不新增 `AvatarStateKind`：提示以 `.reacting` 表示，`Reaction` 增加"来自提示、不可被感知反应打断"的标记。

| 编号 | 约定 |
|---|---|
| EM-1 | 非 Listening / Thinking / Speaking 状态收到 `assistantCue(c)` → 进入 `.reacting`（表情 `c.emotion`），立即播放 `c.action`（若有）；替换当前的提示或感知反应 |
| EM-2 | Listening / Thinking / Speaking 中收到 `assistantCue(c)` → 记为"保持中的提示"，不改变当前状态；`assistantSpeechEnded` 后回到该提示的 `.reacting`，而不是 Attending |
| EM-3 | 提示期间感知反应（表情、手势、快速靠近）一律不触发，也不进入冷却 |
| EM-4 | `c.hold == true` 保持到下一个提示或 `assistantCueEnded`；`false` 按默认反应时长（1.5 s）结束后回到原状态 |
| EM-5 | `assistantCueEnded` 清除保持中的提示，回到 Attending（有人脸）/ Idle |

## 感知反应映射

| 用户表情 / 手势 | 形象回应（表情 + 动作） | ReactionKey |
|---|---|---|
| smiling | `happy` | `smile` |
| frowning | `concerned` | `frown` |
| surprised | `surprised` | `surprise` |
| wave | `happy` + `wave` | `wave` |
| heart | `shy` + `heart` | `heart` |
| thumbsUp | `happy` + `nod` | `thumbsUp` |

同一 `ReactionKey` 冷却 8 s。冷却期间同类刺激只把 `baseEmotion` 的强度轻微提升。

## 姿态合成顺序（`pose(at:)`）

1. 底色：`baseEmotion` 预设 × 0.3
2. 状态层：当前状态对应预设（Thinking → `gentle` 微表情 + 视线略上移；Speaking(e) → 预设 e × 1.0；Reacting → 反应预设 × 1.0）
3. 过渡：按预设的 blendIn / blendOut 做时间插值
4. 口型层：`assistantAudioLevel` → `jawOpen`、`mouthFunnel`（覆盖嘴部系数）
5. 待机层：呼吸（头部微动）、眨眼（覆盖 `eyeBlinkLeft/Right`），始终叠加
6. 视线：Attending / Listening / Speaking / Reacting 时朝向用户脸位置；Idle 时随机游走；Thinking 时略偏上

## 不变式（测试必须覆盖）

| 编号 | 不变式 |
|---|---|
| S-1 | `AvatarPose.expressionWeights` 中不存在任何直接来自 `rawBlendShapes` 的值 |
| S-2 | 同一 `ReactionKey` 在冷却期内最多触发一次 |
| S-3 | 表情反应的触发时间与刺激时间之差 ∈ [300 ms, 800 ms] |
| S-4 | `userSpeechEnded` 后 100 ms 内 `state.kind == .thinking` |
| S-5 | Speaking 期间感知反应不改变 `state.kind` |
| S-6 | 所有权重 ∈ [0, 1] |
| S-7 | 提示（`assistantCue`）生效期间，感知反应不改变 `state.kind`，也不写入冷却 |
| S-8 | 有保持中的提示时，`assistantSpeechEnded` 之后 `state.kind` 为该提示的 `.reacting` |
