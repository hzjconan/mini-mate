# Handoff Ledger

> 滚动活体台账（严格 ≤ 100 行）。仅作上下文承接种子线索，已解决待办立即删除，过旧契约滚动裁剪。

## 1. 未清零遗留待办（非阻断项 / 已知限制）

- `[002-m1-us4 / issue-001]` 真机偶发观察：静止注视时约每 14–15 s 向左下方低头约 3 s 后回平视（2026-11-27 10 分钟 SC-006 压测期间未复现，继续观察），排查线索与取证步骤见 `docs/issues/001-periodic-bottom-left-head-drop.md`。
- `[002-m1-avatar]` `Assets/avatar/auto-build/scripts/validate_phase1.py` 动作防穿模目前仅校验第 15 帧（独立全帧 `1..35` 实测无穿模），后续修改动作轨道时可按需扩至多帧抽检。
- `[002-m1-polish]` 极轻优化备忘：`AvatarDebugPanel` 表情预设导出 JSON 可按需增加缓存；`AvatarScreen.swift:491` 非热态中断回传可用 `min(currentThermal, .fair)` 替代 `.nominal` 避免 `.fair` 态多出 1 对瞬态跳变。

## 2. 已实测的环境与第三方依赖陷阱

- **Swift 6.4 `Swift.Clock` 命名冲突**：裸写 `any Clock` 会与标准库 `Swift.Clock` 歧义报错 → 所有源码与测试引用 `MMCore` 时钟协议必须显式写 `any MMCore.Clock`。
- **沙盒内 `swift test` Clang Module Cache 权限**：默认 `/var/folders/.../C/clang/ModuleCache` 不可写 → 沙盒内运行单测须带 `CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox`（常规本机终端直接 `swift test`）。
- **ARKit `ARFrame.timestamp` 与 `Clock.now` 时间基不一致**：`ARFrame.timestamp` 为 `systemUptime` 单调秒数，与 `timeIntervalSinceReferenceDate` 相差约 8 亿秒 → `ARKitPerceptionSource` 须以 `systemUptime - frame.timestamp` 差值换算至 `clock.now.timeIntervalSinceReferenceDate` 并做单调递增保护。
- **ARKit 真机 `BlendShapeLocation.rawValue` 带 `_L`/`_R` 后缀**：真机返回 `"mouthSmile_L"` 等非标准键名 → 已在 `ARKitPerceptionSource` 用 52 键显式映射表规范为 camelCase `Left`/`Right`，并在 `FaceSignalDeriver` 保留 `_L`/`_R` 兼容兜底。
- **Swift 6 `CVPixelBuffer` 非 `Sendable` + 前置横向缓冲区**：跨 `gestureQueue` 禁止持有 `ARFrame`（会耗尽帧池），须仅传 `UncheckedBox(frame.capturedImage)` + 单飞行丢帧；`VNImageRequestHandler` 必须显式传 `orientation: .leftMirrored`。
- **RealityKit 骨架动画防飞出铁律（`docs/avatar-action-binding-issue.md`）**：严禁删除 `RealityKitAvatarRenderer` 的 `guard playback == nil else { return }`，且 `FromToByAnimation<JointTransforms>` 必须传完整 `skeletonJointNames` 整骨架数组。
- **SwiftPM `.process("Resources")` 扁平化路径**：`expression-presets.json` 位于 `Bundle.module` 根目录 → 必须用 `Bundle.module.url(forResource:withExtension:)`，严禁传 `subdirectory: "Resources"`。
- **Blender 5.3 / Phase 1 资产管线**：内建 NumPy 2.x 已移除 `ndarray.ptp()`（须用 `np.ptp(arr)`）；手指骨骼反向且枢轴错位，严禁对骨骼执行 `armature_apply`（改为网格空间解剖枢轴变形）；`build_phase1.py` 保存前须调用 `ac.make_actions` 防回退旧动作；Phase 1 脚本零依赖 VRM Add-on 可在沙盒直跑。
- **`M_feedback` 与 SC-006 FPS 在全屏调试面板下的采集**：`NavigationDestination` 推入全屏 `AvatarDebugPanel` 时底层 `RealityView` `tick()` 暂停 → `M_feedback` 面板开启态直接记录；SC-006 压测必须在 `setDebugPanelPresented(_:)` 中 `pause`/`resume` 防止恢复后产生假 0 fps。
- **`AvatarScene` `@MainActor deinit` 与前后台防锁屏**：严禁在 `@MainActor` 类 `deinit` 访问 `UIApplication.shared`；`isIdleTimerDisabled` 须在 `startPerception` / `stopPerception` / `handleBackground` / `handleForeground` 成对维护并配合 `isSceneActive` 防挂起竞态。
- **`AVAudioConverter` 48k→16k FIR 延迟与路由切直通**：48k→16k 单块 4,800 帧会滞留 240 帧（15 ms）→ 须循环拉取 + `flush()`（`.endOfStream`）排空，且同率直通切换时须清空旧转换器状态防残留旧路由样本。
- **Swift 6.4 `~`/`～` 非标点与枚举键字典 JSON 编解码**：`Character("~").isPunctuation` / `Character("～").isPunctuation` 均为 `false`（Unicode `Sm` 类），可播内容判定须用 `isLetter || isNumber`；`JSONDecoder` 对 `[EmotionTag: V]` 默认按交替数组解析，须经 `[String: V]` 手动对象编解码且 `JSONScalar` 按 `Bool → Double → String` 顺序解码。
- **系统 `zlib` / `.copy("Fixtures")` / 流式 PCM 对齐与短凭证遮罩**：`import zlib` 须在 `Package.swift` 声明 `linkerSettings: [.linkedLibrary("z")]`；SwiftPM `.copy("Fixtures")` 保留子目录，须传 `subdirectory: "Fixtures"`；流式 TTS PCM 奇数字节跨帧须经 `PCMByteAligner` 拼接防声道错位；短凭证（≤ 4 字符）须全遮罩为 `"****"`；静态密钥/厂商残留扫描须覆盖未跟踪文件（`grep` 而非仅 `git grep`）。

## 3. 近期关键契约变更（滚动保留最近 5–8 项）

- `[003-m2-phase3a]` 厂商无关多供应商架构与插件化 `mm-probe` 底座：彻底删除 `MMSecurity/VendorID.swift`（代码库实现零厂商残留）；新增 `ProviderRole`（`realtimeBrain` / `emotionalTTS`）、`ProviderProfile`、`JSONFileProviderProfileStore` 与按 `profileID: UUID` 键控的 Keychain `CredentialStore` v2（主+副凭证）；重构 `SettingsView` + `ProviderProfileEditorSheet`（双用途 1..N 动态增删 + Active 切换）；泛化 `TTSEmotionMapping`（`driverID: String` + `EmotionParameterSet`）；落地 `WAVCodec`/`PCMByteAligner`、`SecretRedactor`、`WebSocketTransport`/`HTTPStreamingTransport`/`RecordingWebSocketTransport`、`GzipCodec`、`FakeRealtimeTextSession`、`ProviderRegistry`（内置 `mock-realtime`/`mock-tts`）与 `MMProbeCore`/`MMProbeCLI` 5 子命令；`AGENTS.md` 写入开发/Debug 隐私红线；全量单测基线 **190/190（31 suites）**。
- `[003-m2-phase1-2]` M2 工程基座与纯逻辑底座（`T001`–`T014`）：新增 `MMAudio`、`MMConversation`、`MMProbeCLI`（`mm-probe` 占位）及 `MMAudioTests`/`MMConversationTests`；`MMCore` 新增 `ConnectionState`/`GateState`/`GateThreshold` 及 `ConversationEvent` 扩展；落地 `TagParser`（T-1–T-10）、`SentenceSplitter`（S-1–S-7）、`Persona`（`persona.md` + 1–6 条 instructions）、`RealtimeTextSession`/`TTSProvider`/`TTSEmotionMapping`/`FakeTTSProvider`/`PCMConverter`；App `project.pbxproj` 补麦克风权限；全量单测基线 **180/180（28 suites）**。
- `[002-m1-polish]` M1 正式收官（`T048`–`T050`）：`MMCore` 新增 `StabilitySessionRecorder` / `ProcessMemory`（1 Hz `phys_footprint`）；`ARKitPerceptionSource` 新增 `sessionInterruptionCount` / `thermalSessionInterruptionCount` / `isSessionInterrupted` 与 Vision `autoreleasepool`；`AvatarScreen` 接入形象页防自动锁屏与 SC-006 压测导出；`ReactionRules` 快速靠近收紧为 `0.6 s / >0.14 m / ≤0.38 m`；SC-006 10 分钟真机全项通过（avg `59.95 fps` / max `518.2 MiB` / 全程 `nominal`），`tech-selection.md` 升至 `v3.7`；全量单测基线 **146/146（24 suites）**。
- `[002-m1-us5]` `MMCore` 新增 `AssistantCommand`、`PlaybackResult`、`AvatarCue` 并扩展 `ConversationEvent`（`.assistantCommand`/`.assistantCue`/`.assistantCueEnded`）；`RuleBasedEmotionStateMachine` 实现完整对话阶段转换、口型同步与 `EM-1..EM-5` 形象提示；新增 `FeedbackLatencyTracker` 与 `AvatarScreen`/`AvatarDebugPanel` FIFO 串行对话事件注入。
- `[005-voice-photo]` 定稿语音拍照 SDD 全套文档并同步 002/003/004 共享契约（`<cmd>`、`AvatarCue` EM-1–EM-5、`holdReplies`/`releaseReplies` RH-1–RH-5、`PhotoCaptureSource`）。
- `[002-m1-us4]` `MMPerception` 新增 `HandGestureClassifier`（挥手 / 单手韩式比心 / 双手比心 / 点赞）与 `ThermalGesturePolicy`；`ARKitPerceptionSource` 接入 12 Hz Vision 异步抽帧、热降频与 `AsyncStream` 背压手势恢复重发；`RuleBasedEmotionStateMachine` 支持手势立即反应与 `updateCooldown(_:at:)`（App 默认 5 s）。
- `[002-m1-us3]` 新增 `FaceSignalDeriver`、`MirrorCorrelationEvaluator`、`ReflexLatencyTracker`、`RecordingAvatarRenderer` 与 `expression-presets.json`（8 情绪预设）；`RuleBasedEmotionStateMachine` 支持延迟/冷却/防镜像表情反应与 `updatePreset(_:)` 热更新。
- `[002-m1-avatar]` 完成小瓜 3D 形象 Phase 1.4 精修（直腿 / 厚掌 / 微弯手 / 白袜），`minimate.usdz`（39,032 三角面 / 52 ARKit / 124 形态键 / 8 动作 / 295 帧）与 `.actions.json` 同步至 `App/MiniMate/Resources/Avatar/`。
