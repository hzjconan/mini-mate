# Codebase Map

> 仅作冷启动导航与种子线索；与真实代码冲突时以代码为准，并在变更模块边界/入口/公共设施时同步更新。

## 1. 模块 / 子包职责表

| 路径 | 职责边界 |
| :--- | :--- |
| `App/MiniMate/` | iOS 26+ SwiftUI App 与组合根（`MiniMateApp`、`AppComposition`）；objectVersion 77 文件系统同步组，新增文件自动纳入 target |
| `App/MiniMate/Screens/` | 主页面与调试面板：`HomeView`、`AvatarScreen`（含 `AvatarScene` 60 Hz 渲染与感知/对话接线）、`DiagnosticsView`、`SettingsView`、`Debug/AvatarDebugPanel` |
| `App/MiniMate/Resources/Avatar/` | 真机打包 3D 资产：`minimate.usdz` 与 `minimate.actions.json`（由 `Assets/avatar/auto-build` 产出并字节同步） |
| `Packages/MiniMateKit/Sources/MMCore/` | 零外部依赖核心领域模型与基础设施：`Clock`/`SystemClock`、`EmotionTag`、`ActionTag`、`UserEmotion`、`AssistantCommand`、`AvatarCue`、`PlaybackResult`、`ConversationEvent`、`Metrics/LatencyRecorder` |
| `Packages/MiniMateKit/Sources/MMDiagnostics/` | 端侧能力探测（V1–V3：`ARKitProbe`、`FoundationModelsProbe`、`NLEmbeddingProbe`、`SpeechProbes`、`EmbeddingSmokeTest`）与 `DiagnosticsRunner` |
| `Packages/MiniMateKit/Sources/MMSecurity/` | API Key 安全存储协议 `CredentialStore`、`KeychainCredentialStore` 与 `VendorID` |
| `Packages/MiniMateKit/Sources/MMPerception/` | 本地感知层：`PerceptionSource` 协议、`PerceptionFeatures`、`ARKitPerceptionSource`（`#if os(iOS)`，TrueDepth + 12 Hz Vision 手势 + 热降频）、`ScriptedPerceptionSource`、`FaceSignalDeriver`、`HandGestureClassifier`、`LookingAtScreenDetector`、`OneEuroFilter`、`ThermalGesturePolicy` |
| `Packages/MiniMateKit/Sources/MMEmotion/` | 情绪与注意力状态机：`EmotionStateMachine`、`RuleBasedEmotionStateMachine`、`AvatarState`/`AvatarPose`、`ReactionRules`、`ExpressionPreset`（+ `Resources/expression-presets.json`）、`MirrorCorrelationEvaluator`、`TrackLatencyTracker`、`ReflexLatencyTracker`、`FeedbackLatencyTracker` |
| `Packages/MiniMateKit/Sources/MMAvatar/` | 形象渲染层：`AvatarRenderer` 协议、`RealityKitAvatarRenderer`（`#if os(iOS)` 骨骼/形态键/动作驱动）、`RecordingAvatarRenderer`、`ActionClipManifest`、`AnimationNameMatcher`、`BlendShapeIndex`、`HeartEffect`、`IdleMotionLayer` |
| `Packages/MiniMateKit/Tests/` | Swift Testing 纯逻辑单元测试套件（`MMCoreTests`、`MMDiagnosticsTests`、`MMSecurityTests`、`MMPerceptionTests`、`MMEmotionTests`），macOS 下 `swift test` 直接运行 |
| `Assets/avatar/auto-build/scripts/` | Blender 5.3 + Python 自动化 3D 形象构建、动作时间线、USDZ 导出、渲染与确定性校验管线（Phase 0 / Phase 1） |
| `scripts/` | 本机运维脚本：`deploy-ios.sh`（零依赖一键编译、安装并启动到真机） |
| `specs/` | Spec Kit 规格/计划/任务与跨 feature 契约（`001-m0-foundation` ~ `005-voice-photo`，索引见 `specs/README.md`） |
| `docs/` | 选型依据（`tech-selection.md`）、执行单（`handoffs/`）、偶发问题追踪（`issues/`）、架构与排查文档（`avatar-action-binding-issue.md`、`CODEBASE_MAP.md`、`HANDOFF_LEDGER.md`） |

> 计划中尚未建立的 Package 模块（见 `AGENTS.md` / `specs/003` / `specs/004`）：`MMAudio`、`MMConversation`、`MMMemory` 与 `mm-probe` CLI。

## 2. 外部入口清单

- **iOS App 入口**：`App/MiniMate/MiniMateApp.swift`（`@main MiniMateApp` → `HomeView`，注入 `AppComposition`）
- **组合根**：`App/MiniMate/AppComposition.swift`（构造 `SystemClock`、`KeychainCredentialStore`、`ARKitPerceptionSource`、`RuleBasedEmotionStateMachine`）
- **核心交互页**：`App/MiniMate/Screens/AvatarScreen.swift`（支持 `-freezeIdle` / `-blendName` / `-previewAction` / `-playAction` 启动调试参数；形象页活跃期防自动锁屏；内置 `AvatarDebugPanel` 实时观察、事件注入与 10 分钟 SC-006 稳定性压测导出）
- **真机部署脚本**：`scripts/deploy-ios.sh`（`./scripts/deploy-ios.sh [--device <UDID>] [--configuration Debug|Release] [--no-launch] [--dry-run]`）
- **3D 资产构建管线**：`Assets/avatar/auto-build/scripts/build_phase1.py` → `export_phase1.py` → `validate_phase1.py` → `render_phase1.py` / `render_usd_preview_phase1.py`
- **常用校验命令**：
  - macOS 纯逻辑单测：`cd Packages/MiniMateKit && swift test`
  - iOS 单模块条件编译：`cd Packages/MiniMateKit && xcodebuild -scheme <Module> -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`
  - App 模拟器无签名编译：`xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`

## 3. 公共复用设施与测试夹具

| 能力 | 位置 | 复用说明 |
| :--- | :--- | :--- |
| 时钟抽象 | `Packages/MiniMateKit/Sources/MMCore/MMCore.swift` | 统一注入 `any MMCore.Clock`（严禁裸写 `any Clock` 冲突 `Swift.Clock`）；测试用可控手动时钟 |
| 延迟指标采集与 CSV 导出 | `Packages/MiniMateKit/Sources/MMCore/Metrics/LatencyRecorder.swift` | 统一记录 `M_track`/`M_reflex`/`M_feedback` 及 p50/p90/命中率/CSV，禁止重复造百分位统计 |
| 稳定性压测采样聚合与物理内存工具 | `Packages/MiniMateKit/Sources/MMCore/Metrics/StabilitySessionRecorder.swift` | `StabilitySessionRecorder`（1 Hz FPS/内存/热状态/中断聚合 + Markdown/CSV）与 `ProcessMemory`（`task_vm_info.phys_footprint`） |
| 1€ 低通滤波器 | `Packages/MiniMateKit/Sources/MMPerception/OneEuroFilter.swift` | 含非法参数夹紧与非有限值防御，`ARKitPerceptionSource` 与 `FaceSignalDeriver` 共用 |
| 回放型感知源 | `Packages/MiniMateKit/Sources/MMPerception/ScriptedPerceptionSource.swift` | JSONL 编解码与可编程帧流回放，供离线测试与录制复现复用 |
| 记录型渲染器 | `Packages/MiniMateKit/Sources/MMAvatar/RecordingAvatarRenderer.swift` | 实现 `AvatarRenderer` 协议，用于纯逻辑测试捕获 `AvatarPose` 输出（如非镜像校验） |
| 规范 52 形态键索引 | `Packages/MiniMateKit/Sources/MMAvatar/BlendShapeIndex.swift` | `BlendShapeIndex.arkitNames` 为 52 ARKit camelCase 键唯一事实源 |
| 表情预设默认表 | `Packages/MiniMateKit/Sources/MMEmotion/ExpressionPreset.swift` + `Resources/expression-presets.json` | 进程级惰性缓存 `ExpressionPreset.bundledDefaults`，通过 `Bundle.module` 根目录加载 |
| 延迟追踪器族 | `Packages/MiniMateKit/Sources/MMEmotion/{Track,Reflex,Feedback}LatencyTracker.swift` | 统一纯逻辑 `Sendable` 状态追踪范式（含超时与非法时间防御） |
| 动作时间线唯一事实源 | `Assets/avatar/auto-build/scripts/avatar_common.py` | `make_actions` 与 `build_animation_timeline` 定义全部 8 个动作与 `.actions.json` |

## 4. 依赖方向与禁改边界

- **依赖方向（严格单向，禁止循环依赖）**：
  - `App/MiniMate` → `MMCore`, `MMDiagnostics`, `MMSecurity`, `MMPerception`, `MMEmotion`, `MMAvatar`
  - `MMDiagnostics` → `MMCore`
  - `MMPerception` → `MMCore`（禁止反向依赖 `MMEmotion`）
  - `MMEmotion` → `MMCore`, `MMPerception`（禁止反向依赖 `MMAvatar`）
  - `MMAvatar` → `MMCore`, `MMEmotion`
  - `MMSecurity` → 无包内依赖
- **架构红线（见 `.specify/memory/constitution.md`）**：
  - **陪伴而非镜像**：用户感知信号（除视线追踪外）严禁绕过 `EmotionStateMachine` 直接驱动渲染。
  - **感知在本地**：摄像头帧、blendShapes、手势、视线严禁送入 LLM。
  - **可替换边界**：感知（`PerceptionSource`）、对话（`ConversationEngine`）、渲染（`AvatarRenderer`）以协议隔离；云端鉴权与厂商细节收敛在 Provider 内部。
- **只读 / 禁改 / 隐私边界**：
  - `Assets/voice-samples/*.wav`：含个人声音样本，**严禁提交或读取上传**。
  - `Assets/avatar/VRoid_V110_Female_v1.1.3.vrm`、`Assets/avatar/reference/`：只读原始参考素材，禁止覆盖修改。
  - API Key 仅存 iOS Keychain（App）或环境变量（CLI），**严禁写入仓库、日志或测试夹具**。
  - `debug/`：真机导出的临时录制与指标原始数据，仅作分析参考，不作为代码依赖。
  - `docs/handoffs/`：历史执行单只读留档，**严禁移动、重命名或删除**。
