# 003-m2-voice-conversation Phase 1–2（工程基座与纯逻辑底座）执行单

- **状态**：已完成并验收（T001–T014）
- **Git 基线**：`main` @ `25bc511`
- **关键基线**：Swift 6.4 / Xcode 27.0 / macOS 27.2.0 / `swift-tools-version: 6.2` / 零第三方依赖 / 既有纯逻辑单测 146/146（24 suites）全绿
- **拍板决议摘要**：用户于 2026-11-28 全按推荐项拍板（`1A`：`ConnectionState`/`GateState` 归属 `MMCore`；`2A`：`AudioChunk.samples: [Int16]` + `pcmData` 互转；`3A`：`Persona.makeInstructions` 默认包含第 1–6 条且提供 `includeCommandInstructions` 开关；`4A`：`project.pbxproj` 仅增补 `INFOPLIST_KEY_NSMicrophoneUsageDescription`，暂不预链接 `MMAudio`/`MMConversation`）

> **红线声明**
> - 严禁读取、修改或提交 `Assets/voice-samples/*.wav`、`Assets/avatar/VRoid_V110_Female_v1.1.3.vrm`、`Assets/avatar/reference/`；严禁移动、重命名或删除 `docs/handoffs/` 历史执行单。
> - API Key 仅存 iOS Keychain（App）或环境变量（`mm-probe`），严禁写入仓库、日志、错误描述或测试夹具（宪章 VII）。
> - 不引入任何第三方依赖；Swift 6 严格并发检查；纯逻辑模块严格遵守 Test-First（先写测试确认红灯，再写实现转绿，宪章 V）。
> - 设计阶段仅修改本执行单；未经用户明确确认验收，不得 `git commit`、不得 `git push`、不得勾选 `specs/003-m2-voice-conversation/tasks.md` 任务项。

---

## 上篇：面向用户决策

### 1. 任务目标与选择理由
- **本次任务**：交付 `003-m2-voice-conversation` Phase 1–2（`specs/003-m2-voice-conversation/tasks.md` 的 `T001`–`T014`）——搭好 `MMAudio`、`MMConversation`、`MMProbeCLI`（`mm-probe`）及两套测试 target 的工程基座，落地麦克风权限、语音样本 `.gitignore`、`Persona` 与标签协议 instructions、核心跨模块事件/音频/会话/TTS 协议与假实现，以及全覆盖纯逻辑模块 `TagParser`、`SentenceSplitter`、`PCMConverter` 与对应测试，为 Phase 3（M2a 厂商验证）零阻塞开路。
- **选择理由**：`001-m0-foundation`（28/28）与 `002-m1-presence`（52/52）已全部收官，用户已拍板推进主里程碑 `003` Phase 1–2（解锁 M2a/M2b/004/005 US2+）。前置依赖经源码核验全部满足：`MMCore` 已有 `EmotionTag`/`ActionTag`/`UserEmotion`/`AssistantCommand`/`AvatarCue`/`PlaybackResult`/`ConversationEvent`；`MMSecurity/VendorID.swift` 已含 `aliyun`/`volcengine`/`openai`；`contracts/tag-protocol.md` 已合并 005 的 T-8–T-10 与第 6 条说明；既有 146 项单测全绿，无阻断冲突。
- **摸底关键发现**：
  1. **`GateState` / `ConnectionState` 跨模块依赖冲突（已给无环解）**：`T008` 原文将 `GateState.swift` 写在 `MMAudio/` 下，同时要求 `MMCore/ConversationEvent.swift` 新增 `connectionStateChanged`、`gateStateChanged`。但 `MMCore` 零包内依赖、`MMAudio → MMCore` 单向依赖，且 `MMEmotion`（Phase 7 `T051`）需消费 `gateStateChanged` 而不依赖 `MMAudio`。此外 `RuleBasedEmotionStateMachine.swift:189-416` 对 `ConversationEvent` 是无 `default` 的详尽 `switch`，新增 case 必须同步补齐空忽略分支以维持编译与 M1 行为不变。
  2. **App 无手工 `Info.plist`（已核实 `project.pbxproj` 现状）**：`App/MiniMate/Info.plist` 不存在；工程启用 `GENERATE_INFOPLIST_FILE = YES`，相机权限写在 `App/MiniMate.xcodeproj/project.pbxproj` 的 Debug（L283）与 Release（L313）`INFOPLIST_KEY_NSCameraUsageDescription`。麦克风权限须沿同一机制配置 `INFOPLIST_KEY_NSMicrophoneUsageDescription`，严禁另建冲突的 `Info.plist`。
  3. **三个已实测验证的 Swift 6.4 / Apple 框架坑点**：① `Character("~").isPunctuation` 与 `Character("～").isPunctuation` 均为 `false`（Unicode `Sm` 类），S-6 过滤纯标点句若只用 `!isPunctuation` 会漏放 `"~~~"`/`"～～～"`；② Swift `JSONDecoder` 解码 `[EmotionTag: V]`（无 `CodingKeyRepresentable`）时按交替数组而非 JSON 对象解析，`TTSEmotionMapping` 须自定义对象字典编解码；③ `AVAudioConverter` 48 kHz→16 kHz 流式单块（4,800 帧）会留存 **240 帧（15 ms）** FIR 滤波延迟，仅在 `flush()`（`.endOfStream`）循环排空后才齐满 1,600 帧。

### 2. 待用户拍板的决策清单

1. **`GateState` 与 `ConnectionState` 的模块归属（化解 `T008` 与 `MMCore` 零依赖红线冲突）**
   - **1A（推荐）**：将 `ConnectionState` 与 `GateState`（含 `GateThreshold`，`.closed(threshold:)` / `.open(threshold:)` 默认 `.normal`）定义在 `MMCore`（`MMCore/ConnectionState.swift`、`MMCore/GateState.swift`），与 `EmotionTag`/`AssistantCommand`/`AvatarCue` 同处零依赖共享契约层；`MMAudio` 依赖 `MMCore` 直接复用，不声明易引起双 `import` 歧义的 `typealias`；`RuleBasedEmotionStateMachine` 详尽 `switch` 补 `.connectionStateChanged, .gateStateChanged: break`。
   - **1B**：`MMCore` 仅放无关联值纯枚举 `GatePhase`（`muted`/`paused`/`closed`/`open`），`MMAudio` 另建含 `threshold` 的 `AudioGateStatus` 并转换（*差量：若选 1B，需对下篇 §4.1、§5.1、§5.2、§6 Step 2 与 §7.1 调整：`MMCore/GateState.swift` 改为纯枚举无 `threshold` 载荷，`ConversationEvent.gateStateChanged` 不再携带阈值，新增 `MMAudio/GateState.swift` 定义 `GateThreshold` 与 `AudioGateStatus`*）。

2. **`AudioChunk.samples` 底层存储类型（`data-model.md:18` 明确待选：`[Int16]` 或 `Data`）**
   - **2A（推荐）**：`samples: [Int16]` 作为唯一存储字段，同时提供 `pcmData: Data`（小端字节序）计算属性与 `init(pcmData: Data, sampleRate: Int, hostTime: UInt64 = 0, marks: [AudioTimeMark] = [])` 构造器。类型系统天然保证 16-bit 对齐与偶数字节，消除 `PCMConverter` / `FakeTTSProvider` / 后续 `EnergyVoiceGate` 的不安全指针错位读风险，同时不损失 WebSocket/HTTP 字节流互操作性。
   - **2B**：`samples: Data`（小端 16-bit 原始字节），另提供 `withInt16Samples` 读取辅助方法（*差量：若选 2B，需对下篇 §5.2 `AudioChunk` 字段与奇数字节校验、§5.6 `FakeTTSProvider` 静音块构造、§5.7 `PCMConverter` 读写路径及 §7.1 `AudioChunk` 测试断言改为 `Data` 字节口径*）。

3. **`Persona.makeInstructions` 默认是否包含 `contracts/tag-protocol.md` 第 6 条（005 拍照 `<cmd:…>` 说明）**
   - **3A（推荐）**：默认包含已合并进 003 `contracts/tag-protocol.md:60-79` 的完整 1–6 条，并提供 `includeCommandInstructions: Bool = true` 参数开关。与单源契约 100% 同步，不留 005 返工债；第 6 条已明确约束非明确要求拍照绝不输出 `<cmd>`，不影响 M2a 语气验证，需要精简 prompt 时亦可一键关闭。
   - **3B**：默认仅包含 1–5 条，保留 `includeCommandInstructions: Bool = false` 待 005 开启（*差量：若选 3B，需对下篇 §5.5 `Persona.makeInstructions` 默认参数改为 `false`，并同步调整 §7.1 `FoundationalTests` 中默认指令包含第 6 条的断言*）。

4. **Phase 1–2 期间 `App/MiniMate.xcodeproj` 是否提前链接 `MMAudio` / `MMConversation`**
   - **4A（推荐）**：`project.pbxproj` 本次仅在 Debug/Release 配置新增 `INFOPLIST_KEY_NSMicrophoneUsageDescription`，暂不将 `MMAudio`/`MMConversation` 链接进 App target（避免 Phase 3 M2a 期间将多家待裁剪厂商适配器打入 App）；iOS 兼容编译由门禁中的 `xcodebuild -scheme MMAudio` / `MMConversation -destination 'generic/platform=iOS'` 与 App Simulator 构建共同覆盖，待 Phase 4 `T036` 接线时再链接进 App。
   - **4B**：本次一并在 `project.pbxproj` 预链接 `MMAudio` 与 `MMConversation`（*差量：若选 4B，需对下篇 §4.1 `project.pbxproj` 职责、§4.2 Non-Goals 与 §6 Step 2 增加 `PBXBuildFile`/`PBXFrameworksBuildPhase`/`packageProductDependencies`/`XCSwiftPackageProductDependency` 变更项*）。

---

## 下篇：面向实施方的零歧义施工图

### 3. 现状锚点与环境陷阱预警

#### 3.1 现有代码锚点
| 模块/符号 | 精确位置 | 职责与复用/约束说明 |
| :--- | :--- | :--- |
| `MiniMateKit` manifest | `Packages/MiniMateKit/Package.swift:1-32` | `swift-tools-version: 6.2`，平台 `.iOS(.v26)`/`.macOS(.v26)`；现有 6 个库产物（`MMCore`–`MMAvatar`）与 5 个 testTarget；`MMEmotion`（L24）使用 `resources: [.process("Resources")]` 作为资源打包范式 |
| `.gitignore` | `.gitignore:1-22` | L14–18 已有 `Assets/avatar/*` 资产排除规则，末尾无换行符；尚无 `Assets/voice-samples/*.wav` |
| App 权限与包依赖 | `App/MiniMate.xcodeproj/project.pbxproj:282-286,312-316` | Debug（`202020202020202020200003`）与 Release（`202020202020202020200004`）均设 `GENERATE_INFOPLIST_FILE = YES` 与 `INFOPLIST_KEY_NSCameraUsageDescription`；不存在 `App/MiniMate/Info.plist` |
| `VendorID` | `Packages/MiniMateKit/Sources/MMSecurity/VendorID.swift:1-16` | 已定义 `aliyun`/`volcengine`/`openai` 与 `title`；当前遵循 `String, CaseIterable, Sendable`，缺 `Codable`。全仓调用方：`CredentialStore.swift:6-122`、`SettingsView.swift:7-71`、`CredentialStoreTests.swift:11-78` |
| `ConversationEvent` | `Packages/MiniMateKit/Sources/MMCore/ConversationEvent.swift:1-20` | 现有 13 个 case（含 005 预置 `assistantCommand`/`assistantCue`/`assistantCueEnded`），遵循 `Sendable, Equatable` |
| `EmotionTag` / `ActionTag` / `UserEmotion` / `AssistantCommand` | `Packages/MiniMateKit/Sources/MMCore/{EmotionTag,ActionTag,UserEmotion,AssistantCommand}.swift` | 均遵循 `String, CaseIterable, Codable, Sendable`，`rawValue` 即标签协议字面值；严禁重复定义 |
| `MMCore.Clock` | `Packages/MiniMateKit/Sources/MMCore/MMCore.swift:4-18` | 时钟协议 `Clock`（含 `now` 与 `sleep(for:)`）及 `SystemClock`；`FakeTTSProvider` 延迟注入必须复用，且全仓须写 `any MMCore.Clock` |
| `RuleBasedEmotionStateMachine.handle(_: ConversationEvent)` | `Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift:189-416` | **无 `default` 的详尽 `switch`**（L413 为 `case .assistantCommand, .assistantText, .userTranscript: break`）；新增 `ConversationEvent` case 必须在此补分支 |
| `AvatarScreen` / `AvatarDebugPanel` | `App/MiniMate/Screens/AvatarScreen.swift:630-683`、`AvatarDebugPanel.swift:58-217` | `AvatarScreen` 两处 `switch event` 均有 `default: break`，`AvatarDebugPanel` 仅构造事件；扩展 `ConversationEvent` 无需改动这两个文件 |
| `Bundle.module` 资源加载范式 | `Packages/MiniMateKit/Sources/MMEmotion/ExpressionPreset.swift:104-110` | `Bundle.module.url(forResource:withExtension:)` 根目录查找 + 显式错误类型（无 `subdirectory:`） |
| 并发锁范式 | `Packages/MiniMateKit/Sources/MMPerception/ScriptedPerceptionSource.swift:11,30` | `import os` + `OSAllocatedUnfairLock<State>` 封装 `@unchecked Sendable` 可变内部状态 |
| 既有契约测试锚点 | `Packages/MiniMateKit/Tests/MMCoreTests/MMCoreTests.swift:62-74`、`MMSecurityTests/CredentialStoreTests.swift:11-78`、`MMEmotionTests/ConversationTransitionTests.swift:1-65` | 均用 Swift Testing（`@Suite` / `@Test` / `#expect`）；`ConversationTransitionTests.swift:8-35` 提供 `ManualClock` 范式 |

#### 3.2 环境与第三方依赖实测陷阱
- **Swift 6.4 `Swift.Clock` 命名冲突**：裸写 `any Clock` 会与标准库 `Swift.Clock` 冲突报错 → 所有源码与测试引用 `MMCore` 时钟协议必须显式写 `any MMCore.Clock`。
- **沙盒内运行 `swift test` 的 Module Cache 权限**：默认 `/var/folders/.../C/clang/ModuleCache` 不可写 → 沙盒内运行单测/CLI 必须带 `CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox`（本机常规终端直接 `swift test`）。
- **SwiftPM `.process("Resources")` 扁平化**：`Sources/MMConversation/Resources/persona.md` 打包后位于 `Bundle.module` 根目录 → 必须使用 `Bundle.module.url(forResource: "persona", withExtension: "md")`，严禁传 `subdirectory: "Resources"`。
- **Unicode `~` / `～` 的 `Character.isPunctuation == false`（已实测确认）**：在 Swift 6.4 / macOS 27.2 上，`Character("~").isPunctuation` 与 `Character("～").isPunctuation` 均返回 `false`（属 Unicode `Sm` 数学符号类），而 `Character("好").isLetter == true`、`Character("3").isNumber == true` → `SentenceSplitter` 的 S-6 过滤**严禁**仅凭 `!$0.isPunctuation` 判定可播内容，必须使用 `text.contains { $0.isLetter || $0.isNumber }`。
- **Swift `JSONDecoder` 解码 `[EmotionTag: VendorEmotionParams]` 与 `Bool`/`Double` 顺序陷阱**：
  - `EmotionTag` 未遵循 `CodingKeyRepresentable`，默认合成的 `Codable` 会把 `[EmotionTag: VendorEmotionParams]` 当作 JSON 数组而非 JSON 对象 `{"happy": {...}}` → `TTSEmotionMapping` 必须手写 `init(from:)` / `encode(to:)`，经 `[String: VendorEmotionParams]` 转换并拒绝未知情绪键。
  - `JSONScalar.init(from:)` 解码单值容器时，必须按 **`Bool` → `Double` → `String`** 顺序尝试，避免布尔值被误判为数字。
- **`AVAudioConverter` 流式重采样 FIR 延迟与 `inputBlock` 多次调用陷阱（已实测确认）**：
  - 实测 48 kHz→16 kHz 单块 4,800 帧输入，首次 `convert(to:error:withInputFrom:)` 在 `inputBlock` 首次返回 `.haveData`、二次返回 `.noDataNow` 时仅输出 **1,360 帧**（内部多相 FIR 缓冲滞留 **240 帧 = 15 ms**），随后以 `.endOfStream` 调用 `flush()` 才吐出剩余 240 帧（合计精确 1,600 帧）。
  - 因此：① `inputBlock` 必须用局部布尔标志保证同一输入缓冲只提供一次 `.haveData`，之后返回 `.noDataNow`（流式）或 `.endOfStream`（一次性/排空）；② `convert` 与 `flush` 必须**循环拉取**直至状态为 `.inputRanDry`/`.endOfStream` 或本轮产出 `frameLength == 0`，且单次输出缓冲容量至少 `max(Int(ceil(Double(inputFrames) * ratio)) + 512, 512)`，防止 240+ 帧 FIR 尾部被截断；③ 相同采样率时直接透传不经过 `AVAudioConverter`；④ `AVAudioConverter` 非 `Sendable`，`PCMConverter` 须用 `OSAllocatedUnfairLock` 保护状态以通过 Swift 6 严格并发检查。

---

### 4. 改动范围表与明确不做清单（Non-Goals）

#### 4.1 文件改动表
| 文件路径 | 操作 | 精确职责 |
| :--- | :--- | :--- |
| `.gitignore` | 修改 | 追加 `Assets/voice-samples/*.wav` 排除规则（T002） |
| `App/MiniMate.xcodeproj/project.pbxproj` | 修改 | 在 `MiniMate` target 的 Debug 与 Release 配置各新增 `INFOPLIST_KEY_NSMicrophoneUsageDescription`（T003） |
| `Packages/MiniMateKit/Package.swift` | 修改 | 新增 library 产物 `MMAudio`、`MMConversation` 与 executable 产物 `mm-probe`；新增 target `MMAudio`、`MMConversation`（`.process("Resources")`）、`MMProbeCLI` 及测试 target `MMAudioTests`、`MMConversationTests`（T001） |
| `Packages/MiniMateKit/Sources/MMSecurity/VendorID.swift` | 修改 | 保持 3 厂商 case 不变，补充 `Codable` 遵循供 `TTSEmotionMapping` 复用（T004） |
| `Packages/MiniMateKit/Sources/MMCore/ConnectionState.swift` | 新增 | 定义 `ConnectionState` 枚举（T008） |
| `Packages/MiniMateKit/Sources/MMCore/GateState.swift` | 新增 | 定义 `GateThreshold` 与 `GateState` 枚举（T008） |
| `Packages/MiniMateKit/Sources/MMCore/ConversationEvent.swift` | 修改 | 追加 `.connectionStateChanged(ConnectionState)` 与 `.gateStateChanged(GateState)`（T008） |
| `Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift` | 微调 | L413 详尽 `switch` 补 `.connectionStateChanged, .gateStateChanged: break`（T008 兼容） |
| `Packages/MiniMateKit/Sources/MMAudio/AudioChunk.swift` | 新增 | 定义 `AudioFormatDescription`、`AudioTimeMark`、`AudioChunk`（T008） |
| `Packages/MiniMateKit/Sources/MMAudio/PCMConverter.swift` | 新增 | 基于 `AVAudioConverter` 实现流式/一次性 16-bit 单声道重采样与 `PCMConverterError`（T014） |
| `Packages/MiniMateKit/Sources/MMConversation/Resources/persona.md` | 新增 | 小瓜人格设定 Markdown 源文件（T005） |
| `Packages/MiniMateKit/Sources/MMConversation/Persona.swift` | 新增 | `Persona`、`PersonaError`、Markdown 解析、`Bundle.module` 加载与完整 instructions 拼装（T013） |
| `Packages/MiniMateKit/Sources/MMConversation/Realtime/RealtimeTextSession.swift` | 新增 | `RealtimeTextSession` 协议、`RealtimeOutput`、`RealtimeError`（T009） |
| `Packages/MiniMateKit/Sources/MMConversation/TTS/TTSProvider.swift` | 新增 | `TTSProvider` 协议与 `TTSError`（T010） |
| `Packages/MiniMateKit/Sources/MMConversation/TTS/EmotionMapping.swift` | 新增 | `JSONScalar`、`VendorEmotionParams`、`TTSEmotionMapping`、`TTSEmotionMappingError`（T010） |
| `Packages/MiniMateKit/Sources/MMConversation/TTS/FakeTTSProvider.swift` | 新增 | 线程安全测试假实现（静音分块、延迟/失败/字级时间戳注入、TTS-5 严格取消）（T010） |
| `Packages/MiniMateKit/Sources/MMConversation/TagParser.swift` | 新增 | `TaggedSegment`、`TagParseWarning` 与流式 `TagParser`（T-1–T-10）（T011） |
| `Packages/MiniMateKit/Sources/MMConversation/SentenceSplitter.swift` | 新增 | `SentenceAction`、`Sentence` 与流式 `SentenceSplitter`（S-1–S-7）（T012） |
| `Packages/MiniMateKit/Sources/MMProbeCLI/main.swift` | 新增 | `mm-probe` 最小可编译占位 CLI 入口（支持 `--help`，具体子命令归 Phase 3 `T020`）（T001） |
| `Packages/MiniMateKit/Tests/MMCoreTests/MMCoreTests.swift` | 修改 | 增补 `ConnectionState`、`GateState` 及 `ConversationEvent` 新 case 的 Equatable 测试 |
| `Packages/MiniMateKit/Tests/MMSecurityTests/CredentialStoreTests.swift` | 修改 | 增补 `VendorID` 全枚举与 `Codable` 往返测试 |
| `Packages/MiniMateKit/Tests/MMEmotionTests/ConversationTransitionTests.swift` | 修改 | 增补状态机收到 `.connectionStateChanged` / `.gateStateChanged` 不改变状态的回归测试 |
| `Packages/MiniMateKit/Tests/MMAudioTests/PCMConverterTests.swift` | 新增 | `AudioChunk` 与 `PCMConverter` 全场景确定性单测（T014） |
| `Packages/MiniMateKit/Tests/MMConversationTests/TagParserTests.swift` | 新增 | T-1–T-10 与参数化随机切分一致性单测（T006，先写） |
| `Packages/MiniMateKit/Tests/MMConversationTests/SentenceSplitterTests.swift` | 新增 | S-1–S-7 与随机切分一致性单测（T007，先写） |
| `Packages/MiniMateKit/Tests/MMConversationTests/FoundationalTests.swift` | 新增 | `Persona`、`TTSEmotionMapping`、`FakeTTSProvider`、`RealtimeOutput`/`RealtimeError` 单测 |

#### 4.2 明确不做清单（Non-Goals）
- **严禁实现 Phase 3+ 厂商与 CLI 逻辑**：不实现 `QwenOmniRealtimeSession`、`DoubaoRealtimeSession`、`CosyVoiceTTSProvider`、`DoubaoTTSProvider`、`mm-probe` 的 `realtime`/`tone-suite`/`tts`/`record-fixture` 子命令，不创建虚假的 `Resources/tts-emotion-*.json` 占位文件（归 `T015`–`T025`）。
- **严禁实现 Phase 4–8 引擎与设备音频**：不实现 `ConversationEngine` 协议实现、`RealtimeTextConversationEngine`、`TurnCoordinator`、`TurnMetrics`、`AudioIO`、`AudioSessionController`、`PreRollBuffer`、`VoiceActivityGate`、`EnergyVoiceGate`、`GazeGatePolicy`、`BargeInDetector`、`ConversationDebugPanel`（归 `T026`–`T055`）。
- **严禁改动 App 业务代码与 `Info.plist`**：不创建 `App/MiniMate/Info.plist`，不改动 `AppComposition.swift`、`AvatarScreen.swift`、`AvatarDebugPanel.swift`、`SettingsView.swift`，不在 `project.pbxproj` 预链接 `MMAudio`/`MMConversation`。
- **严禁提前实现状态机静音姿态**：`RuleBasedEmotionStateMachine` 本次仅对 `.gateStateChanged` 做无副作用空忽略；静音姿态与 `paused → Idle` 留待 Phase 7 `T051`。
- **严禁修改 `specs/` 文档或勾选 `tasks.md`**：不改 `specs/003-m2-voice-conversation/tasks.md`、`research.md`、`docs/tech-selection.md` 或任何历史执行单。

---

### 5. 精确接口与行为契约

#### 5.1 `MMCore` 扩展：`ConnectionState`、`GateState` 与 `ConversationEvent`
- **`Packages/MiniMateKit/Sources/MMCore/ConnectionState.swift`**：
  ```swift
  /// 实时语音会话连接状态。
  public enum ConnectionState: Sendable, Equatable {
      case connecting
      case connected
      case reconnecting(attempt: Int)
      case lost
  }
  ```
- **`Packages/MiniMateKit/Sources/MMCore/GateState.swift`**：
  ```swift
  /// 本地人声闸门判定阈值档位。
  public enum GateThreshold: String, CaseIterable, Codable, Sendable {
      case normal
      case raised
      case playback
  }

  /// 本地收音闸门状态。仅 `.open` 允许向云端推送音频（audio-gating.md PV-1）。
  public enum GateState: Sendable, Equatable {
      case muted
      case paused
      case closed(threshold: GateThreshold = .normal)
      case open(threshold: GateThreshold = .normal)

      /// 是否正在向云端上传音频。
      public var isUploading: Bool {
          if case .open = self { return true }
          return false
      }

      /// 当前生效的闸门阈值；`muted` 与 `paused` 下未监听，返回 `nil`。
      public var threshold: GateThreshold? {
          switch self {
          case .muted, .paused: nil
          case .closed(let threshold), .open(let threshold): threshold
          }
      }
  }
  ```
- **`Packages/MiniMateKit/Sources/MMCore/ConversationEvent.swift`**：在既有 13 个 case 后追加：
  ```swift
  /// 003：实时会话连接状态变化，不属于对话轮次（conversation-engine.md E-4）。
  case connectionStateChanged(ConnectionState)
  /// 003：收音闸门状态变化（驱动静音姿态与调试面板显示，E-4）。
  case gateStateChanged(GateState)
  ```
- **兼容性约束**：`Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift:413` 改为：
  ```swift
  case .assistantCommand, .assistantText, .userTranscript, .connectionStateChanged, .gateStateChanged:
      break
  ```
  不得修改其他 case 分支逻辑。

#### 5.2 `MMAudio` 基础类型：`AudioFormatDescription`、`AudioTimeMark`、`AudioChunk`
- **位置**：`Packages/MiniMateKit/Sources/MMAudio/AudioChunk.swift`（仅 `import Foundation`）。
- **精确签名**：
  ```swift
  public struct AudioFormatDescription: Sendable, Equatable, Codable {
      public let sampleRate: Int
      public let channels: Int
      public let bitsPerSample: Int

      public init(sampleRate: Int, channels: Int = 1, bitsPerSample: Int = 16) {
          self.sampleRate = sampleRate
          self.channels = channels
          self.bitsPerSample = bitsPerSample
      }

      public static let pcm16kMono = AudioFormatDescription(sampleRate: 16_000, channels: 1, bitsPerSample: 16)
      public static let pcm24kMono = AudioFormatDescription(sampleRate: 24_000, channels: 1, bitsPerSample: 16)
      public static let pcm48kMono = AudioFormatDescription(sampleRate: 48_000, channels: 1, bitsPerSample: 16)
  }

  /// TTS 字级 / 音素级时间戳（contracts/tts-provider.md TTS-6）。
  public struct AudioTimeMark: Sendable, Equatable, Codable {
      public let text: String
      public let offsetSeconds: TimeInterval
      public let charOffset: Int?

      public init(text: String, offsetSeconds: TimeInterval, charOffset: Int? = nil) {
          self.text = text
          self.offsetSeconds = max(0, offsetSeconds.isFinite ? offsetSeconds : 0)
          self.charOffset = charOffset
      }
  }

  /// PCM 16-bit 单声道音频块。
  public struct AudioChunk: Sendable, Equatable {
      public let samples: [Int16]
      public let sampleRate: Int
      public let hostTime: UInt64
      public let marks: [AudioTimeMark]

      public init(
          samples: [Int16],
          sampleRate: Int,
          hostTime: UInt64 = 0,
          marks: [AudioTimeMark] = []
      ) {
          self.samples = samples
          self.sampleRate = sampleRate
          self.hostTime = hostTime
          self.marks = marks
      }

      /// 从小端 16-bit signed PCM 字节流构造；若存在尾部多余的 1 个奇数字节则忽略该不完整字节。
      public init(
          pcmData: Data,
          sampleRate: Int,
          hostTime: UInt64 = 0,
          marks: [AudioTimeMark] = []
      ) {
          let sampleCount = pcmData.count / MemoryLayout<Int16>.size
          var decoded = [Int16]()
          decoded.reserveCapacity(sampleCount)
          pcmData.withUnsafeBytes { raw in
              for i in 0..<sampleCount {
                  let offset = i * 2
                  let lo = UInt16(raw[offset])
                  let hi = UInt16(raw[offset + 1])
                  decoded.append(Int16(bitPattern: lo | (hi << 8)))
              }
          }
          self.init(samples: decoded, sampleRate: sampleRate, hostTime: hostTime, marks: marks)
      }

      /// 小端 16-bit signed PCM 字节流（供 WebSocket / HTTP 传输）。
      public var pcmData: Data {
          var data = Data(capacity: samples.count * 2)
          for sample in samples {
              let bits = UInt16(bitPattern: sample).littleEndian
              data.append(UInt8(truncatingIfNeeded: bits))
              data.append(UInt8(truncatingIfNeeded: bits >> 8))
          }
          return data
      }

      /// 音频块时长（秒）；`sampleRate <= 0` 时返回 `0`。
      public var duration: TimeInterval {
          guard sampleRate > 0 else { return 0 }
          return Double(samples.count) / Double(sampleRate)
      }

      /// PCM 字节数（`samples.count * 2`）。
      public var byteCount: Int {
          samples.count * MemoryLayout<Int16>.size
      }
  }
  ```
- **边界口径**：字节解包按字节拼 `lo | (hi << 8)`，完全不依赖对齐，永不触发 `load(as:)` 错位 UB；空 `Data` 返回空 `samples`；1 字节畸形输入产出 0 样本不崩溃。

#### 5.3 `MMSecurity.VendorID`
- **位置**：`Packages/MiniMateKit/Sources/MMSecurity/VendorID.swift:4`。
- **改动**：仅将 `public enum VendorID: String, CaseIterable, Sendable` 更新为 `public enum VendorID: String, CaseIterable, Codable, Sendable`。
- **兼容性约束**：保留 `aliyun` / `volcengine` / `openai` 三个 case 及其 `rawValue`、`title` 不变；不改动 `CredentialStore.swift` 与 `SettingsView.swift`。

#### 5.4 `RealtimeTextSession`、`RealtimeOutput`、`RealtimeError`
- **位置**：`Packages/MiniMateKit/Sources/MMConversation/Realtime/RealtimeTextSession.swift`（`import Foundation`、`import MMAudio`）。
- **精确签名**（对齐 `contracts/realtime-session.md` 与 `data-model.md:61-69`）：
  ```swift
  public enum RealtimeError: Error, Sendable, Equatable {
      case authFailed
      case rateLimited
      case unsupportedConfiguration(String)
      case notConnected
      case network(underlying: String)
      case server(code: String, message: String)
  }

  public enum RealtimeOutput: Sendable, Equatable {
      case speechStarted
      case speechEnded
      case userTranscript(String, isFinal: Bool)
      case textDelta(String)
      case responseDone
      case error(RealtimeError)
  }

  public protocol RealtimeTextSession: Sendable {
      /// 建立 WebSocket 并完成会话配置：只输出文字、服务端 VAD、instructions。
      func connect(instructions: String) async throws
      /// 推送一段音频（已转换为厂商要求的格式）；未连接时抛 `RealtimeError.notConnected`（RS-4）。
      func send(_ audio: AudioChunk) async throws
      /// 取消当前正在生成的回答（打断）。
      func cancelResponse() async
      /// 清空服务端尚未处理的输入音频缓冲。
      func clearInputBuffer() async
      var output: AsyncThrowingStream<RealtimeOutput, Error> { get }
      func close() async
  }
  ```
- **安全红线（RS-1）**：`RealtimeError` 各关联字符串与后续所有实现严禁携带 API Key 或原始鉴权头。

#### 5.5 `Persona` 与 `Resources/persona.md`
- **`Packages/MiniMateKit/Sources/MMConversation/Resources/persona.md`**（固定结构，确保解析确定性）：
  ```markdown
  # 小瓜

  - 称呼用户：你

  ## 性格与说话风格
  呆萌、俏皮、话不多，像陪伴在桌边的小朋友。说话自然口语化，语气真诚温暖，偶尔带点可爱的小调皮，但不过度浮夸。

  ## 规则
  - 每次回答控制在 1–3 句，简短自然。
  - 只使用普通话中文交流。
  - 不使用表情符号（emoji）或颜文字，不用括号描写动作。
  - 不自称 AI、语言模型或助手。
  - 只在用户说话后回应，不主动挑起长篇话题。
  ```
- **`Packages/MiniMateKit/Sources/MMConversation/Persona.swift`**（`import Foundation`、`import MMCore`）：
  ```swift
  public enum PersonaError: Error, Sendable, Equatable {
      case resourceNotFound
      case invalidFormat(String)
  }

  public struct Persona: Sendable, Equatable {
      public let name: String
      public let description: String
      public let addressUserAs: String
      public let rules: [String]

      public init(name: String, description: String, addressUserAs: String, rules: [String]) { ... }

      /// 解析固定结构 Markdown；缺失 `# 名字`、`- 称呼用户：...`、`## 性格与说话风格` 正文或 `## 规则` 任一必填项时抛 `PersonaError.invalidFormat`，禁止静默构造空字段。
      public static func parse(markdown: String) throws -> Persona

      /// 从 `Bundle.module` 根目录加载内置 `persona.md`（禁止传 `subdirectory:`）。
      public static func loadBundled() throws -> Persona

      /// 标签协议说明（逐字对齐 `contracts/tag-protocol.md:60-79`；枚举列表从 `MMCore` `allCases` 动态拼接防漂移）。
      public static func tagProtocolInstructions(includeCommandInstructions: Bool = true) -> String

      /// 拼装完整会话 instructions：人格设定 + 标签协议说明（默认含 1–6 条）+ 可选 `extraInstructions`（004 记忆扩展；纯空白时省略）。
      public func makeInstructions(
          extraInstructions: String? = nil,
          includeCommandInstructions: Bool = true
      ) -> String
  }
  ```
- **指令内容硬要求**：
  - `tagProtocolInstructions(includeCommandInstructions: true)` 必须包含：
    - 第 1 条：`UserEmotion.allCases.map(\.rawValue).joined(separator: ", ")`（`happy, calm, sad, tired, angry, anxious`）
    - 第 2 条：`EmotionTag.allCases.map(\.rawValue).joined(separator: ", ")`（`happy, gentle, sad, surprised, shy, playful, concerned, neutral`）
    - 第 3 条：`ActionTag.allCases.map(\.rawValue).joined(separator: ", ")`（`nod, wave, spin, heart, shyCover, leanBack, lookAround, notice`）
    - 第 4 条：标签不会被念出来，不要解释标签
    - 第 5 条：语气优先原则（当用户的语气和文字含义不一致时，以语气为准来回应）
    - 第 6 条（当 `includeCommandInstructions == true`）：`contracts/tag-protocol.md:71-78` 完整拍照指令规则（含 `<cmd:photo>` / `<cmd:photoReady>` / `<cmd:photoCancel>`）
  - 当 `includeCommandInstructions == false` 时仅输出第 1–5 条，不包含 `<cmd:` 字样。

#### 5.6 `TTSProvider`、`TTSEmotionMapping`、`FakeTTSProvider`
- **`Packages/MiniMateKit/Sources/MMConversation/TTS/TTSProvider.swift`**：
  ```swift
  public enum TTSError: Error, Sendable, Equatable {
      case cancelled
      case synthesisFailed(String)
      case invalidConfiguration(String)
  }

  public protocol TTSProvider: Sendable {
      /// 流式合成一句话。返回的音频格式由 `outputFormat` 给出。
      func synthesize(_ sentence: String, emotion: EmotionTag) -> AsyncThrowingStream<AudioChunk, Error>
      var outputFormat: AudioFormatDescription { get }
      /// 取消所有进行中的合成（打断，TTS-5）。
      func cancelAll() async
  }
  ```
- **`Packages/MiniMateKit/Sources/MMConversation/TTS/EmotionMapping.swift`**（`import Foundation`、`import MMCore`、`import MMSecurity`）：
  ```swift
  public enum JSONScalar: Sendable, Equatable, Codable {
      case string(String)
      case number(Double)
      case bool(Bool)
  }

  /// 单个情绪对应的厂商参数集合（JSON 中直接编码/解码为平面对象 `{ ... }`）。
  public struct VendorEmotionParams: Sendable, Equatable, Codable {
      public let parameters: [String: JSONScalar]
      public static let empty = VendorEmotionParams([:])

      public init(_ parameters: [String: JSONScalar] = [:])
      public var isEmpty: Bool { parameters.isEmpty }
      public func string(_ key: String) -> String?
      public func number(_ key: String) -> Double?
      public func bool(_ key: String) -> Bool?
  }

  public enum TTSEmotionMappingError: Error, Sendable, Equatable {
      case resourceNotFound(VendorID)
      case emptyVoice
      case unknownEmotionKey(String)
      case missingNeutralMapping
  }

  public struct TTSEmotionMapping: Sendable, Equatable, Codable {
      public let vendor: VendorID
      public let voice: String
      public let map: [EmotionTag: VendorEmotionParams]

      public init(vendor: VendorID, voice: String, map: [EmotionTag: VendorEmotionParams])

      /// TTS-2：返回指定情绪的参数；缺失时回退至 `.neutral`，若手工构造且连 `.neutral` 也缺失则回退 `.empty`。
      public func params(for emotion: EmotionTag) -> VendorEmotionParams

      /// 解码 JSON 并校验：`voice` 去空白后非空（TTS-1）、`map` 中每个键必须为合法 `EmotionTag.rawValue`（非法键抛 `.unknownEmotionKey`）、`map[.neutral]` 必存在（缺失抛 `.missingNeutralMapping`）。
      public static func load(from data: Data) throws -> TTSEmotionMapping

      /// 从 `Bundle.module` 根目录加载 `tts-emotion-<vendor>.json`；不存在抛 `.resourceNotFound(vendor)`。
      public static func loadBundled(for vendor: VendorID) throws -> TTSEmotionMapping
  }
  ```
  - **编解码约束**：
    - `JSONScalar.init(from:)` 按 **`Bool` → `Double` → `String`** 尝试解码单值容器；若 `Double` 非有限值则抛 `DecodingError.dataCorruptedError`。
    - `TTSEmotionMapping.init(from:)` 将 `map` 按 `[String: VendorEmotionParams]` 解码后映射为 `[EmotionTag: VendorEmotionParams]`；`encode(to:)` 将 `map` 编码为 JSON 对象（键为 `emotion.rawValue`）。
- **`Packages/MiniMateKit/Sources/MMConversation/TTS/FakeTTSProvider.swift`**（`import Foundation`、`import os`、`import MMCore`、`import MMAudio`）：
  ```swift
  public final class FakeTTSProvider: TTSProvider, @unchecked Sendable {
      public struct Request: Sendable, Equatable {
          public let sentence: String
          public let emotion: EmotionTag
      }

      public let outputFormat: AudioFormatDescription

      public init(
          outputFormat: AudioFormatDescription = .pcm24kMono,
          millisecondsPerCharacter: Double = 120,
          chunkDurationMilliseconds: Int = 100,
          chunkDelay: Duration = .zero,
          clock: any MMCore.Clock = SystemClock(),
          includeWordMarks: Bool = false,
          failureRule: (@Sendable (String, EmotionTag) -> (any Error)?)? = nil
      )

      /// 已收到的全部合成请求（按调用顺序，线程安全）。
      public var recordedRequests: [Request] { get }
      /// `cancelAll()` 调用次数（线程安全）。
      public var cancelCount: Int { get }

      public func synthesize(_ sentence: String, emotion: EmotionTag) -> AsyncThrowingStream<AudioChunk, Error>
      public func cancelAll() async
  }
  ```
  - **精确行为口径**：
    - 非法参数防护：`millisecondsPerCharacter` 非有限或 `<= 0` 时退回默认 `120`；`chunkDurationMilliseconds <= 0` 时退回默认 `100`；`outputFormat.sampleRate <= 0` 时按 `24_000` 计算帧数。
    - `synthesize` 同步记录 `Request(sentence: sentence, emotion: emotion)`。
    - 若 `failureRule?(sentence, emotion)` 返回非 `nil` 错误 → 立即 `continuation.finish(throwing: error)`，产出 0 个音频块（TTS-4）。
    - 若 `sentence.isEmpty` → 立即 `continuation.finish()`，产出 0 个音频块。
    - 正常合成：总样本数 = `max(1, Int((Double(sentence.count) * msPerChar / 1000.0 * Double(sampleRate)).rounded()))`；每块上限样本数 = `max(1, Int((Double(chunkMs) / 1000.0 * Double(sampleRate)).rounded()))`；逐块生成静音（全 `0` `[Int16]`）并通过流式 `yield` 输出（TTS-3）。若 `includeWordMarks == true`，在首块（或对应时间落点块）附带逐字 `AudioTimeMark(text: String(char), offsetSeconds: Double(idx) * msPerChar / 1000.0, charOffset: idx)`（TTS-6）；否则 `marks` 为空。
    - **TTS-5 严格无竞态取消**：使用 `OSAllocatedUnfairLock` 维护活动流表 `[UUID: ActiveStream]`。生产者 `Task` 在 `chunkDelay > .zero` 时先 `try await clock.sleep(for: chunkDelay)`，随后在持锁区内确认自身 `UUID` 仍在活动表中且未取消，**在持锁区内调用 `continuation.yield(chunk)`**；`cancelAll()` 在持锁区内将全部活动条目移出并递增 `cancelCount`，随后统一 `task.cancel()` + `continuation.finish()`。由此线性化保证：`cancelAll()` 返回之后，旧请求的流**绝对不可能**再产出任何音频块；且 `cancelAll()` 之后新发起的 `synthesize` 请求正常工作。

#### 5.7 `TagParser`（流式标签解析器，纯逻辑）
- **位置**：`Packages/MiniMateKit/Sources/MMConversation/TagParser.swift`（`import Foundation`、`import MMCore`）。
- **精确签名**：
  ```swift
  public enum TaggedSegment: Sendable, Equatable {
      case userEmotion(UserEmotion)
      case emotion(EmotionTag)
      case action(ActionTag)
      case command(AssistantCommand)
      case text(String)
  }

  public struct TagParseWarning: Sendable, Equatable {
      public enum Reason: Sendable, Equatable {
          case unknownTagType(String)
          case unknownUserEmotion(String)
          case unknownEmotion(String)
          case unknownAction(String)
          case unknownCommand(String)
      }
      public let rawTag: String
      public let reason: Reason
  }

  public struct TagParser: Sendable {
      public static let maxTagLength = 24

      public private(set) var warnings: [TagParseWarning] = []

      public init() {}

      /// 喂入一段流式文字增量，返回可确定的已解析片段（相邻纯文本段在同次返回中自动合并，不产出空 `.text("")`）。
      public mutating func feed(_ delta: String) -> [TaggedSegment]

      /// 回答结束时按 T-7 刷出未闭合缓存（幂等：重复调用返回 `[]`）。
      public mutating func finish() -> [TaggedSegment]

      /// 重置状态以复用解析器（清空缓存、标记位与 `warnings`）。
      public mutating func reset()
  }
  ```
- **状态机与 T-1–T-10 精确口径**：
  - 逐 `Character` 处理输入，确保任意切分流与整段输入完全等价：
    - 非缓冲态：遇 `<` 进入缓冲态 `tagBuffer = "<"`；其他字符追加到当前输出文本（若含非空白字符，置 `hasSeenNonWhitespaceText = true`）。
    - 缓冲态（`tagBuffer` 以 `<` 开头）：
      - 遇 `<`（嵌套/未闭合 `<` 后出现新 `<`，如 `"1<2<emo:happy>"`）：将当前 `tagBuffer` 按普通文本刷出（并更新 `hasSeenNonWhitespaceText`），再重置 `tagBuffer = "<"`；
      - 遇 `>`：将 `>` 追加到 `tagBuffer`（总长 `<= 25` 即 `<` 后闭合于 24 字符内），清空 `tagBuffer` 并按标签语法判定：
        - 去掉首尾 `<` 与 `>` 得 `inner`；校验是否符合标签外形：`inner` 恰含 1 个 `:`，左侧 `kind` 非空且全为 ASCII 字母（`A-Z`/`a-z`），右侧 `value` 全为 ASCII 字母/数字/`_`/`-`（可为空以便 `<cmd:>` 命中 T-9 警告）。
        - **不匹配标签外形**（如 `"<2 and 3>"`、`"<你好>"`、`"<>"`）→ 按 T-6 作为普通文字输出（更新 `hasSeenNonWhitespaceText`）。
        - **匹配标签外形** → 按 `kind` 分派：
          - `"user"`：若 `UserEmotion(rawValue: value)` 合法，仅当 `!hasEmittedUserEmotion && !hasSeenNonWhitespaceText && !hasSeenBodyTag` 时产出 `.userEmotion(e)` 并置 `hasEmittedUserEmotion = true`，否则按 T-5 静默丢弃；若不合法，按 T-3 丢弃并记录 `.unknownUserEmotion(value)` 警告。
          - `"emo"`：若 `EmotionTag(rawValue: value)` 合法，置 `hasSeenBodyTag = true` 并产出 `.emotion(e)`；否则按 T-3 丢弃并记录 `.unknownEmotion(value)` 警告。
          - `"act"`：若 `ActionTag(rawValue: value)` 合法，置 `hasSeenBodyTag = true` 并产出 `.action(a)`；否则按 T-3 丢弃并记录 `.unknownAction(value)` 警告。
          - `"cmd"`：若 `AssistantCommand(rawValue: value)` 合法，置 `hasSeenBodyTag = true` 并按 T-8/T-10 立即产出 `.command(c)`（不去重）；否则按 T-9 丢弃并记录 `.unknownCommand(value)` 警告。
          - 其他 `kind`：按 T-3 丢弃并记录 `.unknownTagType(kind)` 警告。
      - 遇其他字符：追加到 `tagBuffer`；若 `tagBuffer.count > Self.maxTagLength`（超过 24 个字符仍无 `>`，T-2），立即将整个 `tagBuffer` 作为普通文本刷出并退出缓冲态（同时更新 `hasSeenNonWhitespaceText`）。
  - `finish()`：若 `tagBuffer` 非空，按 T-7 原样作为普通文本刷出并清空 `tagBuffer`。

#### 5.8 `SentenceSplitter`（流式分句器，纯逻辑）
- **位置**：`Packages/MiniMateKit/Sources/MMConversation/SentenceSplitter.swift`（`import Foundation`、`import MMCore`）。
- **精确签名**：
  ```swift
  public struct SentenceAction: Sendable, Equatable, Codable {
      public let action: ActionTag
      public let charOffset: Int

      public init(action: ActionTag, charOffset: Int) {
          self.action = action
          self.charOffset = charOffset
      }
  }

  public struct Sentence: Sendable, Equatable {
      public let turnID: UUID
      public let index: Int
      public let text: String
      public let emotion: EmotionTag
      public let actions: [SentenceAction]

      public init(
          turnID: UUID,
          index: Int,
          text: String,
          emotion: EmotionTag,
          actions: [SentenceAction] = []
      )
  }

  public struct SentenceSplitter: Sendable {
      public let turnID: UUID
      public let firstSentenceCommaMinLength: Int
      public let maxSentenceLength: Int

      /// `finish()` 后若有紧跟句末/无后续可播文字的孤立 `<act>`，按出现顺序记录在此（不产出空句）。
      public private(set) var trailingActions: [ActionTag] = []

      public init(
          turnID: UUID,
          initialEmotion: EmotionTag = .neutral,
          firstSentenceCommaMinLength: Int = 6,
          maxSentenceLength: Int = 40
      )

      public mutating func feed(_ segments: [TaggedSegment]) -> [Sentence]
      public mutating func feed(_ segment: TaggedSegment) -> [Sentence]
      public mutating func finish() -> [Sentence]
  }
  ```
- **S-1–S-7 精确行为口径**：
  - 标点集合：
    - `sentenceEndPunctuation: Set<Character> = ["。", "！", "？", "…", "~", "～", ".", "!", "?"]`
    - `commaPunctuation: Set<Character> = ["，", "、", ","]`
  - 可播性判定（S-6）：`hasSpeakableContent(_ s: String) -> Bool { s.contains { $0.isLetter || $0.isNumber } }`（正确过滤空白、纯中文/英文标点以及 `~`/`～`）。
  - 忽略段：`.userEmotion` 与 `.command` 不产出文字、不改变 `pendingSentenceEnd`、不触发切分（T-8）。
  - `.emotion(newEmotion)`（S-4）：
    1. 若 `pendingSentenceEnd == true`，先刷出前一句（旧 `sentenceEmotion`）；
    2. 若 `newEmotion != currentEmotion`：
       - 若当前 `buffer` 含可播内容：将 `charOffset == buffer.count` 的末尾待发动作先分离暂存，按旧 `sentenceEmotion` 刷出当前 `buffer`，随后将这些末尾动作以 `charOffset = 0` 迁入新句；
       - 若当前 `buffer` 仅含不可播字符：清空 `buffer` 并把已有 `pendingActions` 的偏移归 `0`；
    3. 更新 `currentEmotion = newEmotion`；若此时 `buffer.isEmpty`，同步更新 `sentenceEmotion = newEmotion`。
  - `.action(act)`（S-5）：
    1. 若 `pendingSentenceEnd == true`，先刷出前一句（确保 `今天累坏了吧？<act:nod>先歇会儿` 中 `.nod` 落在第二句 `charOffset = 0`）；
    2. 追加 `SentenceAction(action: act, charOffset: buffer.count)`。
  - `.text(str)` 逐 `Character` 处理：
    1. 若 `pendingSentenceEnd == true`：
       - 若字符属于 `sentenceEndPunctuation`（连续标点，如跨块的 `"！？"`、`"……"`、`"..."`）：直接追加到 `buffer`，继续保持 `pendingSentenceEnd = true`；
       - 否则：先刷出前一句，置 `pendingSentenceEnd = false`，再处理当前字符。
    2. 若 `buffer.isEmpty && (ch.isWhitespace || ch.isNewline)`：直接跳过前导空白（保证句首 `<act>` 精确对齐 `0`）。
    3. 若字符属于 `sentenceEndPunctuation`（S-1）：
       - 若 `buffer` 即将首个进入且空，锁定 `sentenceEmotion = currentEmotion`；
       - 追加该字符到 `buffer`，置 `pendingSentenceEnd = true`。
    4. 若字符属于 `commaPunctuation`（S-2）：
       - 追加到 `buffer`（首次进入锁定 `sentenceEmotion = currentEmotion`）；
       - 若 `emittedSentenceCount == 0 && buffer.count - 1 >= firstSentenceCommaMinLength && hasSpeakableContent(buffer)`（即逗号前已达至少 6 字且为首句）：立即刷出首句！
       - 否则若 `buffer.count > maxSentenceLength`：执行下述 S-3 强切。
    5. 其他普通字符：
       - 若 `buffer.isEmpty`，锁定 `sentenceEmotion = currentEmotion`；
       - 追加字符到 `buffer`；
       - 若 `buffer.count > maxSentenceLength`（S-3，超过 40 字无句末标点）：
         - 在前 `maxSentenceLength` 字符（下标 `0..<maxSentenceLength`）中从右向左找最后一个 `commaPunctuation` 的索引 `commaIdx`；
         - 若找到且 `buffer[0...commaIdx]` 含可播内容，取 `splitOffset = commaIdx + 1`；否则取 `splitOffset = maxSentenceLength`；
         - 按 `splitOffset` 拆分为 `head` 与 `tail`；动作 `< splitOffset` 归 `head`，动作 `>= splitOffset` 归 `tail` 并减去 `splitOffset`；
         - 刷出 `head`；对 `tail` 剥离前导空白（剥离个数 `trimmedLead`），对应将 `tail` 的动作偏移减 `trimmedLead` 并夹紧 `>= 0`；将剩余 `tail` 设为新 `buffer`（`sentenceEmotion = currentEmotion`）。
  - 刷出辅助逻辑：去除尾部空白后检查 `hasSpeakableContent`；通过则构造 `Sentence(turnID: turnID, index: emittedSentenceCount, text: trimmed, emotion: sentenceEmotion, actions: clampedActions)` 并递增 `emittedSentenceCount`；不通过则丢弃文本（S-6），不递增 `emittedSentenceCount`，若 `pendingActions` 非空则偏移归 0 留待下一句。
  - `finish()`（S-7）：刷出剩余 `buffer`（若有可播内容则输出尾句）；若刷出后仍有未挂靠的 `pendingActions`，转入 `trailingActions` 并清空 `pendingActions`。幂等，重复调用返回 `[]`。
  - **非法参数防护**：`firstSentenceCommaMinLength = max(1, firstSentenceCommaMinLength)`，`maxSentenceLength = max(firstSentenceCommaMinLength, maxSentenceLength)`。

#### 5.9 `PCMConverter`（`MMAudio` 纯逻辑/离线音频重采样）
- **位置**：`Packages/MiniMateKit/Sources/MMAudio/PCMConverter.swift`（`import Foundation`、`import AVFoundation`、`import os`）。
- **精确签名**：
  ```swift
  public enum PCMConverterError: Error, Sendable, Equatable {
      case invalidSampleRate(Int)
      case unsupportedFormat(String)
      case conversionFailed(String)
  }

  /// 将输入音频重采样为目标采样率的 16-bit signed PCM 单声道 `AudioChunk`（默认支持 16 / 24 kHz）。
  public final class PCMConverter: @unchecked Sendable {
      public let targetFormat: AudioFormatDescription

      /// `targetSampleRate` 必须 > 0，否则抛 `PCMConverterError.invalidSampleRate`。
      public init(targetSampleRate: Int) throws

      /// 流式转换一个 `AudioChunk`：保留内部重采样滤波器状态以消除块间爆音；若输入与目标同采样率则零转换直通。
      public func convert(_ chunk: AudioChunk) throws -> AudioChunk

      /// 流式转换一个 `AVAudioPCMBuffer`（支持 Float32/Int16、单声道/多声道），输出目标采样率 Int16 单声道 `AudioChunk`。
      public func convert(_ buffer: AVAudioPCMBuffer, hostTime: UInt64 = 0) throws -> AudioChunk

      /// 排空流式转换器内部 FIR 尾部样本并重置转换器状态；无缓存转换器或无尾部样本时返回 `nil`。
      public func flush(hostTime: UInt64 = 0) throws -> AudioChunk?

      /// 重置内部重采样滤波器状态（路由切换或新一轮开始时调用）。
      public func reset()

      /// 一次性完整转换（等价于独立转换器 `convert` + `flush`，适合 WAV 文件整段重采样）。
      public static func convertComplete(_ chunk: AudioChunk, toSampleRate targetSampleRate: Int) throws -> AudioChunk
  }
  ```
- **边界与异常口径**：
  - `targetSampleRate <= 0` → `init` / `convertComplete` 抛 `.invalidSampleRate(targetSampleRate)`。
  - `chunk.sampleRate <= 0` → `convert` 抛 `.invalidSampleRate(chunk.sampleRate)`。
  - `chunk.samples.isEmpty` 或 `buffer.frameLength == 0` → 直接返回空 `AudioChunk(samples: [], sampleRate: targetFormat.sampleRate, hostTime: chunk.hostTime, marks: chunk.marks)`，不调用 `AVAudioConverter`。
  - `chunk.sampleRate == targetFormat.sampleRate` → 原样返回 `chunk`（保持 `samples`、`hostTime`、`marks` 逐位一致）。
  - 输入采样率或通道/格式与上次缓存的 `AVAudioConverter` 不同时（例如 48 kHz 切换至 44.1 kHz 或蓝牙 HFP 16 kHz），安全重建 `AVAudioConverter`；若重建失败抛 `.unsupportedFormat`。
  - `convert` 与 `flush` 均按 §3.2 陷阱规避写法循环拉取输出缓冲（每次分配 `>= max(expected + 512, 512)` 帧），彻底杜绝 240 帧 FIR 延迟截断。
  - 全程用 `OSAllocatedUnfairLock` 保护 `converter` 与格式状态，满足 Swift 6 严格并发安全。

#### 5.10 工程配置与 CLI 占位（`T001`、`T002`、`T003`）
- **`Packages/MiniMateKit/Package.swift`**：
  - `products` 追加：
    ```swift
    .library(name: "MMAudio", targets: ["MMAudio"]),
    .library(name: "MMConversation", targets: ["MMConversation"]),
    .executable(name: "mm-probe", targets: ["MMProbeCLI"]),
    ```
  - `targets` 追加：
    ```swift
    .target(name: "MMAudio", dependencies: ["MMCore"]),
    .target(
        name: "MMConversation",
        dependencies: ["MMCore", "MMAudio", "MMSecurity"],
        resources: [.process("Resources")]
    ),
    .executableTarget(
        name: "MMProbeCLI",
        dependencies: ["MMConversation", "MMAudio", "MMSecurity"]
    ),
    .testTarget(name: "MMAudioTests", dependencies: ["MMAudio", "MMCore"]),
    .testTarget(
        name: "MMConversationTests",
        dependencies: ["MMConversation", "MMAudio", "MMCore", "MMSecurity"]
    ),
    ```
- **`Packages/MiniMateKit/Sources/MMProbeCLI/main.swift`**：
  - `#if os(macOS)` 下解析 `CommandLine.arguments`：无参数或 `--help` / `-h` 打印 M2a 子命令预告（`realtime` / `tone-suite` / `tts` / `record-fixture`，待 Phase 3 `T020` 实现）并以退出码 `0` 退出；未知参数打印提示并以退出码 `2` 退出；`#else` 空入口保证跨平台打包不出错。
- **`.gitignore`**：追加：
  ```gitignore
  # Personal voice samples for M2a tone verification (never commit)
  Assets/voice-samples/*.wav
  ```
- **`App/MiniMate.xcodeproj/project.pbxproj`**：在 Debug（L283 后）与 Release（L313 后）紧邻 `INFOPLIST_KEY_NSCameraUsageDescription` 各新增一行：
  ```text
  INFOPLIST_KEY_NSMicrophoneUsageDescription = "用于与你语音对话。仅在本地检测到人声时才会上传音频，可随时一键静音。";
  ```

---

### 6. 原子化施工步骤（自底向上）

- **Step 1：基础配置、隐私忽略、权限声明与人格资源（`T002`, `T003`, `T004`, `T005`）**
  - 改动文件：`.gitignore`、`App/MiniMate.xcodeproj/project.pbxproj`、`Packages/MiniMateKit/Sources/MMSecurity/VendorID.swift`、`Packages/MiniMateKit/Tests/MMSecurityTests/CredentialStoreTests.swift`、`Packages/MiniMateKit/Sources/MMConversation/Resources/persona.md`
  - 改动要点：
    1. `.gitignore` 追加 `Assets/voice-samples/*.wav`；
    2. `project.pbxproj` 在 Debug 与 Release 两处补齐 `INFOPLIST_KEY_NSMicrophoneUsageDescription`；
    3. `VendorID` 增加 `Codable` 并在 `CredentialStoreTests.swift` 增补 `VendorID` 全枚举与 `Codable` 往返测试；
    4. 按 §5.5 创建 `Resources/persona.md`。
  - 最小验证命令：
    ```bash
    git check-ignore -v Assets/voice-samples/test.wav && \
    git grep -n "INFOPLIST_KEY_NSMicrophoneUsageDescription" App/MiniMate.xcodeproj/project.pbxproj && \
    (cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter CredentialStore)
    ```

- **Step 2：核心共享模型、协议边界、Package target 注册与兼容回归（`T001`, `T008`, `T009`, `T010` 协议）**
  - 改动文件：`Packages/MiniMateKit/Sources/MMCore/{ConnectionState.swift,GateState.swift,ConversationEvent.swift}`、`Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift`、`Packages/MiniMateKit/Sources/MMAudio/AudioChunk.swift`、`Packages/MiniMateKit/Sources/MMConversation/Realtime/RealtimeTextSession.swift`、`Packages/MiniMateKit/Sources/MMConversation/TTS/TTSProvider.swift`、`Packages/MiniMateKit/Sources/MMProbeCLI/main.swift`、`Packages/MiniMateKit/Package.swift`、`Packages/MiniMateKit/Tests/MMCoreTests/MMCoreTests.swift`、`Packages/MiniMateKit/Tests/MMEmotionTests/ConversationTransitionTests.swift`
  - 改动要点：按 §5.1–§5.4、§5.6（协议）、§5.10 落盘并补齐 `MMCoreTests` / `ConversationTransitionTests` 兼容回归用例；为保证 `MMAudioTests`/`MMConversationTests` 存在可编译文件，可先放后续 Step 3/5 的初始测试壳或紧接执行 Step 3a。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && \
    CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift build --disable-sandbox && \
    CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift run --disable-sandbox mm-probe --help && \
    CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter "MMCoreContractTests|ConversationTransition"
    ```

- **Step 3：`TagParser` 与 `SentenceSplitter`（严格 Test-First：`T006`/`T007` 红灯 → `T011`/`T012` 绿灯）**
  - 改动文件：`Packages/MiniMateKit/Sources/MMConversation/{TagParser.swift,SentenceSplitter.swift}`、`Packages/MiniMateKit/Tests/MMConversationTests/{TagParserTests.swift,SentenceSplitterTests.swift}`
  - 改动要点：
    - **3a（红灯）**：先在 `TagParser.swift` / `SentenceSplitter.swift` 放仅含公共类型签名与空返回（`return []`）的最小壳，按 §7.1 完整写完 `TagParserTests.swift`（T-1–T-10 + 参数化随机切分）与 `SentenceSplitterTests.swift`（S-1–S-7 + 随机切分），运行单测确认编译通过且测试失败（红灯）。
    - **3b（绿灯）**：按 §5.7 与 §5.8 完整实现 `TagParser.swift` 与 `SentenceSplitter.swift`，重跑单测确认全绿。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter "TagParser|SentenceSplitter"
    ```

- **Step 4：`Persona`、`TTSEmotionMapping` 与 `FakeTTSProvider`（Test-First 红灯 → `T010`/`T013` 绿灯）**
  - 改动文件：`Packages/MiniMateKit/Sources/MMConversation/{Persona.swift,TTS/EmotionMapping.swift,TTS/FakeTTSProvider.swift}`、`Packages/MiniMateKit/Tests/MMConversationTests/FoundationalTests.swift`
  - 改动要点：
    - **4a（红灯）**：先放签名壳 + 写完 `FoundationalTests.swift`（覆盖 `Persona`、`TTSEmotionMapping`、`FakeTTSProvider`、`RealtimeOutput`/`RealtimeError`），运行确认红灯。
    - **4b（绿灯）**：按 §5.5 与 §5.6 完整实现三个文件，重跑确认全绿。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter "MMConversationTests"
    ```

- **Step 5：`PCMConverter`（Test-First 红灯 → `T014` 绿灯）**
  - 改动文件：`Packages/MiniMateKit/Sources/MMAudio/PCMConverter.swift`、`Packages/MiniMateKit/Tests/MMAudioTests/PCMConverterTests.swift`
  - 改动要点：
    - **5a（红灯）**：先放 `PCMConverter.swift` 签名壳 + 写完 `PCMConverterTests.swift`（覆盖 `AudioChunk` 字节往返、48k→16k / 48k→24k / 44.1k→16k / 16k→24k 频率与 RMS 校验、同率直通、流式多块 + flush、动态切换采样率、`AVAudioPCMBuffer`、边界与异常），运行确认红灯。
    - **5b（绿灯）**：按 §5.9 完整实现 `PCMConverter.swift`，重跑确认全绿。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter "MMAudioTests"
    ```

- **Step 6：全量门禁、跨平台 iOS 编译与只读基线核验**
  - 执行 §7.2 完整门禁命令清单，确认 macOS 全量单测、CLI、iOS 单模块构建、App Simulator 构建（含产物 `Info.plist` 权限键）及零密钥泄露检查全部通过。

---

### 7. 确定性测试矩阵与验收门禁

#### 7.1 测试矩阵（严禁非确定性断言）
| 目标测试文件 | 覆盖类别 | 测试场景 | 必须写死的断言底线（禁止弱断言） |
| :--- | :--- | :--- | :--- |
| `MMCoreTests.swift` | 正例/回归 | `ConnectionState`、`GateState`（含 `isUploading` / `threshold`）、`ConversationEvent` 新 case | `.open(threshold: .playback).isUploading == true`、`.muted/.paused/.closed().isUploading == false`；`.muted.threshold == nil`、`.closed(threshold: .raised).threshold == .raised`；`Equatable` 精确区分不同 `attempt` 与不同 `GateThreshold` |
| `CredentialStoreTests.swift` | 兼容回归 | `VendorID` 枚举与 `Codable` 往返 | `VendorID.allCases == [.aliyun, .volcengine, .openai]`；每个 case JSON 编解码往返相等，且编出字面量等于 `rawValue` |
| `ConversationTransitionTests.swift` | 兼容回归 | 状态机收到 `.connectionStateChanged` / `.gateStateChanged` | 处于 `.attending` 与 `.speaking(.happy)` 时分别输入 `.connectionStateChanged(.reconnecting(attempt: 1))`、`.gateStateChanged(.muted)` 后，`state.kind` 与 `baseEmotion` 完全不变 |
| `TagParserTests.swift` | 正例 | 完整对话样例（`<user>` + `<emo>` + `<act>` + `<cmd>` + 文字） | 逐项断言产出 `[TaggedSegment]` 精确序列，且 `warnings.isEmpty` |
| `TagParserTests.swift` | 正例（T-1） | 标签跨 2/3 个增量切分（`<em`+`o:happy>`、`<cm`+`d:photo`+`Cancel>`） | 与整段输入产出完全一致的 `[TaggedSegment]` |
| `TagParserTests.swift` | 边界（T-2/T-6/T-7） | 未闭合 `<` 达 25 字符（>24）、`"1<2"`、`"1<2 and 3>2"`、`"1<2<emo:happy>你好"`、`finish()` 刷尾 | 25 字符未闭合在 `feed` 内即刷出 `.text`；`"1<2 and 3>2"` 原样保留为 `.text` 且 `warnings.isEmpty`；`"1<2<emo:happy>你好"` 精确产出 `[.text("1<2"), .emotion(.happy), .text("你好")]`；`finish()` 二次调用返回 `[]` |
| `TagParserTests.swift` | 异常反例（T-3/T-9） | `<emo:excited>`、`<foo:bar>`、`<act:jump>`、`<user:unknown>`、`<cmd:video>`、`<cmd:>` | 均不输出为 `.text`、不产出业务标签；`warnings.count == 6` 且每条 `reason` 与 `rawTag` 精确匹配 |
| `TagParserTests.swift` | 边界（T-4/T-5） | 无 `<user>`、文字后 `<user:sad>`、重复 `<user:happy><user:sad>`、`<emo:happy><user:sad>`、前导换行 `\n<user:tired>` | 无 `<user>` 时零 `.userEmotion`；文字后/重复/`<emo>` 后的 `<user>` 全部丢弃；前导换行后 `<user:tired>` 正常产出 `.userEmotion(.tired)` |
| `TagParserTests.swift` | 正例（T-8/T-10） | 三种 `<cmd>`（`photo`/`photoReady`/`photoCancel`）及同轮多个指令（含重复与冲突） | 分别精确产出对应 `.command` 且无 `.text`；多指令按原序全量产出，数量与顺序精确匹配 |
| `TagParserTests.swift` | 参数化一致性 | `@Test(arguments:)` 覆盖逐字切分、固定步长（2/3/5/7）、及固定种子伪随机切分（20 组切分点），输入含全部标签、`<cmd>`、T-3、T-5、T-6 | 合并相邻 `.text` 后，每组切分结果的 `[TaggedSegment]` 与 `warnings` 均与整段单次输入 **100% 相等** |
| `SentenceSplitterTests.swift` | 正例（S-1） | 中文/英文句末标点与连续标点（`"真的吗！？先歇会儿。"`、`"嗯……好吧！"`、`"Hi... ok~!"`），含 `"真的吗！"`+`"？"` 跨块 | 精确拆成预期句数与文本，`index` 从 0 严格递增；跨块 `"！"`+`"？"` 合并为同一句 `"真的吗！？"`，不出现孤立 `"？"` 句 |
| `SentenceSplitterTests.swift` | 正例（S-2） | 首句逗号提速：`"嗨，今天天气真好，去散步吧。"`（第 1 逗号前 1 字不切，第 2 逗号前 ≥6 字切）与第二句含逗号（`"先歇会儿，我陪着你。"` 不切） | 首句精确在第二个逗号处切分（`"嗨，今天天气真好，"`）；第二句完整保留逗号不切分 |
| `SentenceSplitterTests.swift` | 边界（S-3） | 45 字无标点；45 字且第 20 字有逗号且第 25 字有 `<act:nod>`；40 字 + `。` | 无标点拆为 40 字 + 5 字；有逗号在第 21 字处（含逗号）拆开且 `.nod` 迁至第 2 句 `charOffset == 4`；40 字 + `。` 保持单句 41 字 |
| `SentenceSplitterTests.swift` | 正例/边界（S-4） | 沿用上一个 `<emo>`；句中切新 `<emo>` 强切；句中重复同 `<emo>` 不切；连续 `<emo:happy><emo:gentle>你好。`；`"你好<act:nod><emo:gentle>再见。"` | 每句 `emotion` 精确匹配；同 `<emo>` 保持单句；末尾 `.nod` 归属 `"再见。"` 的 `charOffset == 0` |
| `SentenceSplitterTests.swift` | 正例/边界（S-5/S-6/S-7） | 句首/句中/多动作偏移；`"   。。。~~~！！！<emo:gentle>你好。"`；`<cmd:photo>` 插入句中/句尾；`"拜拜！<act:wave>"` 尾动作；`finish()` 幂等 | 偏移精确等于前导 Swift `Character` 数；空白/纯标点/纯 `~`/`～` 句全被过滤且不占用 `index`；`<cmd>` 零影响分句；尾动作进 `trailingActions == [.wave]` 且无空句；二次 `finish()` 返回 `[]` |
| `SentenceSplitterTests.swift` | 参数化一致性 | 与 `TagParser` 串联，多组固定种子随机切分流（覆盖 `tag-protocol.md` 全部示例 + 含 `<cmd>` 示例） | 每种切分最终产出的 `[Sentence]`（含 `index`/`text`/`emotion`/`actions`）与单次输入 **100% 相等** |
| `FoundationalTests.swift` | 正例/反例 | `Persona.loadBundled()`、`Persona.parse(markdown:)`（正常/缺标题/缺称呼/缺规则）、`makeInstructions`（含/不含第 6 条、含/不含 `extraInstructions`） | 内置 `name == "小瓜"`、`addressUserAs == "你"`、`!rules.isEmpty`；畸形 Markdown 抛 `PersonaError.invalidFormat`；`makeInstructions()` 精确包含全部 `UserEmotion`/`EmotionTag`/`ActionTag`/`AssistantCommand` `rawValue` 及"以语气为准"；`includeCommandInstructions: false` 不含 `"<cmd:"` |
| `FoundationalTests.swift` | 正例/反例 | `TTSEmotionMapping` JSON 对象解编码（含字符串/数值/布尔参数）、缺失情绪回退 `.neutral`（TTS-2）、空 `voice` / 未知情绪键 / 缺 `neutral` / 资源缺失报错 | 往返编码精确相等；缺失 `.shy` 返回 `.neutral` 参数；非法配置分别精确抛 `.emptyVoice` / `.unknownEmotionKey("excited")` / `.missingNeutralMapping` / `.resourceNotFound(.aliyun)` |
| `FoundationalTests.swift` | 正例/并发反例 | `FakeTTSProvider`：按字数多块静音输出、可注入 `ManualClock` 延迟、失败规则（TTS-4）、`cancelAll()` 后旧流零后续产出且新请求正常（TTS-5）、`includeWordMarks: true` 透传 `marks`（TTS-6）、空句 0 块 | 总帧数等于 `round(chars * msPerChar / 1000 * sr)`、全部样本为 `0`；失败流精确抛注入错误；`cancelAll()` 后旧流终止且无新增块、`cancelCount == 1`、后续新请求产出全部预期帧；`recordedRequests` 精确匹配 |
| `PCMConverterTests.swift` | 正例/边界/异常 | `AudioChunk` `pcmData` 往返（含极端值 `Int16.min`/`Int16.max` 与奇数字节截断）；48k→16k、48k→24k、44.1k→16k、16k→24k（1 s 440 Hz 正弦波）；同率直通；10×100 ms 流式 + `flush()`；48k→44.1k 动态切率；Float32 `AVAudioPCMBuffer`；空块与 `sampleRate <= 0` | 重采样后总帧数（含 `flush`）落在目标理论帧数 ±1% 内（如 16k 为 `[15_950, 16_050]`）；440 Hz 单频 DFT 幅度比 1000 Hz 杂散高 **> 20 dB** 且稳态 RMS 与输入偏差 **< 5%**；同率直通 `samples` 逐位相等；非法采样率精确抛 `PCMConverterError.invalidSampleRate` |

#### 7.2 完整门禁命令清单
```bash
# 1. 目标新增模块单测（沙盒内带 cache 环境变量；本机终端可直接省略环境变量与 --disable-sandbox）
cd Packages/MiniMateKit && \
CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache \
SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache \
swift test --disable-sandbox --filter "MMAudioTests|MMConversationTests"

# 2. Swift Package 全量纯逻辑测试（既有 146 用例 + 本次全部新增用例）
cd Packages/MiniMateKit && \
CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache \
SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache \
swift test --disable-sandbox

# 3. macOS CLI 占位产物构建与运行核验
cd Packages/MiniMateKit && \
CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache \
SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache \
swift run --disable-sandbox mm-probe --help

# 4. iOS 单模块条件编译验证（需在宿主环境运行，验证 MMAudio / MMConversation iOS 26 兼容）
cd Packages/MiniMateKit && \
xcodebuild -scheme MMAudio -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO && \
xcodebuild -scheme MMConversation -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

# 5. App 模拟器无签名编译 + 核验生成包 Info.plist 含 NSMicrophoneUsageDescription
xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# 6. .gitignore 与零密钥泄露及仓库状态核验
git check-ignore -v Assets/voice-samples/sample.wav && \
git grep -n -E "sk-[A-Za-z0-9]{16,}|MM_QWEN_KEY=|MM_DOUBAO_KEY=" Packages/ App/ ; \
git status
```

---

### 8. 项目附加产出要求
- **待用户明确确认验收进入收口阶段时**（验收前严禁提前修改）：
  1. 同步更新 `docs/CODEBASE_MAP.md`：
     - §1 模块职责表补充 `MMAudio`、`MMConversation`、`MMProbeCLI`（`mm-probe`）以及 `MMAudioTests`/`MMConversationTests`，并从“计划中尚未建立的 Package 模块”移除这三个模块（仅保留 `MMMemory`）；
     - §1 `MMCore` 行补充 `ConnectionState`、`GateState`/`GateThreshold`；
     - §3 公共复用设施表补充 `TagParser`、`SentenceSplitter`、`Persona`、`TTSEmotionMapping`、`FakeTTSProvider`、`PCMConverter`；
     - §4 依赖方向补充：`MMAudio → MMCore`、`MMConversation → MMCore, MMAudio, MMSecurity`、`MMProbeCLI → MMConversation, MMAudio, MMSecurity`。
  2. 同步更新 `docs/HANDOFF_LEDGER.md`：记录 `[003-m2-phase1-2]` 完成基线、最新全量测试数、以及 `AVAudioConverter` 240 帧 FIR 延迟 / `~` 非 `isPunctuation` / `JSONDecoder` 枚举键等实测陷阱（控制 ≤ 100 行）。
  3. 按用户确认结果勾选 `specs/003-m2-voice-conversation/tasks.md` 中的 `T001`–`T014`。

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

- **闭环结果**：一致通过（共 **3 轮**，阻断项 = 0，无未决分歧）
- **审查通道与模型**：单节点独立只读审查员 `reviewer`（模型 `gemini-4-neon-high` / `Gemini 4 Neon (High)`），每轮均核验只读快照指纹字节级零修改，闭环结束后已回收。
- **每轮问题与处置**：
  - **Round 1（需修改：2 阻断 + 3 非阻断）**：
    1. 阻断 #1：`PCMConverter` 同采样率直通快路径未清理既有 `AVAudioConverter` 状态（48k → 16k 路由切换后 `flush()` 会吐出旧 48k 残留 FIR 帧）且 `AVAudioPCMBuffer` 采样率比较用了取整 → 在两条直通路径均于 `state.withLock` 清空 `converter` / `inputFormatKey`，改为精确 `inputRate == Double(targetFormat.sampleRate)`，补充 `routeSwitchToPassthroughClearsStaleConverterState` 回归测试。
    2. 阻断 #2：`FakeTTSProvider` 无 `deinit` 且 `producer` 在 `self == nil` 时未 `continuation.finish()` 导致消费方永挂 → 新增 `deinit` 与兜底 `continuation.finish()` 并补充测试。
    3. 非阻断 1–3 一并修复：移除 `PCMConverter.State.inputSampleRate` 冗余字段、`flush()` 改用 `defer { converter.reset() }`、`StepManualClock.sleep` 取消判定移入锁内、`fakeTTSCancelAllLinearizability` 扩至首块后中途取消、`personaParseRejectsMalformedMarkdown` 补缺风格正文反例。
  - **Round 2（需修改：1 阻断）**：
    1. 阻断 #1：`FakeTTSProvider` `producer` `Task` 顶部 `guard let self` 导致 `await clock.sleep` 期间仍强持有 `self`，挂起中途释放无法触发 `deinit` 且新测试存在调度竞态 → 移除跨 `await` 强绑定，改为仅在 `await` 后同步锁区绑定 `strongSelf`；测试改为确定性等待 `clock.sleeperCount > 0` 后再释放 `ephemeral = nil`。
  - **Round 3（通过：0 阻断 / 0 非阻断）**：全部修复与确定性测试独立复跑通过。
- **最终验收实测证据**：
  - `swift test --disable-sandbox`（全量）：**180/180（28 suites）通过**（`MMSecurityTests` 8、`MMPerceptionTests` 32、`MMEmotionTests` 72、`MMDiagnosticsTests` 14、`MMCoreTests` 23、`MMConversationTests` 24、`MMAudioTests` 7；0 skip）
  - `swift run --disable-sandbox mm-probe --help`：退出码 `0`（未知参数退出码 `2`）
  - `xcodebuild -scheme MMAudio` & `MMConversation -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`：均 `BUILD SUCCEEDED`
  - `xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`：`BUILD SUCCEEDED`，`plutil -extract NSMicrophoneUsageDescription` 验证产物 `Info.plist` 精确含中文权限说明
  - `git check-ignore -v Assets/voice-samples/sample.wav` 命中 `.gitignore:25`，零密钥泄露扫描通过

### 验收收口待办（待用户明确确认验收后落盘再提交）
- 更新 `docs/HANDOFF_LEDGER.md`：
  - 陷阱补充：`AVAudioConverter` 48k→16k FIR 滞留 240 帧（需循环拉取 + `flush()` + 路由切直通清旧转换器）；Swift 6.4 `~`/`～` 的 `isPunctuation == false`（须 `isLetter || isNumber`）；`JSONDecoder` 对枚举键字典默认按数组编解码（须经 `[String: V]` 对象转换）。
  - 近期契约变更：`[003-m2-phase1-2]` 完成 M2 工程基座与纯逻辑底座（`T001`–`T014`），新增 `MMAudio` / `MMConversation` / `MMProbeCLI`、`ConnectionState` / `GateState`、`TagParser` / `SentenceSplitter` / `Persona` / `TTSEmotionMapping` / `FakeTTSProvider` / `PCMConverter`，全量单测基线 **180/180（28 suites）**。
- 更新 `docs/CODEBASE_MAP.md`：按执行单 §8 同步 §1 模块表、§3 公共复用设施表与 §4 依赖方向。
- 勾选 `specs/003-m2-voice-conversation/tasks.md` 中的 `T001`–`T014`。
