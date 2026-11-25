# 002-m1-presence US2（T020–T028）“它在看我”实现级执行单

- **状态**：已完成实现与独立复审（待用户验收）
- **Git 基线**：`main` @ `4f9d59b`（工作区干净，上游 M1 US1 / T019 已合并于 `23967fc`）
- **关键基线**：Swift `6.4`（`swift-tools-version: 6.2`，Swift 6 严格并发）、Xcode `27.0`（`27A266a`）、iOS `26+` / macOS `26+`、Swift Testing、零第三方运行时依赖；素材 `App/MiniMate/Resources/Avatar/minimate.usdz` + `minimate.actions.json`（52/52 形态键、8/8 动作已于 2026-11-25 真机验收通过）
- **拍板决议摘要**：用户于 2026-11-25 确认按全部推荐项实施（`1A` 实施 US2 全量代码与测试 T020–T028；`2A` 将 `IdleMotion`/`IdleMotionLayer` 迁入 `MMEmotion` 并在 `MMAvatar` 保留 `public typealias` 兼容别名；`3A` 在保留防飞出保护前提下微调 `RealityKitAvatarRenderer` 连续转头静态目标姿态 + 40 ms 过渡与稀疏权重自动归零）。

> **红线声明**
> - 严格遵守 `.specify/memory/constitution.md`（最高优先级）：① **陪伴而非镜像**——`rawBlendShapes` 严禁进入 `AvatarPose` / 渲染器，唯一允许跟随用户数据的通道是人脸位置驱动视线与头部朝向；② **感知在本地**——无网络访问、不显示也不保存摄像头画面；③ **纯逻辑测试先行**——`MMPerception` / `MMEmotion` 纯逻辑模块必须先写测试、确认失败再实现；④ **零新增第三方依赖**；⑤ **隐私与密钥**——不得引入/泄露任何凭证，不提交 `Assets/voice-samples/*.wav`。
> - 设计阶段仅创建/维护本执行单，严禁改动任何业务代码、测试、配置或 `tasks.md`。
> - 收口策略：未经用户明确确认验收，不得勾选 `specs/002-m1-presence/tasks.md`，不得修改 `research.md` 实测结论，不得 `git commit`，不得 `git push`。

---

## 上篇：面向用户决策

### 1. 任务目标与选择理由

- **本次任务**：`002-m1-presence` Phase 4 — **US2“它在看我”（T020–T028 代码与测试闭环）**。交付 ARKit 人脸位置/注视感知、One Euro 平滑、JSONL 录制与脚本回放、规则情绪状态机（Idle ↔ Attending / `notice` / `leanBack` / `lookAround` + 视线与头部追踪 + 待机层合成）、`AvatarScreen` 感知→状态机→渲染全链路接线、`M_track` 时延采集，以及调试面板的感知录制导出与指标展示。完成后即可直接在真机执行 Quickstart §2（T029）验收 `SC-002`。
- **为何优先做它（候选项横向对比）**：
  1. **首选 · `002-m1-presence` US2（T020–T028）**：上游 M0（001）全部完成、M1 US1（T001–T019）刚合并到 `main`，依赖 100% 就绪；零外部阻塞（无需云端 API Key 或录制个人语音样本）；完成后立刻解锁 M1 后续全部 Story（US3 表情回应、US4 手势、US5 对话状态）并为 M2 US5 视线软闸门提供 `isLookingAtScreen`；且交付后真机立刻获得“小瓜在看我”的核心体验。
  2. **暂缓 · 合并 US3（T030–T038）**：US2 已横跨 3 个模块 + App 接线 + 调试面板 + 5 组单测，本身是完整垂直切片；US3 的 `expression-presets.json`（T034）需在真机调试面板调参导出，且应在 US2 真机核对完视线坐标系与 `M_track` 后再叠加表情回应，不宜膨胀单次变更面。
  3. **暂缓 · `003-m2-voice-conversation` Phase 1–3（M2a 厂商验证）**：虽可与 002 并行，但强依赖人工核对最新云端厂商文档、配置有效云端 Key 与自录 9 条个人语气样本（T021），当前趁 M1 US1 刚落地推进 US2 连续性与产出效率更高。
- **摸底关键发现（3 个最需知情的技术风险/锚点）**：
  1. **App 工程尚未显式链接 `MMPerception` 与 `MMEmotion`**：`App/MiniMate.xcodeproj/project.pbxproj` 目前只链接了 `MMCore`/`MMDiagnostics`/`MMSecurity`/`MMAvatar`，本轮必须显式补齐 `MMPerception` 与 `MMEmotion` 产品依赖（`INFOPLIST_KEY_NSCameraUsageDescription` 已在 `project.pbxproj:277,307` 配好，无需新增 `Info.plist`）。
  2. **模块依赖方向冲突（`IdleMotionLayer` 位置）**：`Package.swift:24-25` 中 `MMAvatar` 依赖 `MMEmotion`，而 `IdleMotionLayer` 当前位于 `MMAvatar`；但 `contracts/emotion-state-machine.md` 要求 `MMEmotion` 中的 `RuleBasedEmotionStateMachine.pose(at:)` 负责姿态合成第 5 步（呼吸+眨眼），否则状态机单测与真机管线会割裂或双重叠加待机动作。
  3. **时间基与连续转头滞后风险**：① `ARFrame.timestamp` 是开机单调时钟，而 `IdleMotionLayer.updateNow()` 用 `Date.timeIntervalSinceReferenceDate`，不统一时间基会导致状态机误判人脸丢失 25 年且 `M_track` 失真；② `RealityKitAvatarRenderer.applyHeadRotation`（`RealityKitAvatarRenderer.swift:520-541`）当前每帧新建动画都从 `skeletonRestPoses`（0°）起步配 80 ms 淡入，60 Hz 连续跟随转头时会产生欠冲滞后，可能拉高 `M_track`。

### 2. 已拍板决策清单（已定稿）

1. **任务范围粒度 → 1A**：实施 US2 完整代码与测试闭环（**T020–T028**，不含人工真机验收 T029）。完成后 `swift test` 与 iOS 编译门禁全绿，可直接真机跑 Quickstart §2 验收。
2. **`IdleMotionLayer` 的模块归属 → 2A**：将 `IdleMotion` / `IdleMotionLayer` 源码迁入 `MMEmotion/IdleMotionLayer.swift`，并在 `MMAvatar/IdleMotionLayer.swift` 保留 `public typealias IdleMotion = MMEmotion.IdleMotion` 与 `public typealias IdleMotionLayer = MMEmotion.IdleMotionLayer`。`RuleBasedEmotionStateMachine` 直接完成姿态合成第 1、5、6 步，`AvatarScene` 不再重复持有 `IdleMotionLayer`，且既有 `IdleMotionLayerTests.swift` 零修改 100% 兼容。
3. **`RealityKitAvatarRenderer` 连续转头平滑与稀疏权重微调 → 3A**：在严格保留整条骨架 `skeletonRestPoses` 数组与 `guard playback == nil`（真机防模型飞出保护）的前提下，对 `RealityKitAvatarRenderer.swift` 做两处局部微调：① `applyHeadRotation` 改为目标静态姿态（`from: JointTransforms(to)`、`duration: 1.0/60.0`）配合 `transitionDuration: 0.04`；② `applyExpressionWeights` 对上帧非零但本帧省略的键自动写回 `0`。

---

## 下篇：面向实施方的零歧义施工图

### 3. 现状锚点与环境陷阱预警

#### 3.1 现有代码锚点

| 模块/符号 | 精确位置 | 职责与复用/约束说明 |
| :--- | :--- | :--- |
| `Package.swift` targets | `Packages/MiniMateKit/Package.swift:19-31` | `MMPerception` 依赖 `MMCore`；`MMEmotion` 依赖 `MMCore`、`MMPerception`；`MMAvatar` 依赖 `MMCore`、`MMEmotion`。`MMPerceptionTests`/`MMEmotionTests` 需显式补齐 `MMCore`/`MMPerception` 依赖以适配 Swift 6.4 严格模块检查 |
| `MMCore.Clock` / `SystemClock` | `Packages/MiniMateKit/Sources/MMCore/MMCore.swift:4-18` | 统一时间抽象，所有可测时钟必须注入 `any MMCore.Clock`（注意命名避免与 Swift 标准库 `Swift.Clock` 冲突，必要时写 `MMCore.Clock`） |
| `LatencyRecorder` | `Packages/MiniMateKit/Sources/MMCore/Metrics/LatencyRecorder.swift:4-62` | 已有 `record(_:metric:)`、`count(for:)`、`p50(for:)`、`p90(for:)`、`csv()`，直接复用，禁止重写百分位/CSV 逻辑 |
| `PerceptionFeatures` / `FaceSignals` / `GestureEvent` | `Packages/MiniMateKit/Sources/MMPerception/PerceptionFeatures.swift:4-78` | 已实现 `Codable, Sendable, Equatable`，包含 `timestamp`、`isFaceTracked`、`rawBlendShapes`、`signals`、`facePosition: SIMD3<Float>?`、`isLookingAtScreen`、`gesture` |
| `PerceptionSource` / `PerceptionError` | `Packages/MiniMateKit/Sources/MMPerception/PerceptionSource.swift:2-20` | 已有协议 `features`、`start() async throws`、`stop()`、`setGestureRate(_:)` 及 3 个错误枚举；`ARKitPerceptionSource` 与 `ScriptedPerceptionSource` 必须严格遵循此签名 |
| `AvatarState` / `AvatarStateKind` / `Reaction` | `Packages/MiniMateKit/Sources/MMEmotion/AvatarState.swift:5-72` | 已有 `idle/attending/listening/thinking/speaking/reacting` 与 `enteredAt`/`baseEmotion`/`cooldowns`/`scheduled`/`lastFaceSeenAt` |
| `AvatarPose` / `ActionCommand` | `Packages/MiniMateKit/Sources/MMEmotion/AvatarPose.swift:4-30` | `expressionWeights: [String: Float]`、`headRotation: SIMD3<Float>`（欧拉角弧度 ±25°）、`eyeTarget: SIMD2<Float>`、`action: ActionCommand?`（边沿触发） |
| `ReactionRules` | `Packages/MiniMateKit/Sources/MMEmotion/ReactionRules.swift:14-47` | 已有 `attendingEnter = 0.2`、`idleAfterFaceLost = 3`、`approachWindow = 1`、`approachDistance = 0.15`、`reactionDuration = .milliseconds(1500)`、`cooldown = 8` |
| `EmotionStateMachine` | `Packages/MiniMateKit/Sources/MMEmotion/EmotionStateMachine.swift:6-15` | 协议方法：`handle(_ features:) async`、`handle(_ event:) async`、`pose(at:) async -> AvatarPose`、`var state: AvatarState { get async }` |
| `IdleMotion` / `IdleMotionLayer` | `Packages/MiniMateKit/Sources/MMAvatar/IdleMotionLayer.swift:5-94` | 呼吸 + 眨眼纯逻辑；既有测试 `Packages/MiniMateKit/Tests/MMEmotionTests/IdleMotionLayerTests.swift:1-95` 仅 `import MMAvatar` 并校验其全部行为，必须保持 100% 兼容 |
| `BlendShapeIndex.arkitNames` | `Packages/MiniMateKit/Sources/MMAvatar/BlendShapeIndex.swift:7-29` | 规范的 52 个 ARKit 形态键名称列表，含 8 个 `eyeLook*` 名称（第 11–14 行） |
| `RealityKitAvatarRenderer` | `Packages/MiniMateKit/Sources/MMAvatar/RealityKitAvatarRenderer.swift:121-154,403-542` | `apply(_:)` 驱动 `expressionWeights`、`headRotation`、`action`；`applyHeadRotation`（494–542 行）含两项真机防崩溃铁律（见 3.2） |
| `AppComposition` | `App/MiniMate/AppComposition.swift:7-19` | `@Observable` 组合根，目前持有 `clock` 与 `credentialStore` |
| `AvatarScene` / `AvatarScreen` | `App/MiniMate/Screens/AvatarScreen.swift:12-308` | 持有 `RealityKitAvatarRenderer`、虚拟相机、`SceneEvents.Update` 60 Hz 订阅、`-freezeIdle`/`-blendName`/`-previewAction`/`-playAction` 调试启动参数与 `shyEyeBlend` 逻辑，必须全部兼容保留 |
| `AvatarDebugPanel` | `App/MiniMate/Screens/Debug/AvatarDebugPanel.swift:6-91` | 现有“动作”“表情系数（52）”“全部归零”三段，本轮只增不删 |
| `DiagnosticsView` `ShareLink` 模式 | `App/MiniMate/Screens/DiagnosticsView.swift:48-56` | SwiftUI `ShareLink` 导出文本的既定模式，可直接参考 |
| Xcode 工程依赖与权限 | `App/MiniMate.xcodeproj/project.pbxproj:10-14,29-39,78-83,277,307,358-377` | `INFOPLIST_KEY_NSCameraUsageDescription` 已存在；`MMPerception`、`MMEmotion` 尚未加入 `MiniMate` target 的 packageProductDependencies / Frameworks |

#### 3.2 环境与平台实测陷阱预警

1. **Swift 标准库 `Clock` 命名冲突（Swift 6.4 必踩）**：
   - 表现：同一文件同时使用 `MMCore.Clock` 与 `Duration` / `Task.sleep` 时，裸写 `any Clock` 易与标准库 `Swift.Clock` 歧义报错。
   - **必须采用的写法**：函数/构造器签名涉及 `MMCore` 的时钟协议时统一写 `any MMCore.Clock`（参考 `App/MiniMate/AppComposition.swift:9,13`）。
2. **`ARFrame.timestamp` 与 `Clock.now` 时间基不一致（致命隐蔽 Bug）**：
   - 表现：`ARFrame.timestamp` 是设备开机单调秒数（同 `ProcessInfo.processInfo.systemUptime`），而 `IdleMotionLayer.updateNow()` 与 `Clock.now.timeIntervalSinceReferenceDate` 是自 2001-01-01 起的秒数（相差 ~8 亿秒）。混用会立刻导致 `time - lastFaceSeenAt >> 3 s`、永远无法维持 Attending，且 `M_track` 算成 25 年。
   - **必须采用的写法**：`ARKitPerceptionSource` 统一将每帧时间戳换算到 `MMCore.Clock` 的 `timeIntervalSinceReferenceDate` 时间基：`age = min(max(ProcessInfo.processInfo.systemUptime - frame.timestamp, 0), 0.5)`，`timestamp = clock.now.timeIntervalSinceReferenceDate - age`，并做单调递增保护（`max(computed, lastTimestamp + 1e-5)`）；`OneEuroFilter` 内部可直接使用该单调时间戳。
3. **ARKit 坐标系与角色骨骼轴向（极易左右/上下反向）**：
   - 已核对 `Assets/avatar/auto-build/scripts/avatar_common.py:65,407`、`audit.json:1565-1576` 与 `RealityKitAvatarRenderer.swift:514-522`：
     - 形象面向 `+Z`（朝向屏幕前的用户），`+Y` 向上，`+X` 指向**屏幕右侧（角色解剖学左侧）**。
     - 头部旋转欧拉角语义：`euler.x > 0` 为**低头**、`euler.x < 0` 为**抬头**；`euler.y > 0` 为**向屏幕右侧（角色左侧）转头**、`euler.y < 0` 为**向屏幕左侧（角色右侧）转头**。
     - 眼睛 blendShape 解剖学语义：看向屏幕右侧（`eyeTarget.x > 0` = 角色左侧）→ `eyeLookOutLeft` + `eyeLookInRight`；看向屏幕左侧（`eyeTarget.x < 0` = 角色右侧）→ `eyeLookInLeft` + `eyeLookOutRight`；向上（`eyeTarget.y > 0`）→ `eyeLookUpLeft/Right`；向下（`eyeTarget.y < 0`）→ `eyeLookDownLeft/Right`。
     - `ARCamera.viewMatrix(for: .portrait)` 将世界坐标变换到竖屏相机视角空间（相机沿 `-Z` 看向用户，因此相机右轴 `+X` 是用户物理左侧，脸在前方 `z < 0`）。换算到规范的“面向屏幕坐标系”（`+X` = 屏幕右侧 / 用户物理右侧，`+Y` = 上方，`+Z` = 离屏距离正米数）：`rawPos = SIMD3<Float>(-faceViewPos4.x, faceViewPos4.y, -faceViewPos4.z)`。
     - `lookAtPoint` 夹角必须在 `ARFaceAnchor` 局部空间计算：`cameraPosInFace = (simd_inverse(faceAnchor.transform) * frame.camera.transform).columns.3.xyz`，直接求 `lookAtPoint` 与 `cameraPosInFace` 的夹角——对支架倾角、重力对齐、左右镜像 100% 不变。
4. **RealityKit 真机防模型飞出两条铁律（`docs/avatar-action-binding-issue.md` & `research.md:64`）**：
   - **严禁删除** `RealityKitAvatarRenderer.swift:500` 的 `guard playback == nil else { return }`（动作层与头部 additive 层同时驱动同一骨架会把 rest pose 二次套用、模型瞬间拉飞）。
   - **严禁精简** `FromToByAnimation<JointTransforms>` 的 `jointNames: skeletonJointNames` 整骨架数组（只传单关节会被 RealityKit 套到根关节导致整体位移 1.5 m）。
5. **Swift 6 严格并发 + RealityKit 60 Hz 渲染循环**：
   - `SceneEvents.Update` 在 `@MainActor` 同步触发，而 `EmotionStateMachine.pose(at:)` 是 `actor` 异步方法。严禁每帧无节制创建并发 `Task` 堆积；必须用**单飞行（single-flight）`poseTask` 槽位**：每帧同步应用最新缓存 `latestPose`（保 `apply` < 2 ms），仅当 `poseTask == nil` 时拉起下一次 `await stateMachine.pose(at:)` 刷新缓存。
   - `ARSessionDelegate` 回调为 Objective-C `nonisolated` 方法，且在自定义串行 `DispatchQueue` 上回调；`ARKitPerceptionSource` 内部所有可变状态必须用 `OSAllocatedUnfairLock` 或串行队列隔离（`import os`），满足 Swift 6 `Sendable` 严格并发无警告。
6. **真机 `notice` 触发条件防误清陷阱**：
   - 当用户离开 > 3 s 后返回并看向屏幕时，进入 Attending 需要持续 200 ms。若在返回第 1 帧就无条件把 `lastFaceSeenAt` 覆写为当前时间，200 ms 后再判断 `now - lastFaceSeenAt > 3 s` 会恒为 false，`notice` 永远不会触发！必须在“人脸从丢失重新出现”的那一帧先记录 `pendingNoticeOnAttend = (now - lastFaceSeenAt > rules.idleAfterFaceLost)`，待进入 Attending 时消费并清零。

---

### 4. 改动范围表与明确不做清单（Non-Goals）

#### 4.1 文件改动表

| 文件路径 | 操作 | 精确职责 |
| :--- | :--- | :--- |
| `Packages/MiniMateKit/Package.swift` | 微调 | 为 `MMPerceptionTests` 补齐 `"MMCore"` 依赖，为 `MMEmotionTests` 补齐 `"MMCore"`、`"MMPerception"` 显式依赖 |
| `Packages/MiniMateKit/Sources/MMPerception/OneEuroFilter.swift` | 新增 | `OneEuroFilter`（标量 1€ 平滑器）与 `OneEuroFilter3D`（`SIMD3<Float>` 三轴平滑封装） |
| `Packages/MiniMateKit/Sources/MMPerception/LookingAtScreenDetector.swift` | 新增 | 纯逻辑注视夹角计算与最短持续 200 ms 状态判定器 |
| `Packages/MiniMateKit/Sources/MMPerception/ScriptedPerceptionSource.swift` | 新增 | `PerceptionSource` 的脚本/JSON Lines 回放实现 + 共享 JSONL 编解码静态方法与错误类型 |
| `Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift` | 新增 | `#if os(iOS)` 独立 `ARSession` 人脸追踪实现（摄像头权限、60 Hz 位置平滑、`isLookingAtScreen`、后台中断恢复） |
| `Packages/MiniMateKit/Sources/MMEmotion/IdleMotionLayer.swift` | 新增（迁移，2A） | 迁入原 `MMAvatar/IdleMotionLayer.swift` 的 `IdleMotion` 与 `IdleMotionLayer` 完整实现 |
| `Packages/MiniMateKit/Sources/MMAvatar/IdleMotionLayer.swift` | 修改（2A） | 改为 `import MMEmotion` + `public typealias IdleMotion = MMEmotion.IdleMotion` / `public typealias IdleMotionLayer = MMEmotion.IdleMotionLayer`，保持源码 100% 兼容 |
| `Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift` | 新增 | `EmotionStateMachine` 的 `actor` 实现（US2：Idle ↔ Attending、`notice`、`lookAround`、`leanBack`、视线/头部/`eyeLook*` 合成、第 1/5/6 步合成、`resetToIdle`） |
| `Packages/MiniMateKit/Sources/MMEmotion/TrackLatencyTracker.swift` | 新增 | 纯逻辑 `M_track` 采样判定器（人脸位移事件 → 形象头部朝向变化时间差） |
| `Packages/MiniMateKit/Sources/MMAvatar/RealityKitAvatarRenderer.swift` | 微调（3A） | ① `applyHeadRotation` 改用静态目标姿态 `from = to` + `transitionDuration: 0.04`；② `applyExpressionWeights` 对省略的前非零键自动归零 |
| `App/MiniMate.xcodeproj/project.pbxproj` | 微调 | 为 `MiniMate` target 显式链接 `MMPerception`（`0A0A...0005`/`5050...0005`）与 `MMEmotion`（`0A0A...0006`/`5050...0006`） |
| `App/MiniMate/AppComposition.swift` | 微调 | 提供 `makePerceptionSource()` 与 `makeEmotionStateMachine()` 工厂方法（保留现有 `clock` 与 `credentialStore`） |
| `App/MiniMate/Screens/AvatarScreen.swift` | 修改 | 接入 `PerceptionSource` → `RuleBasedEmotionStateMachine` → `RealityKitAvatarRenderer`、单飞行 `poseTask`、`M_track` 采集、JSONL 录制控制、摄像头权限降级提示、`scenePhase` 后台重置 |
| `App/MiniMate/Screens/Debug/AvatarDebugPanel.swift` | 修改 | 新增“状态与感知”“录制感知（JSONL 导出）”“指标（M_track p50/p90 + CSV 导出）”三个区块，保留既有动作与 52 滑杆调试区 |
| `Packages/MiniMateKit/Tests/MMPerceptionTests/OneEuroFilterTests.swift` | 新增 | T020：静止收敛、阶跃响应延迟上限、参数与时间戳边界 |
| `Packages/MiniMateKit/Tests/MMPerceptionTests/LookingAtScreenTests.swift` | 新增 | T021：夹角计算、20° 阈值边界、最短持续 200 ms、人脸丢失重置 |
| `Packages/MiniMateKit/Tests/MMPerceptionTests/ScriptedPerceptionSourceTests.swift` | 新增 | T025：JSONL 编解码、空行容错、坏行报错、`.immediate`/`.timed` 回放与 `stop()` 取消 |
| `Packages/MiniMateKit/Tests/MMEmotionTests/AttentionTransitionTests.swift` | 新增 | T022：Idle ↔ Attending、3 s 丢失回 Idle + `lookAround`、>3 s 回来 `notice`、快速靠近 `leanBack`、视线与 `eyeLook*` 方向、S-1/S-6 不变式 |
| `Packages/MiniMateKit/Tests/MMEmotionTests/TrackLatencyTrackerTests.swift` | 新增 | `M_track` 正常采样、微小抖动过滤、超限丢弃与与 `LatencyRecorder` 联动 |

#### 4.2 明确不做清单（Non-Goals）

- **严禁修改素材与构建管线**：不动 `App/MiniMate/Resources/Avatar/minimate.usdz`、`minimate.actions.json` 及 `Assets/avatar/` 下任何文件。
- **不做 US3 / US4 / US5 功能**：
  - 不实现 `FaceSignalDeriver.swift`（T033）、不填充 `expression-presets.json`（T034，保持 `[]`）、不实现表情反应延迟队列/冷却逻辑（T035）、不实现 `RecordingAvatarRenderer.swift`（T036）与镜像检测 UI（T037）；
  - 不实现 `HandGestureClassifier.swift`（T040）与 `VNDetectHumanHandPoseRequest` 手势抽帧（T041）；`ARKitPerceptionSource.setGestureRate(_:)` 仅记录并夹紧至 `0...15` 供 US4 读取，`gesture` 固定输出 `nil`；
  - 不实现完整对话事件状态机转换与口型层（T045）及调试面板对话事件注入（T046）；`RuleBasedEmotionStateMachine.handle(_ event: ConversationEvent)` 在本轮保持无副作用空实现（仅满足协议，留给 US5）。
- **严禁改写既有测试**：不动 `IdleMotionLayerTests.swift`、`BlendShapeIndexTests.swift`、`ActionClipManifestTests.swift`、`LatencyRecorderTests.swift` 及 `MMDiagnosticsTests` / `MMSecurityTests`。
- **严禁修改项目进度与实测文档**：本次代码实施阶段不勾选 `specs/002-m1-presence/tasks.md`，不向 `specs/002-m1-presence/research.md` 写入虚构的 `SC-002` 数据。
- **不引入任何第三方库**，不触碰 `MMDiagnostics`、`MMSecurity`、`SettingsView`、`DiagnosticsView`、`HomeView`。

---

### 5. 精确接口与行为契约

#### 5.1 `OneEuroFilter` & `OneEuroFilter3D`（T023）

- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMPerception/OneEuroFilter.swift`
  ```swift
  import Foundation
  import simd

  public struct OneEuroFilter: Sendable, Equatable {
      public let minCutoff: Double
      public let beta: Double
      public let dCutoff: Double

      /// 无效参数夹紧而非崩溃：minCutoff/dCutoff 下限 1e-4，beta 下限 0；非有限值回退默认。
      public init(minCutoff: Double = 1.0, beta: Double = 0.0, dCutoff: Double = 1.0)

      /// 输入新采样值与时间戳（秒），返回平滑后的值。
      public mutating func filter(_ value: Double, at timestamp: TimeInterval) -> Double

      /// 清空历史状态（如人脸丢失重获时调用）。
      public mutating func reset()
  }

  public struct OneEuroFilter3D: Sendable, Equatable {
      public init(minCutoff: Double = 1.5, beta: Double = 0.4, dCutoff: Double = 1.0)
      public mutating func filter(_ value: SIMD3<Float>, at timestamp: TimeInterval) -> SIMD3<Float>
      public mutating func reset()
  }
  ```
- **精确算法**：
  - $\alpha(f_c, \Delta t) = \frac{1}{1 + \frac{1}{2\pi f_c \Delta t}}$
  - 首帧直接记录 `xPrev = value, dxPrev = 0, tPrev = timestamp` 并返回 `value`。
  - 后续帧 `dt = timestamp - tPrev`：`dx = (value - xPrev) / dt`，`edx = lerp(dxPrev, dx, alpha(dCutoff, dt))`，`cutoff = minCutoff + beta * abs(edx)`，`xHat = lerp(xPrev, value, alpha(cutoff, dt))`。
- **边界与异常口径**：
  - `value` 或 `timestamp` 非有限（`NaN`/`Inf`）：不更新内部状态；若已有 `xPrev` 则返回 `xPrev`，否则返回 `0`。
  - `dt <= 0`（重复或倒退时间戳）：禁止除以 0，不更新内部状态，直接返回 `xPrev`。
  - `OneEuroFilter3D` 任一分量非有限或 `timestamp` 非有限时同上不污染状态。

#### 5.2 `LookingAtScreenDetector`（T021/T024 共享纯逻辑）

- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMPerception/LookingAtScreenDetector.swift`
  ```swift
  import Foundation
  import simd

  public struct LookingAtScreenDetector: Sendable, Equatable {
      public let maxAngleRadians: Float
      public let minDuration: TimeInterval
      public private(set) var isLookingAtScreen: Bool

      public init(maxAngleDegrees: Float = 20, minDuration: TimeInterval = 0.2)

      /// 在 ARFaceAnchor 局部坐标系中计算视线与相机方向夹角（弧度 ∈ [0, π]）。
      /// 任一向量含非有限值或模长 < 1e-5 返回 nil。
      public static func gazeAngleRadians(
          lookAtPointInFaceSpace: SIMD3<Float>,
          cameraPositionInFaceSpace: SIMD3<Float>
      ) -> Float?

      /// 更新状态并返回当前是否满足“持续看向屏幕”。
      public mutating func update(
          isFaceTracked: Bool,
          gazeAngleRadians: Float?,
          at timestamp: TimeInterval
      ) -> Bool

      public mutating func reset()
  }
  ```
- **边界口径**：
  - `maxAngleDegrees` 夹紧至 `> 0`（下限 `0.1`），`minDuration` 夹紧至 `>= 0`。
  - 判定条件：`isFaceTracked == true` 且 `angle` 有限且 **`angle < maxAngleRadians`**（严格小于 20°）。
  - 首次满足时记录 `candidateStartedAt = timestamp`；当 `timestamp - candidateStartedAt + 1e-9 >= minDuration` 时置 `isLookingAtScreen = true`。
  - 若 `!isFaceTracked` 或 `gazeAngleRadians == nil` 或 `angle >= maxAngleRadians`：立即清空 `candidateStartedAt = nil` 并置 `isLookingAtScreen = false`。
  - 若 `timestamp < candidateStartedAt`（时间戳倒退）：重置 `candidateStartedAt = timestamp`，`isLookingAtScreen = false`。

#### 5.3 `ScriptedPerceptionSource`（T025）

- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMPerception/ScriptedPerceptionSource.swift`
  ```swift
  import Foundation
  import MMCore

  public enum ScriptedPerceptionError: Error, Sendable, Equatable {
      case invalidUTF8
      case invalidLine(lineNumber: Int, message: String)
  }

  public final class ScriptedPerceptionSource: PerceptionSource, @unchecked Sendable {
      public enum ReplayMode: Sendable, Equatable {
          /// 立即按顺序推送所有帧并结束流（单元测试默认模式）。
          case immediate
          /// 按相邻帧 timestamp 差值除以 speed 调用 clock.sleep 推送。
          case timed(speed: Double = 1.0)
      }

      public let frames: [PerceptionFeatures]
      public let replayMode: ReplayMode

      public init(
          frames: [PerceptionFeatures],
          replayMode: ReplayMode = .immediate,
          clock: any MMCore.Clock = SystemClock()
      )

      public convenience init(
          jsonLinesData: Data,
          replayMode: ReplayMode = .immediate,
          clock: any MMCore.Clock = SystemClock()
      ) throws

      public convenience init(
          fileURL: URL,
          replayMode: ReplayMode = .immediate,
          clock: any MMCore.Clock = SystemClock()
      ) throws

      public var features: AsyncStream<PerceptionFeatures> { get }
      public func start() async throws
      public func stop()
      public func setGestureRate(_ hz: Double)

      /// 解码 JSON Lines（跳过纯空白行，支持 \n 与 \r\n；坏行抛出 invalidLine，1-based 行号）。
      public static func decodeJSONLines(_ data: Data) throws -> [PerceptionFeatures]
      /// 编码 JSON Lines（每帧一行紧凑 JSON + "\n"；空数组返回空 Data）。
      public static func encodeJSONLines(_ frames: [PerceptionFeatures]) throws -> Data
  }
  ```
- **复用约束**：调试面板（T028）录制导出必须直接调用 `ScriptedPerceptionSource.encodeJSONLines(_:)`，禁止手拼 JSON。
- **边界与异常口径**：
  - 订阅必须在 `start()` 前或后均可安全建立；建议测试中先获取 `let stream = source.features` 再调用 `try await source.start()`（或在 `start()` 后消费不会因竞态漏帧：若在 `start()` 时无订阅者，允许缓冲或明确文档——实现上推荐在 `features` getter 注册 continuation，`start()` 启动内部 replay `Task`，推送完毕自动 `finish()` 所有活跃 continuation）。
  - 坏 JSON 行严禁静默跳过，必须抛 `ScriptedPerceptionError.invalidLine(lineNumber:message:)`。
  - `stop()` 必须取消内部回放 `Task` 并 `finish()` 所有 continuation；`.timed(speed:)` 对 `speed <= 0` 夹紧至 `1e-3`。

#### 5.4 `ARKitPerceptionSource`（T024，`#if os(iOS)`）

- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift`
  ```swift
  #if os(iOS)
  import ARKit
  import AVFoundation
  import Foundation
  import os
  import simd
  import MMCore

  public final class ARKitPerceptionSource: PerceptionSource, @unchecked Sendable {
      public init(
          clock: any MMCore.Clock = SystemClock(),
          positionFilter: OneEuroFilter3D = OneEuroFilter3D(minCutoff: 1.5, beta: 0.4, dCutoff: 1.0),
          lookingDetector: LookingAtScreenDetector = LookingAtScreenDetector()
      )

      public var features: AsyncStream<PerceptionFeatures> { get }
      public func start() async throws
      public func stop()
      public func setGestureRate(_ hz: Double)
      /// 供后续 US4 读取当前已夹紧的手势帧率上限（0...15 Hz，默认 12）。
      public var gestureRateHz: Double { get }
  }
  #endif
  ```
- **复用约束**：
  - 位置平滑必须复用 `OneEuroFilter3D`；注视判定必须复用 `LookingAtScreenDetector`（含 `gazeAngleRadians`）。
  - `features` 使用 `AsyncStream(bufferingPolicy: .bufferingNewest(2))`，防 60 Hz 消费稍慢时队列积压拉高 `M_track`。
- **边界与异常口径**：
  - `start()`：① 若 `!ARFaceTrackingConfiguration.isSupported` → 抛 `PerceptionError.faceTrackingUnsupported`；② 查询 `AVCaptureDevice.authorizationStatus(for: .video)`，`.notDetermined` 时调用 `await AVCaptureDevice.requestAccess(for: .video)`，拒绝/受限 → 抛 `PerceptionError.cameraPermissionDenied`；③ 以 `ARFaceTrackingConfiguration()`（`isLightEstimationEnabled = false`、`maximumNumberOfTrackedFaces = 1`）启动独立 `ARSession`（`delegateQueue` 为专用串行队列 `ai.minimate.perception.arkit`）。
  - **Contract P-1**：人脸丢失（无 `isTracked == true` 的 `ARFaceAnchor`）时重置 `positionFilter`、更新 `lookingDetector(isFaceTracked: false, ...)`，并继续推送 `PerceptionFeatures(timestamp:, isFaceTracked: false, rawBlendShapes: [:], signals: FaceSignals(), facePosition: nil, isLookingAtScreen: false, gesture: nil)`。
  - **Contract P-5**：`sessionWasInterrupted(_:)` 置 `isInterrupted = true`、重置滤波器与注视器，期间**不推送任何帧**；`sessionInterruptionEnded(_:)` 置 `isInterrupted = false` 并重新 `session.run(configuration, options: [.resetTracking, .removeExistingAnchors])`。
  - **Contract P-6**：无任何网络请求、不保存或暴露 `capturedImage`。

#### 5.5 `IdleMotionLayer` 迁移与兼容别名（2A）

- **位置**：
  - 实体迁移至：`Packages/MiniMateKit/Sources/MMEmotion/IdleMotionLayer.swift`（完整保持原 `IdleMotion`、`IdleMotionLayer`、`Config`、所有 `public` 属性/方法签名不变，仅将 `any Clock` 显式写为 `any MMCore.Clock`）。
  - 兼容壳文件：`Packages/MiniMateKit/Sources/MMAvatar/IdleMotionLayer.swift`：
    ```swift
    import MMEmotion

    public typealias IdleMotion = MMEmotion.IdleMotion
    public typealias IdleMotionLayer = MMEmotion.IdleMotionLayer
    ```
- **兼容性约束**：`Packages/MiniMateKit/Tests/MMEmotionTests/IdleMotionLayerTests.swift` 不得改动一行，必须原样编译并 100% 通过。

#### 5.6 `RuleBasedEmotionStateMachine`（T026）

- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift`
  ```swift
  import Foundation
  import simd
  import MMCore
  import MMPerception

  public actor RuleBasedEmotionStateMachine: EmotionStateMachine {
      public static let maxHeadAngleRadians: Float = 25 * .pi / 180

      public init(
          rules: ReactionRules = .defaults,
          presets: [EmotionTag: ExpressionPreset] = [:],
          clock: any MMCore.Clock = SystemClock(),
          random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
          idleConfig: IdleMotionLayer.Config = .init()
      )

      public func handle(_ features: PerceptionFeatures) async
      public func handle(_ event: ConversationEvent) async
      public func pose(at time: TimeInterval) async -> AvatarPose
      public var state: AvatarState { get async }

      /// App 退到后台或外部显式中断时复位到 Idle，清空待触发动作与靠近历史。
      public func resetToIdle(at time: TimeInterval? = nil) async
  }
  ```
- **精确状态与行为规则（US2 范围，严格对齐 `contracts/emotion-state-machine.md`）**：
  1. **严禁读取 `features.rawBlendShapes`**（不变式 S-1）。
  2. **人脸重现与 `notice` 判定**：
     - 维护 `wasFaceTracked: Bool`（初值 `false`）与 `pendingNoticeOnAttend: Bool`（初值 `false`）。
     - 当 `features.isFaceTracked == true` 且 `!wasFaceTracked`：若存在 `let lastSeen = currentState.lastFaceSeenAt`，且 `features.timestamp - lastSeen > rules.idleAfterFaceLost`（严格 `>` 3 s），置 `pendingNoticeOnAttend = true`。
     - 随后更新 `wasFaceTracked = features.isFaceTracked`；仅当 `features.isFaceTracked == true` 时更新 `currentState.lastFaceSeenAt = features.timestamp` 与 `latestFacePosition = features.facePosition`。
  3. **Idle → Attending**：
     - 处于 `.idle` 时：
       - 若 `features.isFaceTracked && features.isLookingAtScreen`：若 `lookingStartedAt == nil` 记录 `features.timestamp`；当 `features.timestamp - lookingStartedAt! + 1e-9 >= rules.attendingEnter`（默认 0.2 s）：
         - 状态切换为 `.attending`，`enteredAt = features.timestamp`，清空 `lookingStartedAt` 与 `nextLookAroundAt`。
         - 若 `pendingNoticeOnAttend == true`：消费之（置 `false`），置 `pendingAction = .play(.notice)`。
       - 否则清空 `lookingStartedAt = nil`。
  4. **Attending → Idle（人脸丢失 ≥ `idleAfterFaceLost`）**：
     - 在 `handle(_ features:)`（以 `features.timestamp`）及 `pose(at: time)`（以 `time`）两处均检查：
       - 若处于 `.attending`，且 `!wasFaceTracked`（或超过 3 s 无新追踪帧）且 `let lastSeen = currentState.lastFaceSeenAt`，`now - lastSeen + 1e-9 >= rules.idleAfterFaceLost`：
         - 状态切换为 `.idle`，`enteredAt = now`，清空 `latestFacePosition = nil`、靠近窗口与 `lookingStartedAt`。
         - 置 `pendingAction = .play(.lookAround)`，并安排下一次低频 `lookAround`：`nextLookAroundAt = now + lerp(8.0, 14.0, unitRandom())`。
     - 持续处于 `.idle` 期间：若 `nextLookAroundAt == nil` 则初始化为 `time + lerp(8.0, 14.0, unitRandom())`；当 `time >= nextLookAroundAt!` 时置 `pendingAction = .play(.lookAround)` 并推进 `nextLookAroundAt = time + lerp(8.0, 14.0, unitRandom())`。
  5. **Attending + 快速靠近 → Reacting(`.surprised`, `.leanBack`)**：
     - 处于 `.attending` 且 `features.isFaceTracked == true` 且 `let pos = features.facePosition`：
       - `distance = abs(pos.z)`（同时兼容正 Z 规范坐标系与负 Z 原始相机夹具）；忽略非有限值。
       - 维护滑动窗口 `distanceHistory: [(time: TimeInterval, distance: Float)]`，裁剪 `features.timestamp - item.time > rules.approachWindow`（1.0 s）的旧记录，追加 `(features.timestamp, distance)`。
       - 若未在靠近冷却内（`approachCooldownUntil == nil || features.timestamp >= approachCooldownUntil!`），取窗口内 `maxDist = distanceHistory.map(\.distance).max()`；当 `maxDist - distance > rules.approachDistance`（0.15 m）：
         - 构造 `reaction = Reaction(expression: .surprised, action: .leanBack, duration: rules.reactionDuration, returnTo: .attending)`；
         - 切换为 `.reacting(reaction)`，`enteredAt = features.timestamp`；
         - 置 `pendingAction = .play(.leanBack)`；
         - 清空 `distanceHistory`，设置 `approachCooldownUntil = features.timestamp + rules.cooldown`。
     - **Reacting 到期回收**（在 `handle` 与 `pose(at:)` 检查）：
       - 当 `case .reacting(let reaction) = currentState.kind`，且 `now - currentState.enteredAt + 1e-9 >= durationSeconds(reaction.duration)`：
         - 若 `let lastSeen = currentState.lastFaceSeenAt` 且 `now - lastSeen >= rules.idleAfterFaceLost`，直接回到 `.idle`（并触发 `lookAround`）；否则回到 `reaction.returnTo`，更新 `enteredAt = now`。
  6. **姿态合成 `pose(at time: TimeInterval) -> AvatarPose`（第 1、5、6 步）**：
     - 若 `time` 早于内部上次求值时间，夹紧至 `lastEvaluatedTime` 以保证 `IdleMotionLayer` 时间单调递增。
     - **Step 1（底色）**：若 `presets[currentState.baseEmotion]` 存在，按 `weight * 0.3` 写入 `weights`；若处于 `.reacting(let r)` 且 `presets[r.expression]` 存在，按满强度合并（US2 默认 `presets` 为空，但测试注入预设时立即生效）。
     - **Step 5（待机层，2A）**：`let idleMotion = idleLayer.update(at: evalTime)`：
       - `weights["eyeBlinkLeft"] = max(weights["eyeBlinkLeft"] ?? 0, idleMotion.eyeBlink)`
       - `weights["eyeBlinkRight"] = max(weights["eyeBlinkRight"] ?? 0, idleMotion.eyeBlink)`
     - **Step 6（视线与头部朝向）**：
       - 若处于 `.attending` / `.listening` / `.speaking` / `.reacting` 且 `let pos = latestFacePosition`：
         - `let dist = max(abs(pos.z), 0.15)`
         - `let rawYaw = atan2(pos.x, dist)`，`let rawPitch = -atan2(pos.y, dist)`
         - `gazeYaw = clamp(rawYaw * 0.7, -maxHeadAngle, maxHeadAngle)`
         - `gazePitch = clamp(rawPitch * 0.5, -maxHeadAngle, maxHeadAngle)`
         - `eyeTarget = SIMD2(clamp(rawYaw / maxHeadAngle, -1, 1), clamp(atan2(pos.y, dist) / maxHeadAngle, -1, 1))`
       - 若处于 `.idle`：平滑随机游走（每 `2.5...5.0` s 用注入 `random` 生成新目标，yaw ∈ `[-8°, +8°]`、pitch ∈ `[-5°, +5°]`、`eyeTarget` ∈ `[-0.35, +0.35]`，按 `0.8 s` 缓动插值过去，无人脸时头部回中并缓慢四处看）。
       - 叠加呼吸微动并再次夹紧到 `[-maxHeadAngle, +maxHeadAngle]`：
         - `headRotation = SIMD3(clamp(gazePitch + idleMotion.headRotation.x, -max, max), clamp(gazeYaw + idleMotion.headRotation.y, -max, max), clamp(idleMotion.headRotation.z, -max, max))`
       - 将 `eyeTarget` 映射为 8 个 `eyeLook*` 权重（缩放系数 `0.70`）：
         - `eyeTarget.x > 0` → `eyeLookOutLeft`、`eyeLookInRight`
         - `eyeTarget.x < 0` → `eyeLookInLeft`、`eyeLookOutRight`
         - `eyeTarget.y > 0` → `eyeLookUpLeft`、`eyeLookUpRight`
         - `eyeTarget.y < 0` → `eyeLookDownLeft`、`eyeLookDownRight`
     - **不变式 S-6**：所有 `weights` 值夹紧至 `0...1`。
     - **边沿动作消费**：取 `let cmd = pendingAction; pendingAction = nil` 填入 `AvatarPose.action`。

#### 5.7 `TrackLatencyTracker`（T027 纯逻辑辅助）

- **位置与精确签名**：`Packages/MiniMateKit/Sources/MMEmotion/TrackLatencyTracker.swift`
  ```swift
  import Foundation
  import simd

  /// 测量 M_track：用户人脸位置显著变化 → 形象头部朝向跨越阈值的时间差（秒）。
  public struct TrackLatencyTracker: Sendable, Equatable {
      public let positionDeltaThreshold: Float      // 默认 0.015 m（1.5 cm）
      public let headRotationThreshold: Float       // 默认 0.5 * .pi / 180（0.5°，对齐渲染器阈值）
      public let timeout: TimeInterval              // 默认 1.0 s

      public init(
          positionDeltaThreshold: Float = 0.015,
          headRotationThreshold: Float = 0.5 * .pi / 180,
          timeout: TimeInterval = 1.0
      )

      /// 在收到感知帧时调用；记录显著位移起点。
      public mutating func observeFacePosition(
          _ position: SIMD3<Float>?,
          currentHeadRotation: SIMD3<Float>,
          at timestamp: TimeInterval
      )

      /// 在渲染器应用姿态时调用；若满足响应条件返回单次 M_track 样本（秒），否则返回 nil。
      public mutating func observeAppliedHeadRotation(
          _ headRotation: SIMD3<Float>,
          at timestamp: TimeInterval
      ) -> TimeInterval?

      public mutating func reset()
  }
  ```
- **边界口径**：
  - `position == nil`（人脸丢失）时清空待测刺激与基线位置。
  - 若已有未完成刺激且 `timestamp - stimulus.timestamp >= timeout`：丢弃超时刺激，不产生样本。
  - 若 `latency < 0`（异常时钟倒退）：丢弃，不产生负样本。

#### 5.8 `RealityKitAvatarRenderer` 微调（3A）

- **位置**：`Packages/MiniMateKit/Sources/MMAvatar/RealityKitAvatarRenderer.swift`
- **精确改动点**：
  1. `applyExpressionWeights(_ weights: [String: Float])`（约 134–154 行）：遍历完 `weights` 后，再遍历 `lastWrittenWeights` 中存在、不在 `weights` 内且上次值 `>= 0.001` 且在 `weightTargets` 内的键，将其作为 `0` 加入同批 `batches` 并更新 `lastWrittenWeights[name] = 0`。
  2. `applyHeadRotation(_ euler: SIMD3<Float>)`（约 520–541 行）：
     - `headFade` 调为 `0.04`（40 ms）；
     - `FromToByAnimation` 改为 `from: JointTransforms(to)`、`to: JointTransforms(to)`、`duration: 1.0 / 60.0`、`isAdditive: true`、`bindTarget: .jointTransforms`、`fillMode: .forwards`，`playAnimation(..., transitionDuration: Self.headFade, blendLayerOffset: 1, handoffType: .replace())`。
     - **严禁改动**：整骨架 `skeletonJointNames` / `skeletonRestPoses` 构造与第 500 行 `guard playback == nil else { return }`。

#### 5.9 App 层接线与调试面板（T027–T028）

- **`App/MiniMate.xcodeproj/project.pbxproj`**：按现有 `0A0A...0001..0004` / `5050...0001..0004` 编号风格新增 `0005`（`MMPerception`）与 `0006`（`MMEmotion`）四处引用。
- **`App/MiniMate/AppComposition.swift`**：新增 `func makePerceptionSource() -> (any PerceptionSource)?`（`#if os(iOS)` 返回 `ARKitPerceptionSource(clock: clock)`，其余平台返回 `nil`）与 `func makeEmotionStateMachine() -> any EmotionStateMachine`（返回 `RuleBasedEmotionStateMachine(clock: clock)`）。
- **`App/MiniMate/Screens/AvatarScreen.swift`（`AvatarScene` + `AvatarScreen`）**：
  - `AvatarScene` 接收 `clock: any MMCore.Clock`、`perceptionSource: (any PerceptionSource)?`、`stateMachine: any EmotionStateMachine`（保留无参默认构造供 `#Preview` 使用）。
  - **新增可观察状态**：`currentStateKind: AvatarStateKind`、`isFaceTracked: Bool`、`isLookingAtScreen: Bool`、`latestFacePosition: SIMD3<Float>?`、`latestHeadRotation: SIMD3<Float>`、`latestEyeTarget: SIMD2<Float>`、`perceptionErrorMessage: String?`、`isRecordingPerception: Bool`、`recordedFrameCount: Int`、`lastRecordedJSONLines: String?`、`latencyRecorder: LatencyRecorder`。
  - **调试兼容铁律**：
    - `debugWeights` 滑杆非零项覆盖状态机对应权重（保持 T019 52 滑杆逐项测试与 `-blendName` 启动参数 100% 可用）；
    - `debugFreezeIdle == true` 时冻结眨眼/呼吸与自动感知驱动（保持 `-freezeIdle` 截图回归 100% 可用）；
    - `previewAction` / `pendingAction` / `pendingStopAction` 优先于状态机的 `pose.action`，`shyEyeBlend` 逻辑完整保留。
  - **感知启动与权限降级**：`startPerception()` 启动 `perceptionSource.start()` 并拉起异步 `for await features in source.features` 任务转发至 `stateMachine.handle(features)`、`trackLatencyTracker.observeFacePosition(...)` 与录制缓存（录制上限 `10_800` 帧自动停止防 OOM）；捕获 `PerceptionError.cameraPermissionDenied` / `.faceTrackingUnsupported` 时写入友好中文提示并在 `AvatarScreen` 底部/顶部轻量展示（不阻塞形象 Idle）。
  - **生命周期**：`AvatarScreen` 监听 `@Environment(\.scenePhase)`，进入 `.background` 时调用 `await scene.handleBackground()`（调用状态机 `resetToIdle` 并清空 `trackLatencyTracker`）；`.onDisappear` 调用 `scene.stopPerception()`。
- **`App/MiniMate/Screens/Debug/AvatarDebugPanel.swift`**：
  - 在现有“动作”“表情系数（52）”“全部归零”基础上，新增 3 个 `Section`：
    1. **状态与感知**：展示 `state.kind`、`isFaceTracked`、`isLookingAtScreen`、人脸位置 `(x, y, z)`、头部欧拉角（度）与 `eyeTarget`、摄像头状态/错误提示；
    2. **录制感知**：开始/停止录制按钮、已录帧数显示、停止且有数据时展示 `ShareLink(item: jsonLines)` 导出 JSON Lines 与“清空录制”按钮；
    3. **指标（M_track）**：展示样本数、`p50 (ms)`、`p90 (ms)`、`ShareLink(item: scene.metricsCSV())` 导出 CSV 与“清空指标”按钮。

---

### 6. 原子化施工步骤（自底向上，TDD 先行）

- **Step 1：Package 测试依赖微调**
  - 改动文件：`Packages/MiniMateKit/Package.swift`
  - 改动要点：在 `MMPerceptionTests` 依赖加入 `"MMCore"`；在 `MMEmotionTests` 依赖加入 `"MMCore"`、`"MMPerception"`。
  - 最小验证命令：`cd Packages/MiniMateKit && swift test`

- **Step 2：T020 + T023 `OneEuroFilter`（先测试，后实现）**
  - 改动文件：`Packages/MiniMateKit/Tests/MMPerceptionTests/OneEuroFilterTests.swift`（先写）、`Packages/MiniMateKit/Sources/MMPerception/OneEuroFilter.swift`（后写）
  - 改动要点：按 7.1 写齐单测并确认编译/断言失败，再实现 `OneEuroFilter` 与 `OneEuroFilter3D`。
  - 最小验证命令：`cd Packages/MiniMateKit && swift test --filter OneEuroFilterTests`

- **Step 3：T021 `LookingAtScreenDetector`（先测试，后实现）**
  - 改动文件：`Packages/MiniMateKit/Tests/MMPerceptionTests/LookingAtScreenTests.swift`（先写）、`Packages/MiniMateKit/Sources/MMPerception/LookingAtScreenDetector.swift`（后写）
  - 改动要点：先写单测（夹角计算、19°/20°/21° 边界、199 ms vs 200 ms、人脸丢失立即重置），确认失败后实现。
  - 最小验证命令：`cd Packages/MiniMateKit && swift test --filter LookingAtScreenTests`

- **Step 4：T025 `ScriptedPerceptionSource`（先测试，后实现）**
  - 改动文件：`Packages/MiniMateKit/Tests/MMPerceptionTests/ScriptedPerceptionSourceTests.swift`（先写）、`Packages/MiniMateKit/Sources/MMPerception/ScriptedPerceptionSource.swift`（后写）
  - 改动要点：先写单测（JSONL 往返编码解码、空行跳过、坏行精确行号报错、`.immediate`/`.timed` 回放、`stop()` 取消），再实现。
  - 最小验证命令：`cd Packages/MiniMateKit && swift test --filter ScriptedPerceptionSourceTests`

- **Step 5：T024 `ARKitPerceptionSource`（iOS 条件编译验证）**
  - 改动文件：`Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift`
  - 改动要点：按 5.4 实现独立 `ARSession`、权限检查、时间基换算、竖屏相机坐标转换、`OneEuroFilter3D`、`LookingAtScreenDetector`、后台中断恢复。
  - 最小验证命令：`cd Packages/MiniMateKit && xcodebuild -scheme MMPerception -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`

- **Step 6：2A `IdleMotionLayer` 迁移 + T022/T026 `RuleBasedEmotionStateMachine` + `TrackLatencyTracker`（先测试，后实现）**
  - 改动文件：`Packages/MiniMateKit/Sources/MMEmotion/IdleMotionLayer.swift`、`Packages/MiniMateKit/Sources/MMAvatar/IdleMotionLayer.swift`、`Packages/MiniMateKit/Tests/MMEmotionTests/AttentionTransitionTests.swift`（先写）、`Packages/MiniMateKit/Tests/MMEmotionTests/TrackLatencyTrackerTests.swift`（先写）、`Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift`、`Packages/MiniMateKit/Sources/MMEmotion/TrackLatencyTracker.swift`
  - 改动要点：先完成 `IdleMotionLayer` 迁移并确认既有 `IdleMotionLayerTests` 零改动通过；再先写 `AttentionTransitionTests` 与 `TrackLatencyTrackerTests` 确认失败，随后实现 `RuleBasedEmotionStateMachine` 与 `TrackLatencyTracker`。
  - 最小验证命令：`cd Packages/MiniMateKit && swift test --filter "IdleMotionLayerTests|AttentionTransitionTests|TrackLatencyTrackerTests"`

- **Step 7：3A `RealityKitAvatarRenderer` 微调**
  - 改动文件：`Packages/MiniMateKit/Sources/MMAvatar/RealityKitAvatarRenderer.swift`
  - 改动要点：按 5.8 调整 `applyHeadRotation` 静态目标姿态 + 40 ms 过渡，以及 `applyExpressionWeights` 省略键归零。
  - 最小验证命令：`cd Packages/MiniMateKit && xcodebuild -scheme MMAvatar -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO && swift test`

- **Step 8：T027 + T028 App 工程链接、主界面接入与调试面板**
  - 改动文件：`App/MiniMate.xcodeproj/project.pbxproj`、`App/MiniMate/AppComposition.swift`、`App/MiniMate/Screens/AvatarScreen.swift`、`App/MiniMate/Screens/Debug/AvatarDebugPanel.swift`
  - 改动要点：补齐 `MMPerception`/`MMEmotion` 链接；注入感知源与状态机到 `AvatarScreen`；接入单飞行 `poseTask`、`M_track` 记录、权限提示与 `scenePhase` 后台复位；扩展 `AvatarDebugPanel` 展示状态/录制 JSONL/指标 CSV。
  - 最小验证命令：`xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`

---

### 7. 确定性测试矩阵与验收门禁

#### 7.1 测试矩阵（严禁非确定性断言，全部使用固定时钟与固定随机源）

| 目标测试文件 | 覆盖类别 | 测试场景 | 必须写死的断言底线（禁止弱断言） |
| :--- | :--- | :--- | :--- |
| `MMPerceptionTests/OneEuroFilterTests.swift` | 正例 | 静止常值叠加正弦/方波小幅噪声（60 Hz，2 s） | 输出标准差严格小于输入噪声标准差的 40%，且末段收敛在真值 ±0.02 内 |
| `MMPerceptionTests/OneEuroFilterTests.swift` | 正例 | 阶跃输入（0 → 1，`beta > 0` vs `beta == 0`） | 高 `beta` 达到 90% 目标值所需时间 `< 100 ms` 且严格快于 `beta == 0` |
| `MMPerceptionTests/OneEuroFilterTests.swift` | 边界/反例 | `minCutoff <= 0`、`beta < 0`、`dt == 0`、`dt < 0`、`NaN`/`Inf` 输入、`reset()` | 无 NaN/Inf 污染；`dt <= 0` 返回上一有效值；`reset()` 后首帧原样返回新值；`OneEuroFilter3D` 三轴独立收敛 |
| `MMPerceptionTests/LookingAtScreenTests.swift` | 正例 | `gazeAngleRadians`：同向 0°、垂直 90°、反向 180°、典型 15°/25° | 精确断言弧度误差 `< 1e-4` |
| `MMPerceptionTests/LookingAtScreenTests.swift` | 边界 | 19.9° 持续 199 ms vs 200 ms；20.0° 精确边界 | 199 ms 为 `false`，200 ms 翻为 `true`；20.0°（非严格小于）保持 `false` |
| `MMPerceptionTests/LookingAtScreenTests.swift` | 异常/反例 | 看向屏幕中途某帧 `isFaceTracked = false` 或 `angle = nil` 或零向量 | 立即翻为 `false` 且计时清零，重新注视需再满 200 ms 才恢复 `true` |
| `MMPerceptionTests/ScriptedPerceptionSourceTests.swift` | 正例 | `encodeJSONLines` → `decodeJSONLines` 往返 + `.immediate` 回放 | 完整 `PerceptionFeatures`（含 `facePosition`、`rawBlendShapes`）逐字段相等，流自然结束 |
| `MMPerceptionTests/ScriptedPerceptionSourceTests.swift` | 边界/反例 | 含空行与 `\r\n` 的合法 JSONL；第 2 行损坏 JSON；回放中途 `stop()` | 空行跳过；第 2 行精准抛出 `ScriptedPerceptionError.invalidLine(lineNumber: 2, ...)`；`stop()` 后提前结束流 |
| `MMPerceptionTests/ScriptedPerceptionSourceTests.swift` | 正例 | `.timed(speed: 2.0)` 注入 `FakeClock` 记录 `sleep` 时长 | 断言 `FakeClock` 收到的 sleep 时长等于帧间时间差 / 2.0（误差 `< 1e-6`） |
| `MMEmotionTests/AttentionTransitionTests.swift` | 正例 | Idle 收到 `isLookingAtScreen = true` 199 ms vs 200 ms | 199 ms 仍 `.idle`；200 ms 进入 `.attending`，首次见人无 `notice` 动作 |
| `MMEmotionTests/AttentionTransitionTests.swift` | 正例 | Attending 人脸丢失 2.9 s vs 3.0 s | 2.9 s 仍 `.attending`；3.0 s 回到 `.idle` 且 `pose(at:).action == .play(.lookAround)`，下一帧 `action == nil`（边沿触发） |
| `MMEmotionTests/AttentionTransitionTests.swift` | 正例 | 离开 5.0 s 后回来并持续看屏 200 ms（验证防误清逻辑） | 进入 `.attending` 且 `pose(at:).action == .play(.notice)`；若仅离开 1.5 s 再回则 `action == nil` |
| `MMEmotionTests/AttentionTransitionTests.swift` | 正例 | Attending 1 s 内 `z` 从 `0.60 m` 缩短至 `0.40 m`（Δ=0.20 m > 0.15 m） | 立即进入 `.reacting(Reaction(expression: .surprised, action: .leanBack, ...))`，`pose.action == .play(.leanBack)`；1.5 s 后回到 `.attending`；冷却期内重复靠近不重复触发 |
| `MMEmotionTests/AttentionTransitionTests.swift` | 正例/边界 | 人脸在右上方 `(0.3, 0.2, 0.5)` / 极端大偏角 `(2.0, 2.0, 0.2)` | 右上方：`headRotation.y > 0`、`headRotation.x < 0`、`eyeTarget.x > 0`、`eyeTarget.y > 0`、`eyeLookOutLeft > 0`、`eyeLookInRight > 0`、`eyeLookUpLeft > 0`；极端偏角时 `abs(headRotation)` 每轴均 `<= 25° + 1e-5` |
| `MMEmotionTests/AttentionTransitionTests.swift` | 不变式 S-1/S-6 | 输入 `rawBlendShapes = ["jawOpen": 0.95, "mouthSmileLeft": 0.9]` | `pose.expressionWeights["jawOpen"]` 为 `nil` 或 `0`；`mouthSmileLeft` 为 `nil` 或 `0`；所有输出权重 `∈ [0, 1]` |
| `MMEmotionTests/AttentionTransitionTests.swift` | 兼容/复位 | `resetToIdle()` 与 Idle 持续眨眼/呼吸/游走 | Attending 下调用 `resetToIdle()` 立即回到 `.idle`；注入固定随机源验证眨眼在 `[2, 6] s` 出现 |
| `MMEmotionTests/TrackLatencyTrackerTests.swift` | 正例/边界/反例 | 2 cm 位移 → 45 ms 后头转 1°；0.5 cm 抖动不触发；1.2 s 超时丢弃；写入 `LatencyRecorder` | 精准返回 `0.045`；小抖动与超时均返回 `nil`；接入 `LatencyRecorder` 后 `p50`/`p90` 准确 |
| `MMEmotionTests/IdleMotionLayerTests.swift`（既有） | 兼容回归 | 零修改原样运行全部 7 个已有用例 | 全部通过，证明 `MMAvatar` 别名兼容无损 |

#### 7.2 完整门禁命令清单

```bash
# 1. 目标模块纯逻辑单元测试（macOS）
cd Packages/MiniMateKit && swift test --filter "MMPerceptionTests|MMEmotionTests|MMCoreTests"

# 2. Swift Package 全量单元测试（macOS）
cd Packages/MiniMateKit && swift test

# 3. 包内 iOS 条件编译验证（校验 ARKitPerceptionSource 与 MMAvatar 的 #if os(iOS) 分支）
cd Packages/MiniMateKit && xcodebuild -scheme MMPerception -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
cd Packages/MiniMateKit && xcodebuild -scheme MMEmotion -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
cd Packages/MiniMateKit && xcodebuild -scheme MMAvatar -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

# 4. App 模拟器编译验证（无签名，验证 project.pbxproj 链接与 SwiftUI/RealityKit 接线）
xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# 5. 隐私与仓库基线校验
git status
git diff --stat
```

#### 7.3 后续人工真机验收步骤（T029，不计入代码施工门禁）

代码闭环且通过复审后，由用户在 Xcode 真机安装运行 `specs/002-m1-presence/quickstart.md` 第二节（US2 / SC-002）：
1. 首次进入“形象”页授权摄像头（另测一次系统设置关闭权限，确认提示清晰且形象仍正常 Idle）；
2. 不看屏幕 10 秒：观察呼吸、眨眼、低频四处张望；
3. 看向屏幕：0.5 s 内进入 Attending 并转向自己；
4. 左右上下移动头部：核对调试面板中 `facePosition` 与 `headRotation` 符号一致（向右移 `x > 0`、`yaw > 0`、形象看向屏幕右侧；向上移 `y > 0`、`pitch < 0`、形象抬头），且跟随平滑无抖动；
5. 离开画面 5 秒再回来：离开 3 s 后回 Idle 张望，回来后触发一次 `notice`；
6. 1 秒内凑近 > 15 cm：触发 `leanBack`；
7. 调试面板测试“录制感知”导出 `.jsonl` 与“指标”读取 `M_track` p50 / p90（目标 p50 < 100 ms、p90 < 150 ms）；验收确认后再填写 `research.md` 并勾选 T020–T029。

---

### 8. 项目附加产出要求

- 本轮代码施工阶段**无需修改** `docs/tech-selection.md`、`specs/002-m1-presence/research.md` 或 `specs/002-m1-presence/tasks.md`。
- 若 T029 真机验收时发现坐标系符号、平滑参数或 `SC-002` 结论与文档假设不符，再按宪章 III/V 与用户确认后同步回写 `research.md` 与 `docs/tech-selection.md`。

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

- **闭环结论**：一致通过（共 2 轮独立只读复审，独立审查员模型：Gemini 4 Neon (High)，两轮送审前后 `git status`/`git diff`/未跟踪文件哈希 100% 字节级一致，确认审查员零修改）。
- **Round 1（需修改 — 4 阻断项 + 3 非阻断建议）**：
  1. **[已根治] 阻断项 1（并发重入 + 摄像头泄漏 + 旧 session 回调隔离）**：`AvatarScene.startPerception()` 增加 `isStartingPerception` 防重入与 `perceptionGeneration` 代次校验，启动挂起后若已取消或停用立即 `source.stop()`；`ARKitPerceptionSource.start()` 在 `requestAccess` 后检查 `Task.isCancelled`，替换旧 session 前清 `delegate = nil`，`handleFrame`/`handleSessionWasInterrupted` 均校验当前活跃 session。
  2. **[已根治] 阻断项 2（`M_track` 采样口径）**：`AvatarScene` 新增 `canMeasureTrackLatency`（仅 `currentStateKind == .attending && playingAction == nil`），非追踪态或动作播放期复位 `trackLatencyTracker`，杜绝呼吸/游走虚假样本污染 `SC-002`。
  3. **[已根治] 阻断项 3（`ScriptedPerceptionSource` 重复 `start()` 并发竞态）**：引入 `activeRunID: UUID?`，锁内原子切换并校验 `activeRunID` 与取消状态，避免旧任务取消收尾误杀新流；补齐确定性回归测试 `restartDoesNotFinishNewStreamFromCancelledPreviousRun`。
  4. **[已根治] 阻断项 4（后台 `poseTask` 取消 + 调试面板实时刷新）**：`handleBackground()` 开头取消并清空 `poseTask` 与头部/视线状态；`AvatarDebugPanel` 打开期间在 `perceptionTask` 同步刷新 `currentStateKind`、`latestHeadRotation`、`latestEyeTarget`（保留非空 `pose.action`，不计入 `M_track`）。
  5. **[已顺带采纳] 非阻断建议 1–3**：`RuleBasedEmotionStateMachine.checkReactingExpiration` 补齐 `+ 1e-9` 容差；补充 Idle 8–14 s 周期性 `lookAround`、Reacting 到期人脸丢失 ≥ 3 s 回 Idle、负延迟丢弃 3 个回归断言；`AvatarScreen` 改用 `isShowingDebugPanel` + `.navigationDestination(isPresented:)` 显式驱动 `setDebugPanelPresented`。
- **Round 2（通过 — 阻断项 0）**：
  - 全部 4 个阻断项与 3 条顺带修复均获独立复核确认无回归。
  - 极轻备忘（无需返工）：`canMeasureTrackLatency` 后续可按需加 `&& !isDebugPanelPresented`。
- **最终验收门禁证据**：
  - `swift test`（macOS 全量）：**76/76 全部通过**（`MMSecurityTests` 7、`MMPerceptionTests` 13、`MMEmotionTests` 34 含既有 `IdleMotionLayerTests` 7、`MMDiagnosticsTests` 14、`MMCoreTests` 8）。
  - `xcodebuild` iOS 编译（`MMPerception`、`MMEmotion`、`MMAvatar`）与 `MiniMate` iOS Simulator 编译：全部 `BUILD SUCCEEDED`；审查员亦独立以 `swiftc -sdk iPhoneOS27.0.sdk -swift-version 6` 校验全包与 App Debug/Release 零错误零警告。
  - 人工真机验收（T029 / Quickstart §2）：待用户在真机执行，尚未勾选 `tasks.md`、未写入 `research.md`、未 `git commit`。
