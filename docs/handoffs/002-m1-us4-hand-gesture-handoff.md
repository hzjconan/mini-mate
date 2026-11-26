# 002-m1-presence US4（T039–T042）“回应手势”实现级执行单

- **状态**：已完成验收与收口（真机 T043 验收通过、两阶段独立复审通过、已授权勾选 `tasks.md` / 更新 `research.md` 并本地提交）
- **Git 基线**：`main` @ `4a99980`（工作区干净；上游 M0、M1 US1 + Phase 1.4 精修、US2 T020–T029、US3 T030–T038 均已合入 `main`）
- **关键基线**：Swift `6.4`（`swift-tools-version: 6.2`，Swift 6 严格并发）、Xcode `27.0`（`27A266a`，`iPhoneOS27.0.sdk`）、iOS `26+` / macOS `26+`、Swift Testing（当前全量单测 `102/102` 全绿）、零第三方运行时依赖；素材 `minimate.usdz` + `minimate.actions.json`（含 `nod` 0.93 s、`wave` 1.27 s、`heart` 1.20 s + 爱心特效）与 8 个情绪预设（`happy`、`shy` 等）均已真机验收
- **拍板决议摘要**：**1A / 2A / 3A**（2026-11-26 用户按默认推荐项全选拍板：1A 仅 US4 T039–T042 代码与测试闭环；2A 任意非 Speaking 非冷却状态含 Idle 均响应手势；3A 增加 ARKitPerceptionSource 只读遥测属性与 AvatarDebugPanel 手势/热状态只读观察区）

> **红线声明**
> - 严格遵守 `.specify/memory/constitution.md`（最高优先级）与 `AGENTS.md`：
>   1. **陪伴而非镜像（NON-NEGOTIABLE）**：手势识别输出仅为语义事件 `GestureEvent`，必须经 `EmotionStateMachine` 映射为形象自己的情绪预设与动作，严禁绕过状态机直接驱动渲染；
>   2. **感知在本地，永不经过 LLM**：Vision 手部关节点检测仅跑在本地 `ARFrame.capturedImage` 上，不显示摄像头画面、不保存图像、无网络访问；
>   3. **纯逻辑测试先行（TDD）**：`HandGestureClassifier`、`ThermalGesturePolicy` 及状态机手势反应映射必须先写 Swift Testing 测试、确认失败再实现，全部可在 macOS 通过 `swift test` 确定性运行；
>   4. **可替换边界与简单优先**：保持 `PerceptionSource`、`EmotionStateMachine`、`AvatarRenderer` 协议与 `PerceptionFeatures` JSONL 编解码兼容；零新增第三方依赖（仅用系统 `Vision` / `ImageIO` / `ARKit` / `Foundation`）；
>   5. **隐私与密钥**：不写入任何 API Key，不提交 `Assets/voice-samples/*.wav`。
> - 设计阶段仅创建/维护本执行单，严禁改动任何业务代码、测试、Xcode 工程、配置、spec/tasks 或历史执行单。
> - 收口策略：未经用户明确确认验收，不得勾选 `specs/002-m1-presence/tasks.md`，不得修改 `research.md` 实测结论，不得 `git commit`，不得 `git push`。

---

## 上篇：面向用户决策

### 1. 任务目标与选择理由

- **本次任务**：`002-m1-presence` Phase 6 — **US4“回应手势”（T039–T042 代码与测试闭环）**。交付纯逻辑、尺度无关的 21 关节点手势分类器 `HandGestureClassifier`（支持挥手 `wave`、双手比心 `heart`、竖大拇指 `thumbsUp` 三种手势，带防摸脸/防抬手误触保护与边沿触发 P-3）及热降频频率策略 `ThermalGesturePolicy`；在 `ARKitPerceptionSource` 中以独立串行队列 + 单飞行防堆积机制按 12 Hz 抽帧运行 `VNDetectHumanHandPoseRequest`（监听 `ProcessInfo.thermalState` 在 `.serious` 降频至 5 Hz、`.critical` 暂停）；在 `RuleBasedEmotionStateMachine` 接入 3 种手势即时反应映射（`wave`→`happy`+`wave`、`heart`→`shy`+`heart`、`thumbsUp`→`happy`+`nod`，含 8 s 同类冷却 + 柔和底色增强、Speaking S-5 保护）；并在 `AvatarDebugPanel` 补充只读手势计数与热状态观测区，便于随后直接在真机执行 Quickstart §4（T043）验收 `SC-005`。
- **为何优先做它（剩余候选任务横向对比）**：
  1. **首选 · `002-m1-presence` Phase 6 / US4（P2，回应手势 T039–T042）**：
     - 优先级高于 US5（P2 > P3），且前置依赖 100% 就绪：`wave`/`heart`/`nod` 动作与 `heart` 爱心特效（US1）、`ARKitPerceptionSource.setGestureRate` 与 `GestureEvent`（US2）、`happy`/`shy` 表情预设与冷却反应队列（US3）全部到位，零外部阻塞；
     - 立即释放真机最直观的双向互动体验（挥手、比心冒爱心、点赞点头），同时把 Vision 手部追踪负载与热降频纳入主链路，为后续 Phase 8 的 10 分钟稳定性压力验收（SC-006）扫清前置；
     - US4 包含 Vision 摄像头方向、手势几何阈值与防误触（SC-005 ≥ 8/10 准确、1 分钟日常动作 ≤ 1 次误触）等强真机验证项，独立成单延续 US2/US3 的小步快跑节奏，风险可控。
  2. **次选 · `002-m1-presence` Phase 7 / US5（P3，对话阶段状态 T044–T047）**：
     - 优先级为 P3，且纯属状态机对话事件 + 口型层 + 调试注入（零摄像头/Vision 风险），紧随 US4 之后收口 M1 功能非常顺滑；与 US4 合并会导致单次执行单同时跨越 Vision 异步管线与对话状态/口型合成两套面，增大排障面（下方提供 `1B` 合并选项由用户拍板）。
  3. **暂缓 · `003-m2-voice-conversation` Phase 1–3（M2a 厂商验证）**：
     - 需人工核查云端实时语音厂商文档、配置云端 API Key 环境变量并自录 9 条个人语气样本（`Assets/voice-samples/*.wav`）。目前 M1 仅剩 US4、US5 与 Polish，优先完成 M1 本地陪伴完整闭环更高效。
- **摸底关键发现（3 个最值得知情的技术事实/风险）**：
  1. **Swift 6 严格并发 + `ARFrame` 缓冲池防卡死（已用本机 `iPhoneOS27.0.sdk` 实测确认）**：实测 `CVPixelBuffer`（`CVBuffer`）在 Swift 6 下非 `Sendable`；且 `ARSession` 回调在 60 Hz `sessionQueue` 上，既**严禁**同步跑 Vision（每次 10–30 ms 会直接拖垮 60 fps 人脸追踪和 `M_track`），也**严禁**跨队列持有 `ARFrame`（会耗尽 ARKit 帧池导致卡帧）。必须仅抽取 `frame.capturedImage` 经 `UncheckedBox` 投递至独立串行 `gestureQueue`，配合 `isVisionInFlight` 单飞行丢帧，并由 60 Hz `handleFrame` 统一消费 `pendingGesture`，确保时间戳严格单调且零数据竞争。
  2. **模块单向依赖边界（`plan.md` 文字与实际 Target 拓扑的偏差）**：`plan.md:124` 写“手势阈值集中在 `ReactionRules`”，但 `Package.swift:23-24` 中 `MMEmotion` 依赖 `MMPerception`（不可反向依赖）。沿用 US3 `FaceSignalDeriver.Config` 范式，手势几何阈值必须定义在 `MMPerception` 的 `HandGestureClassifier.Config`，冷却/反应时长保留在 `MMEmotion` 的 `ReactionRules`。
  3. **Vision 常见误触与双检陷阱**：`VNDetectHumanHandPoseRequest` 设 `maximumHandCount = 2` 时，偶发将同一只手重复检出为 2 个高度重叠的观测，若比心只判“双指尖距离近”会造成单手误触比心；且原始 `wrist.x` 帧间差在 12 Hz 静止举手时存在 ±1% 抖动。本方案通过**手掌尺度（`wrist`→`middleMCP`）归一化 + 双手腕最小间距 `>= 0.60 * avgScale` + 滞回摆幅翻转检测 + 竖直移动排除**系统性阻断摸脸、抬手与单手双检误触。

### 2. 待用户拍板的决策清单

<!-- 用户回复如 "1A 2A 3A" 即可。定稿后将结论固化进下篇正文，清理落选分支。 -->

1. **任务范围粒度**
   - **1A（推荐）**：聚焦 **M1 Phase 6 / US4 回应手势（T039–T042 代码与测试闭环，不含 T043 人工真机验收）**；US5 留作下一份执行单。
     - *理由*：延续 US2/US3 节奏，聚焦 Vision 异步管线、防误触算法与热降频，便于真机单独验收 SC-005 并调优阈值。
   - **1B**：本次合并 **US4（T039–T042）+ US5（T044–T046）** 一次性完成 M1 剩余全部代码。
     - *权衡*：减少一次执行单往返，但单轮改动横跨 `MMPerception`（Vision）与 `MMEmotion`（手势 + 对话状态 + 口型层）及两块调试 UI，复审与排障复杂度明显上升。

2. **Idle 状态下收到明确手势时的状态机行为**
   - **2A（推荐）**：严格按 `contracts/emotion-state-machine.md` 第 34 行（`任意（非 Speaking） | 感知：gesture | 不在冷却 | Reacting`），**在 `.idle`、`.attending`、`.listening`、`.thinking` 或其他 `.reacting` 状态下（非 Speaking、非冷却）均立即进入 `.reacting`** 播放手势回应动作与表情，1.5 s 后回到原底层状态（若人脸持续丢失 ≥ 3 s 则回 `.idle`）。
     - *理由*：与契约 100% 一致，且解决用户刚抬手挥手（未满 200 ms 注视）或双手比心短暂遮挡面部时漏响应的问题。
   - **2B**：仅在 `.attending`（或 `.reacting`）且 `isFaceTracked == true` 时响应手势，`.idle` 期间忽略手势。
     - *权衡*：可进一步压低未看屏幕时路过动作的误触，但偏离契约原文且比心遮脸时可能漏触发。

3. **调试面板手势与热状态观测区**
   - **3A（推荐）**：在 `ARKitPerceptionSource` 暴露轻量只读遥测属性（`effectiveGestureRateHz`、`lastDetectedHandCount`、`currentThermalState`，不改动 `PerceptionSource` 协议与 `PerceptionFeatures` JSONL 结构），并在 `AvatarDebugPanel` 增加精简的**“手势与热状态（US4 / SC-005）”只读观察区**（实时手数、最近手势与置信度、挥手/比心/点赞累计次数 + 清零按钮、热状态与实际采样率 Hz）。
     - *理由*：T043 真机需要做“各 10 次触发统计 + 1 分钟误触计数”，有只读计数器与实时手数可大幅降低真机验证和排查前置方向/热降频的成本，且严格零图像预览。
   - **3B**：仅做底层感知与状态机接线，不修改 `AvatarScreen` / `AvatarDebugPanel`。
     - *权衡*：App 层零改动，但 T043 需纯肉眼统计且真机排查手势识别状态较黑盒。

---

## 下篇：面向实施方的零歧义施工图

> 本施工图已按拍板决议 **1A / 2A / 3A** 锁定。

### 3. 现状锚点与环境陷阱预警

#### 3.1 现有代码锚点

| 模块/符号 | 精确位置 | 职责与复用/约束说明 |
| :--- | :--- | :--- |
| `Package.swift` targets | `Packages/MiniMateKit/Package.swift:19-31` | `MMPerception` 依赖 `MMCore`；`MMEmotion` 依赖 `MMCore`、`MMPerception`；`MMPerceptionTests` 依赖 `MMPerception`、`MMCore`；`MMEmotionTests` 依赖 `MMEmotion`、`MMAvatar`、`MMCore`、`MMPerception`。**本轮无需修改 `Package.swift` 或 `project.pbxproj`** |
| `PerceptionFeatures` / `GestureKind` / `GestureEvent` | `Packages/MiniMateKit/Sources/MMPerception/PerceptionFeatures.swift:4-78` | 第 14 行已定义 `gesture: GestureEvent?`；第 62–78 行已定义 `GestureKind`（`wave`/`heart`/`thumbsUp`）与 `GestureEvent(kind:confidence:timestamp:)`，**直接复用，严禁改动字段名与 Codable 结构**（`ScriptedPerceptionSourceTests.swift:62` 已测试其编解码） |
| `PerceptionSource` | `Packages/MiniMateKit/Sources/MMPerception/PerceptionSource.swift:1-20` | 第 13 行已定义 `func setGestureRate(_ hz: Double)`，保持协议零修改 |
| `ARKitPerceptionSource` | `Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift:9-360` | 已有 `UncheckedBox<T>`（:9-11）、`MutableState.gestureRateHz = 12.0`（:25）、`setGestureRate(_:)`（:61-64）；当前第 204 与 224 行硬编码 `gesture: nil`；本轮接入 12 Hz Vision 异步抽帧、`ThermalGesturePolicy` 热降频与生命周期清理 |
| `FaceSignalDeriver` | `Packages/MiniMateKit/Sources/MMPerception/FaceSignalDeriver.swift:4-276` | 同模块纯逻辑状态机范式（`Config` 夹紧、`+ 1e-9` 浮点时长边界、`reset()`、非有限时间防御），`HandGestureClassifier` 沿用其代码风格 |
| `ReactionKey` / `ReactionRules` | `Packages/MiniMateKit/Sources/MMEmotion/ReactionRules.swift:4-47` | `ReactionKey` 已包含 `.wave`、`.heart`、`.thumbsUp`（:8-10）；`ReactionRules` 已有 `reactionDuration = .milliseconds(1500)` 与 `cooldown = 8`，直接复用 |
| `RuleBasedEmotionStateMachine` | `Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift:86-804` | 已实现 US2 注意力与 US3 表情反应、`cooldownBoost`（2A）、`speakingOverlay`（S-5）、`fadingLayers`、`.shy` 轻微低头（:270-272, :372-374）、`processScheduledReactions` 动作防纯表情打断（:559-563）；本轮在 `handle(_ features:)` 增量接入 `features.gesture` 立即反应逻辑，既有 `AttentionTransitionTests`（9 用例）与 `ExpressionReactionTests`（7 用例）零破坏 |
| `ReflexLatencyTracker` | `Packages/MiniMateKit/Sources/MMEmotion/ReflexLatencyTracker.swift:74-79` | 仅统计 `reaction.action == nil` 的纯表情 `.reacting`，天然忽略带动作的手势反应，无需修改 |
| `RealityKitAvatarRenderer` & `minimate.actions.json` | `Packages/MiniMateKit/Sources/MMAvatar/RealityKitAvatarRenderer.swift:349-444,527-535`; `App/MiniMate/Resources/Avatar/minimate.actions.json:7-22` | 3 个手势动作时长均小于 1.5 s（`nod` 0.93 s、`wave` 1.27 s、`heart` 1.20 s + 爱心特效 1.30 s）；动作播完自动归零并平滑恢复头部追踪。**本轮严禁修改 `MMAvatar` 与 3D 资产** |
| `AvatarScene` / `AvatarScreen` | `App/MiniMate/Screens/AvatarScreen.swift:35-56,248-346` | `handleIncomingFeatures` 接收每帧 `PerceptionFeatures`；本轮增量记录 `lastGestureEvent`、`gestureEventCounts`、`thermalState`、`effectiveGestureRateHz`、`detectedHandCount` |
| `AvatarDebugPanel` | `App/MiniMate/Screens/Debug/AvatarDebugPanel.swift:13-106` | 本轮在“状态与感知”下方增量插入“手势与热状态（US4 / SC-005）”只读观察区，其余全部既有分区零改动 |

#### 3.2 环境与平台实测陷阱预警

1. **陷阱 1 · Swift 6 下 `CVPixelBuffer` 非 `Sendable`，且跨队列不可持有 `ARFrame`（已用本机 `iPhoneOS27.0.sdk` + `swiftc -swift-version 6` 实测确认）**：
   - 表现：直接在 `gestureQueue.async` 闭包捕获 `frame.capturedImage` 会触发 Swift 6 并发警告/错误（`class 'CVBuffer' does not conform to the 'Sendable' protocol`）；若把整个 `ARFrame` 传给异步队列会导致 ARKit 帧缓冲池耗尽、人脸追踪卡顿。
   - **必须采用的写法**：在 `handleFrame` 内仅提取 `let pixelBuffer = frame.capturedImage` 并用已有的 `UncheckedBox(value: pixelBuffer)` 包装后投递至专用串行 `gestureQueue`；同时用锁内 `isVisionInFlight: Bool` 做单飞行丢帧（任何时刻最多 1 帧在跑 Vision），确保 `ARFrame` 在 `didUpdate` 返回时立刻释放。
2. **陷阱 2 · 前置 TrueDepth 摄像头 `ARFrame.capturedImage` 竖屏方向与 Vision 坐标系**：
   - 表现：`ARFaceTrackingConfiguration` 输出的 `ARFrame.capturedImage` 始终为传感器原生横向缓冲区，直接传给 `VNImageRequestHandler(cvPixelBuffer:options:)`（默认 `.up`）会导致竖屏下所有手部关节点旋转 90°，点赞 `+y` 朝上与挥手 `x` 水平判定全错。
   - **必须采用的写法**：调用 `VNImageRequestHandler(cvPixelBuffer: boxedBuffer.value, orientation: handPoseOrientation, options: [:])`，默认 `handPoseOrientation: CGImagePropertyOrientation = .leftMirrored`（EXIF 5：竖屏前置自拍 upright + 水平镜像；Vision 归一化坐标 `(0, 0)` 左下、`(1, 1)` 右上、`+y` 向上，且水平镜像对 `wave`/`heart`/`thumbsUp` 三种规则均数学不变）。
3. **陷阱 3 · `VNDetectHumanHandPoseRequest` 双手模式下的单手重复检出与低置信度噪点**：
   - 表现：设 `maximumHandCount = 2` 时，Vision 偶发对同一只手返回 2 个位置几乎重合的 `VNHumanHandPoseObservation`，导致比心规则误判为“两手贴近”；此外被遮挡关节点仍可能返回 `confidence == 0` 的 `(0, 0)` 坐标。
   - **必须采用的写法**：① 转换 `VNHumanHandPoseObservation` 时丢弃 `confidence < config.minJointConfidence`（默认 `0.3`）或坐标非有限的关节点；② 比心判定强制要求 `dist(wristA, wristB) >= avgScale * 0.60` 且 `dist(indexMCP_A, indexMCP_B) > dist(indexTipA, indexTipB)`，彻底杜绝单手双检与双手合十误触。
4. **陷阱 4 · `MMPerception` 禁止反向依赖 `MMEmotion`**：
   - 表现：`Package.swift:23-24` 中 `MMEmotion` 依赖 `MMPerception`，若按 `plan.md:124` 字面将手势几何阈值放进 `MMEmotion.ReactionRules` 并在 `HandGestureClassifier` 中 `import MMEmotion`，将触发循环依赖编译失败。
   - **必须采用的写法**：手势几何/时长阈值集中在 `MMPerception.HandGestureClassifier.Config`；状态机反应时长与 8 s 冷却复用 `MMEmotion.ReactionRules`。
5. **陷阱 5 · `NotificationCenter` 热状态观察者与跨 session 竞态**：
   - 表现：① `ARKitPerceptionSource.stop()` 或 `deinit` 若未移除 `ProcessInfo.thermalStateDidChangeNotification` 观察者会泄漏；② `stop()` 后尚未结束的 `gestureQueue` 回调若未校验 `runGeneration`，可能把旧会话的手势写进新会话。
   - **必须采用的写法**：在 `MutableState` 维护 `runGeneration: UInt64`（每次 `start()`/`stop()`/中断递增）与 `thermalObserver: UncheckedBox<NSObjectProtocol>?`；`gestureQueue` 回调回写 `pendingGesture` 前必须校验 `s.isRunning && !s.isInterrupted && s.runGeneration == gen`；`stop()` 与 `deinit` 均执行 `NotificationCenter.default.removeObserver`。
6. **陷阱 6 · 沙盒内运行 `swift test` 的 Clang Module Cache 路径**：
   - 在受限沙盒内运行 `swift test` 须带 `CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox`；本机常规终端直接 `cd Packages/MiniMateKit && swift test` 即可。
7. **陷阱 7 · `Swift.Clock` 命名冲突（延续 US2/US3）**：
   - 所有新增测试与源码引用 `MMCore` 时钟协议时均须显式写 `any MMCore.Clock`。

---

### 4. 改动范围表与明确不做清单（Non-Goals）

#### 4.1 文件改动表

| 文件路径 | 操作 | 精确职责 |
| :--- | :--- | :--- |
| `Packages/MiniMateKit/Tests/MMPerceptionTests/HandGestureClassifierTests.swift` | 新增 | **T039（先写测试）**：合成 21 关节点序列测试 `wave`/`heart`/`thumbsUp` 正例、尺度无关性、P-3 边沿触发与释放重触发、负样本（抬手/摸脸/静止抖动/单次晃手/合十/单手双检/低置信度/非有限时间）以及 `ThermalGesturePolicy` 热降频测试 |
| `Packages/MiniMateKit/Sources/MMPerception/ThermalGesturePolicy.swift` | 新增 | **T041 纯逻辑部分**：`ProcessInfo.ThermalState` → 手势最大采样率策略（`.nominal`/`.fair` 不限，`.serious` ≤ 5 Hz，`.critical` = 0 Hz），可在 macOS 与 iOS 共享与单测 |
| `Packages/MiniMateKit/Sources/MMPerception/HandGestureClassifier.swift` | 新增 | **T040**：定义 `HandJointName`、`HandJointPoint`、`HandPoseFrame`、`HandGestureClassifier.Config` 与 `HandGestureClassifier`（3 种手势几何规则、防误触保护、边沿触发 P-3、`reset()`） |
| `Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift` | 修改 | **T041（iOS only）**：接入 `gestureQueue` 12 Hz 单飞行 `VNDetectHumanHandPoseRequest`（`maximumHandCount = 2`、`.leftMirrored` 方向）、`ProcessInfo.thermalStateDidChangeNotification` 降频监听、`pendingGesture` 统一出帧消费，以及只读遥测属性（`effectiveGestureRateHz`、`lastDetectedHandCount`、`currentThermalState`） |
| `Packages/MiniMateKit/Tests/MMEmotionTests/GestureReactionTests.swift` | 新增 | **T042 测试（先写测试）**：验证 `wave`→`happy`+`wave`、`heart`→`shy`+`heart`（含低头因子）、`thumbsUp`→`happy`+`nod` 立即进入 `.reacting`（0 延迟 ≤ 300 ms）、8 s 冷却 + 2A 柔和底色增强、Idle/Attending/被打断/无脸遮挡场景、Speaking S-5 保护、不同手势打断旧反应与 `ReflexLatencyTracker` 不受手势污染 |
| `Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift` | 修改 | **T042**：在 `handle(_ features:)` 接入 `features.gesture` 立即反应映射与 S-2/S-5/2A 逻辑；复用 `snapshotCurrentReactingIfNeeded(at:)` 共享淡出逻辑 |
| `App/MiniMate/Screens/AvatarScreen.swift` | 修改 | **3A 观测接线**：`AvatarScene` 新增 `lastGestureEvent`、`gestureEventCounts`、`thermalState`、`effectiveGestureRateHz`、`detectedHandCount` 与 `resetGestureCounters()`，在 `handleIncomingFeatures` / `stopPerception` / `handleBackground` 同步刷新与清理 |
| `App/MiniMate/Screens/Debug/AvatarDebugPanel.swift` | 修改 | **3A 调试 UI**：新增“手势与热状态（US4 / SC-005）”只读观察区（手数、最近手势、各手势累计触发次数、热状态、实际采样率 Hz、清零计数按钮） |

#### 4.2 明确不做清单（Non-Goals）

- **严禁修改**：
  - `Packages/MiniMateKit/Package.swift` 与 `App/MiniMate.xcodeproj/project.pbxproj`；
  - `Packages/MiniMateKit/Sources/MMPerception/PerceptionFeatures.swift` 与 `PerceptionSource.swift`（保持既有协议与 JSONL 契约不变）；
  - `Packages/MiniMateKit/Sources/MMAvatar/*`、`App/MiniMate/Resources/Avatar/*`、`Assets/avatar/*`；
  - `Packages/MiniMateKit/Sources/MMEmotion/Resources/expression-presets.json`、`ReflexLatencyTracker.swift`、`MirrorCorrelationEvaluator.swift`；
  - 全部既有测试文件（`AttentionTransitionTests.swift`、`ExpressionReactionTests.swift`、`NoMirroringTests.swift`、`FaceSignalDeriverTests.swift` 等）的既有断言；
  - `specs/002-m1-presence/tasks.md`、`specs/002-m1-presence/research.md`、`docs/tech-selection.md`（验收确认前不勾选、不回写）。
- **本次不实现**：
  - US5 对话事件完整状态转换（`Listening`/`Thinking`/`Speaking` 事件处理、口型层、调试面板对话事件注入）；
  - Phase 8 稳定性压测与主观验收（T048–T050）；
  - T043 人工真机验收记录；
  - 003（M2 语音对话）或 004（M3 记忆/离线）的任何代码。

---

### 5. 精确接口与行为契约

#### 5.1 `ThermalGesturePolicy`（`MMPerception`）
- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMPerception/ThermalGesturePolicy.swift`
  ```swift
  import Foundation

  /// 热状态驱动的手势采样频率上限策略（对应 plan.md 热降频与 contracts/perception-source.md P-4）。
  public enum ThermalGesturePolicy: Sendable {
      /// 各热状态允许的最大手势检测频率（Hz）：
      /// - `.nominal` / `.fair` → `15.0`
      /// - `.serious` → `5.0`
      /// - `.critical` → `0.0`（暂停手势，保证人脸追踪优先）
      public static func maxRate(for state: ProcessInfo.ThermalState) -> Double

      /// 结合外部配置频率（先夹紧至 `0...15`，非有限按 `0`）与当前热状态，返回实际生效频率（Hz）。
      public static func effectiveRate(
          configuredHz: Double,
          thermalState: ProcessInfo.ThermalState
      ) -> Double
  }
  ```
- **边界口径**：
  - `configuredHz` 为 `NaN` / `±infinity` / `< 0` → 返回 `0.0`；
  - `configuredHz > 15` → 夹紧至 `15.0` 后再与 `maxRate(for:)` 取 `min`；
  - `@unknown default` 热状态保守按 `5.0` 处理。

#### 5.2 `HandGestureClassifier`（`MMPerception` — T040）
- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMPerception/HandGestureClassifier.swift`
  ```swift
  import Foundation

  /// Vision 21 个手部关节点的平台无关枚举标识。
  public enum HandJointName: String, CaseIterable, Codable, Sendable, Hashable {
      case wrist
      case thumbCMC, thumbMP, thumbIP, thumbTip
      case indexMCP, indexPIP, indexDIP, indexTip
      case middleMCP, middlePIP, middleDIP, middleTip
      case ringMCP, ringPIP, ringDIP, ringTip
      case littleMCP, littlePIP, littleDIP, littleTip
  }

  /// Vision 归一化坐标系中的单个关节点：x ∈ [0, 1]（左→右），y ∈ [0, 1]（下→上）。
  public struct HandJointPoint: Codable, Sendable, Equatable {
      public let x: Float
      public let y: Float
      public let confidence: Float

      public init(x: Float, y: Float, confidence: Float = 1.0)
  }

  /// 单只手的关节点快照。
  public struct HandPoseFrame: Codable, Sendable, Equatable {
      public let joints: [HandJointName: HandJointPoint]

      public init(joints: [HandJointName: HandJointPoint])
  }

  /// 纯逻辑规则手势分类器（支持挥手、双手比心、竖大拇指；尺度无关；严格边沿触发 P-3）。
  public struct HandGestureClassifier: Sendable, Equatable {
      public struct Config: Sendable, Equatable {
          /// 有效关节点最低置信度（默认 0.30）。
          public var minJointConfidence: Float
          /// 最小手掌尺度 dist(wrist, middleMCP)（默认 0.03，过滤远景噪声）。
          public var minPalmScale: Float

          // 挥手（wave）
          /// 统计方向翻转的时间窗（默认 1.5 s，对应 plan.md）。
          public var waveWindowDuration: TimeInterval
          /// 窗内最少水平方向翻转次数（默认 3 次 = 2 个完整来回，对应 spec.md & plan.md）。
          public var waveMinReversals: Int
          /// 单次有效摆动最小水平位移（归一化坐标下限，默认 0.045）。
          public var waveMinNormalizedAmplitude: Float
          /// 单次有效摆动相对手掌尺度的最小比例（默认 0.45）。
          public var waveMinPalmScaleRatio: Float
          /// 摆动水平/垂直分量比下限 |dx| / max(|dy|, ε)（默认 0.80，过滤竖直抬手）。
          public var waveMinHorizontalRatio: Float
          /// 张开手掌中断超过此时长后重置挥手轨迹（默认 0.35 s）。
          public var waveGapResetDuration: TimeInterval
          /// 挥手触发后需静默/收手达到此时长才允许再次触发（默认 0.45 s）。
          public var waveReleaseDuration: TimeInterval

          // 比心（heart）
          /// 双手比心需持续保持的最短时长（默认 0.50 s，对应 spec.md）。
          public var heartHoldDuration: TimeInterval
          /// 两手拇指尖/食指尖间距相对平均手掌尺度的上限（默认 0.75）。
          public var heartTipMaxDistanceRatio: Float
          /// 食指尖中点高于拇指尖中点的最小比例（默认 0.25，过滤双手平合/拍手）。
          public var heartVerticalSeparationRatio: Float
          /// 两手腕最小间距相对平均手掌尺度下限（默认 0.60，防单手双检误触）。
          public var heartMinWristSeparationRatio: Float
          /// 两手腕最大间距相对平均手掌尺度上限（默认 4.50）。
          public var heartMaxWristSeparationRatio: Float

          // 点赞（thumbsUp）
          /// 点赞需持续保持的最短时长（默认 0.50 s，对应 spec.md）。
          public var thumbsUpHoldDuration: TimeInterval
          /// 拇指方向向量 y 分量占比下限（默认 0.75，约 ±41° 朝上锥角）。
          public var thumbsUpMinUpwardCosine: Float

          // 通用防抖与边沿释放
          /// 静态保持期间允许的短时丢帧容忍窗口（默认 0.15 s，约 1–2 帧 Vision 抖动）。
          public var holdDropoutTolerance: TimeInterval
          /// 静态手势结束后需持续不匹配此时长才释放边沿锁存（默认 0.25 s）。
          public var holdReleaseDuration: TimeInterval

          public init(
              minJointConfidence: Float = 0.30,
              minPalmScale: Float = 0.03,
              waveWindowDuration: TimeInterval = 1.5,
              waveMinReversals: Int = 3,
              waveMinNormalizedAmplitude: Float = 0.045,
              waveMinPalmScaleRatio: Float = 0.45,
              waveMinHorizontalRatio: Float = 0.80,
              waveGapResetDuration: TimeInterval = 0.35,
              waveReleaseDuration: TimeInterval = 0.45,
              heartHoldDuration: TimeInterval = 0.50,
              heartTipMaxDistanceRatio: Float = 0.75,
              heartVerticalSeparationRatio: Float = 0.25,
              heartMinWristSeparationRatio: Float = 0.60,
              heartMaxWristSeparationRatio: Float = 4.50,
              thumbsUpHoldDuration: TimeInterval = 0.50,
              thumbsUpMinUpwardCosine: Float = 0.75,
              holdDropoutTolerance: TimeInterval = 0.15,
              holdReleaseDuration: TimeInterval = 0.25
          )

          public static let defaults = Config()
      }

      public let config: Config
      /// 当前处于边沿锁存中的手势（手势未结束前保持非 nil，供诊断/单测观察）。
      public private(set) var latchedGesture: GestureKind?

      public init(config: Config = .defaults)

      /// 输入单帧检测到的 0–2 只手关节点与时间戳（秒）；仅在新手势首次成立时返回一次 `GestureEvent`（P-3）。
      public mutating func update(hands: [HandPoseFrame], at timestamp: TimeInterval) -> GestureEvent?

      /// 清空全部保持计时器、挥手轨迹与边沿锁存状态。
      public mutating func reset()
  }
  ```
- **精确几何与判定口径（严禁凭感觉偏离）**：
  1. **关节点过滤与手掌尺度**：
     - 仅保留 `x.isFinite && y.isFinite && confidence.isFinite && confidence >= config.minJointConfidence` 的关节点；
     - `palmScale` = 若 `wrist` 与 `middleMCP` 均有效则为 `dist(wrist, middleMCP)`；否则取所有有效 `dist(wrist, {index,middle,ring,little}MCP)` 的平均值；无有效值或 `palmScale < config.minPalmScale` 则忽略该只手。
  2. **四指伸直 / 弯曲判定**（分别对 `index`、`middle`、`ring`、`little` 四指，记 `mcp`、`pip`、`tip`）：
     - 若 `wrist`、`mcp`、`pip`、`tip` 均有效：
       - **伸直（extended）**：`dist(tip, wrist) >= dist(pip, wrist) * 1.15` && `dist(tip, mcp) >= palmScale * 0.55` && `cosAngle(pip - mcp, tip - pip) >= 0.45`；
       - **弯曲（curled）**：`!extended` && (`dist(tip, wrist) <= dist(pip, wrist) * 1.10` || `dist(tip, mcp) <= palmScale * 0.72`) && `dist(tip, mcp) <= palmScale * 0.95`。
  3. **比心（`heart`）单帧匹配**：
     - 要求有效手数 `>= 2`，对配对 `(A, B)` 校验：
       - 两手均含有效 `wrist`、`thumbTip`、`indexTip`、`indexMCP`；令 `avgScale = (scaleA + scaleB) * 0.5`；
       - `dist(thumbTipA, thumbTipB) <= avgScale * config.heartTipMaxDistanceRatio`；
       - `dist(indexTipA, indexTipB) <= avgScale * config.heartTipMaxDistanceRatio`；
       - `((indexTipA.y + indexTipB.y) * 0.5) - ((thumbTipA.y + thumbTipB.y) * 0.5) >= avgScale * config.heartVerticalSeparationRatio`；
       - `dist(wristA, wristB) >= avgScale * config.heartMinWristSeparationRatio` && `dist(wristA, wristB) <= avgScale * config.heartMaxWristSeparationRatio`；
       - `dist(indexMCP_A, indexMCP_B) > dist(indexTipA, indexTipB)`（双食指呈心形弧顶向内收拢，排除平行双指/拍手）；
     - 置信度取两手 8 个参与关节点的平均置信度（夹紧 `[0, 1]`）。
  4. **点赞（`thumbsUp`）单帧匹配**：
     - 任意单只有效手满足（当且仅当本帧未匹配 `heart`）：
       - 有效 `wrist`、`thumbCMC`、`thumbMP`、`thumbIP`、`thumbTip`、`indexMCP`；
       - 拇指伸直：`dist(thumbTip, thumbCMC) >= palmScale * 0.65` && `dist(thumbTip, thumbMP) >= palmScale * 0.35` && `dist(thumbTip, wrist) > dist(thumbIP, wrist)` && `dist(thumbTip, indexMCP) >= palmScale * 0.55`；
       - 拇指朝上：令 `v = (thumbTip.x - thumbMP.x, thumbTip.y - thumbMP.y)`，要求 `v.y > 0`、`v.y / hypot(v.x, v.y) >= config.thumbsUpMinUpwardCosine`、`thumbTip.y > thumbCMC.y`，且 `thumbTip.y >= maxVisibleFingerMCP_Y + palmScale * 0.15`；
       - 其余四指弯曲：四指中有效可见手指 `>= 3` 根，**全部**有效可见手指均满足 `curled == true` 且 `extended == false`；
     - 置信度取参与关节点的平均置信度（夹紧 `[0, 1]`）。
  5. **挥手（`wave`）滑动窗口翻转判定**：
     - 张开竖直手掌（`openPalm`）条件：四指中至少 **3** 根满足 `extended == true`，且所有伸直指尖的平均 `y` 满足 `meanExtendedTipY >= wrist.y + palmScale * 0.40`（排除自然垂手）；
     - 若存在多只张开手掌，选与上次记录手腕位置距离最近的一只（防止双手跳变伪造摆动）；
     - 若本帧无 `openPalm`：当距上次 `openPalm` 时间 `> config.waveGapResetDuration` 时清空挥手摆动状态与翻转时间戳列表；
     - 若本帧有 `openPalm`（记录 `wrist`、`palmScale`、`timestamp`）：
       - 令 `minSwing = max(config.waveMinNormalizedAmplitude, palmScale * config.waveMinPalmScaleRatio)`；
       - 维护当前极值锚点 `anchorPoint`、当前已确立方向 `direction: Int`（`-1` 左 / `+1` 右 / `0` 未确立）与历史翻转时间戳 `reversalTimestamps: [TimeInterval]`；
       - 每次更新先淘汰 `timestamp - t > config.waveWindowDuration` 的旧翻转；
       - 当 `direction == 0`：若 `|wrist.x - anchorPoint.x| >= minSwing` 且 `|wrist.x - anchorPoint.x| >= |wrist.y - anchorPoint.y| * config.waveMinHorizontalRatio`，确立初始方向 `direction = wrist.x > anchorPoint.x ? +1 : -1` 并更新 `anchorPoint = wrist`；若仅大幅竖直移动（`|dy|` 主导），将 `anchorPoint` 平移至当前 `wrist`（防止抬手后小幅横移误计数）；
       - 当 `direction == +1`：若 `wrist.x > anchorPoint.x` 则推进右极值 `anchorPoint = wrist`；若 `anchorPoint.x - wrist.x >= minSwing` 且 `|anchorPoint.x - wrist.x| >= |wrist.y - anchorPoint.y| * config.waveMinHorizontalRatio`，记录一次向右→向左翻转（`reversalTimestamps.append(timestamp)`）、切换 `direction = -1`、`anchorPoint = wrist`；
       - 当 `direction == -1`：对称处理；
       - 当 `reversalTimestamps.count >= config.waveMinReversals` 时，挥手条件成立！
  6. **保持容错、优先级与边沿触发（P-3）**：
     - 时间戳非有限或严格回退（`timestamp < lastTimestamp`）时直接返回 `nil`，不破坏状态；
     - 静态保持（`heart`、`thumbsUp`）：分别维护 `startedAt` 与 `lastMatchedAt`；未匹配但 `timestamp - lastMatchedAt <= config.holdDropoutTolerance` 时保留 `startedAt`（容忍 1 帧 Vision 抖动）；超过容忍窗口则清零 `startedAt`；匹配时若 `timestamp - startedAt + 1e-9 >= holdDuration` 则视为成立；
     - 边沿锁存释放：
       - 若 `latchedGesture == .heart`（或 `.thumbsUp`）：连续不匹配时长 `>= config.holdReleaseDuration` 时释放 `latchedGesture = nil`；
       - 若 `latchedGesture == .wave`：无有效新挥手活动（无 `openPalm` 或无新翻转）持续 `>= config.waveReleaseDuration` 时释放 `latchedGesture = nil`；
       - 若出现与 `latchedGesture` **不同**的新成立手势（例如挥完手立刻点赞），允许立即切换并触发新手势；
     - 同帧优先级：`heart` > `thumbsUp` > `wave`；
     - 触发 `.wave` 时立刻清空 `reversalTimestamps` 并置 `direction = 0`、`anchorPoint = wrist`，防止旧窗口翻转重复触发。

#### 5.3 `ARKitPerceptionSource` Vision 12 Hz 抽帧与热降频（`MMPerception` — T041，iOS only）
- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift`
  ```swift
  // 保持既有调用方 100% 兼容，仅追加带默认值的参数：
  public init(
      clock: any MMCore.Clock = SystemClock(),
      positionFilter: OneEuroFilter3D = OneEuroFilter3D(minCutoff: 3.5, beta: 2.5, dCutoff: 1.0),
      lookingDetector: LookingAtScreenDetector = LookingAtScreenDetector(),
      signalDeriver: FaceSignalDeriver = FaceSignalDeriver(),
      gestureClassifier: HandGestureClassifier = HandGestureClassifier(),
      handPoseOrientation: CGImagePropertyOrientation = .leftMirrored
  )

  /// 当前结合热状态后实际生效的手势检测频率（0...15 Hz）。
  public var effectiveGestureRateHz: Double { get }
  /// 最近一次 Vision 手部检测识别到的手数量（0...2）。
  public var lastDetectedHandCount: Int { get }
  /// 当前缓存的系统热状态。
  public var currentThermalState: ProcessInfo.ThermalState { get }
  ```
- **核心管线契约**：
  1. `start()`：
     - 刷新 `s.thermalState = ProcessInfo.processInfo.thermalState`；
     - 注册 `NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil)`（若此前已有旧 observer 先移除），回调内更新 `s.thermalState`，若新 `effectiveRate == 0` 则重置 `s.gestureClassifier.reset()` 与 `s.lastDetectedHandCount = 0`；
     - 递增 `s.runGeneration &+= 1`，重置 `s.gestureClassifier.reset()`、`s.isVisionInFlight = false`、`s.lastVisionDispatchedAt = nil`、`s.pendingGesture = nil`、`s.lastDetectedHandCount = 0`。
  2. `stop()` 与 `deinit`：
     - 递增 `s.runGeneration &+= 1`，清理全部手势状态，并在锁外移除 `thermalObserver`。
  3. `handleSessionWasInterrupted` / `handleSessionInterruptionEnded`：
     - 递增 `s.runGeneration &+= 1`，重置 `s.gestureClassifier.reset()`、`s.pendingGesture = nil`、`s.lastDetectedHandCount = 0`、`s.lastVisionDispatchedAt = nil`。
  4. `handleFrame(_ frame: ARFrame, from session: ARSession)`：
     - 在锁内同时完成：
       - ① 消费本帧待发射手势：`let gestureToEmit = s.pendingGesture; s.pendingGesture = nil`（同时用于 tracked 与 untracked 两个分支的 `PerceptionFeatures(..., gesture: gestureToEmit)`）；
       - ② 决定是否调度 Vision：`let rate = ThermalGesturePolicy.effectiveRate(configuredHz: s.gestureRateHz, thermalState: s.thermalState)`；若 `rate > 0 && !s.isVisionInFlight && (s.lastVisionDispatchedAt == nil || timestamp - s.lastVisionDispatchedAt! + 1e-9 >= 1.0 / rate)`，置 `s.isVisionInFlight = true`、`s.lastVisionDispatchedAt = timestamp` 并记下 `dispatchGeneration = s.runGeneration`。
     - 在锁外（`didUpdate` 返回前）：若需要调度，**仅包装** `let boxedPixelBuffer = UncheckedBox(value: frame.capturedImage)` 派发至 `gestureQueue.async`：
       - 使用 `defer` 确保无论成功或抛错均复位 `isVisionInFlight = false`（仅当 `s.runGeneration == dispatchGeneration` 或直接复位，注意若期间重启了新 session，`start()` 已复位 `isVisionInFlight = false`，因此仅在 `s.runGeneration == dispatchGeneration` 时清 `isVisionInFlight = false` 避免误清下一代状态！）；
       - 执行 `VNDetectHumanHandPoseRequest`（`maximumHandCount = 2`）+ `VNImageRequestHandler(cvPixelBuffer: boxedPixelBuffer.value, orientation: handPoseOrientation, options: [:])`；
       - 将 `request.results ?? []` 映射为 `[HandPoseFrame]`（全 21 关节点映射表）；
       - 加锁校验 `s.isRunning && !s.isInterrupted && s.runGeneration == dispatchGeneration`，更新 `s.lastDetectedHandCount = handFrames.count`，调用 `s.gestureClassifier.update(hands: handFrames, at: timestamp)`，若非 nil 则写入 `s.pendingGesture = event`。

#### 5.4 `RuleBasedEmotionStateMachine` 手势反应映射（`MMEmotion` — T042）
- **位置**：`Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift`
- **映射表（严格对应 `contracts/emotion-state-machine.md:46-48`）**：
  - `GestureKind.wave` → `(key: ReactionKey.wave, emotion: EmotionTag.happy, action: ActionTag.wave)`
  - `GestureKind.heart` → `(key: ReactionKey.heart, emotion: EmotionTag.shy, action: ActionTag.heart)`
  - `GestureKind.thumbsUp` → `(key: ReactionKey.thumbsUp, emotion: EmotionTag.happy, action: ActionTag.nod)`
- **行为契约**：
  1. 在 `handle(_ features: PerceptionFeatures)` 完成注意力转换（step 2）之后、语义表情边沿触发（step 3）之前，检查 `if let gesture = features.gesture { handleGestureTrigger(gesture, at: now) }`；
  2. **Speaking 保护（S-5）**：若 `case .speaking = currentState.kind`：
     - 不改变 `currentState.kind`、不设置 `pendingAction`；
     - 若不在冷却（`cooldowns[key]` 为 `nil` 或 `now >= until`）：激活 `speakingOverlay = SpeakingOverlay(emotion: emotion, startedAt: now, duration: Self.durationSeconds(rules.reactionDuration))` 并写入 `cooldowns[key] = now + rules.cooldown`；
  3. **冷却保护（S-2 + 2A）**：若 `let until = currentState.cooldowns[key]`, `now < until`：
     - 不进入 `.reacting`、不发 `pendingAction`；
     - 激活 `cooldownBoost = CooldownBoost(emotion: emotion, startedAt: now, duration: Self.durationSeconds(rules.reactionDuration))`；
  4. **立即触发（契约第 34 行：延迟 ≤ 300 ms，状态机内 0 ms 立即进入）**：
     - 若当前已处于 `.reacting`，先调用 `snapshotCurrentReactingIfNeeded(at: now)` 将旧反应表情推入 `fadingLayers` 平滑淡出；
     - `let returnTo = Self.underlyingStateKind(of: currentState.kind)`（防嵌套 `.reacting`）；
     - 构造 `Reaction(expression: emotion, action: action, duration: rules.reactionDuration, returnTo: returnTo)`；
     - 写入 `cooldowns[key] = now + rules.cooldown`，切换 `currentState.kind = .reacting(reaction)`、`enteredAt = now`、`activeReactionKey = key`、`pendingAction = .play(action)`；
  5. **与既有逻辑兼容性**：
     - 既有 `AttentionTransitionTests`（9 用例）、`ExpressionReactionTests`（7 用例）、`NoMirroringTests` 均传 `gesture: nil`，行为 100% 不变；
     - `ReflexLatencyTracker` 只追踪 `reaction.action == nil`，手势反应均有 `action != nil`，不会污染 `M_reflex`。

#### 5.5 `AvatarScene` 与 `AvatarDebugPanel` 只读观测（`App/MiniMate` — 3A）
- **`AvatarScene` 新增成员**（`App/MiniMate/Screens/AvatarScreen.swift`）：
  ```swift
  private(set) var lastGestureEvent: GestureEvent?
  private(set) var gestureEventCounts: [GestureKind: Int] = [:]
  private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
  private(set) var effectiveGestureRateHz: Double = 12.0
  private(set) var detectedHandCount: Int = 0

  func resetGestureCounters()
  ```
  - 在 `handleIncomingFeatures(_ features:)` 中：若 `let gesture = features.gesture` 则记录 `lastGestureEvent = gesture` 且 `gestureEventCounts[gesture.kind, default: 0] += 1`；同步更新 `thermalState`、`effectiveGestureRateHz`、`detectedHandCount`（`#if os(iOS)` 从 `ARKitPerceptionSource` 读取，非 iOS 回退为 `ThermalGesturePolicy.effectiveRate(configuredHz: 12.0, thermalState: thermalState)` 与 `0`）。
  - 在 `stopPerception()` 与 `handleBackground()` 中重置 `detectedHandCount = 0`（保留累计计数供调试面板查看，清零由 `resetGestureCounters()` 显式触发）。
- **`AvatarDebugPanel` 新增分区**（`App/MiniMate/Screens/Debug/AvatarDebugPanel.swift`）：
  - 在 `Section("状态与感知")` 下方新增 `Section("手势与热状态（US4 / SC-005）")`，展示：
    - `检测到手数`（`0` / `1` / `2`）
    - `最近手势`（如 `wave (0.91)` 或 `none`）
    - `累计触发 (挥手/比心/点赞)`（如 `3 / 2 / 4`）
    - `热状态 / 采样率`（如 `nominal · 12 Hz`、`serious · 5 Hz`、`critical · 0 Hz (已暂停)`）
    - `Button("清零手势计数", role: .destructive) { scene.resetGestureCounters() }`

---

### 6. 原子化施工步骤（自底向上，严格 TDD）

- **Step 1（TDD 红灯）：编写手势分类与热降频单测（T039）**
  - 改动文件：`Packages/MiniMateKit/Tests/MMPerceptionTests/HandGestureClassifierTests.swift`（新增）
  - 改动要点：按第 7.1 节测试矩阵编写全部合成 21 关节点测试（含工具函数构建标准伸直手掌、点赞拳头、双手比心、摸脸/抬手/单手双检/合十负样本）与 `ThermalGesturePolicy` 用例。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter HandGestureClassifierTests
    ```
    （预期因符号未实现而编译失败，确认 TDD 红灯）

- **Step 2（绿灯）：实现 `ThermalGesturePolicy` 与 `HandGestureClassifier`（T040）**
  - 改动文件：`Packages/MiniMateKit/Sources/MMPerception/ThermalGesturePolicy.swift`（新增）、`Packages/MiniMateKit/Sources/MMPerception/HandGestureClassifier.swift`（新增）
  - 改动要点：严格按第 5.1 / 5.2 节契约实现热策略与 3 种手势几何规则、尺度归一化、防误触保护与边沿锁存释放。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter MMPerceptionTests
    ```

- **Step 3（TDD 红灯 → 绿灯）：状态机手势反应映射测试与实现（T042）**
  - 改动文件：`Packages/MiniMateKit/Tests/MMEmotionTests/GestureReactionTests.swift`（新增）→ 确认失败 → `Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift`（修改）
  - 改动要点：先写 `GestureReactionTests` 覆盖 3 种手势映射、0 延迟进入 `.reacting`、冷却与 2A 柔和增强、Speaking S-5 保护、Idle/遮脸/动作打断与 `ReflexLatencyTracker` 隔离；再在 `RuleBasedEmotionStateMachine` 实现 `handleGestureTrigger` 与共享 `snapshotCurrentReactingIfNeeded`。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter MMEmotionTests
    ```

- **Step 4：接入 `ARKitPerceptionSource` 的 12 Hz Vision 手部检测与热降频（T041）**
  - 改动文件：`Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift`（修改）
  - 改动要点：按第 5.3 节接入 `Vision` / `ImageIO`、`gestureQueue` 单飞行抽帧（`UncheckedBox(value: frame.capturedImage)`、`.leftMirrored`、`maximumHandCount = 2`）、`ProcessInfo.thermalStateDidChangeNotification` 监听与 `runGeneration` 防串帧、以及 3 个只读遥测属性。
  - 最小验证命令（验证 `#if os(iOS)` 分支在 Swift 6 严格并发下零警告零报错编译）：
    ```bash
    cd Packages/MiniMateKit && xcodebuild -scheme MMPerception -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
    ```

- **Step 5：接入 `AvatarScene` 与 `AvatarDebugPanel` 只读观测区**
  - 改动文件：`App/MiniMate/Screens/AvatarScreen.swift`（修改）、`App/MiniMate/Screens/Debug/AvatarDebugPanel.swift`（修改）
  - 改动要点：按第 5.5 节接线手势计数与热状态只读展示，不改动任何既有调试功能。
  - 最小验证命令（iOS Simulator 完整 App 编译）：
    ```bash
    xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
    ```

---

### 7. 确定性测试矩阵与验收门禁

#### 7.1 测试矩阵（严禁非确定性断言）

| 目标测试文件 | 覆盖类别 | 测试场景 | 必须写死的断言底线（禁止弱断言） |
| :--- | :--- | :--- | :--- |
| `Packages/MiniMateKit/Tests/MMPerceptionTests/HandGestureClassifierTests.swift` | 正例 | 挥手：张开竖直手掌在 1.5 s 内水平左右摆动产生 3 次翻转（2 个来回） | 2 次翻转时返回 `nil`；第 3 次翻转瞬间返回 `GestureEvent.kind == .wave`、`confidence > 0.3`、`timestamp` 精确匹配 |
| 同上 | 正例 | 双手比心：双手拇指尖/食指尖贴近、食指高于拇指、手腕间距合法，持续 0.5 s | `t = 0.45 s` 返回 `nil`；`t = 0.50 s` 返回 `kind == .heart`；不同手掌尺度（近距离 `0.24` / 远距离 `0.08`）均触发 |
| 同上 | 正例 | 竖大拇指：拇指竖直向上、其余 4 指弯曲，持续 0.5 s（含 1 帧 ≤ 0.15 s 短丢帧容忍） | `t = 0.45 s` 返回 `nil`；中间插入 1 帧空手（83 ms）后在 `t = 0.50 s` 仍准确返回 `kind == .thumbsUp` |
| 同上 | 边界（P-3） | 边沿触发与释放重触发（三种手势均覆盖） | 成立后继续保持 1.0 s 全部返回 `nil`、`latchedGesture == kind`；收手满释放时长后 `latchedGesture == nil`，再次做手势可重新触发第 2 次 |
| 同上 | 异常反例 | 负样本抗误触：竖直抬手、静止张手叠加 ±0.01 随机抖动、摸脸（手指伸向面部无水平来回）、单次左右晃手、双手平合拍手、单手重复检出（双手腕重合）、大拇指朝下/水平 | 全部序列逐帧输出 `nil`，误触发次数严格 `== 0` |
| 同上 | 异常反例 | 低置信度（`< 0.3`）、超小手掌（`< 0.03`）、`NaN`/回退时间戳与 `reset()` | 返回 `nil` 不崩溃不污染状态；`reset()` 后清零锁存与计时器 |
| 同上 | 正例/边界 | `ThermalGesturePolicy.effectiveRate` | `(12, .nominal)==12`、`(12, .fair)==12`、`(12, .serious)==5`、`(12, .critical)==0`、`(3, .serious)==3`、`(20, .nominal)==15`、`(.nan, .nominal)==0` |
| `Packages/MiniMateKit/Tests/MMEmotionTests/GestureReactionTests.swift` | 正例 | 三种手势反应映射与 0 延迟即时进入（≤ 300 ms） | `wave` → `.reacting(happy, .wave)` + `pose.action == .play(.wave)`；`heart` → `.reacting(shy, .heart)` + `pose.action == .play(.heart)` 且 `headRotation.x` 包含 `+8°` 低头增量；`thumbsUp` → `.reacting(happy, .nod)` + `pose.action == .play(.nod)`；均不进 `scheduled` 队列，1.5 s 后回到原状态 |
| 同上 | 边界（S-2 + 2A） | 同类手势 8 s 冷却期内再次触发 & 冷却结束后恢复 | 冷却期内 `state.kind` 保持 `.attending`、`pose.action == nil`、产生柔和底色增强权重 `∈ (0, 0.3]`；超过 8 s 后再次挥手正常重新进入 `.reacting(happy, .wave)` |
| 同上 | 边界（S-5） | Speaking 期间收到手势 & Idle/遮脸场景收到手势 & 不同手势打断旧动作 | Speaking 期间不改 `state.kind`、不发 `action`、仅叠加 `<= 0.3` 轻量微表情；Idle 收到 `wave` 立即进入 `.reacting(returnTo: .idle)`；`wave` 进行中收到 `heart` 立即切换至 `heart` 且旧权重进入平滑淡出 |
| 同上 | 兼容回归 | 表情与手势并发 + `ReflexLatencyTracker` 隔离 | 手势 `.reacting` 期间到期纯表情计划反应被跳过不打断动作；`ReflexLatencyTracker.observeAppliedState` 收到手势 `.reacting` 返回 `nil` |

#### 7.2 完整门禁命令清单

```bash
# 1. 目标单测（MMPerception + MMEmotion）
cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter "HandGestureClassifierTests|GestureReactionTests"

# 2. 全量 macOS 纯逻辑单测（确认既有 102 用例 + 新增用例全绿）
cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox

# 3. iOS 目标编译验证（核验 #if os(iOS) Vision/ARKit/Thermal 代码在 Swift 6 下零报错）
cd Packages/MiniMateKit && xcodebuild -scheme MMPerception -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

# 4. App 模拟器完整编译验证（无签名）
xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# 5. 仓库状态与只读基线检查（确认未触碰 tasks.md / research.md / 资产）
git status
```

> **后续人工真机验收（T043，不在本次代码提交范围内，待用户确认本轮代码验收后执行）**：
> 在 iPhone 16 Pro Max 上按 `specs/002-m1-presence/quickstart.md` 第四节实测：挥手 / 比心 / 点赞各 10 次记录触发次数（目标 ≥ 8/10），正常说话/摸脸/抬手 1 分钟记录误触发（目标 ≤ 1 次），并视真机手感微调 `HandGestureClassifier.Config` 后写入 `research.md`。

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

- **审查通道与模型**：单节点独立只读审查员 `reviewer`（`gemini-4-neon-high` / `Gemini 4 Neon (High)`），每轮均通过送审前/后 `git status --porcelain`、`git diff` 哈希与未跟踪文件 SHA-1 指纹核验字节级零修改，闭环结束后已回收节点。
- **闭环结论**：共 **2 轮**复审，**一致通过**（Round 2 阻断项 = 0，非阻断建议 = 0，无新增回归）。

### Round 1（结论：需修改 — 2 项阻断项、3 项非阻断建议）
1. **阻断项 1（已根因修复）**：`ARKitPerceptionSource.swift` 在 `setGestureRate(0)` 或 `.critical` 热状态切入 `effectiveRate == 0` 时清零了手势状态，但在途 `gestureQueue.async` 回调回写未校验独立手势重置代次与当前 `effectiveRate > 0`，可能导致暂停后回写脏 `lastDetectedHandCount` / `pendingGesture`。
   - **修复**：新增独立 `gestureResetGeneration: UInt64`，在 `start()`/`stop()`/中断及 `effectiveRate == 0` 清零路径递增；调度时捕获并在回写锁块同时校验 `s.gestureResetGeneration == dispatch.gestureResetGeneration && ThermalGesturePolicy.effectiveRate(...) > 0`（`defer` 仍只校验 `runGeneration` 释放 `isVisionInFlight`）。
2. **阻断项 2（已根因修复）**：`GestureReactionTests.swift` 中 `ReflexLatencyTracker` 隔离测试在 `sm.pose(at: 1.35)` 之后才调用 `observePerception`，此时 `scheduled` 已清空，属于未武装假阳性断言。
   - **修复**：改为在 `t = 1.0`（`scheduled.count == 1`）武装 `tracker`，验证 `t = 1.35` 对带动作手势 `.reacting(happy, .wave)` 返回 `nil`，并补充同武装 `tracker` 接收无动作纯表情 `.reacting(happy, action: nil)` 精准返回 `0.35 s`（`< 1e-6`）的正例对照。
3. **非阻断建议（全部采纳）**：
   - `HandGestureClassifier.swift` 释放 `.heart`/`.thumbsUp` 边沿锁存时同步清零 `heartStartedAt`/`thumbsUpStartedAt`；
   - `HandGestureClassifierTests.swift` 新增“平行双指（合法 `verticalSepRatio` 但 `indexMCPGap <= indexTipGap`）”与“超过 1.5 s 窗口旧翻转淘汰”反例；
   - `AvatarScreen.swift` 将 `effectiveGestureRateHz` 初始值改为 `ThermalGesturePolicy.effectiveRate(configuredHz: 12.0, thermalState: ProcessInfo.processInfo.thermalState)`。

### Round 2（结论：通过 — 0 项阻断项、0 项非阻断建议）
- 审查员独立复核确认 Round 1 的 2 项阻断项已彻底根治、3 项非阻断建议已妥善落地，无新增回归。

### 最终验收门禁实测证据
- `cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox`：**113/113 通过**（`MMCoreTests` 10 + `MMSecurityTests` 7 + `MMDiagnosticsTests` 14 + `MMPerceptionTests` 28 [含 `HandGestureClassifier` 7] + `MMEmotionTests` 54 [含 `GestureReaction` 4]）
- `cd Packages/MiniMateKit && xcodebuild -scheme MMPerception -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`：**BUILD SUCCEEDED**
- `xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`：**BUILD SUCCEEDED**
- 收口策略：`specs/002-m1-presence/tasks.md` 与 `research.md` 未触碰，未执行 `git commit` / `git push`。

### 真机验收与增量调优记录（2026-11-26，T043）
在 iPhone 16 Pro Max 真机实测过程中，结合调试面板只读诊断与真实 Vision 21 关节点实测完成了 5 项高价值调优：
1. **挥手灵敏度与防死锁**：跟踪点改为手腕与指尖加权重心（`0.35*wrist + 0.65*meanTip`）、翻转门槛调为 2 次、修复手竖直换高度后旧 `anchor.y` 永久卡死的 Bug，并放宽端点倾斜角度（`tipDeltaY >= -0.25*palmScale`）；
2. **背压零丢手势事件**：修复 `ARKitPerceptionSource` 60 Hz `AsyncStream(.bufferingNewest(2))` 在主线程高负载下挤丢单帧 `gesture` 的根因（扩容至 `.bufferingNewest(8)` 并拦截 `.dropped(let dropped)` 自动恢复重发，生命周期重置同步清理）；
3. **冷却时间调试面板可控**：`RuleBasedEmotionStateMachine.updateCooldown(_:at:)` 支持 `3...8 s` 热更新，App 端默认 `5.0 s` 并在 `AvatarDebugPanel` 提供实时滑杆（`ReactionRules.defaults.cooldown` 保持 `8 s` 兼容既有单测）；
4. **单手比心（韩式手指比心）左右手适配与泛化**：基于本机 Vision 实测 21 关节点升级为 2D 线段 X 交叉 + 上段最小距离 + 抗透视有效尺度 + 近距离手腕裁出底边时的 MCP 虚拟手腕兜底 + `holdDropoutTolerance = 0.22 s`，覆盖 ±35° 歪手、大小手缩放与手背局部遮挡，同时严防 OK / 剪刀手 / L 字手枪 / 握拳 / 点赞误触；
5. **潜在问题建档**：真机调优中偶发观察到“静止注视时每 14–15 s 向左下方低头约 3 s 后回平视”（后无法复现），已按统一模板沉淀至 [`docs/issues/001-periodic-bottom-left-head-drop.md`](../issues/001-periodic-bottom-left-head-drop.md)。

### 真机调优后复审闭环记录（`reviewer-v2`，2026-11-26）

- **审查通道与模型**：单节点独立只读审查员 `reviewer-v2`（`gemini-4-neon-high` / `Gemini 4 Neon (High)`），每轮送审前/后均核验 `git status --porcelain`、`git diff` 哈希与未跟踪文件 SHA-1 指纹完全一致，闭环结束后已回收节点。
- **闭环结论**：共 **2 轮**复审，**一致通过**（Round 2 阻断项 = 0，非阻断建议 = 0，无新增回归）。
  - **Round 1（2 项阻断项 + 4 项非阻断建议）**：
    1. 阻断项 1（已根因修复）：`ARKitPerceptionSource.swift` 在 `.critical` 热状态切入 `effectiveRate == 0` 时未清空 `SubscriberEntry.recoveredGesture`，且 `handleFrame` 回写 `droppedGestures` 时未校验 `runGeneration`/`gestureResetGeneration` 与热状态；已补全清零、代次守卫与 `1.0 s` 过期丢弃。
    2. 阻断项 2（已根因修复）：`HandGestureClassifier.swift` 在 `matchesSingleHandHeart` 缺失 `thumbMP/thumbCMC/indexMCP` 回退到共享 `hand.wrist` 时，`segmentsIntersect` 因共端点退化恒返回 `true`；已以 `hasDistinctBases` 隔离共端点退化并新增 `sharedWristOpenV` 回归单测。
    3. 非阻断建议（全部采纳）：同步更新 `HandGestureClassifier.swift` 与测试注释；`RuleBasedEmotionStateMachine.updateCooldown` 增加 `now.isFinite` 守卫并同步夹紧 `approachCooldownUntil`（补充上限夹紧与 `.nan` 断言）；`AvatarScreen.swift` 改为可取消 `cooldownSyncTask` 防滑杆乱序写回；更新本执行单最终状态与实测口径。
  - **Round 2（通过 — 0 项阻断项、0 项非阻断建议）**：独立只读全量复跑与逐项证据核查通过。
- **最终验收门禁与收口**：
  - `swift test`（macOS）：**118 / 118 全部通过**（`MMCoreTests` 10 + `MMSecurityTests` 7 + `MMDiagnosticsTests` 14 + `MMPerceptionTests` 32 + `MMEmotionTests` 55）
  - `xcodebuild -scheme MMPerception -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`：**BUILD SUCCEEDED**
  - `xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`：**BUILD SUCCEEDED**
  - **用户授权收口**：用户已明确确认真机验收与收工，已勾选 `specs/002-m1-presence/tasks.md`（T039–T043）、回填 `specs/002-m1-presence/research.md`（`SC-005`），并执行本地 `git commit`（未 `git push`）。
