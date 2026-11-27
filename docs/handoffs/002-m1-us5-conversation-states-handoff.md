# 002-m1-presence US5（T044 / T044a / T045 / T046）“对话阶段状态与形象提示”实现级执行单

- **状态**：已验收完成（2026-11-27，含 T047 真机验收）
- **Git 基线**：`main` @ `ee38bea`（注：起草前工作区已含用户未提交修改 `AGENTS.md`；上游 M0、M1 US1–US4 T001–T043 及 005 SDD 全套契约同步 `5aef3f3` 均已合入 `main`）
- **关键基线**：Swift `6.4`（`swift-tools-version: 6.2`，Swift 6 严格并发）、Xcode `27.0`（`27A266a`）、iOS `26+` / macOS `26+`、Swift Testing（当前全量单测 `118/118` across 20 suites 全绿：`MMCoreTests` 10 + `MMSecurityTests` 7 + `MMDiagnosticsTests` 14 + `MMPerceptionTests` 32 + `MMEmotionTests` 55）、零第三方运行时依赖；素材 `minimate.usdz` + `minimate.actions.json`（52/52 形态键、8/8 动作）与 8 个情绪预设均已真机验收
- **拍板决议摘要**：用户已拍板全按推荐方案 **1A / 2A / 3A** 实施（1A：实施 `002-m1-presence` US5 T044/T044a/T045/T046；2A：调试面板新增对话注入区 + 可选默认关闭的主界面悬浮对话条；3A：`UserEmotion` 6 语气映射且 `Thinking` 非中性 `baseEmotion` 以 0.65 主导不叠 `gentle`）。

> **红线声明**
> - 严格遵守 `.specify/memory/constitution.md`（最高优先级）与 `AGENTS.md`：
>   1. **陪伴而非镜像（NON-NEGOTIABLE）**：对话事件与 `assistantCue` 必须经 `EmotionStateMachine` 映射为形象自己的情绪预设、动作与口型层，严禁绕过状态机直接驱动渲染，严禁把 `rawBlendShapes` 写入 `AvatarPose`（S-1）；
>   2. **感知在本地，永不经过 LLM**：本任务不引入任何网络请求、录音或摄像头图像保存；
>   3. **纯逻辑测试先行（TDD）**：`MMCore` 新类型、`RuleBasedEmotionStateMachine` 对话转换与 `assistantCue`（EM-1–EM-5、S-4/S-5/S-7/S-8）及 `FeedbackLatencyTracker` 必须先写 Swift Testing 测试、确认失败再实现，全部可在 macOS 通过 `swift test` 确定性运行；
>   4. **可替换边界与简单优先**：保持 `EmotionStateMachine`、`PerceptionSource`、`AvatarRenderer` 协议零改动，不新增 `AvatarStateKind` case，零新增第三方依赖；
>   5. **隐私与密钥**：不写入任何 API Key，不提交 `Assets/voice-samples/*.wav`。
> - 设计阶段仅创建/维护本执行单，严禁改动任何业务代码、测试、Xcode 工程、配置、spec/tasks 或历史执行单。
> - 收口策略：未经用户明确确认验收，不得勾选 `specs/002-m1-presence/tasks.md`（或任何 `tasks.md`），不得修改 `research.md` 实测结论，不得 `git commit`，不得 `git push`。

---

## 上篇：面向用户决策

### 1. 任务目标与选择理由

- **本次任务**：`002-m1-presence` Phase 7 — **US5“对话阶段状态与形象提示”（T044、T044a、T045、T046 代码与测试闭环；不含 T047 人工真机验收与 Phase 8 稳定性压测）**。
  - 在 `MMCore` 落地跨 feature 共享契约：`AssistantCommand`、`AvatarCue`、`PlaybackResult`，并在 `ConversationEvent` 增补 `.assistantCommand`、`.assistantCue`、`.assistantCueEnded`；
  - 在 `MMEmotion` 完整实现 `RuleBasedEmotionStateMachine.handle(_ event: ConversationEvent)`：覆盖 `Listening` / `Thinking` / `Speaking` 全部对话转换、打断清空计划反应（含 003 E-2 乱序保护）、`userEmotion` → `baseEmotion` 映射、Thinking 姿态与微上移视线、口型层（姿态合成第 4 步 `assistantAudioLevel` 覆盖 `jawOpen`/`mouthFunnel`）、`assistantAction` 高优先级动作、Speaking S-5 保护，以及 005 增补的 `assistantCue` / `assistantCueEnded` 规则（EM-1–EM-5、S-7、S-8）；新增纯逻辑 `FeedbackLatencyTracker` 测量 `M_feedback`；
  - 在 `AvatarScreen` / `AvatarDebugPanel` 增加“对话事件注入（含 `assistantCue`/`assistantCueEnded`、口型电平与模拟说话口型）”、底色情绪/保持提示状态展示与 `M_feedback` 指标统计导出，为真机执行 Quickstart §5（T047）做好准备。
- **选择理由（全部未完成候选任务横向对比）**：
  1. **首选 · `002-m1-presence` Phase 7 / US5（T044–T046）**：
     - **M1 编码收口临门一脚**：`001` 已 100% 完成，`002` US1–US4（T001–T043）已全部完成，US5 是 M1 **最后一个功能 User Story**；完成后 M1 全部代码功能闭环，随后可在真机一次走完 T047 + Phase 8（SC-006 10 分钟压测 & SC-007 主观验收）正式关停 M1。
     - **消除 002 / 005 共享类型重复改动并同时解锁下游**：`002` T045 与 `005` T009 均需在 `MMCore` 新增 `AssistantCommand`、`AvatarCue`、`PlaybackResult` 和 `ConversationEvent` 3 个新 case。先在 002 US5 一次性落地并配齐状态机消费逻辑，同时解除 `003` US6 与 `005` Phase 2/4 的上游依赖。
     - **零外部阻塞、纯确定性逻辑**：无需云端厂商 Key 或自录语音样本，无需修改 `Package.swift` 或 `project.pbxproj`，小步快跑风险极低。
     - **不合并 Phase 8 Polish（T048–T050）的原因**：T048–T050 为真机 10 分钟压测记录、主观验收与文档回写，无预设代码改动，适合在 T047 真机验收阶段一并执行。
  2. **次选 · `005-voice-photo` Phase 1–3 / US1（语音拍照技术路径验证 T001–T022）**：
     - 注：005 Phase 0（T000 契约同步）的实际文档更新已在 `5aef3f3` 写入 002/003/004（仅 `005/tasks.md` 复选框尚未勾选）。
     - 虽然 005 US1 技术上只依赖 002 US1–US4，但其跨度大（新建 `MMPhoto` target、改 `Info.plist`、ARKit 高分辨率抓帧 + Vision 关键点 + RealityKit 离屏克隆快照 + 大量真机实测 R1–R5/R9/R10/R11），且与 002 T045 在 `MMCore` 重叠，排在 002 US5 之后收口 M1 更清爽。
  3. **暂缓 · `003-m2-voice-conversation` Phase 1–3 / M2a（T001–T025）**：
     - 需人工核查最新云端实时语音厂商文档、配置 API Key 环境变量并录制 9 条个人语气样本（`Assets/voice-samples/*.wav`），不适合打断即将完工的 M1。
  4. **未解锁 · `004-m3-memory-offline`**：硬依赖 003 完成。
- **摸底关键发现（3 个最关键的技术事实与风险）**：
  1. **跨 003 / 004 / 005 的 4 处隐蔽状态机边界已全部对齐**：
     - **003 E-2 乱序打断**：对话打断时引擎先发新一轮 `userSpeechStarted`、再发旧轮 `assistantSpeechEnded`；状态机必须仅在 `.speaking` 响应 `assistantSpeechEnded`，否则旧轮结束会把新轮 `.listening` 误踢回 `.attending`。
     - **005 CV-2 / 004 PP-3 非 Speaking 口型驱动**：拍照短句（“准备好了吗”“3、2、1、茄子”）播放时不发 `assistantSpeechStarted/Ended`，只发 `assistantCue` + `assistantAudioLevel`；因此口型层（Step 4）不能写死仅在 `.speaking` 生效，而应在收到非零 `assistantAudioLevel` 时覆盖 `jawOpen`/`mouthFunnel`（Speaking 期间 `0` 同样保持覆盖以便停顿闭嘴，非 Speaking 收到 `0` 或状态结束时释放回预设）。
     - **005 `photoCancel` 在对话中触发 `assistantCueEnded`**：确认环节用户说“不拍了”时，拍照控制器会在模型说完“好，不拍啦”之前发出 `assistantCueEnded`；因此 `Listening/Thinking/Speaking` 期间收到 `assistantCueEnded` **只清除 `heldCue`**，绝不打断正在播出的回复。
     - **`hold == true` 提示不走 1.5 s 衰减包络**：`RuleBasedEmotionStateMachine.swift:305-321,740-759` 现有 `.reacting` 均按 1.5 s `duration` 自动 `blendOut` 并到期退出；`holdsUntilEnded == true` 必须跳过过期判定并维持满强度 `1.0`（直到新提示或 `assistantCueEnded` 将其推入 `fadingLayers` 平滑淡出）。
  2. **`ReflexLatencyTracker` 与现有 `.thinking` 视线存在真实代码缺口**：
     - `ReflexLatencyTracker.swift:74-79` 仅检查 `reaction.action == nil && reaction.expression == expected`，若用户在微笑排程期间收到无动作的 `assistantCue(.happy, action: nil)`，会误算为 `M_reflex`；需加 `!reaction.isCue` 隔离。
     - `RuleBasedEmotionStateMachine.swift:381-416` 目前将 `.thinking` 归入 `isEngaged = false` 走了随机游走（可能低头），不符合契约“Thinking 时视线略偏上”；本轮修正为确定性微仰视（抬头 `-4°` + 眼球上移）。
  3. **全屏 `NavigationStack` 调试面板与 `M_feedback` 计时陷阱**：
     - `AvatarDebugPanel` 当前通过 `.navigationDestination` 全屏推入，推入期间底层 `RealityView` 的 `SceneEvents.Update`（`tick()`）可能暂停；若 `M_feedback` 盲目等 `tick()` 落帧才会记录，在面板内点“用户结束说话”会漏记或记出数秒假延迟。因此调试面板内注入时必须在 `stateMachine.handle` + `pose(at:)` 完成后立即落样本，主界面可见（如开启悬浮条）时再由 `tick()` 渲染应用后落端到端样本。

### 2. 待用户拍板的决策清单

<!-- 用户回复如 "1A 2A 3A" 即可。定稿后将结论固化进下篇正文，清理落选分支。 -->

1. **下一步任务选择与范围粒度**
   - **1A（推荐）**：实施 **`002-m1-presence` Phase 7 / US5（T044、T044a、T045、T046 代码与测试闭环，不含 T047 人工真机验收与 Phase 8 压测）**。
     - *理由*：收口 M1 最后一个功能 story，一次性落地 `MMCore` 共享契约并同时解锁 003/005，零外部依赖、风险最低。
   - **1B**：暂缓 002 US5，转而先启动 **`005-voice-photo` Phase 1–3 / US1（语音拍照技术路径验证）**。
     - *权衡*：提前验证 ARKit 抓帧与离屏快照，但会拖延 M1 收口，且与 002 T045 在 `MMCore` 变更上重叠、单轮体量大。

2. **真机调试注入交互形态（`AvatarScreen` 可选悬浮条）**
   - **2A（推荐）**：在 `AvatarDebugPanel` 新增完整**“对话事件注入（US5）”**分区，并在该分区顶部提供一个**“主界面悬浮对话条”开关（默认关闭）**；开启后返回主界面可在底部直接一边看小瓜实时表情/视线/口型/动作，一边点击步进（`Listening → Thinking → <user:sad> → Speaking(gentle) → Attending`）、切换模拟口型和触发 `assistantCue` / `assistantCueEnded`。
     - *理由*：避免全屏进出调试面板遮挡 3D 形象，大幅提升 T047（含“Speaking 时微笑不打断”与口型观察）真机验收效率；默认关闭对正常主界面零视觉侵入。
   - **2B**：仅在 `AvatarDebugPanel` 内提供对话事件注入分区，不在 `AvatarScreen` 增加可选悬浮条。
     - *权衡*：`AvatarScreen` UI 更简，但真机验收需反复在面板与形象页之间切换。

3. **`Thinking` 收到非中性 `<user:…>`（如 `<user:sad>`）时的表情合成与 6 语气映射**
   - **3A（推荐）**：6 个 `UserEmotion` 映射为 `happy → .happy`、`calm → .neutral`、`sad / tired / anxious / angry → .concerned`（用户生气时表达关切，不镜像愤怒）；`Thinking` 下当 `baseEmotion == .neutral` 时叠加 `gentle × 0.35` 微表情，**当 `baseEmotion != .neutral` 时改由 `baseEmotion` 预设以 `0.65` 强度主导 Thinking 表情（不再叠加 `gentle` 微笑）**，并保持视线略偏上。
     - *理由*：避免 `<user:sad>` 时 `concerned` 的 `mouthFrown` 与 `gentle` 的 `mouthSmile` 互相抵消，使 US5 验收场景 3“注入 `<user:sad>` 切换为关切神情并保持 Thinking”在真机上清晰可辨。
   - **3B**：`Thinking` 始终固定叠加 `baseEmotion × 0.3` + `gentle × 0.35`，不做互斥增强。
     - *权衡*：字面直译契约简写，但真机上 `<user:sad>` 的撇嘴与 `gentle` 微笑会相互中和、关切感偏弱。

---

## 下篇：面向实施方的零歧义施工图

> 以下正文已按拍板决议 **1A / 2A / 3A** 定稿，无条件分支。

### 3. 现状锚点与环境陷阱预警

#### 3.1 现有代码锚点

| 模块/符号 | 精确位置 | 职责与复用/约束说明 |
| :--- | :--- | :--- |
| `Package.swift` targets | `Packages/MiniMateKit/Package.swift:19-31` | `MMCore` 无外部依赖；`MMEmotion` 依赖 `MMCore`、`MMPerception`；`MMCoreTests` 依赖 `MMCore`；`MMEmotionTests` 依赖 `MMEmotion`、`MMAvatar`、`MMCore`、`MMPerception`。**本轮严禁修改 `Package.swift` 或 `project.pbxproj`** |
| `EmotionTag` / `ActionTag` / `UserEmotion` | `Packages/MiniMateKit/Sources/MMCore/EmotionTag.swift:1-11`、`ActionTag.swift:1-11`、`UserEmotion.swift:1-9` | `MMCore` 枚举范式：`public enum ...: String, CaseIterable, Codable, Sendable`。新增 `AssistantCommand`、`PlaybackResult` 严格沿用该声明风格 |
| `ConversationEvent` | `Packages/MiniMateKit/Sources/MMCore/ConversationEvent.swift:1-14` | 当前含 10 个 case，全仓尚无 `switch` 消费方（`git grep` 已核实）。本轮追加 `.assistantCommand(AssistantCommand)`、`.assistantCue(AvatarCue)`、`.assistantCueEnded` |
| `LatencyRecorder` | `Packages/MiniMateKit/Sources/MMCore/Metrics/LatencyRecorder.swift:4-80` | 通用按 `metric: String` 记录与导出 CSV；直接写入 `"M_feedback"`，**无需修改** |
| `AvatarStateKind` / `Reaction` / `AvatarState` | `Packages/MiniMateKit/Sources/MMEmotion/AvatarState.swift:5-72` | 严禁新增 `AvatarStateKind` case。`Reaction` 新增 `isCue: Bool = false`、`holdsUntilEnded: Bool = false`；`AvatarState` 新增 `heldCue: AvatarCue? = nil`（默认参数保证 `AttentionTransitionTests.swift:145` 与 `GestureReactionTests.swift:285` 100% 源码及相等性兼容） |
| `EmotionStateMachine` | `Packages/MiniMateKit/Sources/MMEmotion/EmotionStateMachine.swift:6-15` | 协议已声明 `func handle(_ event: ConversationEvent) async`，**保持协议零修改** |
| `RuleBasedEmotionStateMachine` | `Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift:7-924` | `:171-173` 当前为空实现；`:211-220` `_setStateKindForTesting` 被 `GestureReactionTests.swift:155` 使用，**必须保留**；`:305-369` 姿态合成 Step 2/3；`:381-416` 视线合成（`.thinking` 当前误走 `evaluateIdleWander`）；`:500-638, 803-886` 感知反应/淡出层/手势触发；`:740-759` `checkReactingExpiration`（`AttentionTransitionTests.swift:265` 依赖 `.attending` 回落 `Idle` + `lookAround` 行为） |
| `ReflexLatencyTracker` | `Packages/MiniMateKit/Sources/MMEmotion/ReflexLatencyTracker.swift:60-83` | `:74-79` 需增补 `!reaction.isCue`，防止无动作 `assistantCue` 误触发 `M_reflex` |
| `TrackLatencyTracker` | `Packages/MiniMateKit/Sources/MMEmotion/TrackLatencyTracker.swift:5-94` | 纯逻辑时延追踪器范式，新增 `FeedbackLatencyTracker` 沿用其 `Sendable` + `Equatable` + `timeout` 防御风格 |
| `ExpressionPreset` & `expression-presets.json` | `Packages/MiniMateKit/Sources/MMEmotion/Resources/expression-presets.json:1-98` | 8 情绪预设已真机调优完毕；其中 `happy` 含 `jawOpen: 0.2`、`surprised` 含 `jawOpen: 0.65`、`playful` 含 `jawOpen: 0.15`。**本轮严禁修改 `expression-presets.json`** |
| `RealityKitAvatarRenderer` | `Packages/MiniMateKit/Sources/MMAvatar/RealityKitAvatarRenderer.swift:140-168, 417-444` | 已支持稀疏 `expressionWeights` 省略键自动归零与全部 8 动作播完平滑恢复，**本轮严禁修改 `MMAvatar`** |
| `AvatarScene` / `AvatarScreen` | `App/MiniMate/Screens/AvatarScreen.swift:35-98, 264-330, 671-767, 782-906` | `:264-284` 感知循环；`:671-767` `tick()`；`:879-884` `AvatarDebugPanel` 导航推入。本轮增量接入串行对话事件注入、口型模拟、`FeedbackLatencyTracker` 及可选主界面悬浮对话条 |
| `AvatarDebugPanel` | `App/MiniMate/Screens/Debug/AvatarDebugPanel.swift:13-38, 173-194, 417-431` | `:13-38` 状态区增量显示 `baseEmotion`、`heldCue`；新增“对话事件注入（US5）”分区；`:173-194` 指标区增量显示 `M_feedback` 并更新 `:186` 导出可见条件；`:417-431` `stateLabel` 标注 `cue` 与 `hold` |

#### 3.2 环境与平台实测陷阱预警

1. **陷阱 1 · `Swift.Clock` 命名冲突（已实测确认）**：
   - 表现：Swift 6 标准库已内置 `Swift.Clock`，直接使用 `Clock` 会与 `MMCore.Clock` 冲突编译失败。
   - **必须采用的写法**：所有源码与测试均显式写 `any MMCore.Clock`。
2. **陷阱 2 · `handle(_ event: ConversationEvent)` 无时间戳参数时的测试时基对齐**：
   - 表现：`EmotionStateMachine.handle(_ event:)` 签名不带时间参数，内部必须读取 `clock.now.timeIntervalSinceReferenceDate`；若测试用不可变 `FixedClock(0)` 同时以 `t = 10.0` 调用 `handle(PerceptionFeatures)` 与 `pose(at: 10.0)`，会导致 `enteredAt = 0` 与 `evalTime = 10.0` 脱节、1.5 s 反应瞬间过期。
   - **必须采用的写法**：`RuleBasedEmotionStateMachine.handle(_ event:)` 统一使用 `currentEventTime()`（取有限的 `clock.now.timeIntervalSinceReferenceDate`，异常时回退 `lastEvaluatedTime ?? currentState.enteredAt`）；新增测试 `ConversationTransitionTests` 与 `AvatarCueTests` 必须使用可变 `ManualClock`，确保 `clock.now`、感知帧 `timestamp` 与 `pose(at:)` 处于同一推进时基。
3. **陷阱 3 · `AttentionTransitionTests:265` 对 `checkReactingExpiration` 的隐含依赖（已读源码确认）**：
   - 表现：`AttentionTransitionTests.swift:276-285` 在 `t = 10.7` 触发 `leanBack`（`returnTo == .attending`，未发送 `isFaceTracked: false` 帧），随后直接调用 `pose(at: 14.7)` 断言回到 `.idle` 且产出 `.play(.lookAround)`。若给 `checkReactingExpiration` 错加 `!wasFaceTracked` 条件会直接破坏该既有测试；反之若不区分 `reaction.returnTo`，在 `.listening`/`.thinking` 期间的感知反应到期时会误把对话中断回 `.idle`。
   - **必须采用的写法**：`checkReactingExpiration` 仅在 `!reaction.holdsUntilEnded` 时检查到期；到期后仅当 `case .attending = reaction.returnTo` 且 `now - lastSeen + 1e-9 >= rules.idleAfterFaceLost` 时转 `transitionToIdleWithLookAround(at: now)`，否则回到 `reaction.returnTo`。
4. **陷阱 4 · `NavigationDestination` 全屏面板导致 `tick()` 暂停下的 `M_feedback` 失真**：
   - 表现：用户在全屏 `AvatarDebugPanel` 内点击“用户结束说话”时，底层 `RealityView` 的 `tick()` 不再每帧回调，若仅在 `tick()` 里完成 `FeedbackLatencyTracker.observeAppliedState`，会导致样本缺失或退出面板后记出数秒假延迟。
   - **必须采用的写法**：`AvatarScene.injectConversationEvent` 串行执行 `handle(event)` + `pose(at:)` + `state` 刷新；当 `isDebugPanelPresented == true` 时在 `pose(at:)` 返回后立即完成 `feedbackLatencyTracker.observeAppliedState` 记录，当 `isDebugPanelPresented == false`（如主界面悬浮条或后续 M2 实时对话）时由 `tick()` 在 `renderer.apply(pose)` 之后完成端到端记录。
5. **陷阱 5 · 沙盒内 `swift test` 的 Clang Module Cache 路径（已本机实测确认）**：
   - 在受限沙盒内执行单测须使用：`cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox`；常规本机终端直接 `cd Packages/MiniMateKit && swift test` 即可。

---

### 4. 改动范围表与明确不做清单（Non-Goals）

#### 4.1 文件改动表

| 文件路径 | 操作 | 精确职责 |
| :--- | :--- | :--- |
| `Packages/MiniMateKit/Sources/MMCore/AssistantCommand.swift` | 新增 | **T045**：定义 `AssistantCommand`（`photo` / `photoReady` / `photoCancel`，`String, CaseIterable, Codable, Sendable`） |
| `Packages/MiniMateKit/Sources/MMCore/AvatarCue.swift` | 新增 | **T045**：定义 `AvatarCue(emotion: EmotionTag, action: ActionTag? = nil, hold: Bool = false)`（`Sendable, Equatable, Codable`） |
| `Packages/MiniMateKit/Sources/MMCore/PlaybackResult.swift` | 新增 | **T045**：定义 `PlaybackResult`（`completed` / `stopped`，`String, CaseIterable, Codable, Sendable`） |
| `Packages/MiniMateKit/Sources/MMCore/ConversationEvent.swift` | 修改 | **T045**：追加 `.assistantCommand(AssistantCommand)`、`.assistantCue(AvatarCue)`、`.assistantCueEnded` |
| `Packages/MiniMateKit/Tests/MMCoreTests/MMCoreTests.swift` | 修改 | **T045 测试（先写）**：验证 `AssistantCommand` rawValue 与 Codable、`AvatarCue` 默认值与 Equatable/Codable、`PlaybackResult` 枚举、`ConversationEvent` 新 case 相等性 |
| `Packages/MiniMateKit/Sources/MMEmotion/AvatarState.swift` | 修改 | **T045**：`Reaction` 增补 `isCue: Bool = false`、`holdsUntilEnded: Bool = false`；`AvatarState` 增补 `heldCue: AvatarCue? = nil` |
| `Packages/MiniMateKit/Sources/MMEmotion/FeedbackLatencyTracker.swift` | 新增 | **T045/T046 纯逻辑**：测量 `userSpeechEnded`（自 Listening）→ `.thinking` 的 `M_feedback` 时延（秒） |
| `Packages/MiniMateKit/Sources/MMEmotion/ReflexLatencyTracker.swift` | 微调 | **T045 防污染**：`observeAppliedState` 增补 `!reaction.isCue` 守卫，避免无动作提示误计为 `M_reflex` |
| `Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift` | 修改 | **T045**：实现完整对话事件转换、EM-1–EM-5 `assistantCue`/`assistantCueEnded`、`userEmotion` → `baseEmotion` 映射、Thinking 姿态与微仰视、Speaking 过渡、Step 4 口型层、`assistantAction` 优先级保护及 `resetToIdle` 清理 |
| `Packages/MiniMateKit/Tests/MMEmotionTests/ConversationTransitionTests.swift` | 新增 | **T044（先写测试）**：覆盖对话转换表全部行、S-4/S-5/S-6、打断清空计划反应与 003 E-2 回归、Thinking 视线与 `<user:…>` 6 映射、口型层覆盖与释放、`assistantAction` 优先级、`FeedbackLatencyTracker` |
| `Packages/MiniMateKit/Tests/MMEmotionTests/AvatarCueTests.swift` | 新增 | **T044a（先写测试）**：覆盖 EM-1–EM-5、S-7、S-8、`hold` 与非 `hold`、提示替换、Speaking 期间收到提示与 `assistantSpeechEnded` 返回提示（含动作不重复播放）、`assistantCueEnded` 在不同状态的行为、提示期间表情/手势/快速靠近被抑制且不写冷却、005 CV-2 口型联动、`assistantCommand` 忽略及 `ReflexLatencyTracker` 隔离 |
| `App/MiniMate/Screens/AvatarScreen.swift` | 修改 | **T046**：`AvatarScene` 新增串行 FIFO `injectConversationEvent(_:)`、`currentBaseEmotion`、`currentHeldCue`、`debugAudioLevel`、`isSimulatingSpeechMouth`、`FeedbackLatencyTracker`（写入 `"M_feedback"`）、口型模拟定时器、重置方法及（2A）可选主界面悬浮对话调试条 |
| `App/MiniMate/Screens/Debug/AvatarDebugPanel.swift` | 修改 | **T046**：状态区增补 `baseEmotion`/`heldCue` 与 `cue`/`hold` 标签；新增“对话事件注入（US5）”完整分区（含 `assistantCue`/`assistantCueEnded` 与 005 预设、口型滑杆与模拟开关、2A 悬浮条开关）；指标区增补 `M_feedback` 样本/p50/p90 与导出条件 |

#### 4.2 明确不做清单（Non-Goals）

- **严禁修改**：
  - `Packages/MiniMateKit/Package.swift`、`App/MiniMate.xcodeproj/project.pbxproj`、`App/MiniMate/AppComposition.swift`；
  - `Packages/MiniMateKit/Sources/MMPerception/*`、`Packages/MiniMateKit/Sources/MMAvatar/*`、`Packages/MiniMateKit/Sources/MMDiagnostics/*`、`Packages/MiniMateKit/Sources/MMSecurity/*`；
  - `Packages/MiniMateKit/Sources/MMEmotion/EmotionStateMachine.swift`、`ReactionRules.swift`、`ExpressionPreset.swift`、`Resources/expression-presets.json`、`MirrorCorrelationEvaluator.swift`、`TrackLatencyTracker.swift`、`IdleMotionLayer.swift`；
  - `App/MiniMate/Resources/Avatar/*`、`Assets/avatar/*`；
  - 全部既有测试文件（`AttentionTransitionTests.swift`、`ExpressionReactionTests.swift`、`GestureReactionTests.swift`、`NoMirroringTests.swift` 等）的既有断言；
  - `specs/002-m1-presence/tasks.md`、`specs/002-m1-presence/research.md`、`specs/005-voice-photo/tasks.md`、`docs/tech-selection.md`（确认验收前不勾选、不回写）。
- **本次不实现**：
  - T047 人工真机验收记录与 Phase 8（T048–T050）稳定性压测/主观验收；
  - `003` 的 `MMAudio` / `MMConversation` / `TagParser` 或 `005` 的 `MMPhoto` 业务代码；
  - `docs/issues/001-periodic-bottom-left-head-drop.md` 的定向排查（该问题当前无法复现，留待 Phase 8 压测观察）。

---

### 5. 精确接口与行为契约

#### 5.1 `MMCore` 新增与扩展类型

1. **`Packages/MiniMateKit/Sources/MMCore/AssistantCommand.swift`**
   ```swift
   /// 模型输出的 App 指令。rawValue 即 `<cmd:...>` 标签值（005 `contracts/command-tag.md`）。
   public enum AssistantCommand: String, CaseIterable, Codable, Sendable {
       case photo
       case photoReady
       case photoCancel
   }
   ```
2. **`Packages/MiniMateKit/Sources/MMCore/AvatarCue.swift`**
   ```swift
   /// 非对话轮次的形象提示（如 005 拍照流程的准备/倒数/完成表现），经 `ConversationEvent.assistantCue` 进入情绪状态机。
   public struct AvatarCue: Sendable, Equatable, Codable {
       public let emotion: EmotionTag
       public let action: ActionTag?
       public let hold: Bool

       public init(
           emotion: EmotionTag,
           action: ActionTag? = nil,
           hold: Bool = false
       ) {
           self.emotion = emotion
           self.action = action
           self.hold = hold
       }
   }
   ```
3. **`Packages/MiniMateKit/Sources/MMCore/PlaybackResult.swift`**
   ```swift
   /// 一段 App 主动播放的音频（拍照短句、预置短句）是否完整播完。供 `MMPhoto` 与 `004` 共用。
   public enum PlaybackResult: String, CaseIterable, Codable, Sendable {
       case completed
       case stopped
   }
   ```
4. **`Packages/MiniMateKit/Sources/MMCore/ConversationEvent.swift`**（在末尾追加 3 个 case，既有 10 个 case 与签名不变）
   ```swift
   /// 005：模型输出的 App 指令，情绪状态机忽略。
   case assistantCommand(AssistantCommand)
   /// 005：非对话轮次的形象提示（emotion-state-machine.md EM-1–EM-5）。
   case assistantCue(AvatarCue)
   /// 005：结束当前保持中的提示。
   case assistantCueEnded
   ```

#### 5.2 `MMEmotion` 状态模型与时延追踪器

1. **`Packages/MiniMateKit/Sources/MMEmotion/AvatarState.swift`**
   - `AvatarStateKind` 保持现有 6 个 case **严禁新增**。
   - `Reaction` 增补 2 个带默认值的属性：
     ```swift
     public struct Reaction: Sendable, Equatable {
         public let expression: EmotionTag
         public let action: ActionTag?
         public let duration: Duration
         public let returnTo: AvatarStateKind
         /// 是否来自 `assistantCue`（EM-1–EM-5）：为 true 时不可被感知反应打断，且不写入感知冷却。
         public let isCue: Bool
         /// 提示是否保持到下一个 `assistantCue` 或 `assistantCueEnded`（EM-4）。
         public let holdsUntilEnded: Bool

         public init(
             expression: EmotionTag,
             action: ActionTag? = nil,
             duration: Duration = .milliseconds(1500),
             returnTo: AvatarStateKind,
             isCue: Bool = false,
             holdsUntilEnded: Bool = false
         )
     }
     ```
   - `AvatarState` 增补 1 个带默认值的属性：
     ```swift
     /// 当前保持中（或对话期间暂存待恢复）的形象提示（EM-2、EM-4、EM-5）。
     public let heldCue: AvatarCue?
     ```
     `init` 末尾新增参数 `heldCue: AvatarCue? = nil`，既有调用方零修改。

2. **`Packages/MiniMateKit/Sources/MMEmotion/FeedbackLatencyTracker.swift`**
   ```swift
   import Foundation
   import MMCore

   /// 测量 M_feedback：从 `userSpeechEnded`（Listening 态）到观测到 `.thinking` 状态的时间差（秒）。
   public struct FeedbackLatencyTracker: Sendable, Equatable {
       public let timeout: TimeInterval
       private var pendingStartedAt: TimeInterval?

       public init(timeout: TimeInterval = 3.0)

       /// 在 `userSpeechEnded` 送入状态机前调用；仅当 `previousState` 为 `.listening`
       /// （或底层状态为 `.listening` 的非提示 `.reacting`）且 `timestamp.isFinite` 时武装。
       public mutating func observeUserSpeechEnded(
           previousState: AvatarStateKind,
           at timestamp: TimeInterval
       )

       /// 在状态机产出新状态/渲染应用姿态后调用；首次观测到 `.thinking` 且 `0 <= latency < timeout` 时
       /// 返回单次 M_feedback 样本（秒）并解除武装；超时或负值则清零返回 `nil`。
       public mutating func observeAppliedState(
           _ stateKind: AvatarStateKind,
           at timestamp: TimeInterval
       ) -> TimeInterval?

       public mutating func reset()
   }
   ```

3. **`Packages/MiniMateKit/Sources/MMEmotion/ReflexLatencyTracker.swift`**（微调 `:74-79`）
   - 在 `guard case .reacting(let reaction) = stateKind` 条件中新增 `!reaction.isCue`，其余行为与测试完全不变。

#### 5.3 `RuleBasedEmotionStateMachine` 对话状态、形象提示与口型层精确契约

- **公开静态常量**（复用同文件 `maxHeadAngleRadians` 风格）：
  - `public static let lipSyncJawOpenScale: Float = 0.80`
  - `public static let lipSyncMouthFunnelScale: Float = 0.35`
  - `public static let thinkingHeadPitchRadians: Float = -4 * .pi / 180`（负 X 弧度 = 微微抬头）
  - `public static let thinkingHeadYawRadians: Float = 2 * .pi / 180`
  - `public static let thinkingEyeTarget = SIMD2<Float>(0.15, 0.45)`（`eyeTarget.y > 0` 驱动 `eyeLookUpLeft/Right`）
- **内部状态新增字段**：
  - `private struct StoredCue: Sendable, Equatable { let cue: AvatarCue; var actionPlayed: Bool }`
  - `private var storedCue: StoredCue?`（同步镜像到 `currentState.heldCue = storedCue?.cue`）
  - `private var activeAudioLevel: Float?`（`nil` 表示当前无口型覆盖；非 `nil` 时 Step 4 强制覆盖 `jawOpen` / `mouthFunnel`）
  - `private var pendingActionIsAssistant: Bool = false`（保护 `assistantAction` / `assistantCue` 动作不被同帧感知动作覆写；`pose(at:)` 消费 `pendingAction` 时同步重置为 `false`）
  - `private var hasActiveFaceSession: Bool = false`（收到 `isFaceTracked == true` 时置 `true`；`resetToIdle`、`transitionToIdleWithLookAround` 或对话/提示结束落回 `.idle` 时置 `false`）
- **辅助方法口径**：
  - `currentEventTime() -> TimeInterval`：读取 `clock.now.timeIntervalSinceReferenceDate`；若非有限则回退 `lastEvaluatedTime ?? currentState.enteredAt`。
  - `hasFacePresent(at now: TimeInterval) -> Bool`：
    ```swift
    if wasFaceTracked { return true }
    guard hasActiveFaceSession, let lastSeen = currentState.lastFaceSeenAt else { return false }
    return now - lastSeen + 1e-9 < rules.idleAfterFaceLost
    ```
  - `isCueActive: Bool`：`if case .reacting(let r) = currentState.kind { return r.isCue }; return false`。
  - `isConversationState(_ kind: AvatarStateKind) -> Bool`：`.listening` / `.thinking` / `.speaking` 返回 `true`（`.reacting` 返回 `false`）。
  - `baseEmotion(for userEmotion: UserEmotion) -> EmotionTag`（按 3A）：
    - `.happy` → `.happy`
    - `.calm` → `.neutral`
    - `.sad`, `.tired`, `.anxious`, `.angry` → `.concerned`
  - `reactionFactor(for reaction: Reaction, elapsed: TimeInterval, preset: ExpressionPreset) -> Float`（`pose(at:)` 与 `snapshotCurrentReactingIfNeeded` 唯一共享源）：
    - 若 `reaction.holdsUntilEnded == true`：若 `elapsed < 0` 返回 `0`；若 `blendIn > 0` 返回 `clamp(elapsed / blendIn, 0, 1)`，否则返回 `1.0`（永不自动 `blendOut`）。
    - 若 `reaction.holdsUntilEnded == false`：复用现有 `Self.envelope(elapsed:duration:blendIn:blendOut:)`。
  - `speakingFactor(elapsed: TimeInterval, preset: ExpressionPreset) -> Float`：
    - 若 `elapsed < 0` 返回 `0`；若 `blendIn > 0` 返回 `clamp(elapsed / blendIn, 0, 1)`，否则返回 `1.0`。

- **`handle(_ event: ConversationEvent)` 逐 case 精确语义**（入口先用 `let now = currentEventTime()` 执行 `checkReactingExpiration(at: now)` 与 `pruneTransientLayers(at: now)`）：
  1. **`.userSpeechStarted`**：
     - 任意状态（`Idle` / `Attending` / `Reacting` / `Listening` / `Thinking` / `Speaking`）均转入 `.listening`（`enteredAt: now`）；
     - 若原为 `.reacting` 或 `.speaking`，将当前权重快照推入 `fadingLayers` 平滑淡出；
     - **清空 `scheduled = []`**、`activeReactionKey = nil`、`cooldownBoost = nil`、`speakingOverlay = nil`、`activeAudioLevel = nil`；
     - **保留 `storedCue`**（若原本有保持中的 `hold: true` 提示，本轮对话结束后按 EM-2/S-8 恢复该提示；若原为 `hold: false` 提示，其 `storedCue` 本就为 `nil`，不会复活）。
  2. **`.userSpeechEnded`**：
     - 当 `currentState.kind == .listening`，或 `case .reacting(let r) = currentState.kind` 且 `!r.isCue && Self.underlyingStateKind(of: r.returnTo) == .listening` 时：
       - 若原为 `.reacting`，快照推入 `fadingLayers` 并清 `activeReactionKey = nil`；
       - 立即转入 `.thinking`（`enteredAt: now`，确保 S-4 ≪ 100 ms）。
     - 其他状态（`.idle` / `.attending` / `.thinking` / `.speaking` / `.reacting(isCue: true)`）：忽略，不改变状态。
  3. **`.userEmotion(let userEmotion)`**：
     - 当 `Self.underlyingStateKind(of: currentState.kind) == .thinking` 且 `!isCueActive` 时：
       - 更新 `currentState.baseEmotion = Self.baseEmotion(for: userEmotion)`，保持 `kind` 与 `enteredAt` 不变。
     - 其他状态：忽略。
  4. **`.assistantSpeechStarted`**：
     - 当 `currentState.kind` 为 `.thinking` / `.listening`，或非提示 `.reacting` 且 `underlyingStateKind` 为 `.thinking` / `.listening` 时：
       - 若原为 `.reacting`，快照推入 `fadingLayers`；
       - 清空 `scheduled = []`、`activeReactionKey = nil`、`cooldownBoost = nil`、`speakingOverlay = nil`；
       - 转入 `.speaking(currentState.baseEmotion)`（`enteredAt: now`）。
     - 其他状态（包括已在 `.speaking`、`.idle`、`.attending`、`.reacting(isCue: true)`）：不改变状态。
  5. **`.assistantEmotion(let emotion)`**：
     - 仅当 `case .speaking(let currentEmotion) = currentState.kind` 时生效：
       - 若 `currentEmotion != emotion`：将当前 `.speaking(currentEmotion)` 权重快照推入 `fadingLayers`，更新为 `.speaking(emotion)`（`enteredAt: now`）；
       - 若相同：无操作（不重启 `blendIn`）。
     - 非 `.speaking` 状态：忽略（严格保证 005 D13 契约）。
  6. **`.assistantSpeechEnded`**：
     - 仅当 `case .speaking = currentState.kind` 时生效（保障 **003 E-2**：打断后迟到的旧轮 `assistantSpeechEnded` 到达 `.listening` 时被安全忽略！）：
       - 将当前 `.speaking` 权重快照推入 `fadingLayers`；
       - 清空 `speakingOverlay = nil`、`activeAudioLevel = nil`；
       - **EM-2 / S-8 检查**：若 `var held = storedCue` 非空：
         - 计算 `returnTo: AvatarStateKind = hasFacePresent(at: now) ? .attending : .idle`；
         - 构造 `Reaction(expression: held.cue.emotion, action: held.cue.action, duration: rules.reactionDuration, returnTo: returnTo, isCue: true, holdsUntilEnded: held.cue.hold)` 并进入 `.reacting(reaction)`（`enteredAt: now`）；
         - 仅当 `!held.actionPlayed` 且 `let action = held.cue.action` 时设置 `pendingAction = .play(action)`、`pendingActionIsAssistant = true`；标记 `held.actionPlayed = true`；
         - 若 `held.cue.hold == true`：写回 `storedCue = held`；否则（`hold == false`）：清空 `storedCue = nil`（本轮结束后按 1.5 s 过期，不再重复恢复）。
       - 若 `storedCue == nil`：
         - 若 `hasFacePresent(at: now)`：进入 `.attending`（清 `lookingStartedAt`、`nextLookAroundAt`、`pendingNoticeOnAttend = false`；重置 `distanceHistory` 为当前 `latestFacePosition` 若存在）；
         - 否则：进入 `.idle`（清 `hasActiveFaceSession = false`、`latestFacePosition = nil`、`distanceHistory`、`lookingStartedAt`、`nextLookAroundAt = nil`，**不额外触发 `lookAround`**）。
  7. **`.assistantAction(let action)`**：
     - 任意状态均**不改变 `currentState.kind`**；
     - 立即设置 `pendingAction = .play(action)`、`pendingActionIsAssistant = true`（覆写任何待消费的感知动作，且同帧后续感知动作不得覆写它）。
  8. **`.assistantAudioLevel(let rawLevel)`**：
     - 若 `!rawLevel.isFinite`：忽略（防止 NaN 污染 S-6）。
     - 夹紧 `let clamped = min(max(rawLevel, 0), 1)`：
       - 若 `clamped > 0`：`activeAudioLevel = clamped`；
       - 若 `clamped == 0`：若当前为 `.speaking` 则设 `activeAudioLevel = 0`（说话句间停顿强制闭嘴覆盖预设 `jawOpen`），否则设为 `nil`（如 005 短句播完后归零释放回提示预设表情）。
  9. **`.assistantCue(let cue)`**（EM-1、EM-2、EM-4）：
     - 若当前状态为 `.listening` / `.thinking` / `.speaking`（EM-2）：
       - **不改变 `currentState.kind`**；
       - 覆盖记录 `storedCue = StoredCue(cue: cue, actionPlayed: false)`，同步更新 `currentState.heldCue = cue`。
     - 其他状态（`.idle` / `.attending` / `.reacting`，含感知反应与旧提示，EM-1）：
       - 将原 `.reacting`（若有）快照推入 `fadingLayers`；
       - 清空 `scheduled = []`、`activeReactionKey = nil`、`cooldownBoost = nil`；
       - 计算 `returnTo = Self.underlyingStateKind(of: currentState.kind)`；
       - 构造 `Reaction(expression: cue.emotion, action: cue.action, duration: rules.reactionDuration, returnTo: returnTo, isCue: true, holdsUntilEnded: cue.hold)`；
       - 若 `cue.hold == true`：`storedCue = StoredCue(cue: cue, actionPlayed: true)`；否则 `storedCue = nil`；
       - 进入 `.reacting(reaction)`（`enteredAt: now`，`heldCue: storedCue?.cue`）；
       - 若 `let action = cue.action`：设置 `pendingAction = .play(action)`、`pendingActionIsAssistant = true`。
  10. **`.assistantCueEnded`**（EM-5）：
      - 清空 `storedCue = nil`；
      - 若当前处于 `.reacting(let r)` 且 `r.isCue == true`：
        - 快照当前提示权重推入 `fadingLayers`；
        - 清空 `activeAudioLevel = nil`、`activeReactionKey = nil`；
        - 若 `hasFacePresent(at: now)`：进入 `.attending`（重置 `distanceHistory`、清 `lookingStartedAt`、`nextLookAroundAt`、`pendingNoticeOnAttend = false`）；
        - 否则：进入 `.idle`（清 `hasActiveFaceSession = false`、`latestFacePosition = nil`、`distanceHistory`、`lookingStartedAt`、`nextLookAroundAt = nil`）。
      - 若当前处于 `.listening` / `.thinking` / `.speaking`：仅同步清除 `currentState.heldCue = nil`，**保持当前对话状态不受影响**。
      - 若当前处于 `.idle` / `.attending` / 非提示 `.reacting(isCue: false)`：仅同步清除 `currentState.heldCue = nil`，不改变状态。
  11. **`.assistantCommand` / `.assistantText` / `.userTranscript`**：
      - 任意状态下严格无副作用（完全忽略）。

- **EM-3 / S-7 感知抑制落点（必须逐一检查）**：
  - `handleExpressionTrigger` 入口首行：`if isCueActive { return }`（不排程、不进 `.reacting`、不写 `cooldowns`、不设 `cooldownBoost`）；
  - `handleGestureTrigger` 入口首行：`if isCueActive { return }`（不进 `.reacting`、不发动作、不写 `cooldowns`、不设 `cooldownBoost`）；
  - `processScheduledReactions` 循环内兜底：`if isCueActive { continue }`；
  - `evaluateRapidApproach` 仅在 `case .attending:` 被调用，提示期间天然不触发、不写 `approachCooldownUntil`；
  - 所有感知侧写入 `pendingAction` 处（`enterAttending` 的 `.notice`、`transitionToIdleWithLookAround` / `pose` 的 `.lookAround`、`evaluateRapidApproach` 的 `.leanBack`、`processScheduledReactions` / `handleGestureTrigger` 的动作）均通过私有辅助 `setPerceptionAction(_ action: ActionTag)` 写入：`guard !pendingActionIsAssistant else { return }; pendingAction = .play(action)`。

- **`pose(at:)` 6 步合成增量约定**：
  - **Step 2（`.thinking` 分支，按 3A）**：
    - 当 `currentState.baseEmotion == .neutral`：叠加 `presets[.gentle]` × `0.35`；
    - 当 `currentState.baseEmotion != .neutral`：叠加 `presets[currentState.baseEmotion]` × `0.65`（不再叠加 `gentle`，避免微笑与皱眉抵消；若 `.shy` 同步设 `shyFactor = max(shyFactor, 0.65)`）。
  - **Step 2（`.speaking(emotion)` 分支）**：按 `speakingFactor(elapsed:preset:)` 乘以 `speakPreset.weights`（`blendIn` 200 ms 渐入至 `1.0`），`speakingOverlay` 维持现有 `0.25 * factor <= 0.3` 规则不变。
  - **Step 2（`.reacting(reaction)` 分支）**：改用 `reactionFactor(for:elapsed:preset:)`（`holdsUntilEnded == true` 时渐入后恒定 `1.0`）。
  - **Step 4（口型层，插入 Step 3 淡出层之后、Step 5 待机层之前）**：
    ```swift
    if let level = activeAudioLevel {
        weights["jawOpen"] = level * Self.lipSyncJawOpenScale
        weights["mouthFunnel"] = level * Self.lipSyncMouthFunnelScale
        weights.removeValue(forKey: "mouthClose")
    }
    ```
  - **Step 6（视线与头部朝向）**：
    - `.attending` / `.listening` / `.speaking` / `.reacting`：维持现有朝向 `latestFacePosition`（无位置时回退 `evaluateIdleWander`）；
    - `.thinking`：固定轻微仰视（`gazePitch = Self.thinkingHeadPitchRadians`，`gazeYaw = Self.thinkingHeadYawRadians`，`eyeTarget = Self.thinkingEyeTarget`），经后续 `eyeLook*` 映射自然产出 `eyeLookUpLeft/Right > 0`；
    - `.idle`：维持现有 `evaluateIdleWander(at: evalTime)`。
  - **`resetToIdle(at:)`**：清零 `baseEmotion = .neutral`、`storedCue = nil`、`heldCue = nil`、`activeAudioLevel = nil`、`pendingActionIsAssistant = false`、`hasActiveFaceSession = false`。

#### 5.4 `AvatarScene` 与 `AvatarDebugPanel`（T046 + 2A 悬浮条）

1. **`App/MiniMate/Screens/AvatarScreen.swift`（`AvatarScene` 增量接口）**：
   - 新增只读可观察属性：
     - `private(set) var currentBaseEmotion: EmotionTag = .neutral`
     - `private(set) var currentHeldCue: AvatarCue?`
     - `private(set) var debugAudioLevel: Float = 0`
     - `private(set) var isSimulatingSpeechMouth: Bool = false`
     - `var showConversationOverlay: Bool = false`（仅 2A；默认 `false`）
   - 新增内部状态：
     - `@ObservationIgnored private var feedbackLatencyTracker = FeedbackLatencyTracker()`
     - `@ObservationIgnored private var pendingConversationEvents: [ConversationEvent] = []`
     - `@ObservationIgnored private var conversationEventTask: Task<Void, Never>?`
     - `@ObservationIgnored private var mouthSimulationTask: Task<Void, Never>?`
   - 新增方法：
     - `func injectConversationEvent(_ event: ConversationEvent)`：追加到 `pendingConversationEvents` FIFO 队列并确保单条 `conversationEventTask` 按序消费。消费每条事件时：
       1. 若 `event == .userSpeechEnded`：记录 `let injectedAt = clock.now.timeIntervalSinceReferenceDate` 并调用 `feedbackLatencyTracker.observeUserSpeechEnded(previousState: currentStateKind, at: injectedAt)`；
       2. 若 `event == .userSpeechStarted`：重置 `feedbackLatencyTracker.reset()` 并停止口型模拟；
       3. `await stateMachine.handle(event)`；
       4. 立刻求值 `let evalTime = clock.now.timeIntervalSinceReferenceDate`、`pose = await stateMachine.pose(at: evalTime)`、`state = await stateMachine.state`，同步刷新 `latestPose`、`currentStateKind`、`currentBaseEmotion`、`currentHeldCue`、`latestHeadRotation`、`latestEyeTarget`、以及 `if let cmd = pose.action { pendingStateMachineAction = cmd }`；
       5. 若 `isDebugPanelPresented` 且 `let sample = feedbackLatencyTracker.observeAppliedState(state.kind, at: clock.now.timeIntervalSinceReferenceDate)`：写入 `latencyRecorder.record(sample, metric: "M_feedback")`；
       6. 若 `event == .assistantSpeechEnded` 或 `event == .assistantCueEnded`：自动关闭 `isSimulatingSpeechMouth` 并归零 `debugAudioLevel = 0`。
     - `func injectSpeakingStart(emotion: EmotionTag)`：按序入队 `.assistantSpeechStarted` 与 `.assistantEmotion(emotion)`（严格匹配 Quickstart §5“助手开始说话 + `<emo:gentle>`”）。
     - `func setDebugAudioLevel(_ level: Float)`：停止自动模拟，夹紧 `0...1` 更新 `debugAudioLevel` 并调用 `injectConversationEvent(.assistantAudioLevel(clamped))`。
     - `func setSimulatingSpeechMouth(_ enabled: Bool)`：开启后启动 ~30 Hz（33 ms）`Task`，按复合正弦波形输出 `0.05...0.85` 电平经 `injectConversationEvent(.assistantAudioLevel(...))`；关闭时取消任务并注入 `.assistantAudioLevel(0)`、归零 `debugAudioLevel`。
     - `func resetConversationState()`：取消口型模拟与在途事件队列，调用 `handleBackground()` 或仅将状态机 `resetToIdle` 并清 `feedbackLatencyTracker`（不停止摄像头感知！便于真机立刻重新进入 `Attending` 跑下一轮）。
   - `tick()` 同步增补：在 `renderer.apply(pose)` 之后，若 `!freezeIdle && !isDebugPanelPresented`，检查 `if let feedbackSample = feedbackLatencyTracker.observeAppliedState(currentStateKind, at: now) { latencyRecorder.record(feedbackSample, metric: "M_feedback") }`；`perceptionTask` 与 `tick()` 刷新状态时同步更新 `currentBaseEmotion = state.baseEmotion`、`currentHeldCue = state.heldCue`。
   - `stopPerception()`、`handleBackground()`、`clearMetrics()` 同步取消 `mouthSimulationTask`、清理 `feedbackLatencyTracker.reset()` 并重置相关 UI 状态。
   - **2A 可选主界面悬浮对话条**：在 `AvatarScreen` 底部 overlay 中，仅当 `scene.showConversationOverlay` 为 `true` 时渲染紧凑 `.thinMaterial` 卡片：第一行显示当前 `state` + `baseEmotion` + `heldCue` + 关闭按钮；第二行提供横向可滚动快捷按钮（`开始说`、`说完(M_fb)`、`<user:sad>`、`开讲(gentle)`、`开讲(happy)`、`讲完`、`口型模拟`、`Cue:问好(hold)`、`Cue:茄子(hold)`、`结束Cue`、`重置`）。

2. **`App/MiniMate/Screens/Debug/AvatarDebugPanel.swift`**：
   - `Section("状态与感知")`：增补 `LabeledContent("底色情绪", value: scene.currentBaseEmotion.rawValue)` 与 `LabeledContent("保持提示", value: formatHeldCue(scene.currentHeldCue))`；`stateLabel` 对 `.reacting(r)` 区分 `reacting(cue:emotion[/action], hold)` vs `reacting(cue:emotion[/action])` vs 普通 `reacting(...)`。
   - 新增 `Section("对话事件注入（US5）")`（置于“状态与感知”下方）：
     - 2A Toggle：`主界面悬浮对话调试条`（绑定 `scene.showConversationOverlay`）；
     - 流程主控按钮组：`用户开始说话`、`用户结束说话（记 M_feedback）`、`助手开始说话`、`助手结束说话`、`重置回 Idle`；
     - `<user:…>` 6 按钮网格（点击注入 `.userEmotion(u)`）；
     - `<emo:…>` 选择器 + `注入 <emo>` + `开始说话 + 该情绪` 双按钮；
     - `<act:…>` 8 按钮网格（点击注入 `.assistantAction(a)`）；
     - 口型层控件：`assistantAudioLevel` 滑杆（`0...1`）+ `模拟说话口型（30 Hz）` Toggle；
     - `assistantCue` 构造区：表情 Picker、动作 Picker（含“无”）、`hold` Toggle、`发送 assistantCue`、`发送 assistantCueEnded`、以及 005 预设快捷按钮（`问好 playful/lookAround/hold`、`茄子 happy/heart/hold`、`庆祝 happy/spin/单次`）；
     - `指令忽略验证` 按钮：点击发送 `.assistantCommand(.photo)` 验证状态不变。
   - `Section("指标（M_track / M_reflex / M_feedback）")`：新增 `M_feedback 样本数`、`M_feedback p50`、`M_feedback p90`；导出 CSV 与清空按钮条件改为 `trackCount > 0 || reflexCount > 0 || feedbackCount > 0`。

---

### 6. 原子化施工步骤（自底向上，严格 TDD）

- **Step 1：`MMCore` 共享类型测试先行 → 实现（T045 基础层）**
  - 改动文件：`Packages/MiniMateKit/Tests/MMCoreTests/MMCoreTests.swift`（先写测试确认编译失败），再新增 `Packages/MiniMateKit/Sources/MMCore/AssistantCommand.swift`、`AvatarCue.swift`、`PlaybackResult.swift` 并修改 `ConversationEvent.swift`。
  - 改动要点：严格按第 5.1 节精确签名实现，确保 rawValue 与 `002`/`005` data-model 逐字一致。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter "MMCoreTests"
    ```

- **Step 2：`MMEmotion` 状态模型扩容与测试先行（T044 & T044a 红灯基线）**
  - 改动文件：`Packages/MiniMateKit/Sources/MMEmotion/AvatarState.swift`（增补 `isCue`、`holdsUntilEnded`、`heldCue` 默认参数）、`Packages/MiniMateKit/Sources/MMEmotion/FeedbackLatencyTracker.swift`（先搭骨架或完整实现）、`Packages/MiniMateKit/Tests/MMEmotionTests/ConversationTransitionTests.swift`（新增，T044）、`Packages/MiniMateKit/Tests/MMEmotionTests/AvatarCueTests.swift`（新增，T044a）。
  - 改动要点：按第 7.1 节测试矩阵写全所有确定性断言（使用可变 `ManualClock`），先运行确认测试失败（TDD 红灯），且既有 `AttentionTransitionTests` / `ExpressionReactionTests` / `GestureReactionTests` / `NoMirroringTests` 零编译错误。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter "ConversationTransitionTests|AvatarCueTests"
    ```

- **Step 3：实现 `RuleBasedEmotionStateMachine` 对话状态、`assistantCue`、口型层与 `ReflexLatencyTracker` 防污染（T045 核心实现）**
  - 改动文件：`Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift`（修改）、`Packages/MiniMateKit/Sources/MMEmotion/ReflexLatencyTracker.swift`（微调 `!reaction.isCue`）、`Packages/MiniMateKit/Sources/MMEmotion/FeedbackLatencyTracker.swift`（完善实现）。
  - 改动要点：严格按第 5.2–5.3 节逐条实现全部 13 个 `ConversationEvent` case、EM-1–EM-5、Step 2 Thinking/Speaking、Step 4 口型覆盖、Step 6 Thinking 仰视、S-4/S-5/S-6/S-7/S-8 不变式与 `resetToIdle` 清理。
  - 最小验证命令（确认新增 + 全部既有 118 单测 100% 绿灯）：
    ```bash
    cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox
    ```

- **Step 4：接入 `AvatarScene` / `AvatarScreen` 与 `AvatarDebugPanel` 对话注入及 `M_feedback`（T046）**
  - 改动文件：`App/MiniMate/Screens/AvatarScreen.swift`（修改）、`App/MiniMate/Screens/Debug/AvatarDebugPanel.swift`（修改）。
  - 改动要点：按第 5.4 节接入串行 FIFO `injectConversationEvent`、`FeedbackLatencyTracker` → `"M_feedback"`、口型滑杆与 30 Hz 模拟开关、`assistantCue`/`assistantCueEnded` 注入区、2A 可选主界面悬浮对话条与指标导出可见性修复。
  - 最小验证命令（iOS Simulator 完整 App 无签名编译验证）：
    ```bash
    xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
    ```

---

### 7. 确定性测试矩阵与验收门禁

#### 7.1 测试矩阵（严禁非确定性断言）

| 目标测试文件 | 覆盖类别 | 测试场景 | 必须写死的断言底线（禁止弱断言） |
| :--- | :--- | :--- | :--- |
| `Packages/MiniMateKit/Tests/MMCoreTests/MMCoreTests.swift` | 正例 | `AssistantCommand`、`AvatarCue`、`PlaybackResult`、`ConversationEvent` 新 case | 精确断言 rawValue（`"photo"` / `"photoReady"` / `"photoCancel"`）、JSON 编解码往返相等、`AvatarCue` 默认值（`action == nil`、`hold == false`）及新 case `Equatable` 区分不同载荷 |
| `Packages/MiniMateKit/Tests/MMEmotionTests/ConversationTransitionTests.swift` | 正例 | 全流程主干：`Idle` / `Attending` → `userSpeechStarted` → `Listening` → `userSpeechEnded` → `Thinking` → `userEmotion` → `assistantSpeechStarted` → `Speaking` → `assistantEmotion` → `assistantSpeechEnded` → `Attending`/`Idle` | 逐状态精确断言 `state.kind` 与 `state.baseEmotion`；断言 S-4：`userSpeechEnded` 后 `0 ms`（`< 100 ms`）内 `state.kind == .thinking`；有人脸返回 `.attending`，无人脸及离屏 ≥ 3 s 返回 `.idle`（且不意外触发 `lookAround`） |
| 同上 | 正例 | `userEmotion` 全 6 值映射与 `Thinking` 姿态/微仰视视线 | 断言 6 个 `UserEmotion` 精确映射（`happy→.happy`、`calm→.neutral`、`sad/tired/anxious/angry→.concerned`）；`baseEmotion == .neutral` 时 `mouthSmileLeft == 0.5 * 0.35`；`<user:sad>` 后 `mouthFrownLeft >= 0.75 * 0.65 - 1e-4` 且 `mouthSmileLeft == 0`；断言 `headRotation.x < 0`、`eyeTarget.y > 0`、`eyeLookUpLeft > 0`、`eyeLookUpRight > 0` |
| 同上 | 边界 | `Listening` 直接收 `assistantSpeechStarted`；非 `Speaking` 收 `assistantEmotion`；`Speaking` 切换不同情绪过渡 | `Listening` → `assistantSpeechStarted` 进入 `.speaking(baseEmotion)`；`Idle`/`Attending`/`Thinking` 收 `assistantEmotion(.happy)` 保持原 `state.kind`；`.speaking(.happy)` 切 `.speaking(.sad)` 在 `t+0.1 s` 同时存在淡出的 `mouthSmileLeft > 0` 与淡入的 `mouthFrownLeft > 0` |
| 同上 | 正例/边界 | 打断（`Listening`/`Thinking`/`Speaking` 收 `userSpeechStarted`）与 003 E-2 乱序保护 | 3 种状态收 `userSpeechStarted` 均切 `.listening` 且 `state.scheduled.isEmpty`；排程中微笑到期后不再触发 `.reacting`；`Speaking` → `userSpeechStarted` → 迟到旧轮 `assistantSpeechEnded` 仍严格保持 `.listening` |
| 同上 | 正例/边界 | `assistantAction` 高优先级动作与 `Speaking` S-5 保护 | 在 `Idle`/`Attending`/`Thinking`/`Speaking`/`Reacting` 收 `assistantAction(.spin)` 均不改变 `state.kind` 且 `pose.action == .play(.spin)`；同帧后续感知手势动作不覆盖 `assistantAction`；`Speaking(.gentle)` 期间微笑/挥手/快速靠近均保持 `.speaking(.gentle)`、`pose.action == nil`、叠加权重 `<= 0.30` |
| 同上 | 正例/边界 | Step 4 口型层覆盖与释放（`assistantAudioLevel`）及异常输入 | 在 `.speaking(.surprised)`（预设 `jawOpen == 0.65`）下：① 收到 `0.5` 时 `jawOpen == 0.40`（`±1e-4`）、`mouthFunnel == 0.175`（证明严格覆盖而非 `max`），同时 `eyeWideLeft == 0.90` 保留；② 收到 `0.0` 时 `jawOpen == 0`、`mouthFunnel == 0`；③ 收到 `1.5`/`-0.2`/`.nan` 全部权重满足 S-6 `∈ [0, 1]` 无 NaN；④ `assistantSpeechEnded` 后释放覆盖 |
| 同上 | 正例/异常反例 | `FeedbackLatencyTracker` | Listening 态武装后 12 ms 观测到 `.thinking` 精确返回 `0.012`（`< 1e-6`）；非 Listening 态武装返回 `nil`；超时（`>= 3.0 s`）或负时间返回 `nil` 并自动清零；`reset()` 清理状态 |
| `Packages/MiniMateKit/Tests/MMEmotionTests/AvatarCueTests.swift` | 正例（EM-1/EM-4） | 非对话态收到 `assistantCue`（`hold: true` 与 `hold: false`）与提示替换 | `Idle`/`Attending`/感知 `.reacting` 收到 `cue(playful, .lookAround, hold: true)` 立刻进入 `.reacting(isCue: true, holdsUntilEnded: true)`、`pose.action == .play(.lookAround)`、`state.heldCue == cue`、`scheduled.isEmpty`；10 s 后仍保持 `.reacting` 且满强度 `1.0`；新 `cue(happy, .heart, hold: false)` 立即替换旧提示、`heldCue == nil`、1.5 s 后回到原状态 |
| 同上 | 正例（EM-2/S-8） | 对话态收到 `assistantCue`、多轮恢复且动作不重复、`assistantCueEnded` 取消 | `Listening`/`Thinking`/`Speaking` 收到 `cue(happy, .nod, hold: true)` 不改变 `state.kind` 但 `state.heldCue == cue`；`assistantSpeechEnded` 后进入 `.reacting(cue)` 且首进播放 `.nod`；再走一轮 `userSpeechStarted → ... → assistantSpeechEnded` 仍回到 `.reacting(cue)` 且 `pose.action == nil`（不重复播动作）；若 `Speaking` 中收到 `assistantCueEnded`，`Speaking` 不被打断且 `assistantSpeechEnded` 回到 `Attending` |
| 同上 | 边界/反例（EM-3/S-7） | 提示期间全部感知反应被抑制且不写入冷却；005 CV-2 口型联动 | 提示期间分别注入微笑（等待 1 s）、挥手/比心/点赞、快速靠近（1 s 缩短 20 cm）：全程 `state.kind` 不变、`state.cooldowns.isEmpty`、`state.scheduled.isEmpty`、`pose.action == nil`；`assistantCueEnded` 后立刻微笑/挥手能正常进入感知反应；提示期间注入 `assistantAudioLevel(0.5)` 精确驱动 `jawOpen == 0.40`/`mouthFunnel == 0.175`，注入 `0.0` 后恢复提示预设 `jawOpen` |
| 同上 | 正例/边界（EM-5） | `assistantCueEnded` 在有人脸 / 无人脸 / 离屏 ≥ 3 s / 非提示态 | `Reacting(cue)` 有人脸回 `.attending`、无人脸或离屏 ≥ 3 s 回 `.idle`、且 `state.heldCue == nil`、旧提示权重平滑淡出；普通感知 `.reacting(isCue: false)` 收到 `assistantCueEnded` 不被打断 |
| 同上 | 兼容回归 | `assistantCommand` 忽略 & `ReflexLatencyTracker` 隔离 | 全部 3 个 `AssistantCommand` 在任意状态不改变 `state` 与 `pose.action`；微笑武装 `ReflexLatencyTracker` 后进入无动作 `assistantCue(.happy, action: nil, hold: true)` 时 `observeAppliedState` 严格返回 `nil` |

#### 7.2 完整门禁命令清单

```bash
# 1. 目标单测（MMCore + US5 新增对话状态与形象提示套件）
cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter "MMCoreTests|ConversationTransitionTests|AvatarCueTests"

# 2. 全量 macOS 纯逻辑单测（既有 118 用例 + 本轮新增用例 100% 通过）
cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox

# 3. 包内 MMEmotion iOS 目标编译检查（Swift 6 严格并发零警告/零报错）
cd Packages/MiniMateKit && xcodebuild -scheme MMEmotion -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

# 4. App 模拟器完整编译验证（无签名，覆盖 AvatarScreen / AvatarDebugPanel）
xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# 5. 仓库状态与只读基线检查（确认未触碰 tasks.md / research.md / 资产 / Package.swift）
git status
```

> **后续人工真机验收（T047，不在本轮代码自动勾选范围内，待本轮代码经独立复审并由用户确认后在真机执行）**：
> 在 iPhone 16 Pro Max 上按 `specs/002-m1-presence/quickstart.md` 第五节实测：
> 1. 依次注入 `用户开始说话 → 用户结束说话 → <user:sad> → 助手开始说话 + <emo:gentle> → 助手结束说话`，核对状态依次为 `Listening → Thinking → Thinking(concerned)`（视线微上移 + 关切神情）`→ Speaking(gentle) → Attending`，查看 `M_feedback` p50/p90（目标 < 100 ms）；
> 2. 在 `Speaking(gentle)` 开启“模拟说话口型”观察嘴部自然张合，同时对小瓜微笑确认说话表情不被打断（S-5）；
> 3. 测试 005 预设 `assistantCue`（`playful + lookAround + hold` 持续保持、期间微笑/挥手不打断、`assistantCueEnded` 平滑回到 `Attending`）。
> T047 通过后可同机紧接执行 Phase 8（T048 10 分钟稳定性压测 SC-006 + T049 主观验收 SC-007 + T050 结论回写），完成整个 M1 里程碑关单。

---

### 8. 实施方偏差止损规则（固定条款）

- **可自决微调**：内部私有变量名、局部辅助函数拆分、注释与格式调整（不改变对外契约与测试预期）。
- **必须立即停工上报（严禁擅自绕过）**：
  1. 发现既定签名/契约与仓库现状冲突；
  2. 需要修改文件改动表之外的文件；
  3. 需要改写既有测试的预期断言；
  4. 需要放宽安全、只读或隔离红线；
  5. 实测发现新的第三方库或环境阻断问题。

---

## 复审闭环记录（实施后由 task-review-loop 追加）

- **闭环结论**：一致通过（共 **2 轮**独立只读复审，Round 2 阻断项 = 0、非阻断建议 = 0）
- **审查通道与模型**：单节点 `reviewer`（模型：`gemini-4-neon-high` / Gemini 4 Neon，思考等级：`High`；每轮前后均通过 `git status` + `git diff` hash + 新增文件 SHA-256 核验字节级零修改；闭环结束后已回收）
- **Round 1（需修改 → 发现 4 项阻断项 + 2 项非阻断建议，已全部根因修复）**：
  1. **阻断项 1**：`RuleBasedEmotionStateMachine.swift` 对话态叠加感知 `.reacting` 期间收到 `assistantCue` 未走 EM-2 暂存导致后续对话事件被吞 → 修复为 `!isCueActive && Self.isConversationState(Self.underlyingStateKind(of: currentState.kind))`，并在 `AvatarCueTests.swift` 补齐回归测试 `cueDuringPerceptionReactionInConversationDefersWithoutBlockingTurn`；
  2. **阻断项 2**：非持久提示（`hold: false`）自然到期与 `transitionToIdleWithLookAround` 未清空 `activeAudioLevel` → 在 `checkReactingExpiration`（`if reaction.isCue`）与 `transitionToIdleWithLookAround` 同步清空，并在 `AvatarCueTests.swift` 补齐回归测试 `nonHoldCueExpirationClearsActiveAudioLevel`；
  3. **阻断项 3**：`AvatarScreen.swift` 30 Hz 口型模拟任务与结束/打断事件存在异步排队竞态 → 在 `injectConversationEvent` 入队同步点对 `.userSpeechStarted`/`.assistantSpeechEnded`/`.assistantCueEnded` 立即停止口型模拟并清除队列中未消费的 `.assistantAudioLevel`；
  4. **阻断项 4**：`AvatarScreen.swift` `resetConversationState()` fire-and-forget Task 竞态与 `conversationEventTask = nil` 句柄覆写 → 统一收敛为 `ConversationQueueItem`（`.event`/`.reset`）单一 FIFO 队列 + `conversationQueueGeneration` 单调代数校验；
  5. **非阻断建议 1 & 2**：清理 `RuleBasedEmotionStateMachine.swift:170` 旧注释；收紧 `ConversationTransitionTests.swift` S-4 时间戳断言并补充 `Reacting`/`Thinking` 态 `assistantAction` 用例。
- **Round 2（通过）**：逐项复核 4 项阻断项均根治且无新回归，独立复跑全量单测 **138/138 across 23 suites** 全部通过。
- **最终验收门禁实测结果**：
  - 全量 macOS 纯逻辑单测（`swift test`）：**138/138** across **23 suites** 全部通过（`MMCoreTests` 14/2、`MMSecurityTests` 7/1、`MMDiagnosticsTests` 14/3、`MMPerceptionTests` 32/5、`MMEmotionTests` 71/12）；
  - `MMEmotion` generic iOS 编译（`xcodebuild -scheme MMEmotion -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`）：**BUILD SUCCEEDED**；
  - `MiniMate` iOS Simulator 编译（`xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`）：**BUILD SUCCEEDED**；
  - 收口合规：未勾选 `tasks.md`，未修改 `research.md` / `Package.swift` / `project.pbxproj`，未 `git commit` / `git push`。
