# 002-m1-presence US3（T030–T037）“用自己的方式回应表情”实现级执行单

- **状态**：已拍板定稿（待实施）
- **Git 基线**：`main` @ `133f1dd`（工作区干净；上游 M0 全部完成、M1 US1 + Phase 1.4 形象精修 + US2 T020–T029 均已合入 `main`）
- **关键基线**：Swift `6.4`（`swift-tools-version: 6.2`，Swift 6 严格并发）、Xcode `27.0`（`27A266a`）、iOS `26+` / macOS `26+`、Swift Testing（当前全量单测 `76/76` 全绿）、零第三方运行时依赖；素材 `App/MiniMate/Resources/Avatar/minimate.usdz` + `minimate.actions.json`（52/52 ARKit 形态键、8/8 动作、Phase 1.4 精修已验收）
- **拍板决议摘要**：用户于 2026-11-25 指示按本执行单施工，所有待决项均采用推荐方案：**1A**（仅 T030–T037 代码与测试闭环，不含 T038 人工真机验收）、**2A**（冷却期短时柔和底色增强）、**3A**（排除 `eyeLook*` 后以 `maxAbsCorrelation < 0.3` 判定 SC-004）

> **红线声明**
> - 严格遵守 `.specify/memory/constitution.md`（最高优先级）与 `AGENTS.md`：
>   1. **陪伴而非镜像（NON-NEGOTIABLE）**：`PerceptionFeatures.rawBlendShapes` **严禁**进入 `AvatarPose.expressionWeights` 或渲染器；状态机只消费语义信号 `FaceSignals`，只输出形象自己的 `ExpressionPreset` 权重（唯一允许跟随用户数据的通道是人脸位置驱动的视线与头部朝向）；
>   2. **感知在本地**：无网络访问、不显示也不保存摄像头画面；
>   3. **纯逻辑测试先行（TDD）**：`MMCore`、`MMPerception`、`MMEmotion` 纯逻辑模块必须先写测试、确认失败再实现；
>   4. **零新增第三方依赖**：全链路仅用系统框架与 Swift 标准库；
>   5. **隐私与密钥**：不写入任何 API Key，不提交 `Assets/voice-samples/*.wav`。
> - 设计阶段仅创建/维护本执行单，严禁改动任何业务代码、测试、配置、历史产物或 `tasks.md`。
> - 收口策略：未经用户明确确认验收，不得勾选 `specs/002-m1-presence/tasks.md`，不得修改 `research.md` 实测结论，不得 `git commit`，不得 `git push`。

---

## 上篇：面向用户决策

### 1. 任务目标与选择理由

- **本次任务**：`002-m1-presence` Phase 5 — **US3“用自己的方式回应表情”（T030–T037 代码与测试闭环）**。交付用户面部语义信号推导（`FaceSignalDeriver`，含 D5 公式、One Euro 平滑、阈值滞回、最短持续时间）并接入 `ARKitPerceptionSource`；补齐 8 个 `EmotionTag` 的初始 `expression-presets.json` 与加载/导出能力；升级 `RuleBasedEmotionStateMachine` 支持感知表情反应映射（微笑→`happy`、皱眉→`concerned`、惊讶→`surprised`）、300–800 ms 随机延迟计划队列、8 s 同类冷却与柔和底色增强、姿态合成第 2/3 步（`blendIn`/`blendOut` 平滑插值 + `.shy` 轻微低头）；实现 `RecordingAvatarRenderer`、`MirrorCorrelationEvaluator`（SC-004 相关系数检测）与 `ReflexLatencyTracker`（`M_reflex` 记录）；并在 `AvatarScreen` 与 `AvatarDebugPanel` 接入 30 s 镜像检测、`M_reflex` 指标与表情预设预览/导出。完成后即可直接在真机执行 Quickstart §3（T038）验收 `SC-003`、`SC-004` 并调参。
- **为何优先做它（未完成候选项横向对比）**：
  1. **首选 · `002-m1-presence` Phase 5 / US3（P1，T030–T037）**：
     - 上游 M0（001）与 M1 US1/US2（含 Phase 1.4 精修）100% 就绪，零外部阻塞（无需云端 Key 或个人语音录音）；
     - 直接落地宪章第一原则“陪伴而非镜像（NON-NEGOTIABLE）”，真机立刻可体验“我笑小瓜用自己的方式笑、我皱眉小瓜关切、我惊讶小瓜惊讶”；
     - 其产出的 `expression-presets.json`（8 情绪预设）、反应冷却队列与 `blendIn`/`blendOut` 姿态合成是后续 **US4（手势反应需 `happy`/`shy`）**、**US5（对话状态需 `gentle`/`concerned`/`Speaking(e)`）** 与 **M2** 的共同前置依赖。
  2. **次选 · `002-m1-presence` Phase 6 / US4（P2，手势回应 T039–T043）**：优先级为 P2，且手势映射（`wave`→`happy`+`wave`、`heart`→`shy`+`heart`、`thumbsUp`→`happy`+`nod`）依赖 US3 的 `expression-presets.json` 与状态机冷却/反应基础设施，应排在 US3 之后。
  3. **次选 · `002-m1-presence` Phase 7 / US5（P3，对话阶段状态 T044–T047）**：虽在依赖上可与 US3 并行，但同样依赖 US3 的 8 预设与 `blendIn`/`blendOut` 合成；将其拆到 US3 之后可避免单次执行单过度膨胀、让 US3 聚焦手感与 D5 阈值。
  4. **暂缓 · `003-m2-voice-conversation` Phase 1–3（M2a 厂商验证）**：需要人工核查云端厂商最新实时 API 文档、配置有效云端 Key 并自录 9 条个人语气样本（`Assets/voice-samples/*.wav`），适合在 M1 形象与本地互动闭环（或至少 P1 US3）稳定后推进。
- **摸底关键发现（3 个最值得知情的技术事实/风险）**：
  1. **`expression-presets.json` 目前为空数组 `[]` 且 `ARKitPerceptionSource` 尚未推导 `signals`**：`Packages/MiniMateKit/Sources/MMEmotion/Resources/expression-presets.json` 当前仅含 `[]`，`ExpressionPreset.swift` 尚无 `Bundle.module` 加载接口；`ARKitPerceptionSource.swift:214` 仍硬编码 `signals: FaceSignals()`。本轮必须两处同步补齐，否则即使状态机单测全绿，真机也不会对表情做任何反应。
  2. **模块依赖单向边界（`MMEmotion` 不可依赖 `MMAvatar`）**：`Package.swift:24-25` 中 `MMAvatar` 依赖 `MMEmotion`，因此纯逻辑的 `MirrorCorrelationEvaluator` 与 `ReflexLatencyTracker` 必须落在 `MMEmotion`（不引用 `MMAvatar.BlendShapeIndex`），仅在 `MMAvatar` 放 `RecordingAvatarRenderer`；同时 `MMEmotion` 已声明 `resources: [.process("Resources")]`，按 SwiftPM 打包规则 `Bundle.module.url(forResource: "expression-presets", withExtension: "json")` **不能**传 `subdirectory: "Resources"`。
  3. **SC-004 相关系数的两处数学陷阱**：① 宪章 I / FR-014 豁免视线跟随，8 个 `eyeLook*` 形态键由人脸位置驱动，不能计入镜像违规判定；② 30 s 自由表情中，形象不会触发 `cheekPuff`/`mouthPucker` 等未映射系数，标准差为 0，直接算 Pearson `r` 会除零产生 `NaN`，必须显式定义零方差通道相关系数为 `0.0`。

### 2. 已拍板决策摘要（1A / 2A / 3A）

1. **任务范围粒度 — 1A**：聚焦 **M1 US3 代码与测试闭环（T030–T037，不含人工真机验收 T038）**，暂不合并 US5。
2. **冷却期内收到同类表情刺激时的视觉策略 — 2A**：采用**短时柔和底色增强（`cooldownBoost`，不永久改写 `state.baseEmotion`）**——冷却期内绝不进入 `.reacting`、不重复播动作（严守 S-2）；若当前 `baseEmotion != .neutral` 则将底色强度由 `0.3` 临时微提至 `0.45`，若 `baseEmotion == .neutral` 则以低强度（`0.25`）叠加对应情绪预设并经 `blendIn`/`blendOut` 在 `1.5 s` 后自然回落。
3. **SC-004 镜像检测（30 s 相关系数）统计口径与真机交互 — 3A**：按宪章 I / FR-014 排除 8 个 `eyeLook*` 视线通道，对其余 44 个表情形态键逐通道计算 Pearson `r`（零方差通道记 `0.0`），以最严格的 **`maxAbsCorrelation < 0.3`** 作为通过判定（同时展示 `meanAbsCorrelation` 与 Top 3 最高相关通道明细）；在 `AvatarScreen` 显示倒计时悬浮胶囊，允许用户在主界面边看小瓜边做 30 s 自由表情后自动生成可导出报告。

---

## 下篇：面向实施方的零歧义施工图

> 本施工图已按拍板决议 **1A / 2A / 3A** 锁定，无条件分支。

### 3. 现状锚点与环境陷阱预警

#### 3.1 现有代码锚点

| 模块/符号 | 精确位置 | 职责与复用/约束说明 |
| :--- | :--- | :--- |
| `Package.swift` targets | `Packages/MiniMateKit/Package.swift:19-31` | `MMPerception` 依赖 `MMCore`；`MMEmotion` 依赖 `MMCore`、`MMPerception` 且已声明 `resources: [.process("Resources")]`；`MMAvatar` 依赖 `MMCore`、`MMEmotion`；`MMEmotionTests` 已依赖 `MMEmotion`、`MMAvatar`、`MMCore`、`MMPerception`。**本轮无需修改 `Package.swift` 或 `project.pbxproj`** |
| `LatencyRecorder` | `Packages/MiniMateKit/Sources/MMCore/Metrics/LatencyRecorder.swift:4-62` | 已有 `record(_:metric:)`、`count(for:)`、`p50(for:)`、`p90(for:)`、`csv()`；既有 `LatencyRecorderTests.swift` 8 个用例须 100% 保持兼容，本轮仅做纯增量方法 `samples(for:)` 与 `hitRate(in:for:)` |
| `EmotionTag` | `Packages/MiniMateKit/Sources/MMCore/EmotionTag.swift:2-11` | 8 个情绪：`happy`、`gentle`、`sad`、`surprised`、`shy`、`playful`、`concerned`、`neutral`（`CaseIterable`） |
| `PerceptionFeatures` / `FaceSignals` / `UserExpression` | `Packages/MiniMateKit/Sources/MMPerception/PerceptionFeatures.swift:4-60` | 已定义 `FaceSignals(smile:frown:surprise:activeExpression:)` 与 `UserExpression`（`smiling`/`frowning`/`surprised`），直接复用，勿改字段名与 Codable 结构 |
| `OneEuroFilter` | `Packages/MiniMateKit/Sources/MMPerception/OneEuroFilter.swift:5-66` | 已有单通道 1€ 滤波器（含非法参数夹紧、非有限值防御与 `reset()`），`FaceSignalDeriver` **必须复用**，禁止重写滤波公式 |
| `LookingAtScreenDetector` | `Packages/MiniMateKit/Sources/MMPerception/LookingAtScreenDetector.swift:38-68` | 可参考其 `+ 1e-9` 浮点持续时间边界与时间回退保护写法 |
| `ARKitPerceptionSource` | `Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift:14-259` | 当前第 214 行硬编码 `signals: FaceSignals()`；须在 `MutableState` 持有 `signalDeriver: FaceSignalDeriver`，在 tracked 帧调用 `update`，在 `start`/`stop`/人脸丢失/中断/恢复中调用 `reset()` |
| `ScriptedPerceptionSource` | `Packages/MiniMateKit/Sources/MMPerception/ScriptedPerceptionSource.swift:11-212` | 已有 JSONL 编解码与回放，T032 测试可直接用于回放合成/录制序列 |
| `ExpressionPreset` | `Packages/MiniMateKit/Sources/MMEmotion/ExpressionPreset.swift:12-59` | 已实现 `Codable, Sendable, Equatable`，JSON 键为 `emotion`、`weights`、`blendInMs`、`blendOutMs`；本轮仅扩展加载/校验/导出静态方法，不破坏现有 `init` 与 `Codable` 格式 |
| `expression-presets.json` | `Packages/MiniMateKit/Sources/MMEmotion/Resources/expression-presets.json:1` | 当前为 `[]`，本轮写入 8 个 `EmotionTag` 完整初值（全部对称键拆分为 ARKit `Left`/`Right`） |
| `AvatarState` / `Reaction` / `ScheduledReaction` | `Packages/MiniMateKit/Sources/MMEmotion/AvatarState.swift:5-72` | 已定义 `cooldowns: [ReactionKey: TimeInterval]` 与 `scheduled: [ScheduledReaction]`，直接复用，勿改公开字段签名 |
| `ReactionKey` / `ReactionRules` | `Packages/MiniMateKit/Sources/MMEmotion/ReactionRules.swift:4-47` | 已定义 `reactionDelay = 0.3...0.8`、`reactionDuration = .milliseconds(1500)`、`cooldown = 8`、`approachDistance = 0.10` 等，直接复用 |
| `RuleBasedEmotionStateMachine` | `Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift:7-440` | 已实现 US2 全部注意力转换与视线/待机合成；既有 `AttentionTransitionTests.swift` 9 个用例必须零修改全部通过 |
| `TrackLatencyTracker` | `Packages/MiniMateKit/Sources/MMEmotion/TrackLatencyTracker.swift:5-94` | `M_track` 纯逻辑跟踪器范式，新增 `ReflexLatencyTracker` 沿用其风格与容错约定 |
| `AvatarRenderer` / `BlendShapeIndex` | `Packages/MiniMateKit/Sources/MMAvatar/AvatarRenderer.swift:4-23`, `BlendShapeIndex.swift:5-54` | `@MainActor public protocol AvatarRenderer` 与规范 52 个 `arkitNames` 列表；`RecordingAvatarRenderer` 须严格遵循该协议 |
| `RealityKitAvatarRenderer` | `Packages/MiniMateKit/Sources/MMAvatar/RealityKitAvatarRenderer.swift:140-168` | 已支持稀疏 `expressionWeights` 自动归零与 `[0, 1]` 夹紧；**本轮严禁修改** |
| `AppComposition` | `App/MiniMate/AppComposition.swift:10-33` | 组合根；`makeEmotionStateMachine()` 需显式注入 `ExpressionPreset.bundledDefaults`（或由状态机默认加载） |
| `AvatarScene` / `AvatarScreen` | `App/MiniMate/Screens/AvatarScreen.swift:13-624` | 持有 `perceptionTask`、`tick()`、`latencyRecorder`、`trackLatencyTracker`、`-freezeIdle`/`-blendName` 调试参数与 `shyEyeBlend` 逻辑；本轮增量接入 `latestFaceSignals`、`ReflexLatencyTracker`、30 s 镜像检测与预设加载，原有调试能力零破坏 |
| `AvatarDebugPanel` | `App/MiniMate/Screens/Debug/AvatarDebugPanel.swift:7-185` | 已有“状态与感知”“录制感知”“指标（M_track）”“动作”“表情系数（52）”“全部归零”；本轮扩展语义信号显示、镜像检测、`M_reflex` 指标与表情预设调参/导出 |

#### 3.2 环境与平台实测陷阱预警

1. **陷阱 1 · SwiftPM `.process("Resources")` 扁平化路径（`Bundle.module` 必踩）**：
   - 表现：`Package.swift:24` 使用 `resources: [.process("Resources")]`，SwiftPM 会把 `expression-presets.json` 直接拷贝到 `MiniMateKit_MMEmotion.bundle` 根目录；若调用 `Bundle.module.url(forResource: "expression-presets", withExtension: "json", subdirectory: "Resources")` 将返回 `nil`！
   - **必须采用的写法**：`Bundle.module.url(forResource: "expression-presets", withExtension: "json")`（不传 `subdirectory`）。
2. **陷阱 2 · `ARKitPerceptionSource` 漏接 `FaceSignalDeriver`**：
   - 表现：目前 `ARKitPerceptionSource.swift:214` 写死 `signals: FaceSignals()`。若仅写完 `FaceSignalDeriver.swift` 而漏改 `ARKitPerceptionSource`，macOS 单测全绿，但真机永远无法触发微笑/皱眉/惊讶反应。
   - **必须采用的写法**：在 `ARKitPerceptionSource.MutableState` 持有 `signalDeriver: FaceSignalDeriver`，在 tracked 分支调用 `s.signalDeriver.update(blendShapes: face.blendShapes, at: timestamp)` 填入 `signals`，并在 `start()`、`stop()`、人脸丢失分支、`handleSessionWasInterrupted`、`handleSessionInterruptionEnded` 全部调用 `s.signalDeriver.reset()`。
3. **陷阱 3 · `MMEmotion` 禁止反向依赖 `MMAvatar`**：
   - 表现：`Package.swift:25` 中 `MMAvatar` 依赖 `MMEmotion`，若在 `MMEmotion` 中 `import MMAvatar`（只为了拿 `BlendShapeIndex.arkitNames`）会造成循环依赖编译失败。
   - **必须采用的写法**：`MirrorCorrelationEvaluator` 位于 `MMEmotion`，仅维护 8 个 `eyeLook*` 排除集合常量，默认统计输入帧里出现过的所有非视线键（也支持调用方传入显式 `channels` 列表）；`ExpressionPreset` 测试在 `MMEmotionTests` 中（已同时依赖 `MMEmotion` 与 `MMAvatar`）可用 `BlendShapeIndex.arkitNames` 校验 JSON 全部键名合法。
4. **陷阱 4 · Pearson 相关系数零方差除零导致 `NaN`**：
   - 表现：30 s 自由表情里，用户动了 `cheekPuff`/`mouthPucker` 但形象全程保持 `0`，导致 `varY == 0`，直接做 `cov / sqrt(varX * varY)` 产生 `NaN`，Swift 中 `NaN < 0.3` 为 `false` 会导致合法非镜像输出误判失败。
   - **必须采用的写法**：全程使用 `Double` 精度计算均值/协方差/方差；当 `sampleCount < 2` 或 `varX < 1e-12` 或 `varY < 1e-12` 时直接记 `r = 0.0`，最终结果夹紧到 `[-1.0, 1.0]`。
5. **陷阱 5 · 连续 60 Hz `activeExpression` 重复排程 & 嵌套 `.reacting` 死循环**：
   - 表现：① 用户持续微笑 1.5 s 期间，连续 90 帧 `signals.activeExpression` 都是 `.smiling`，若不做边沿检测（`previousActiveExpression != current`）会在 `scheduled` 中塞满重复任务或在反应刚结束时立刻再次触发；② 若在 `.reacting(A)` 尚未结束时另一反应 `B` 切入并直接写 `returnTo: currentState.kind`，会造成 `.reacting(B, returnTo: .reacting(A))` 嵌套且永远回不到 `.attending`。
   - **必须采用的写法**：① 仅在 `activeExpression` 从 `nil` 或其他值**首次切入**新表情时触发调度/冷却增强（并在 `resetToIdle` 与人脸丢失回 Idle 时重置 `previousActiveExpression = nil`）；② 当 `scheduled` 中已存在同 `key` 的待办、或当前正在执行同 `key` 反应时不重复排程；③ 切入 `.reacting` 时始终把 `returnTo` 扁平化为底层非 `.reacting` 状态（若当前为 `.reacting(prev)` 则继承 `prev.returnTo`）；④ 若当前 `.reacting` 携带动作（如 `leanBack`），到期到达的纯表情计划反应直接丢弃，不打断动作。
6. **陷阱 6 · 沙盒内运行 `swift test` 的 Clang Module Cache 路径**：
   - 实测在受限沙盒下直接运行 `swift test` 会因 `/var/folders/.../C/clang/ModuleCache` 无写权限报 manifest 编译失败；在本机开发终端直接运行 `cd Packages/MiniMateKit && swift test` 正常，在沙盒内需带 `CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox`（不修改任何仓库文件）。
7. **陷阱 7 · `Swift.Clock` 命名冲突（延续 US2）**：
   - Swift 6.4 下所有引用 `MMCore` 时钟协议的签名均须显式写 `any MMCore.Clock`。

---

### 4. 改动范围表与明确不做清单（Non-Goals）

#### 4.1 文件改动表

| 文件路径 | 操作 | 精确职责 |
| :--- | :--- | :--- |
| `Packages/MiniMateKit/Sources/MMCore/Metrics/LatencyRecorder.swift` | 微调 | 增量新增 `samples(for:)` 与 `hitRate(in:for:)`，供 `M_reflex` 统计 300–800 ms 命中率（保持既有方法与 CSV 格式 100% 兼容） |
| `Packages/MiniMateKit/Tests/MMCoreTests/LatencyRecorderTests.swift` | 修改 | 新增 `samples(for:)` 与 `hitRate(in:for:)` 的正例/边界/空指标测试（既有 8 个用例不改） |
| `Packages/MiniMateKit/Tests/MMPerceptionTests/FaceSignalDeriverTests.swift` | 新增 | **T030（先写测试）**：D5 公式（参数化）、1€ 平滑、滞回进出阈值、最短持续（300/400/600 ms）、多表情冲突、非法值/reset 边界 |
| `Packages/MiniMateKit/Sources/MMPerception/FaceSignalDeriver.swift` | 新增 | **T033**：实现 D5 语义信号推导、1€ 平滑、阈值滞回与最短持续时间判定 |
| `Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift` | 修改 | 将 `FaceSignalDeriver` 接入 `ARKitPerceptionSource` 逐帧管道与生命周期 `reset()` |
| `Packages/MiniMateKit/Sources/MMEmotion/Resources/expression-presets.json` | 修改 | **T034**：填入全部 8 个 `EmotionTag` 预设初值（对称键展开为 ARKit Left/Right，默认 `blendInMs: 200`、`blendOutMs: 300`） |
| `Packages/MiniMateKit/Sources/MMEmotion/ExpressionPreset.swift` | 修改 | 新增 `ExpressionPresetError`、`load(from:)`、`loadBundled()`、`bundledDefaults` 与 `encodeJSON(_:)` 导出方法 |
| `Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift` | 修改 | **T035**：实现表情感知反应映射、随机延迟计划队列、8 s 冷却 + 柔和底色增强（2A）、`blendIn`/`blendOut` 姿态合成第 2/3 步、`.shy` 轻微低头、Speaking 防打断（S-5）与默认预设加载 |
| `Packages/MiniMateKit/Sources/MMEmotion/ReflexLatencyTracker.swift` | 新增 | 纯逻辑 `M_reflex` 测量器（记录 `activeExpression` 进入且成功入队 → `.reacting` 应用渲染的时间差） |
| `Packages/MiniMateKit/Sources/MMEmotion/MirrorCorrelationEvaluator.swift` | 新增 | 纯逻辑 SC-004 镜像相关性评估器（排除 8 个 `eyeLook*` 通道，逐通道双精度 Pearson `r`，零方差记 `0.0`，产出 `MirrorCorrelationReport`） |
| `Packages/MiniMateKit/Sources/MMAvatar/RecordingAvatarRenderer.swift` | 新增 | **T036**：实现 `@MainActor` `AvatarRenderer` 录制替身，记录每次 `apply(_:)` 收到的 `AvatarPose` 与 `load(named:)` 历史 |
| `Packages/MiniMateKit/Tests/MMEmotionTests/ExpressionPresetTests.swift` | 新增 | **T034 验证（先写测试）**：`loadBundled()` 完整性、52 ARKit 键合法性、非法权重/重复情绪/缺失情绪报错、`encodeJSON` 往返 |
| `Packages/MiniMateKit/Tests/MMEmotionTests/ExpressionReactionTests.swift` | 新增 | **T031（先写测试）**：微笑→`happy`、皱眉→`concerned`、惊讶→`surprised`、S-2 冷却与柔和底色增强、S-3 固定随机种子 `[300, 800] ms` 延迟区间、`blendIn`/`blendOut` 插值曲线、Speaking 不打断（S-5）、`ReflexLatencyTracker` 端到端验证 |
| `Packages/MiniMateKit/Tests/MMEmotionTests/NoMirroringTests.swift` | 新增 | **T032（先写测试）**：S-1 未映射通道零泄漏 + `RecordingAvatarRenderer` + `ScriptedPerceptionSource` 30 s 自由表情回放 `maxAbsCorrelation < 0.3` + 故意镜像反例必检出（`> 0.99`）+ 零方差防 `NaN` + `eyeLook*` 排除验证 |
| `App/MiniMate/AppComposition.swift` | 微调 | `makeEmotionStateMachine()` 显式使用 `ExpressionPreset.bundledDefaults` |
| `App/MiniMate/Screens/AvatarScreen.swift` | 修改 | **T037**：`AvatarScene` 接入 `latestFaceSignals`、`ReflexLatencyTracker`（写入 `latencyRecorder` `"M_reflex"`）、30 s 镜像检测流程（`startMirrorCheck`/`stopMirrorCheck`/`lastMirrorReport`）、预设加载/导出辅助方法；`AvatarScreen` 增加镜像检测倒计时悬浮胶囊 |
| `App/MiniMate/Screens/Debug/AvatarDebugPanel.swift` | 修改 | **T037**：扩展调试面板——显示实时 `FaceSignals`、新增“镜像检测（30 s）”区、新增 `M_reflex` 指标（样本数 / p50 / p90 / 300–800 ms 命中率）与“表情预设（预览 / 导出 JSON）”区 |

#### 4.2 明确不做清单（Non-Goals）

- **严禁修改**：
  - `Packages/MiniMateKit/Package.swift` 与 `App/MiniMate.xcodeproj/project.pbxproj`（当前依赖与资源配置已完全满足）；
  - `Packages/MiniMateKit/Sources/MMAvatar/RealityKitAvatarRenderer.swift` 与 `App/MiniMate/Resources/Avatar/*`、`Assets/avatar/*`（3D 资产与渲染层已验收冻结）；
  - `Packages/MiniMateKit/Tests/MMEmotionTests/AttentionTransitionTests.swift`、`IdleMotionLayerTests.swift` 等全部既有测试的预期断言；
  - `specs/002-m1-presence/tasks.md`、`specs/002-m1-presence/research.md`、`docs/tech-selection.md`（收口前不勾选、不回写实测表）；
- **本次不实现**：
  - US4 手势识别（`HandGestureClassifier`、`VNDetectHumanHandPoseRequest`、手势反应映射）；
  - US5 对话事件完整状态转换（`Listening`/`Thinking`/`Speaking` 事件处理、口型层 `jawOpen`/`mouthFunnel` 覆盖、调试面板对话事件注入）；
  - 003（M2 语音对话）或 004（M3 记忆/离线）的任何代码。

---

### 5. 精确接口与行为契约

#### 5.1 `LatencyRecorder` 增量方法（`MMCore`）
- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMCore/Metrics/LatencyRecorder.swift`
  ```swift
  /// 返回指定指标已记录的全部样本（按记录顺序）；未记录返回空数组。
  public func samples(for metric: String) -> [TimeInterval]

  /// 返回样本落在闭区间 `range` 内的比例（0...1）；无样本返回 `nil`。
  public func hitRate(in range: ClosedRange<TimeInterval>, for metric: String) -> Double?
  ```
- **边界口径**：
  - 无样本时 `samples(for:)` 返回 `[]`，`hitRate(in:for:)` 返回 `nil`；
  - `range` 采用闭区间包含判定（`range.contains(sample)`）；
  - 既有 `record` / `count` / `p50` / `p90` / `percentile` / `csv` 行为与输出格式保持字节级一致。

#### 5.2 `FaceSignalDeriver`（`MMPerception`）
- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMPerception/FaceSignalDeriver.swift`
  ```swift
  public struct FaceSignalDeriver: Sendable, Equatable {
      public struct ThresholdConfig: Sendable, Equatable {
          public var enter: Float
          public var exit: Float
          public var minDuration: TimeInterval

          public init(enter: Float, exit: Float, minDuration: TimeInterval)
      }

      public struct Config: Sendable, Equatable {
          public var smile: ThresholdConfig      // 默认 enter: 0.50, exit: 0.30, minDuration: 0.40
          public var frown: ThresholdConfig      // 默认 enter: 0.38, exit: 0.22, minDuration: 0.50（真机实测调优）
          public var surprise: ThresholdConfig   // 默认 enter: 0.38, exit: 0.22, minDuration: 0.30（真机实测调优）
          public var filterMinCutoff: Double     // 默认 1.5
          public var filterBeta: Double          // 默认 0.5
          public var filterDCutoff: Double       // 默认 1.0

          public init(
              smile: ThresholdConfig = ThresholdConfig(enter: 0.50, exit: 0.30, minDuration: 0.40),
              frown: ThresholdConfig = ThresholdConfig(enter: 0.38, exit: 0.22, minDuration: 0.50),
              surprise: ThresholdConfig = ThresholdConfig(enter: 0.38, exit: 0.22, minDuration: 0.30),
              filterMinCutoff: Double = 1.5,
              filterBeta: Double = 0.5,
              filterDCutoff: Double = 1.0
          )

          public static let defaults = Config()
      }

      public let config: Config
      public private(set) var lastSignals: FaceSignals = FaceSignals()

      public init(config: Config = .defaults)

      /// 纯公式计算（不含平滑与滞回），严格遵循 research.md D5：
      /// - smile    = (mouthSmileLeft + mouthSmileRight) / 2
      /// - frown    = max(browDownLeft, browDownRight) * 0.6 + (mouthFrownLeft + mouthFrownRight) / 2 * 0.4
      /// - surprise = browInnerUp * 0.5 + jawOpen * 0.3 + (eyeWideLeft + eyeWideRight) / 2 * 0.2
      /// 缺失键按 0 处理，非有限值按 0 处理，每个输入系数先夹紧至 [0, 1]。
      public static func rawSignals(from blendShapes: [String: Float]) -> (smile: Float, frown: Float, surprise: Float)

      /// 输入单帧原始系数与时间戳（秒），执行 1€ 平滑 + 滞回 + 最短持续判定。
      public mutating func update(blendShapes: [String: Float], at timestamp: TimeInterval) -> FaceSignals

      /// 重置滤波器、候选计时器与当前 activeExpression。
      public mutating func reset()
  }
  ```
- **复用约束**：内部 3 路平滑必须直接实例化 3 个 `MMPerception.OneEuroFilter`（`Packages/MiniMateKit/Sources/MMPerception/OneEuroFilter.swift:5`），禁止另写 EMA 或滤波代码。
- **滞回、持续时间与多表情冲突口径**：
  1. `ThresholdConfig.init` 夹紧保护：`enter = clampFinite(enter, 0.01, 1.0)`，`exit = clampFinite(exit, 0.0, enter)`（确保 `exit <= enter`），`minDuration = clampFinite(minDuration, 0.0, 60.0)`；
  2. `timestamp` 非有限时直接返回 `lastSignals`，不污染内部滤波器与计时器；
  3. 对平滑后的 3 路信号夹紧至 `[0, 1]`，按频道独立维护 `candidateStartedAt[expr]`：
     - 若 `value >= cfg.enter`：若 `candidateStartedAt[expr] == nil` 或 `timestamp < started`，置 `candidateStartedAt[expr] = timestamp`；
     - 若 `value < cfg.enter`：置 `candidateStartedAt[expr] = nil`；
     - 满足 `timestamp - started + 1e-9 >= cfg.minDuration` 记为 `qualified`；
  4. 状态转移：
     - 若当前 `activeExpression == current` 且 `value(current) < cfg(current).exit`：`activeExpression = nil`；
     - 若 `activeExpression == nil`：从全部 `qualified` 频道中选 `value - cfg.enter` 最大者（相等时固定顺序 `.surprised` > `.frowning` > `.smiling`）；
     - 若 `activeExpression == current` 且 `value(current) < cfg(current).enter`（处于滞回维持带），且存在其他 `other != current` 处于 `qualified` 且 `value(other) > value(current)`：切换为 `other`（避免被滞回带卡死）。
- **`ARKitPerceptionSource` 接线与兼容性**：
  - `ARKitPerceptionSource.init` 签名新增带默认值的 `signalDeriver: FaceSignalDeriver = FaceSignalDeriver()`（保持 `ARKitPerceptionSource(clock: clock)` 零修改兼容）；
  - `handleFrame` 中有脸时调用 `let signals = s.signalDeriver.update(blendShapes: face.blendShapes, at: timestamp)` 并写入 `PerceptionFeatures(..., signals: signals, ...)`；
  - `start()`、`stop()`、`extractedFace == nil`、`handleSessionWasInterrupted`、`handleSessionInterruptionEnded` 中均调用 `s.signalDeriver.reset()`。

#### 5.3 `expression-presets.json` 与 `ExpressionPreset` 加载/导出（`MMEmotion`）
- **JSON 资源路径**：`Packages/MiniMateKit/Sources/MMEmotion/Resources/expression-presets.json`
- **完整 8 预设初值（严格对应 `specs/002-m1-presence/data-model.md:114-125`）**：
  - `happy`: `{"mouthSmileLeft": 0.8, "mouthSmileRight": 0.8, "jawOpen": 0.2, "cheekSquintLeft": 0.4, "cheekSquintRight": 0.4, "browInnerUp": 0.3}`
  - `gentle`: `{"mouthSmileLeft": 0.5, "mouthSmileRight": 0.5, "eyeSquintLeft": 0.2, "eyeSquintRight": 0.2}`
  - `sad`: `{"mouthFrownLeft": 0.6, "mouthFrownRight": 0.6, "browInnerUp": 0.7, "eyeSquintLeft": 0.3, "eyeSquintRight": 0.3}`
  - `surprised`: `{"browInnerUp": 0.5, "browOuterUpLeft": 0.66, "browOuterUpRight": 0.66, "eyeWideLeft": 0.9, "eyeWideRight": 0.9, "jawOpen": 0.65}`（真机实测调优）
  - `shy`: `{"mouthSmileLeft": 0.4, "mouthSmileRight": 0.4, "eyeSquintLeft": 0.5, "eyeSquintRight": 0.5}`
  - `playful`: `{"browOuterUpRight": 0.4, "cheekSquintLeft": 0.35, "cheekSquintRight": 0.35, "eyeBlinkLeft": 0.9, "jawOpen": 0.15, "mouthSmileLeft": 0.75, "mouthSmileRight": 0.75}`（真机实测替换掉 `tongueOut` 防闭嘴穿模，改为单眼 Wink 俏皮）
  - `concerned`: `{"browDownLeft": 0.35, "browDownRight": 0.35, "browInnerUp": 0.85, "eyeBlinkLeft": 0.2, "eyeBlinkRight": 0.2, "eyeSquintLeft": 0.3, "eyeSquintRight": 0.3, "mouthFrownLeft": 0.75, "mouthFrownRight": 0.75}`（真机实测调优）
  - `neutral`: `{}`
  - 每项均显式写 `"blendInMs": 200, "blendOutMs": 300`。
- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMEmotion/ExpressionPreset.swift`
  ```swift
  public enum ExpressionPresetError: Error, Sendable, Equatable {
      case resourceNotFound
      case duplicateEmotion(EmotionTag)
      case missingEmotions([EmotionTag])
      case invalidWeight(emotion: EmotionTag, name: String, value: Float)
  }

  extension ExpressionPreset {
      /// 从 JSON 数据解码并校验预设字典。
      /// - Parameter requireAllEmotions: 为 true 时强制检查 8 个 `EmotionTag` 齐全，缺项抛 `.missingEmotions`。
      public static func load(
          from data: Data,
          requireAllEmotions: Bool = false
      ) throws -> [EmotionTag: ExpressionPreset]

      /// 从 `Bundle.module` 加载内置 `expression-presets.json`（强制 8 个情绪齐全）。
      public static func loadBundled() throws -> [EmotionTag: ExpressionPreset]

      /// 加载内置预设；仅在极端资源异常时回退为空字典，供默认参数与 App 启动使用。
      public static var bundledDefaults: [EmotionTag: ExpressionPreset] { get }

      /// 按 `EmotionTag.allCases` 顺序编码为格式化 JSON（`[.prettyPrinted, .sortedKeys]`），供调试面板导出。
      public static func encodeJSON(_ presets: [EmotionTag: ExpressionPreset]) throws -> Data

      /// 编码单个预设为格式化 JSON，供调试面板单情绪调参导出。
      public static func encodeSingleJSON(_ preset: ExpressionPreset) throws -> Data
  }
  ```
- **边界与异常口径**：
  - `ExpressionPreset.init(from:)` 负值 `blendInMs`/`blendOutMs` 夹紧至 `>= 0`；
  - `load(from:)` 遇到重复 `emotion` 抛 `.duplicateEmotion`；遇到非有限或 `< 0` / `> 1` 权重抛 `.invalidWeight`；`requireAllEmotions == true` 且缺项时按 `EmotionTag.allCases` 顺序抛 `.missingEmotions`；
  - `loadBundled()` 使用 `Bundle.module.url(forResource: "expression-presets", withExtension: "json")`（无 `subdirectory`），找不到抛 `.resourceNotFound`。

#### 5.4 `RuleBasedEmotionStateMachine`（`MMEmotion` — T035）
- **位置**：`Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift`
- **构造器签名与兼容性**：
  ```swift
  public init(
      rules: ReactionRules = .defaults,
      presets: [EmotionTag: ExpressionPreset] = ExpressionPreset.bundledDefaults,
      clock: any MMCore.Clock = SystemClock(),
      random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
      idleConfig: IdleMotionLayer.Config = .init()
  )
  ```
  - 说明：`presets` 默认改为 `ExpressionPreset.bundledDefaults`；因 `.neutral` 权重为 `{}`，既有 `AttentionTransitionTests`（全部 9 个用例，含 `invariantsS1AndS6Hold`）100% 兼容无需修改。
- **感知表情反应映射（严格对应 `contracts/emotion-state-machine.md:41-45`）**：
  - `UserExpression.smiling` → `(key: ReactionKey.smile, emotion: EmotionTag.happy)`
  - `UserExpression.frowning` → `(key: ReactionKey.frown, emotion: EmotionTag.concerned)`
  - `UserExpression.surprised` → `(key: ReactionKey.surprise, emotion: EmotionTag.surprised)`
- **调度、延迟、冷却与 S-1/S-2/S-3/S-5/S-6 契约**：
  1. **严禁读取 `features.rawBlendShapes`**（不变式 S-1）；仅读取 `features.signals.activeExpression`；
  2. **定时推进**：在 `handle(_ features:)` 入口与 `pose(at:)` 入口均按顺序执行：
     - ① `checkReactingExpiration(at: now)`
     - ② `processScheduledReactions(at: now)`
     - ③ `checkCooldownBoostExpiration(at: now)`（及清理已衰减完的 `fadingLayers`）
  3. **边沿触发入队（在 `handle(_ features:)` 末尾，完成注意力转换之后）**：
     - 读取 `let newExpr = features.isFaceTracked ? features.signals.activeExpression : nil`；
     - 仅当 `newExpr != previousActiveExpression` 且 `let expr = newExpr` 时触发处理（随后更新 `previousActiveExpression = newExpr`）：
       - 查映射得 `(key, emotion)`；
       - **Speaking 保护（S-5）**：若 `currentState.kind` 为 `.speaking`：不修改 `state.kind`、不写入 `scheduled`；若不在冷却（`cooldowns[key] <= now`），记录一个轻量叠加层（强度 `0.25 <= 0.3`，持续 `rules.reactionDuration`）并写入 `cooldowns[key] = now + rules.cooldown`；
       - **冷却中（S-2 + 决策 2A）**：若 `let until = currentState.cooldowns[key]`, `now < until`：
         - **绝不**进入 `.reacting`、**绝不**入队 `scheduled`、**绝不**发动作；
         - 激活短时柔和增强 `cooldownBoost = CooldownBoost(emotion: emotion, startedAt: now, duration: durationSeconds(rules.reactionDuration))`（底色非 `.neutral` 时将底色强度由 `0.3` 临时微提至 `0.45`；底色为 `.neutral` 时以 `0.25` 强度叠加 `presets[emotion]`，均按预设 `blendIn`/`blendOut` 平滑起落）；
       - **去重**：若 `currentState.scheduled.contains(where: { $0.key == key })`，或当前已处于 `.reacting` 且来源键等于 `key`：不重复排程；
       - **正常排程（S-3）**：计算 `delay = lerp(rules.reactionDelay.lowerBound, rules.reactionDelay.upperBound, unitRandom())`，构造：
         ```swift
         let returnTo = underlyingStateKind(of: currentState.kind)
         let reaction = Reaction(
             expression: emotion,
             action: nil,
             duration: rules.reactionDuration,
             returnTo: returnTo
         )
         let scheduledItem = ScheduledReaction(
             key: key,
             reaction: reaction,
             triggerAt: now + delay
         )
         ```
         追加到 `currentState.scheduled`（保持按 `triggerAt` 升序）。
  4. **到期触发（`processScheduledReactions(at: evalTime)`）**：
     - 取出全部满足 `evalTime + 1e-9 >= item.triggerAt` 的待办项，并从 `currentState.scheduled` 移除；
     - 对每条到期项：
       - 若已在冷却中（`cooldowns[item.key] > evalTime`）：跳过（二次兜底 S-2）；
       - 若当前为 `.speaking`：跳过（二次兜底 S-5）；
       - 若当前为 `.reacting(active)` 且 `active.action != nil`（如 `leanBack` 正在播放）：跳过，不打断动作；
       - 否则：若当前为 `.reacting(prev)`，先将其当前包络权重快照推入 `fadingLayers` 平滑淡出；用 `returnTo = underlyingStateKind(of: currentState.kind)` 切入 `.reacting(Reaction(expression: item.reaction.expression, action: item.reaction.action, duration: item.reaction.duration, returnTo: returnTo))`，设置 `enteredAt = evalTime`，设置 `cooldowns[item.key] = evalTime + rules.cooldown`，记录 `activeReactionKey = item.key`；若 `item.reaction.action != nil` 则置 `pendingAction = .play(action)`。
  5. **回 Idle 与 `resetToIdle` 清理**：
     - `transitionToIdleWithLookAround(at:)` 与 `resetToIdle(at:)` 均清空 `scheduled`、`previousActiveExpression = nil`、`activeReactionKey = nil`、`cooldownBoost = nil`、`fadingLayers.removeAll()`（注意 `cooldowns` 保留，防止快速离屏再回绕过冷却）。
- **姿态合成第 1、2、3、5、6 步（`pose(at:)`）**：
  - 定义统一包络函数 `envelope(elapsed:duration:blendIn:blendOut:) -> Float`（纯函数，`internal static` 可直测）：
    - 若 `duration <= 0` 或 `elapsed < 0` 或 `elapsed >= duration`：返回 `0`；
    - 令 `effIn = max(blendIn, 0)`，`effOut = max(blendOut, 0)`；若 `effIn + effOut > duration`，按比例缩放 `scale = duration / (effIn + effOut)`，`effIn *= scale`，`effOut *= scale`；
    - 若 `effIn > 0 && elapsed < effIn`：返回 `Float(elapsed / effIn)`（线性或 smoothstep？**明确选线性 `elapsed / effIn`**，单调、易于在单测做精确数值断言如 100 ms/200 ms == `0.5`！）；
    - 若 `effOut > 0 && elapsed > duration - effOut`：返回 `Float((duration - elapsed) / effOut)`；
    - 否则返回 `1.0`。
  - **Step 1（底色层）**：若 `currentState.baseEmotion != .neutral` 且有预设，基础强度 `0.3`；若 `cooldownBoost` 活跃，按 `boostEnv = envelope(...)` 将强度平滑提升至 `0.3 + 0.15 * boostEnv`（最高 `0.45`）。若 `baseEmotion == .neutral` 且 `cooldownBoost` 活跃，对 `presets[cooldownBoost.emotion]` 施加 `0.25 * boostEnv`。
  - **Step 2 + Step 3（状态层 + 过渡插值）**：
    - `.reacting(reaction)`：查 `presets[reaction.expression]`，计算 `factor = envelope(elapsed: evalTime - currentState.enteredAt, duration: durationSeconds(reaction.duration), blendIn: durationSeconds(preset.blendIn), blendOut: durationSeconds(preset.blendOut))`，叠加 `value * factor`（取 `max`）；
    - `.speaking(emotion)`：查 `presets[emotion]`，强度 `1.0`（为 S-5 测试准备；若有 Speaking 轻量感知叠加，强度 `<= 0.3`）；
    - `.thinking`：查 `presets[.gentle]`，强度 `0.35`（若无预设则忽略）；
    - `fadingLayers`：对被打断的旧反应按 `remainingFactor = startFactor * max(0, 1 - (evalTime - fadeStart) / blendOut)` 叠加取 `max`，归零后移除；
    - **`.shy` 轻微低头（`data-model.md:120`）**：若当前激活表情为 `.shy`（`.reacting` 或 `.speaking`），按同包络因子 `factor` 向 `gazePitch` 叠加 `+8° * factor`（`+8 * .pi / 180 * factor`，正值低头，最终仍在 `±25°` 限幅内）。
  - **Step 5（待机层）与 Step 6（视线与头部朝向）**：保持 US2 既有实现；全部权重经 `clamp(..., 0, 1)`（不变式 S-6）。

#### 5.5 `ReflexLatencyTracker`（`MMEmotion`）
- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMEmotion/ReflexLatencyTracker.swift`
  ```swift
  /// 测量 M_reflex：用户语义表情首次进入（且成功进入状态机计划队列）→ 形象开始应用对应 Reacting 姿态的时间差（秒）。
  public struct ReflexLatencyTracker: Sendable, Equatable {
      public let timeout: TimeInterval  // 默认 3.0 s

      public init(timeout: TimeInterval = 3.0)

      /// 在感知帧经状态机 `handle(_:)` 后调用；仅当表情边沿进入且状态机实际为该 key 排程了反应时武装。
      public mutating func observePerception(
          activeExpression: UserExpression?,
          state: AvatarState,
          at timestamp: TimeInterval
      )

      /// 在渲染器应用姿态时调用；当状态首次进入对应 `.reacting`（且无动作，即纯表情反应）时返回单次 M_reflex 样本（秒）。
      public mutating func observeAppliedState(
          _ stateKind: AvatarStateKind,
          at timestamp: TimeInterval
      ) -> TimeInterval?

      public mutating func reset()
  }
  ```
- **边界口径**：
  - `activeExpression` 持续多帧不变时不重复武装（边沿触发）；
  - 冷却期内 `state.scheduled` 不含对应 `key` 时绝不武装（杜绝虚假超时或错配下一次反应）；
  - 若期间发生 `leanBack`（`reaction.action != nil`），忽略该动作反应，不误计为表情 `M_reflex`；
  - 延迟 `< 0` 或 `>= timeout` 直接丢弃返回 `nil` 并清理待测项；非有限时间戳直接忽略。

#### 5.6 `MirrorCorrelationEvaluator`（`MMEmotion`）
- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMEmotion/MirrorCorrelationEvaluator.swift`
  ```swift
  public struct MirrorChannelCorrelation: Sendable, Equatable {
      public let name: String
      public let correlation: Double
      public var absCorrelation: Double { abs(correlation) }
  }

  public struct MirrorCorrelationReport: Sendable, Equatable {
      public let sampleCount: Int
      public let duration: TimeInterval
      public let threshold: Double                       // 默认 0.3
      public let perChannel: [String: Double]            // 仅含被评估的非视线表情通道
      public let maxAbsCorrelation: Double
      public let maxChannelName: String?
      public let meanAbsCorrelation: Double
      public let topChannels: [MirrorChannelCorrelation] // 按 absCorrelation 降序最多前 5 项
      public var passed: Bool { sampleCount >= 2 && maxAbsCorrelation < threshold }

      public func summaryText() -> String
  }

  public enum MirrorCorrelationEvaluator: Sendable {
      /// 宪章 I / FR-014 豁免的 8 个视线通道，不纳入镜像检测。
      public static let gazeBlendShapeNames: Set<String> = [
          "eyeLookDownLeft", "eyeLookDownRight",
          "eyeLookInLeft", "eyeLookInRight",
          "eyeLookOutLeft", "eyeLookOutRight",
          "eyeLookUpLeft", "eyeLookUpRight",
      ]

      /// 单通道双精度 Pearson 相关系数；长度 < 2 或任一序列方差 < 1e-12 返回 0.0（杜绝 NaN）。
      public static func pearson(_ xs: [Double], _ ys: [Double]) -> Double

      /// 评估逐帧配对的用户 rawBlendShapes 与形象 expressionWeights。
      /// - Parameters:
      ///   - pairs: 按时间顺序配对的帧；数量必须一致（不足 2 帧返回 sampleCount 对应报告且 passed == false）。
      ///   - duration: 检测覆盖时长（秒）。
      ///   - channels: 指定评估通道名；为 nil 时自动取所有帧中出现过的非视线键并集。无论是否传入，始终剔除 `gazeBlendShapeNames`。
      ///   - threshold: 通过门槛，默认 0.3（SC-004）。
      public static func evaluate(
          pairs: [(user: [String: Float], avatar: [String: Float])],
          duration: TimeInterval,
          channels: [String]? = nil,
          threshold: Double = 0.3
      ) -> MirrorCorrelationReport
  }
  ```

#### 5.7 `RecordingAvatarRenderer`（`MMAvatar` — T036）
- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMAvatar/RecordingAvatarRenderer.swift`
  ```swift
  /// 测试用渲染器替身：完整记录收到的 `AvatarPose` 序列，用于 S-1 与 SC-004 自动化断言。
  @MainActor
  public final class RecordingAvatarRenderer: AvatarRenderer {
      public private(set) var loadedAssetNames: [String] = []
      public private(set) var poses: [AvatarPose] = []
      private let capabilities: AvatarCapabilities

      public init(
          capabilities: AvatarCapabilities = AvatarCapabilities(
              blendShapeNames: Set(BlendShapeIndex.arkitNames),
              actionNames: Set(ActionTag.allCases.map(\.rawValue))
          )
      )

      public func load(named name: String) async throws -> AvatarCapabilities
      public func apply(_ pose: AvatarPose)
      public func reset()
  }
  ```

#### 5.8 `AvatarScene` 与 `AvatarDebugPanel` 接线（`App/MiniMate` — T037）
- **`AppComposition.swift`**：`makeEmotionStateMachine()` 改为 `RuleBasedEmotionStateMachine(presets: ExpressionPreset.bundledDefaults, clock: clock)`。
- **`AvatarScene` 新增公开状态与方法**（`App/MiniMate/Screens/AvatarScreen.swift`）：
  - `private(set) var latestFaceSignals: FaceSignals = FaceSignals()`
  - `private(set) var isRunningMirrorCheck: Bool = false`
  - `private(set) var mirrorCheckElapsed: TimeInterval = 0`
  - `let mirrorCheckTargetDuration: TimeInterval = 30.0`
  - `private(set) var mirrorCheckSampleCount: Int = 0`
  - `private(set) var lastMirrorReport: MirrorCorrelationReport?`
  - `func startMirrorCheck()` / `func stopMirrorCheck()` / `func clearMirrorCheck()`
  - `func applyPresetToDebugWeights(_ emotion: EmotionTag)`（从 `ExpressionPreset.bundledDefaults[emotion]` 填充 `debugWeights`，先清空旧滑杆）
  - `func exportDebugWeightsAsPresetJSON(emotion: EmotionTag) -> String?`（仅导出 `debugWeights` 中 `> 0.001` 的键）
- **`AvatarScene` 采样与生命周期口径**：
  - 在 `perceptionTask` 中：`await stateMachine.handle(features)` 后读取 `pose` 与 `state`：
    - 当 `!freezeIdle && !isDebugPanelPresented` 时，调用 `reflexLatencyTracker.observePerception(activeExpression: features.signals.activeExpression, state: state, at: features.timestamp)`；
    - 当 `isRunningMirrorCheck && features.isFaceTracked` 时，配对追加 `(user: features.rawBlendShapes, avatar: pose.expressionWeights)`，更新 `mirrorCheckElapsed` 与 `mirrorCheckSampleCount`；满 `30.0 s` 自动调用 `stopMirrorCheck()` 计算并发布 `lastMirrorReport`；
  - 在 `tick()` 中 `renderer.apply(pose)` 之后：
    - 当 `!freezeIdle && !isDebugPanelPresented` 时，调用 `if let sample = reflexLatencyTracker.observeAppliedState(currentStateKind, at: now) { latencyRecorder.record(sample, metric: "M_reflex") }`；
  - 在 `stopPerception()`、`handleBackground()`、`clearMetrics()` 中重置 `reflexLatencyTracker.reset()`；在 `stopPerception()` 与 `handleBackground()` 中若正在运行镜像检测则优雅停止（保留已采集报告或复位，不遗留悬挂状态）。
- **`AvatarScreen` 悬浮提示**：
  - `isRunningMirrorCheck == true` 时在顶部或左下角展示胶囊提示（如 `镜像检测 12s / 30s · 结束`），用户切回主界面对着小瓜做 30 s 自由表情即可自动完成。
- **`AvatarDebugPanel` 增量区块**（只增不删，保留现有全部功能）：
  1. `Section("状态与感知")` 追加：`微笑/皱眉/惊讶` 实时平滑值与 `activeExpression`；
  2. 新增 `Section("镜像检测（SC-004，30 s）")`：开始/停止按钮、进度（已采帧数 / 时长）、结果摘要（最大 `|r|` + 通道名 + 通过/未通过徽标、平均 `|r|`、Top 3 通道明细）与 `ShareLink` 导出报告；
  3. 扩展 `Section("指标")`：并列展示 `M_track`（保留现有）与 `M_reflex`（样本数、p50、p90、**300–800 ms 命中率**如 `95.0% (19/20)`），共用“导出指标 CSV”与“清空指标”；
  4. 新增 `Section("表情预设（预览与导出）")`：8 个 `EmotionTag` 按钮（点选载入滑杆预览）+ `ShareLink` 导出当前滑杆为预设 JSON，方便 T038 真机调参回写 `expression-presets.json`。

---

### 6. 原子化施工步骤（自底向上，纯逻辑严格测试先行）

- **Step 1：`LatencyRecorder` 增量支持 `hitRate`（先测试，后实现）**
  - 改动文件：`Packages/MiniMateKit/Tests/MMCoreTests/LatencyRecorderTests.swift`（先写）、`Packages/MiniMateKit/Sources/MMCore/Metrics/LatencyRecorder.swift`（后写）
  - 改动要点：先写 `samples(for:)` 与 `hitRate(in:for:)` 测试（空指标、全命中、部分命中、闭区间边界 0.300/0.800），确认失败后实现。
  - 最小验证命令：`cd Packages/MiniMateKit && swift test --filter LatencyRecorderTests`

- **Step 2：T030 + T033 `FaceSignalDeriver`（先测试，后实现）并接入 `ARKitPerceptionSource`**
  - 改动文件：`Packages/MiniMateKit/Tests/MMPerceptionTests/FaceSignalDeriverTests.swift`（先写）、`Packages/MiniMateKit/Sources/MMPerception/FaceSignalDeriver.swift`（后写）、`Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift`
  - 改动要点：先写参数化 D5 公式测试 + 滞回 + 300/400/600 ms 持续边界 + 多表情冲突 + NaN/reset 边界测试，确认编译/断言失败；再实现 `FaceSignalDeriver`（复用 `OneEuroFilter`）并接入 `ARKitPerceptionSource`（含全部生命周期 `reset()`）。
  - 最小验证命令：`cd Packages/MiniMateKit && swift test --filter FaceSignalDeriverTests && xcodebuild -scheme MMPerception -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`

- **Step 3：T034 `expression-presets.json` 与 `ExpressionPreset` 加载/校验/导出（先测试，后实现）**
  - 改动文件：`Packages/MiniMateKit/Tests/MMEmotionTests/ExpressionPresetTests.swift`（先写）、`Packages/MiniMateKit/Sources/MMEmotion/Resources/expression-presets.json`、`Packages/MiniMateKit/Sources/MMEmotion/ExpressionPreset.swift`
  - 改动要点：先写测试断言 `loadBundled()` 返回全部 8 情绪、所有键均属于 `BlendShapeIndex.arkitNames`、权重 ∈ `[0, 1]`、异常 JSON（重复/缺失/超界/NaN）抛精确 `ExpressionPresetError`、`encodeJSON` 往返一致；确认失败后再写入 8 预设 JSON 与加载/导出实现。
  - 最小验证命令：`cd Packages/MiniMateKit && swift test --filter ExpressionPresetTests`

- **Step 4：T036 `RecordingAvatarRenderer` + `MirrorCorrelationEvaluator` + `ReflexLatencyTracker`（先测试，后实现）**
  - 改动文件：`Packages/MiniMateKit/Sources/MMAvatar/RecordingAvatarRenderer.swift`、`Packages/MiniMateKit/Sources/MMEmotion/MirrorCorrelationEvaluator.swift`、`Packages/MiniMateKit/Sources/MMEmotion/ReflexLatencyTracker.swift`、`Packages/MiniMateKit/Tests/MMEmotionTests/NoMirroringTests.swift`（基础单测先写）
  - 改动要点：先在 `NoMirroringTests` 写 `MirrorCorrelationEvaluator` 数学正确性、零方差防 `NaN`、`eyeLook*` 剔除与刻意镜像必失败用例，再实现 3 个组件。
  - 最小验证命令：`cd Packages/MiniMateKit && swift test --filter NoMirroringTests`

- **Step 5：T031 + T035 `RuleBasedEmotionStateMachine` 表情反应、计划队列、冷却与 `blendIn`/`blendOut` 合成（先测试，后实现）**
  - 改动文件：`Packages/MiniMateKit/Tests/MMEmotionTests/ExpressionReactionTests.swift`（先写）、`Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift`
  - 改动要点：先写完整 `ExpressionReactionTests`（覆盖微笑→`happy`、皱眉→`concerned`、惊讶→`surprised`、S-2 冷却 + 2A 柔和增强、S-3 固定随机种子 0.0/0.5/1.0 精确验证 300/550/800 ms、`blendIn`/`blendOut` 数值插值、Speaking 不打断、`leanBack` 不被覆盖、`ReflexLatencyTracker` 联合测试），确认失败后再实现状态机升级，并验证既有 `AttentionTransitionTests` 零修改全绿。
  - 最小验证命令：`cd Packages/MiniMateKit && swift test --filter "ExpressionReactionTests|AttentionTransitionTests|IdleMotionLayerTests"`

- **Step 6：T032 补齐 `NoMirroringTests` 30 s 端到端回放验证（`ScriptedPerceptionSource` → `FaceSignalDeriver` → `RuleBasedEmotionStateMachine` → `RecordingAvatarRenderer`）**
  - 改动文件：`Packages/MiniMateKit/Tests/MMEmotionTests/NoMirroringTests.swift`
  - 改动要点：构造确定性 30 s（1800 帧 @ 60 Hz）多表情序列（含微笑、皱眉、惊讶、鼓腮 `cheekPuff`、嘟嘴 `mouthPucker`、歪下巴 `jawLeft`、皱鼻 `noseSneerLeft` 等自由表情 + 头部左右移动），经 `ScriptedPerceptionSource` 回放跑完整链路并断言 S-1 与 `SC-004`（`maxAbsCorrelation < 0.3`）。
  - 最小验证命令：`cd Packages/MiniMateKit && swift test --filter "MMPerceptionTests|MMEmotionTests|MMCoreTests"`

- **Step 7：T037 App 主界面与调试面板接线**
  - 改动文件：`App/MiniMate/AppComposition.swift`、`App/MiniMate/Screens/AvatarScreen.swift`、`App/MiniMate/Screens/Debug/AvatarDebugPanel.swift`
  - 改动要点：注入 `bundledDefaults` 预设；接入 `latestFaceSignals`、`ReflexLatencyTracker`（`"M_reflex"`）、30 s 镜像检测与倒计时胶囊、调试面板语义信号/镜像检测/`M_reflex` 命中率/表情预设预览导出。
  - 最小验证命令：`xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`

---

### 7. 确定性测试矩阵与验收门禁

#### 7.1 测试矩阵（严禁非确定性断言，全部使用固定时钟与固定随机源）

| 目标测试文件 | 覆盖类别 | 测试场景 | 必须写死的断言底线（禁止弱断言） |
| :--- | :--- | :--- | :--- |
| `MMCoreTests/LatencyRecorderTests.swift` | 正例/边界 | `samples(for:)` 与 `hitRate(in: 0.3...0.8, for: "M_reflex")`（空、全中、3/4 命中、恰好 0.300 / 0.800 闭边界） | 空返回 `nil`；闭边界计入命中；3/4 精准断言 `abs(rate - 0.75) < 1e-9` |
| `MMPerceptionTests/FaceSignalDeriverTests.swift` | 正例（参数化） | D5 三组公式（`smile`/`frown`/`surprise` 多组输入，含单侧皱眉 `max(browDownLeft, browDownRight)`） | 精确断言 `abs(raw - expected) < 1e-5` |
| `MMPerceptionTests/FaceSignalDeriverTests.swift` | 正例/边界 | 阈值滞回与最短持续：`smile` 399 ms vs 400 ms、回落到 0.35 维持、跌至 0.29 退出；`frown` 599 ms vs 600 ms；`surprise` 299 ms vs 300 ms | 精准断言切换帧的前一帧为 `nil`/原状态、边界帧翻转；滞回带 `[exit, enter)` 严格保持激活 |
| `MMPerceptionTests/FaceSignalDeriverTests.swift` | 边界/反例 | 持续微笑中途短暂跌破进入阈值、滞回带内切换为强惊讶、`NaN`/`Inf`/负值/`>1`、非单调时间戳、`reset()` | 无 `NaN` 污染，所有信号 ∈ `[0, 1]`；中途跌破重置计时；`reset()` 立即清零 `activeExpression` |
| `MMEmotionTests/ExpressionPresetTests.swift` | 正例 | `ExpressionPreset.loadBundled()` | 返回 8 个情绪零缺失；全部权重键 ∈ `Set(BlendShapeIndex.arkitNames)`；所有值 ∈ `[0, 1]`；`neutral.weights.isEmpty == true`；`encodeJSON` 往返与原字典逐字段相等 |
| `MMEmotionTests/ExpressionPresetTests.swift` | 异常反例 | 重复情绪 JSON、缺失情绪（`requireAllEmotions: true`）、超界权重 `1.2` / `-0.1` | 精准抛出 `.duplicateEmotion`、`.missingEmotions`、`.invalidWeight` |
| `MMEmotionTests/ExpressionReactionTests.swift` | 正例（S-3） | 固定随机种子 `0.0` / `0.5` / `1.0`，分别验证 `smiling`→`happy`、`frowning`→`concerned`、`surprised`→`surprised` | `0.0` 在 `+300 ms` 触发（`+299 ms` 未触发）、`0.5` 在 `+550 ms`、`1.0` 在 `+800 ms`；皱眉绝不输出 `sad` 而精准输出 `.concerned`；`1.5 s` 后回到 `.attending` |
| `MMEmotionTests/ExpressionReactionTests.swift` | 正例（S-2 + 2A） | 微笑反应后 `t + 2 s`（8 s 冷却内）再次微笑，以及 `t + 8.0 s` 冷却结束后再次微笑 | 冷却期内 `state.kind == .attending`、`scheduled.isEmpty`、产生低强度柔和愉悦权重（`0 < mouthSmileLeft <= 0.3` 且严格小于满反应 `0.8`）；冷却结束后重新正常排程进入 `.reacting(.happy)` |
| `MMEmotionTests/ExpressionReactionTests.swift` | 正例（Step 2/3） | `blendIn = 200 ms`、`blendOut = 300 ms`、`duration = 1500 ms` 的插值包络 | `+0 ms` 系数 `0`、`+100 ms` 为 `0.5 × preset`、`+200..+1200 ms` 为 `1.0 × preset`、`+1350 ms` 为 `0.5 × preset`、`+1500 ms` 回 `0` 且回到 `.attending` |
| `MMEmotionTests/ExpressionReactionTests.swift` | 边界/反例 | 持续 60 帧 `smiling` 不重复排程；`leanBack` 动作播放期不被害羞/微笑反应打断；`resetToIdle` 与离屏回 Idle 清空 `scheduled`；`ReflexLatencyTracker` 精准测出 550 ms 且冷却期不产生假样本 | 队列长度始终 `<= 1`；`leanBack` 不被覆盖；`ReflexLatencyTracker` 误差 `< 1e-6`，冷却期返回 `nil` |
| `MMEmotionTests/NoMirroringTests.swift` | 正例（S-1 + SC-004） | `ScriptedPerceptionSource` 回放 30 s（1800 帧 @ 60 Hz）多表情自由序列 → `FaceSignalDeriver` → `RuleBasedEmotionStateMachine` → `RecordingAvatarRenderer` | 未映射通道（`cheekPuff`/`mouthPucker`/`jawLeft`/`noseSneerLeft`）全程 `== 0`（S-1）；`report.sampleCount == 1800`、`report.maxAbsCorrelation < 0.3`、`report.passed == true`、`!report.perChannel.keys.contains("eyeLookOutLeft")` |
| `MMEmotionTests/NoMirroringTests.swift` | 异常/防假绿 | 刻意把 `rawBlendShapes` 直接拷进 `AvatarPose` 送入 `MirrorCorrelationEvaluator`；全零常值通道测试 | 刻意镜像 `maxAbsCorrelation > 0.99` 且 `passed == false`；常值通道返回 `0.0`（`!r.isNaN`） |
| `MMEmotionTests/AttentionTransitionTests.swift`（既有） | 兼容回归 | 零修改原样运行全部 9 个既有 US2 用例 + `IdleMotionLayerTests` 7 个用例 | 全部通过，证明 US2 行为与默认构造零回归 |

#### 7.2 完整门禁命令清单

```bash
# 1. 目标模块纯逻辑单元测试（macOS）
cd Packages/MiniMateKit && swift test --filter "MMCoreTests|MMPerceptionTests|MMEmotionTests"

# 2. Swift Package 全量单元测试（macOS）
cd Packages/MiniMateKit && swift test

# 3. 包内 iOS 条件编译验证（校验 ARKitPerceptionSource 与 MMAvatar 的 #if os(iOS) 分支）
cd Packages/MiniMateKit && xcodebuild -scheme MMPerception -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
cd Packages/MiniMateKit && xcodebuild -scheme MMEmotion -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
cd Packages/MiniMateKit && xcodebuild -scheme MMAvatar -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

# 4. App 模拟器编译验证（无签名，验证 SwiftUI / RealityKit / Bundle.module 资源接线）
xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# 5. 隐私与仓库基线校验
git status
git diff --stat
```

> 注：若在受限 CLI 沙盒内运行 `swift test` 触发 Clang ModuleCache 写权限报错，可加前缀 `CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache` 与 `--disable-sandbox` 仅用于验证。

#### 7.3 后续人工真机验收步骤（T038，不计入代码施工门禁）

代码闭环且通过独立复审后，由用户通过 `./scripts/deploy-ios.sh` 或 Xcode 真机安装执行 `specs/002-m1-presence/quickstart.md` 第三节（US3 / SC-003 / SC-004）：
1. 对小瓜微笑保持约 1 s：确认小瓜在 300–800 ms 后平滑浮现它自己的开心表情，约 1.5 s 后平滑恢复；
2. 立刻在 8 s 内再笑一次：确认不重复完整反应，仅保留柔和轻微愉悦感；等 8 s 后再笑重新触发完整回应；
3. 持续皱眉 ≥ 0.6 s：确认小瓜露出关切（`concerned`）而非模仿皱眉；
4. 做惊讶表情 ≥ 0.3 s：确认小瓜露出惊讶表情；
5. 调试面板启动“镜像检测（30 s）”，返回主界面对着小瓜做 30 s 自由表情（微笑、皱眉、鼓腮、张嘴、挑眉、嘟嘴等），30 s 结束后查看最大 `|r| < 0.3`；
6. 在调试面板读取 `M_reflex` 的 p50/p90 与 300–800 ms 命中率（目标 ≥ 90%），并可借“表情预设”区块微调满意后导出更新 `expression-presets.json`；全部验收确认后再由用户指令回写 `research.md` 并勾选 T030–T038。

---

### 8. 项目附加产出要求

- 本轮代码施工阶段**无需修改** `docs/tech-selection.md`、`specs/002-m1-presence/research.md` 或 `specs/002-m1-presence/tasks.md`。
- 若 T038 真机调参后 D5 阈值或表情预设权重有实测调整，再在验收收口时按宪章 III/V 同步写回 `research.md` 与 `FaceSignalDeriver.Config` / `expression-presets.json`。

---

### 9. 实施方偏差止损规则（固定条款）

- **可自决微调**：内部私有变量名、局部辅助函数拆分、注释与格式调整（不改变对外契约与测试预期）。
- **必须立即停工上报（严禁擅自绕过）**：
  1. 发现既定签名/契约与仓库现状冲突；
  2. 需要修改文件改动表之外的文件；
  3. 需要改写既有测试的预期断言；
  4. 需要放宽安全、只读或隔离红线；
  5. 实测发现新的第三方库或环境阻断问题。

---

## 复审闭环记录（实施后由 task-review-loop 追加）

- **闭环结果**：共 2 轮独立只读复审，**一致通过（阻断项 = 0）**
- **审查通道与模型**：单节点隔离只读审查员 `reviewer`（`gemini-4-neon-high` / Gemini 4 Neon (High)），两轮送审前后均通过 Git 快照指纹核验字节级零修改，闭环结束后已回收。
- **Round 1（需修改 — 发现 3 项阻断项 + 5 项非阻断建议）**：
  1. **阻断项 #1（已根治）**：`RuleBasedEmotionStateMachine.handle(_:)` 在人脸已丢失 ≥ 3 s 时先触发过期排程而非回 `.idle` → 在 `processScheduledReactions` 前增加 `if !features.isFaceTracked { _ = checkFaceLostToIdle(at: now) }`，并补齐经 `handle(at: 4.1, isFaceTracked: false)` 后 `pose(at: 4.1)` 的回归测试。
  2. **阻断项 #2（已根治）**：`ExpressionPreset.bundledDefaults` 原为计算属性，导致 `AvatarDebugPanel` 打开期间在 `@MainActor` 以 60 Hz 同步读盘 + JSON 解码 → 改为进程级线程安全惰性只读缓存 `public static let bundledDefaults: [EmotionTag: ExpressionPreset] = (try? loadBundled()) ?? [:]`。
  3. **阻断项 #3（已根治）**：`ReflexLatencyTracker.observePerception` 在同一表情排程窗口内短暂退出再重入时会覆写 `startedAt` 污染 `M_reflex` → 在 `PendingReflex` 中记录 `(key, scheduledTriggerAt)`，命中同一排程项时保持原 `startedAt`，并补齐 800 ms 窗口内重入回归测试（误差 `< 1e-6`）。
  4. **非阻断建议处置**：采纳 #1（`blendInMs`/`blendOutMs` 夹紧至 `0...60_000` 防 `Int64` 溢出）、#2（`NoMirroringTests` 30 s 序列在 `5.0–5.8 s` 增加冷却期重复微笑）、#3（`FaceSignalDeriverTests` 补充参数夹紧与等余量优先级裁决测试）；留档 #4（调试面板 JSON 编码缓存优化）与 #5（Speaking S-5 测试归口 US5 `T044`）。
- **Round 2（一致通过 — 阻断项 = 0）**：
  - 全部 3 项阻断项与 3 项已采纳非阻断建议核验通过，无新回归；
  - 独立复跑全量 `swift test`：**100 tests / 18 suites 全部通过**（`MMSecurityTests` 7、`MMPerceptionTests` 20、`MMEmotionTests` 49、`MMDiagnosticsTests` 14、`MMCoreTests` 10）；
  - 实施方非沙盒门禁实测：`xcodebuild` iOS Package（`MMPerception`、`MMEmotion`、`MMAvatar`）与 App Simulator（`MiniMate`）均 `BUILD SUCCEEDED`；
  - 收口策略严格遵守：未勾选 `tasks.md`、未修改 `research.md`、未 `git commit` / `git push`。

---

## 真机实测反哺与调参记录（2026-11-26）

Round 2 复审通过后，经用户真机实测定位并合入以下 3 项实质改进（均已补齐单测并重跑验证）：

1. **真机陷阱 · ARKit `BlendShapeLocation.rawValue` 使用 `_L`/`_R` 后缀**：
   - 现象：真机 `faceAnchor.blendShapes` 的 `location.rawValue` 实际返回 `"mouthSmile_L"` / `"browDown_L"` / `"eyeWide_L"` 等带下划线后缀键名，导致 `FaceSignalDeriver` 按标准 camelCase（`"mouthSmileLeft"` 等）查找时信号恒为 `0`。
   - 修复：在 `ARKitPerceptionSource.swift` 新增 52 键显式映射表 `canonicalNamesByLocation`（含 `_L`/`_R` 兜底规范化），统一输出标准 `Left`/`Right` 键名；同时在 `FaceSignalDeriver.rawSignals(from:)` 增加 `_L`/`_R` 兼容读取作为纵深防御，并在 `FaceSignalDeriverTests` 补充回归测试。
2. **真机 D5 阈值与 `concerned`/`surprised` 预设幅值调优**：
   - `FaceSignalDeriver.Config`：`frown` 调为 `enter: 0.38 / exit: 0.22 / minDuration: 0.50 s`；`surprise` 调为 `enter: 0.38 / exit: 0.22 / minDuration: 0.30 s`（`smile` 保持 `0.50 / 0.30 / 0.40 s` 不变）。
   - `expression-presets.json`：按用户真机实测满意值固化 `concerned`（`browInnerUp: 0.85, browDown: 0.35, mouthFrown: 0.75, eyeSquint: 0.30, eyeBlink: 0.20`）与 `surprised`（`jawOpen: 0.65, eyeWide: 0.90, browOuterUp: 0.66, browInnerUp: 0.50`）。
3. **预设热更新与调试面板「表情幅值微调」增强**：
   - `RuleBasedEmotionStateMachine` 新增 `public func updatePreset(_ preset: ExpressionPreset)` 支持运行时热更新单个情绪预设（并在 `ExpressionReactionTests` 补充单测）。
   - `AvatarScene` 持久化 `selectedPresetEmotion: EmotionTag?`（修复退出调试面板再进入重置回 `happy` 的问题），新增 `concernedEyeSquint` / `concernedEyeBlink` / `surprisedEyeWide` / `surprisedBrowOuterUp` 调参状态与 `setConcernedEyeTuning` / `setSurprisedEyeTuning` / `resetEyeTuning` 方法。
   - `AvatarDebugPanel` 在「表情预设」区块新增「还原（回到不做表情状态）」按钮，并新增「表情幅值微调（实时生效）」区块（默认初值自动读取 `expression-presets.json`）。
4. **最新全量验证基线**：
   - `swift test`：**102 tests / 18 suites 全部通过**（`MMSecurityTests` 7、`MMPerceptionTests` 21、`MMEmotionTests` 50、`MMDiagnosticsTests` 14、`MMCoreTests` 10）；
   - `xcodebuild` iOS Package 与 `MiniMate` iOS Simulator 均 `BUILD SUCCEEDED`。

