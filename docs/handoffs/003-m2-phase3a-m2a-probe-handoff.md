# 003-m2 Phase 3a（厂商无关多供应商配置架构、驱动注册表与插件化 `mm-probe` 底座）执行单

- **状态**：已验收收口
- **Git 基线**：`main` @ `331c56a`
- **关键基线**：Swift 6.4（`arm64-apple-macosx27.2.0`），`Packages/MiniMateKit/Package.swift`（`swift-tools-version: 6.2`，`.iOS(.v26)` / `.macOS(.v26)`），零第三方依赖，纯逻辑单测基线 **180/180（28 suites）**；Apple 系统 `zlib 1.2.12` 实测可用（`inflateInit2_(..., 15 + 32, ...)` 返回 `0`）。
- **拍板决议摘要**：`1A`（彻底删除 `VendorID.swift`，全量迁至 `profileID: UUID` 与 `driverID: String`） / `2A`（`JSONFileProviderProfileStore` 落盘 `Application Support/MiniMate/provider-profiles.json`，凭证独占 Keychain） / `3A`（通用 `GzipCodec` 纳入 Phase 3a，零第三方依赖链接系统 `libz`） / `4A`（同步将开发/Debug 隐私红线与 `--driver` 命令规范写入 `AGENTS.md`）

> **红线声明（绝对禁越）**
> - **开发 / Debug 隐私红线**：在开发或 debug 期间，模型与工具**严禁擅自读取用户配置的其他模型厂商的任何信息（连厂商名称都不行）**；若确实需要读取，必须**每次先向用户说明原因并获得用户明确同意**。
> - **代码库零厂商残留红线**：`App/` 与 `Packages/MiniMateKit/` 中的全部源码、测试、资源与注释**严禁残留任何具体模型厂商名称、专有音色名、具体 Endpoint 或硬编码厂商枚举**；验收前必须通过 §7.2 的自动化零残留扫描门禁（返回 0 命中）。历史只读文档（`docs/handoffs/`、`docs/tech-selection.md`、`specs/`）本单保持只读不动。
> - **密钥与个人语音隐私红线**：API Key / 附加凭证仅存 iOS Keychain（App）或环境变量（`mm-probe`），严禁写入仓库、Profile 元数据 JSON、日志、错误描述或测试夹具（RS-1、宪章 VII）；严禁读取、上传或提交 `Assets/voice-samples/*.wav`；`record-fixture` 默认过滤全部上行原始音频帧，禁止个人语音落盘夹具。
> - **零第三方依赖与并发规范**：严禁引入第三方依赖（宪章 VI、`plan.md:15`），仅用 Apple 系统框架（Foundation / Security / AVFoundation / SwiftUI / os / 系统 `zlib`）；Swift 6 严格并发 + Swift Testing；引用 `MMCore` 时钟必须显式写 `any MMCore.Clock`。
> - **收口与只读保护**：设计阶段仅更新本执行单；历史执行单（`docs/handoffs/`）只读留档，严禁移动/重命名/删除；未经用户明确确认验收，不得勾选 `tasks.md`，不得 `git commit`，不得 `git push`。

---

## 上篇：面向用户决策

### 1. 任务目标与选择理由
- **本次任务**：重构 Phase 3a 边界，彻底去厂商硬编码，交付**完全厂商无关**的 5 块核心底座：
  1. **`MMSecurity` 多配置安全存储升级**：删除硬编码厂商枚举 `VendorID`，建立按用途划分（`realtimeBrain` / `emotionalTTS`）的 `ProviderProfile` 非敏感元数据存储（支持每类 `1..N` 配置与独立 Active 切换）+ 按 `profileID: UUID` 键控的 Keychain `CredentialStore`（主凭证 + 可选附加凭证）。
  2. **App 设置页重构（`App/MiniMate/`）**：在 `SettingsView` 中按两类用途清晰分区——**「实时语音理解（对话大脑）」**与**「情感语音合成（小瓜声音）」**，说明各自用途，支持动态新增/编辑/删除多条配置与一键切换 Active；协议驱动下拉列表从注册表动态读取，凭证仅写 Keychain 且永不回显明文。
  3. **`MMConversation` 厂商无关驱动注册表与通用基础设施**：泛化 `TTSEmotionMapping`（去除 `VendorID` 依赖，改为 `driverID: String`）；建立 `ProviderRegistry`（`RealtimeSessionDriver` / `TTSProviderDriver` 动态注册与构造）、内置无厂商信息的离线模拟驱动（`mock-realtime` / `mock-tts`），并落地通用传输/脱敏/压缩/音频基础设施（`WAVCodec`、`SecretRedactor`、`WebSocketTransport`、`HTTPStreamingTransport`、`FixtureRecordingTransport`、`GzipCodec`）。
  4. **插件化 `mm-probe` 验证框架（`MMProbeCore` + `MMProbeCLI`）**：零硬编码厂商名，通过 `--driver <id>` 从 `ProviderRegistry` 动态寻址，实现 `list-drivers`、`realtime`、`tone-suite`、`tts`、`record-fixture`，完整涵盖 WAV 自动重采样 + 尾部静音流式推流、`TagParser` 统计、V4–V7 / SC-002 指标与 Markdown 报告、脱敏夹具录制与离线回放。
  5. **全仓代码零厂商信息清零 + 离线确定性测试套件**：清理现有代码库中全部历史厂商残留，全量离线单测、CLI 端到端模拟跑通与 iOS/macOS 双端编译验证通过；为后续 **Phase 3b（独立低成本探索与接入具体外部驱动）** 留好标准扩展接口。
- **选择理由**：Phase 1–2（`331c56a`，180/180 单测）已交付纯逻辑基础契约；先将配置模型、Keychain 凭证、设置页 UI、驱动注册表、传输脱敏层与 `mm-probe` 评测量尺全部抽象为厂商无关的稳定底座，既能保障架构解耦（宪章 IV）与开发期隐私边界，又能让后续 Phase 3b 接入任意具体外部协议驱动时仅需新增独立驱动文件并注册，无需改动 App UI、安全层或 CLI 框架。
- **摸底关键发现（全仓零信任核验）**：
  1. **全仓代码库厂商名残留已 100% 盘点定位**（仅涉及 3 个文件 + 3 处 `VendorID` 关联引用）：
     - `Packages/MiniMateKit/Sources/MMSecurity/VendorID.swift:5-13`（含 3 个硬编码厂商枚举分支及其中文标题）；
     - `Packages/MiniMateKit/Tests/MMSecurityTests/CredentialStoreTests.swift:14-91`（引用旧 `VendorID` 枚举与硬编码测试字面量）；
     - `Packages/MiniMateKit/Tests/MMConversationTests/FoundationalTests.swift:171-219`（测试夹具 JSON 中含硬编码厂商名与具体音色名）；
     - 关联引用 `VendorID`：`MMSecurity/CredentialStore.swift`、`MMConversation/TTS/EmotionMapping.swift`、`App/MiniMate/Screens/SettingsView.swift`。其余全部源码与测试经全仓正则扫描均无厂商残留。
  2. **`App/MiniMate.xcodeproj/project.pbxproj` 尚未链接 `MMConversation` 与 `MMAudio`**：目前 App 仅链接 6 个模块（`MMCore`、`MMDiagnostics`、`MMSecurity`、`MMAvatar`、`MMPerception`、`MMEmotion`）；要让 `SettingsView` 从 `ProviderRegistry` 动态拉取驱动列表，本单必须同步在 `project.pbxproj` 中链接 `MMConversation`（及 `MMAudio`）。
  3. **`MMProbeCLI` 依赖与可测性拆层**：`Package.swift:35-38` 中 `MMProbeCLI` 尚缺 `MMCore` 直接依赖；且因 `main.swift` 存在顶层入口无法直接被测试 target 导入，新增内部库 target `MMProbeCore`（不对外暴露为 library product、不被 iOS App 链接）可让 `swift test` 100% 确定性覆盖 CLI 参数解析、环境变量加载、报告统计与全部子命令流。

### 2. 待用户拍板的决策清单

1. **旧 `VendorID` 枚举处理方式**
   - **1A（推荐）**：**彻底删除 `MMSecurity/VendorID.swift`**，同步将 `CredentialStore` 升级为 `profileID: UUID` 键控、`TTSEmotionMapping` 泛化为 `driverID: String`，并将 `CredentialStoreTests`、`FoundationalTests`、`SettingsView` 全部迁至厂商无关模型，彻底达成代码库零厂商残留。
   - **1B**：保留 `VendorID` 类型壳但删净具体厂商值并改为纯泛型占位标识。*差量：若选 1B，需在 §4–§5 保留 `VendorID.swift` 及对 `CredentialStore`/`TTSEmotionMapping` 的兼容桥接层。*

2. **非敏感 `ProviderProfile` 元数据的持久化位置**
   - **2A（推荐）**：采用 **JSON 文件存储（`JSONFileProviderProfileStore`）**，落盘至应用沙盒 `Application Support/MiniMate/provider-profiles.json`（`.atomic` 原子写入、带 `schemaVersion: 1`，严禁含任何密钥；凭证 100% 独占 iOS Keychain `service = "ai.minimate.credentials.v2"`），并配套 `InMemoryProviderProfileStore` 供单测与 Preview 使用。
   - **2B**：改用 `UserDefaults` 存储编码后的 JSON Data。*差量：若选 2B，需在 §4.1–§5.1 将 `JSONFileProviderProfileStore` 替换为 `UserDefaultsProviderProfileStore(suiteName:)` 并同步调整持久化单测。*

3. **通用 `GzipCodec`（基于系统 `zlib`）是否纳入 Phase 3a 传输层**
   - **3A（推荐）**：**纳入 Phase 3a**（`MMConversation/Transport/GzipCodec.swift` + `Package.swift` 为 `MMConversation` 声明 `linkerSettings: [.linkedLibrary("z")]`）。纯通用 RFC 1952 压缩/解压能力（零第三方依赖、零厂商绑定，已实测 Swift 6.4 系统 `zlib 1.2.12` 可用），让 Phase 3b 接入任意二进制/压缩流协议时无需回改 `Package.swift`。
   - **3B**：暂不纳入 3a，待 Phase 3b 确有协议需要 GZIP 时再引入。*差量：若选 3B，需从 §4.1 移除 `GzipCodec.swift`、取消 `Package.swift` 的 `linkerSettings: [.linkedLibrary("z")]` 以及 §7.1 对应 GZIP 编解码与解压炸弹防线测试。*

4. **是否同步将「开发 / Debug 隐私红线」写入 `AGENTS.md`**
   - **4A（推荐）**：**本单同步更新 `AGENTS.md`**——在「约定」节新增开发/Debug 隐私红线（严禁擅自读取用户配置的其他模型厂商任何信息含名称，确需读取须逐次说明并获明确同意），并将 `AGENTS.md` 中的 `mm-probe` 示例命令改为厂商无关的 `--driver <id>` 形式。
   - **4B**：本单不改动 `AGENTS.md`，红线仅保留在执行单中，留待后续统一修订项目规范。*差量：若选 4B，需从 §4.1 文件改动表与 §6 Step 1 中移除 `AGENTS.md`。*

---

## 下篇：面向实施方的零歧义施工图

### 3. 现状锚点与环境陷阱预警

#### 3.1 现有代码锚点（含全仓厂商残留清理清单）
| 模块/符号 | 精确位置 | 现状职责 / 残留定位 / 改造约束 |
| :--- | :--- | :--- |
| `VendorID`（**厂商残留 #1**） | `Packages/MiniMateKit/Sources/MMSecurity/VendorID.swift:1-16` | 硬编码 3 家具体厂商枚举与标题 → **本单整文件删除**。 |
| `CredentialStore` / `KeychainCredentialStore` / `InMemoryCredentialStore` | `Packages/MiniMateKit/Sources/MMSecurity/CredentialStore.swift:1-125` | 当前按 `VendorID` 存取单 Key，缺 `load` 与附加凭证 → **重构为按 `profileID: UUID` 存取 `ProviderCredentials(primarySecret, secondarySecret)`**，Keychain 服务名升级为 `"ai.minimate.credentials.v2"`。 |
| `CredentialStoreTests`（**厂商残留 #2**） | `Packages/MiniMateKit/Tests/MMSecurityTests/CredentialStoreTests.swift:1-93` | 行 14–91 含旧枚举与具体厂商字面量 → **重写为基于 `UUID` 的 `CredentialStore` + `ProviderProfileStore` 全量单测**。 |
| `TTSEmotionMapping` / `VendorEmotionParams` | `Packages/MiniMateKit/Sources/MMConversation/TTS/EmotionMapping.swift:44-164` | 依赖 `MMSecurity.VendorID` 且命名带 `Vendor` → **泛化为 `driverID: String` + `EmotionParameterSet`**，`loadBundled(for driverID: String)` + 新增 `load(fromFile url: URL)`。 |
| `FoundationalTests`（**厂商残留 #3**） | `Packages/MiniMateKit/Tests/MMConversationTests/FoundationalTests.swift:167-220` | 行 171–219 含具体厂商名与音色名 → **仅迁移该 2 个 `TTSEmotionMapping` 测试到 `driverID: "mock-tts"` / `voice: "demo-voice"`，其余 178 条测试严禁改动**。 |
| `SettingsView` | `App/MiniMate/Screens/SettingsView.swift:1-105` | 当前 `ForEach(VendorID.allCases)` 硬编码列表 → **重构为双用途分区（实时语音理解 / 情感语音合成）+ 动态 1..N 管理 + Active 切换**，新增独立编辑弹窗 `ProviderProfileEditorSheet.swift`。 |
| `AppComposition` | `App/MiniMate/AppComposition.swift:1-33` | 当前仅持有 `clock` 与 `credentialStore` → **新增持有 `profileStore: any ProviderProfileStore` 与 `providerRegistry: ProviderRegistry`**；保持既有 `makePerceptionSource()` / `makeEmotionStateMachine()` 签名不变。 |
| `App/MiniMate.xcodeproj/project.pbxproj` | `App/MiniMate.xcodeproj/project.pbxproj:10-16,35-41,83-89,366-396` | 当前仅链接 6 个 Package 产物（`0001..0006`），未链接 `MMAudio`/`MMConversation` → **追加 `0007` (`MMAudio`) 与 `0008` (`MMConversation`)**，使 App 可导入 `MMConversation`。 |
| `Package.swift` | `Packages/MiniMateKit/Package.swift:22-49` | ① `MMConversation` 增 `linkerSettings: [.linkedLibrary("z")]`；② 新增内部目标 `MMProbeCore`（依赖 `MMCore`/`MMAudio`/`MMConversation`/`MMSecurity`）；③ `MMProbeCLI` 依赖 `["MMProbeCore"]`；④ `MMConversationTests` 增依赖 `"MMProbeCore"` 与 `resources: [.copy("Fixtures")]`。 |
| `MMCore.Clock` / `EmotionTag` / `UserEmotion` | `Packages/MiniMateKit/Sources/MMCore/{MMCore,EmotionTag,UserEmotion}.swift` | 只读复用；所有时钟参数必须显式写 `any MMCore.Clock`。 |
| `AudioChunk` / `AudioFormatDescription` / `AudioTimeMark` / `PCMConverter` | `Packages/MiniMateKit/Sources/MMAudio/{AudioChunk,PCMConverter}.swift` | 只读复用；`WAVCodec` 必须复用 `PCMConverter` 完成格式与采样率转换及 `flush()`。 |
| `RealtimeTextSession` / `TTSProvider` / `FakeTTSProvider` / `Persona` / `TagParser` | `Packages/MiniMateKit/Sources/MMConversation/` | 既有契约与纯逻辑实现只读复用，**严禁改写既有协议签名**。 |
| `MMProbeCLI/main.swift` | `Packages/MiniMateKit/Sources/MMProbeCLI/main.swift:1-25` | 当前 `--help` 占位 → 改为 `#if os(macOS)` 顶层 `await` 转发至 `MMProbeCore.ProbeCLI.run(...)`。 |
| `AGENTS.md` | `AGENTS.md` | 同步补充「开发 / Debug 隐私红线」并将 `mm-probe` 示例命令改为 `--driver <id>` 形式。 |

#### 3.2 环境与第三方依赖实测陷阱
- **Swift 6.4 `Swift.Clock` 命名冲突**：裸写 `any Clock` 会与标准库冲突 → 全仓统一写 `any MMCore.Clock`。
- **沙盒内 `swift test` / `swift build` 模块缓存权限**：默认系统 ModuleCache 目录在沙盒不可写 → 沙盒内执行须前缀 `CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache` 并传 `--disable-sandbox`（本机常规终端直接 `swift test`）。
- **系统 `zlib` 链接**：已实测 Swift 6.4 下 `import zlib` + `inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, ...)` 返回 `Z_OK (0)`（`zlib 1.2.12`）；必须在 `Package.swift` 的 `MMConversation` 上声明 `linkerSettings: [.linkedLibrary("z")]`，保障 macOS 与 iOS 双端无未定义符号。
- **SwiftPM `.copy("Fixtures")` 路径**：`MMConversationTests` 配置 `resources: [.copy("Fixtures")]` 会保留子目录，读取夹具必须传 `Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")`。
- **`main.swift` 禁止混用 `@main`**：`MMProbeCLI/main.swift` 使用顶层 `await` + `exit(code)`（包裹在 `#if os(macOS)` 中），target 内严禁出现 `@main`。
- **跨平台（iOS + macOS）隔离**：`MMSecurity`、`MMAudio`、`MMConversation` 均被 iOS App 链接，严禁使用 macOS-only API；`MMProbeCore` 若不依赖 macOS-only API 可直接用纯 Swift `Foundation` 实现（从而跨平台可编译），`MMProbeCLI/main.swift` 保持 `#if os(macOS)`。
- **流式 PCM 奇数字节跨帧对齐**：提供通用可复用的 `PCMByteAligner`（在 `MMAudio/WAVCodec.swift` 或 `MMConversation/Transport/`），确保任意 Phase 3b 流式 TTS 驱动在收到奇数长度二进制/Base64 PCM 块时不丢弃奇数字节、不造成声道错位。
- **Keychain 短凭证脱敏边界**：当用户误输长度 ≤ 4 字符的极短测试串时，`CredentialStatus` 的 `suffix` 必须返回 `"****"`（严禁把整条短密钥当作“末 4 位”暴露）；长度 > 4 时返回末 4 位。

---

### 4. 改动范围表与明确不做清单（Non-Goals）

#### 4.1 文件改动表
| 文件路径 | 操作 | 精确职责 |
| :--- | :--- | :--- |
| `AGENTS.md` | 修改 | 在「约定」节写入开发 / Debug 隐私红线；将 `mm-probe` 示例命令改为厂商无关的 `--driver <id>` 形式。 |
| `Packages/MiniMateKit/Package.swift` | 修改 | `MMConversation` 增 `linkerSettings: [.linkedLibrary("z")]`；新增内部目标 `MMProbeCore`（依赖 `MMCore`/`MMAudio`/`MMConversation`/`MMSecurity`）；`MMProbeCLI` 依赖 `["MMProbeCore"]`；`MMConversationTests` 增依赖 `"MMProbeCore"` 与 `resources: [.copy("Fixtures")]`。 |
| `App/MiniMate.xcodeproj/project.pbxproj` | 修改 | 在 `PBXBuildFile`、`PBXFrameworksBuildPhase`、`packageProductDependencies`、`XCSwiftPackageProductDependency` 中追加本地包产物 `MMAudio`（`0007`）与 `MMConversation`（`0008`）。 |
| `Packages/MiniMateKit/Sources/MMSecurity/VendorID.swift` | 删除 | 彻底清除硬编码厂商枚举（残留清理 #1）。 |
| `Packages/MiniMateKit/Sources/MMSecurity/ProviderRole.swift` | 新增 | 定义双用途模型分类 `ProviderRole`（`.realtimeBrain` / `.emotionalTTS`）及面向 UI 的中文标题与用途说明。 |
| `Packages/MiniMateKit/Sources/MMSecurity/ProviderProfile.swift` | 新增 | 定义非敏感模型配置元数据 `ProviderProfile`、校验错误 `ProviderProfileError` 与输入规范化逻辑（永不含密钥）。 |
| `Packages/MiniMateKit/Sources/MMSecurity/ProviderProfileStore.swift` | 新增 | 定义 `ProviderProfileStore` 协议、沙盒 JSON 原子持久化实现 `JSONFileProviderProfileStore`（`Application Support/MiniMate/provider-profiles.json`）与内存实现 `InMemoryProviderProfileStore`。 |
| `Packages/MiniMateKit/Sources/MMSecurity/CredentialStore.swift` | 修改 | 重构为按 `profileID: UUID` 键控的 `CredentialStore`（`save`/`load`/`status`/`delete`）、脱敏自保护 `ProviderCredentials`（主凭证 + 可选附加凭证）、`CredentialStatus`、`KeychainCredentialStore`（v2 单项原子存储）与 `InMemoryCredentialStore`。 |
| `Packages/MiniMateKit/Sources/MMAudio/WAVCodec.swift` | 新增 | 纯 Swift PCM16 单声道 WAV 编解码（支持跳过扩展 RIFF 子块）、多块写盘、`AVAudioFile` + `PCMConverter` 自动重采样加载，以及通用跨帧偶数对齐工具 `PCMByteAligner`。 |
| `Packages/MiniMateKit/Sources/MMConversation/TTS/EmotionMapping.swift` | 修改 | 移除 `VendorID` 依赖；改为 `driverID: String` + `EmotionParameterSet`；支持 `load(from:)`、`load(fromFile:)`、`loadBundled(for driverID:)`。 |
| `Packages/MiniMateKit/Sources/MMConversation/Transport/SecretRedactor.swift` | 新增 | 厂商无关通用脱敏器（RS-1）：擦除注册明文凭证、`Bearer ...`、`sk-...` 及常见鉴权头/JSON 敏感字段。 |
| `Packages/MiniMateKit/Sources/MMConversation/Transport/WebSocketTransport.swift` | 新增 | 可注入 `WebSocketTransport` / `WebSocketConnection` / `WebSocketMessage` / `WebSocketTransportError` 协议 + 基于共享 `URLSession` + `URLSessionWebSocketDelegate` 握手状态码提取的默认实现 `URLSessionWebSocketTransport`。 |
| `Packages/MiniMateKit/Sources/MMConversation/Transport/HTTPStreamingTransport.swift` | 新增 | 可注入 `HTTPStreamingTransport` / `HTTPStreamingResponse` 协议 + 基于 `URLSession.bytes(for:)` 的逐行 UTF-8 流式默认实现 `URLSessionHTTPStreamingTransport`。 |
| `Packages/MiniMateKit/Sources/MMConversation/Transport/FixtureRecordingTransport.swift` | 新增 | `FixtureFrameRecord` JSONL 编解码 + `RecordingWebSocketTransport` 装饰器：不录任何 HTTP 握手头、自动把握手头值加入脱敏集、默认 `outboundFilter` 过滤上行原始音频帧防个人声音泄漏。 |
| `Packages/MiniMateKit/Sources/MMConversation/Transport/GzipCodec.swift` | 新增 | 基于系统 `zlib` 的通用 RFC 1952 GZIP 压缩/解压工具（含 16 MiB 安全解压上限防炸弹）。 |
| `Packages/MiniMateKit/Sources/MMConversation/Realtime/FakeRealtimeTextSession.swift` | 新增 | 厂商无关的离线可控 `RealtimeTextSession` 实现（支持脚本回放、自动按音频+静音触发 VAD/转写/标签文字回复、遵循 RS-1–RS-5）+ `RealtimeSessionAuditable` 可选审计协议（供 Phase 3b 真实驱动上报 V4 意外音频计数）+ 通用 `LoopbackMockWebSocketTransport`（供 `record-fixture` 离线端到端录制验证）。 |
| `Packages/MiniMateKit/Sources/MMConversation/Registry/ProviderDriverDescriptor.swift` | 新增 | 协议驱动描述符 `ProviderDriverDescriptor`、`DriverBuildContext`、`RealtimeSessionDriver` 与 `TTSProviderDriver` 协议。 |
| `Packages/MiniMateKit/Sources/MMConversation/Registry/ProviderRegistry.swift` | 新增 | 线程安全 `ProviderRegistry`（动态注册、按 `ProviderRole` 查询描述符、按 `ProviderProfile` + `ProviderCredentials` 校验并构造会话/TTS 实例）及 `makeDefault()`（预注册内置 `mock-realtime` 与 `mock-tts` 驱动）。 |
| `Packages/MiniMateKit/Sources/MMConversation/Registry/BuiltInMockDrivers.swift` | 新增 | 内置离线演示驱动 `MockRealtimeDriver`（`id: "mock-realtime"`）与 `MockTTSDriver`（`id: "mock-tts"`，包装 `FakeTTSProvider`），零厂商信息。 |
| `Packages/MiniMateKit/Sources/MMProbeCore/ProbeArguments.swift` | 新增 | 零第三方依赖手工 CLI 参数解析（`list-drivers`、`realtime`、`tone-suite`、`tts`、`record-fixture`、`--help`）与精确错误提示。 |
| `Packages/MiniMateKit/Sources/MMProbeCore/ProbeReport.swift` | 新增 | V4–V7 / SC-002 指标计算（含 nearest-rank p50 百分位、3 组语气 `<user>` 可区分度统计）与 Markdown 表格渲染器。 |
| `Packages/MiniMateKit/Sources/MMProbeCore/ProbeRunner.swift` | 新增 | 插件化评测执行器：从环境变量按 `--key-env` / `--secondary-env` 读取凭证、通过 `ProviderRegistry` 动态构造驱动、WAV 自动重采样 + 尾部静音流式推流、复用 `TagParser` 解析、TTS 按情绪导出 WAV、`record-fixture` 脱敏写 JSONL。 |
| `Packages/MiniMateKit/Sources/MMProbeCLI/main.swift` | 修改 | 精简 `#if os(macOS)` 顶层入口，调用 `ProbeRunner.main(arguments:environment:)` 并 `exit(code)`。 |
| `App/MiniMate/AppComposition.swift` | 修改 | 注入并持有 `profileStore: any ProviderProfileStore` 与 `providerRegistry: ProviderRegistry`（默认 `JSONFileProviderProfileStore.appDefault()` + `ProviderRegistry.makeDefault()`）。 |
| `App/MiniMate/Screens/SettingsView.swift` | 修改 | 重构为两类用途分区（实时语音理解 / 情感语音合成）+ 清晰用途说明 + 动态 1..N 配置列表 + Active 点选 + 滑动删除（同步清理 Keychain）+ 保留「诊断 > 能力探测」入口。 |
| `App/MiniMate/Screens/ProviderProfileEditorSheet.swift` | 新增 | 通用配置新增/编辑弹窗：自定义名称、动态驱动 Picker（来自 `ProviderRegistry`）、主凭证/可选附加凭证 `SecureField`（永不回显明文、支持清除）、可选自定义 Endpoint / Model / 音色、保存失败原子回滚。 |
| `Packages/MiniMateKit/Tests/MMSecurityTests/CredentialStoreTests.swift` | 修改 | 清除全部旧厂商残留（#2），重写为 `CredentialStore`（含主/副凭证、短串遮罩、脱敏 description）与 `ProviderProfileStore`（JSON 持久化、自动 Active 切换、删除回退、非法输入拦截）完整单测。 |
| `Packages/MiniMateKit/Tests/MMAudioTests/WAVCodecTests.swift` | 新增 | `WAVCodec` 往返、扩展子块跳过、48k→16k 重采样加载、`PCMByteAligner` 奇数字节拼接与畸形 WAV 异常单测。 |
| `Packages/MiniMateKit/Tests/MMConversationTests/FoundationalTests.swift` | 修改 | 仅迁移第 167–220 行 `TTSEmotionMapping` 测试至厂商无关 `driverID: "mock-tts"` / `voice: "demo-voice"`（残留清理 #3），其余测试保持零改动。 |
| `Packages/MiniMateKit/Tests/MMConversationTests/Fixtures/mock-realtime-sample.jsonl` | 新增 | 厂商无关的脱敏 JSONL 规范夹具（用于离线回放与脱敏验证，零鉴权头、零个人声音）。 |
| `Packages/MiniMateKit/Tests/MMConversationTests/ProviderInfrastructureTests.swift` | 新增 | 覆盖 `ProviderRegistry`、`FakeRealtimeTextSession`、`BuiltInMockDrivers`、`SecretRedactor`、`FixtureRecordingTransport`（RS-1 脱敏 + 上行音频过滤 + JSONL 回放）、`GzipCodec`（往返 + 炸弹上限）与 `MMProbeCore`（参数解析 + 全 5 子命令离线端到端 + SC-002/p50 报告断言）。 |

#### 4.2 明确不做清单（Non-Goals）
- **严禁实现任何具体云端厂商适配器**：本单不写任何外部具体厂商协议代码、具体厂商 Endpoint、具体厂商鉴权头或具体厂商测试夹具（全部留待 Phase 3b 按 §8.2 扩展点独立探索接入）。
- **严禁修改历史只读文档**：不动 `docs/handoffs/`（历史执行单）、`docs/tech-selection.md`、`specs/003-m2-voice-conversation/*`（含 `research.md`、`contracts/`、`tasks.md`）。
- **严禁修改无关业务模块**：不动 `MMCore`、`MMDiagnostics`、`MMPerception`、`MMEmotion`、`MMAvatar`、`MMAudio/{AudioChunk,PCMConverter,GateState}.swift`、`MMConversation/{Persona,TagParser,SentenceSplitter}.swift`、`MMConversation/Realtime/RealtimeTextSession.swift`、`MMConversation/TTS/{TTSProvider,FakeTTSProvider}.swift`、`App/MiniMate/Screens/{AvatarScreen,HomeView,DiagnosticsView}.swift`。
- **严禁新增**：`Resources/tts-emotion-*.json`、`Assets/voice-samples/*.wav`、任何第三方依赖、任何依赖外网的单元测试。

---

### 5. 精确接口与行为契约

#### 5.1 `MMSecurity` 多供应商配置与凭证存储

1. **`ProviderRole`**（`Sources/MMSecurity/ProviderRole.swift`）
   - 签名：`public enum ProviderRole: String, CaseIterable, Codable, Sendable, Identifiable`
   - Case：
     - `case realtimeBrain = "realtime_brain"`：`displayTitle == "实时语音理解（对话大脑）"`，`purposeDescription == "听懂你说的话和语气，决定小瓜要怎么回应（只输出文字与情绪/动作标签）。"`
     - `case emotionalTTS = "emotional_tts"`：`displayTitle == "情感语音合成（小瓜声音）"`，`purposeDescription == "把小瓜的话用固定音色和对应情绪念出来。"`

2. **`ProviderProfile`**（`Sources/MMSecurity/ProviderProfile.swift`）
   - 字段：`id: UUID`、`role: ProviderRole`、`name: String`、`driverID: String`、`customEndpoint: String?`、`modelName: String?`、`voiceID: String?`、`createdAt: Date`、`updatedAt: Date`。
   - 校验与规范化方法 `public func validatedAndNormalized() throws -> ProviderProfile`：
     - `name` 去前后空白后为空 → 抛 `ProviderProfileError.emptyName`；
     - `driverID` 去前后空白后为空 → 抛 `ProviderProfileError.emptyDriverID`；
     - `customEndpoint`、`modelName`、`voiceID` 去空白后为空则归 `nil`；若 `customEndpoint` 非 `nil`，须解析为合法 `URL` 且 `scheme?.lowercased()` 属于 `["https", "wss", "http", "ws"]` 且 `host?.isEmpty == false`，否则抛 `ProviderProfileError.invalidEndpoint(raw)`。

3. **`ProviderProfileStore`**（`Sources/MMSecurity/ProviderProfileStore.swift`）
   - 协议方法：
     - `func profiles(for role: ProviderRole) -> [ProviderProfile]`（按 `createdAt` 升序、同时间戳按 `id.uuidString` 稳定排序）
     - `func profile(id: UUID) -> ProviderProfile?`
     - `func activeProfileID(for role: ProviderRole) -> UUID?`
     - `func activeProfile(for role: ProviderRole) -> ProviderProfile?`
     - `func save(_ profile: ProviderProfile) throws`
     - `func delete(id: UUID) throws`
     - `func setActive(id: UUID?, for role: ProviderRole) throws`
   - 行为边界：
     - `save(_:)` 先调用 `validatedAndNormalized()`；若已存在同 `id` 且 `role` 发生变化，抛 `ProviderProfileError.roleMismatch(expected: existing.role, actual: profile.role)`（禁止把配置跨类篡改）；若该 `role` 当前 `activeProfileID == nil`，自动将本次保存的 `id` 设为 active；
     - `delete(id:)` 对不存在的 `id` 幂等无操作；若删除的正是当前 active，则自动切换为该 `role` 剩余列表中第一条（无剩余则置 `nil`）；
     - `setActive(id:for:)`：传 `nil` 清空该 `role` 激活项；传非 `nil` 时若 `id` 不存在抛 `.profileNotFound(id)`，若 `role` 不一致抛 `.roleMismatch`；
     - `JSONFileProviderProfileStore`：默认路径 `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MiniMate/provider-profiles.json")`；内部用 `OSAllocatedUnfairLock` 保护内存快照 + 写入父目录自动创建 + `Data.write(to: url, options: .atomic)`；磁盘 JSON 带 `schemaVersion: Int = 1`；文件不存在时初始化为空状态（不抛错）；文件损坏无法解码时抛/记录明确错误且不静默覆盖原文件。

4. **`CredentialStore` / `ProviderCredentials` / `CredentialStatus`**（`Sources/MMSecurity/CredentialStore.swift`）
   - `ProviderCredentials`：
     - `public let primarySecret: String`
     - `public let secondarySecret: String?`
     - `description` 与 `debugDescription` 固定返回 `"ProviderCredentials(primary: [REDACTED], secondary: \(secondarySecret == nil ? "nil" : "[REDACTED]"))"`，**严禁泄露任何明文字符**。
   - `CredentialStatus`：
     - 字段：`profileID: UUID`、`isPrimaryConfigured: Bool`、`primarySuffix: String?`、`isSecondaryConfigured: Bool`、`secondarySuffix: String?`、`isConfigured: Bool`（同 `isPrimaryConfigured`）。
     - 遮罩规则：`static func maskedSuffix(for secret: String) -> String`——`secret.count <= 4 ? "****" : String(secret.suffix(4))`。
     - `description` / `debugDescription`：未配置返回 `"未配置"`；仅主凭证返回 `"已配置（末 4 位 \(suffix)）"`；主+副均配置返回 `"已配置（主末 4 位 \(p) · 附加末 4 位 \(s)）"`。
   - `KeychainCredentialStore`：
     - `service = "ai.minimate.credentials.v2"`、`kSecAttrAccount = profileID.uuidString`、`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`；
     - 载荷为 JSON 编码的私有 `StoredSecretPayload(primary: String, secondary: String?)`，单条 Keychain 记录原子存取；
     - `save` 时 `primarySecret` 去空白为空抛 `CredentialStoreError.emptyPrimarySecret`；`secondarySecret` 去空白为空归一化为 `nil`；
     - `delete` 遇到 `errSecItemNotFound` 视作幂等成功。

#### 5.2 `MMAudio/WAVCodec.swift`
- 签名：
  ```swift
  public enum WAVCodecError: Error, Sendable, Equatable {
      case invalidHeader(String)
      case unsupportedFormat(String)
      case ioError(String)
  }

  /// 跨帧流式 PCM16 字节对齐器（防止奇数长度网络帧丢弃或错位半个采样）。
  public struct PCMByteAligner: Sendable {
      public init()
      /// 喂入任意长度小端 PCM16 字节，返回对齐为偶数长度的可解码字节，残留的 1 字节留待下一块拼接。
      public mutating func append(_ data: Data) -> Data
      public var hasPendingByte: Bool { get }
      public mutating func reset()
  }

  public enum WAVCodec {
      public static func encodeWAV(_ chunk: AudioChunk) throws -> Data
      public static func writeWAV(chunks: [AudioChunk], sampleRate: Int, to url: URL) throws
      public static func decodePCM16MonoWAV(_ data: Data) throws -> AudioChunk
      /// 通过 AVAudioFile 读取磁盘音频并经 PCMConverter 重采样为 targetSampleRate Hz Int16 mono。
      public static func loadAudioFile(at url: URL, targetSampleRate: Int) throws -> AudioChunk
  }
  ```
- 复用约束：`loadAudioFile` **必须复用 `PCMConverter`**（`Packages/MiniMateKit/Sources/MMAudio/PCMConverter.swift:101,132`）完成格式/声道/采样率转换与 `flush()` 排空，严禁自写重采样循环。

#### 5.3 `MMConversation` 泛化映射、通用传输层与驱动注册表

1. **`TTSEmotionMapping` 泛化**（`MMConversation/TTS/EmotionMapping.swift`）
   - 签名变更：
     - `VendorEmotionParams` 重命名为 `EmotionParameterSet`（`public struct EmotionParameterSet: Sendable, Equatable, Codable`，保留原有 `parameters`、`empty`、`isEmpty`、`string(_:)`、`number(_:)`、`bool(_:)`）；
     - `TTSEmotionMappingError`：`case resourceNotFound(String)`、`case emptyDriverID`、`case emptyVoice`、`case unknownEmotionKey(String)`、`case missingNeutralMapping`；
     - `TTSEmotionMapping`：`public let driverID: String`、`public let voice: String`、`public let map: [EmotionTag: EmotionParameterSet]`；
     - `load(from data: Data)` 强校验 `driverID` 非空白、`voice` 非空白、`map[.neutral] != nil`、键全属 `EmotionTag`；
     - `load(fromFile url: URL)` 读取磁盘文件并调用 `load(from:)`；
     - `loadBundled(for driverID: String)` 从 `Bundle.module` 根目录查找 `tts-emotion-\(driverID).json`，缺失抛 `.resourceNotFound(driverID)`。

2. **通用传输层与脱敏夹具**（`MMConversation/Transport/`）
   - `SecretRedactor`：
     - `public static func redact(_ text: String, secrets: [String] = []) -> String`
     - `public static func sanitizedErrorMessage(_ error: any Error, secrets: [String] = []) -> String`
     - 脱敏规则：替换所有长度 ≥ 4 的注册 `secrets` 为 `"[REDACTED]"`；正则擦除 `Bearer\s+[A-Za-z0-9._\-]+`、`sk-[A-Za-z0-9_\-]{8,}` 以及大小写不敏感的 `"(authorization|x-api-key|x-api-access-key|x-api-app-id|x-api-app-key|api_key|access_key|secret|token)"\s*:\s*"[^"]*"`。
   - `WebSocketTransport` / `WebSocketConnection` / `URLSessionWebSocketTransport`：
     - `URLSessionWebSocketTransport` 使用共享 `URLSession` + `OSAllocatedUnfairLock` 委托表等待 `didOpenWithProtocol` 完成握手；非 101 HTTP 状态码抛 `WebSocketTransportError.httpRejected(statusCode:message:)`（消息经 `SecretRedactor` 脱敏，严禁带头值）。
   - `HTTPStreamingTransport` / `URLSessionHTTPStreamingTransport`：
     - 使用 `URLSession.bytes(for:)` 逐字节按 `0x0A` (`\n`) 实时切行产出（去除 `\r`，EOF 刷出尾行），`onTermination` 立即取消读取 Task。
   - `FixtureRecordingTransport`（`RecordingWebSocketTransport`）：
     - `FixtureFrameRecord`：`seq: Int`、`direction: Direction (.in/.out)`、`kind: Kind (.text/.binary)`、`timestampMs: Int`、`text: String?`、`base64: String?`。
     - **严禁记录任何 HTTP 握手头**；自动将全部握手头 value（长度 ≥ 4）加入 `SecretRedactor` 脱敏清单；支持 `outboundFilter: (@Sendable (WebSocketMessage) -> Bool)?` 跳过上行原始音频帧，严防个人语音落盘夹具；提供 `encodeJSONLines() throws -> Data` 与 `decodeJSONLines(_:) throws -> [FixtureFrameRecord]`。
   - `GzipCodec`：
     - `compress(_ data: Data) throws -> Data`（`deflateInit2_(..., 15 + 16, ...)`）
     - `decompress(_ data: Data, maxOutputBytes: Int = 16 * 1024 * 1024) throws -> Data`（`inflateInit2_(..., 15 + 32, ...)`；解压输出超过 `maxOutputBytes` 立即终止并抛 `GzipError.sizeLimitExceeded(maxOutputBytes)`）。

3. **驱动注册表与内置离线模拟驱动**（`MMConversation/Registry/` & `MMConversation/Realtime/FakeRealtimeTextSession.swift`）
   - `ProviderDriverDescriptor`、`DriverBuildContext`、`RealtimeSessionDriver`、`TTSProviderDriver`、`ProviderRegistry`（`OSAllocatedUnfairLock` 线程安全，`register` 拒绝重复 ID 或 `role` 不匹配）。
   - `RealtimeSessionAuditable`：`public protocol RealtimeSessionAuditable: Sendable { var unexpectedAudioEventCount: Int { get } }`（供 Phase 3b 真实驱动报告 V4 意外音频计数）。
   - `FakeRealtimeTextSession`（遵循 `RealtimeTextSession` & `RealtimeSessionAuditable`）：
     - 满足 RS-4（未连接或已关闭调用 `send` 抛 `RealtimeError.notConnected`）、A-1–A-6（支持服务端 VAD 模拟、取消、清空缓冲、流式文字增量、用户转写事件）；
     - 支持“经 `WebSocketTransport` 协议模式”（默认走 `LoopbackMockWebSocketTransport` 协议 JSON 帧：`{"type":"session.configure",...}` / `{"type":"audio.chunk",...}` / `{"type":"response.cancel"}` / `{"type":"input.clear"}`；下行 `session.ready` / `speech.started` / `user.transcript` / `speech.ended` / `text.delta` / `response.done`）与“静态脚本模式”；
     - `MockRealtimeDriver`（`id = "mock-realtime"`，`displayName = "本地模拟（离线演示）"`，`requiresPrimarySecret = false`，`isBuiltInMock = true`）使用该会话；当 `send` 累计人声后再收到连续静音（或达到预设阈值）即自动输出确定性带标签回答（如 `<user:calm><emo:playful>收到啦，<act:nod>我在认真听你说话呢～`），并按 `audio.chunk` 元数据/能量特征支持 `tone-suite` 离线演示验证；
     - `MockTTSDriver`（`id = "mock-tts"`，`displayName = "本地模拟音色（离线演示）"`，`requiresPrimarySecret = false`，`isBuiltInMock = true`）包装既有 `FakeTTSProvider(outputFormat: .pcm24kMono, includeWordMarks: true)`，验证全部 8 种 `EmotionTag` 与字级 `AudioTimeMark` 透传。
   - **回放解码器（RS-5）**：在 `FakeRealtimeTextSession.swift` 提供 `MockRealtimeProtocol.replayFixture(_ records: [FixtureFrameRecord]) -> (outputs: [RealtimeOutput], unexpectedAudioCount: Int, ignoredTypes: [String])`，验证从 `Bundle.module` 夹具 `Fixtures/mock-realtime-sample.jsonl` 到 `[RealtimeOutput]` 再到 `TagParser` 的完整回放链路。

#### 5.4 插件化 `mm-probe` CLI（`MMProbeCore` + `MMProbeCLI`）
- **全部子命令（零硬编码厂商名）**：
  1. `mm-probe --help` / `-h`（退出码 `0`）
  2. `mm-probe list-drivers [--role <realtime|tts>]`（退出码 `0`）：打印注册表中全部驱动的 Markdown 表格。
  3. `mm-probe realtime --driver <driverID> --input <path.wav> [--endpoint <url>] [--model <id>] [--key-env <VAR>] [--secondary-env <VAR>] [--chunk-ms <100>] [--silence-ms <1200>] [--pace <1.0>] [--timeout-s <30>]`
     - 默认凭证环境变量：`MM_REALTIME_KEY` + 可选 `MM_REALTIME_SECONDARY_SECRET`；若驱动 `requiresPrimarySecret == true` 且环境变量缺失，向 `stderr` 打印缺失变量名（严禁打印值）并退出码 `2`；
     - 通过 `WAVCodec.loadAudioFile(at:targetSampleRate: 16_000)` 读取重采样，切 `--chunk-ms` 块并追加 `--silence-ms` 全零 PCM16 尾部静音，推流并通过 `TagParser` 解析输出，打印原始文本、剥离文本、`<user>`/`<emo>`/`<act>`/`<cmd>`、用户转写（V7）、`speech_end → first_text` 耗时（ms）、V4 意外音频审计结果（`PASS`/`FAIL`）。
  4. `mm-probe tone-suite --driver <driverID> [--samples-dir <dir>] [--endpoint <url>] [--model <id>] [--key-env <VAR>] [--secondary-env <VAR>] [--chunk-ms <100>] [--silence-ms <1200>] [--pace <1.0>] [--timeout-s <30>] [--allow-partial]`
     - 默认自动探测 `../../Assets/voice-samples` 或 `Assets/voice-samples`；
     - 固定 3 组 × 3 语气共 9 个文件名（对齐 `specs/003-m2-voice-conversation/research.md:60-65`：`fine-{happy,flat,sad}.wav`、`ok-{happy,flat,sad}.wav`、`done-{happy,tired,angry}.wav`）；
     - 缺文件时默认退出码 `2` 并列出缺失路径（`--allow-partial` 跳过缺失继续运行）；
     - 输出 Markdown 对比表 + 汇总（V4 意外音频总数、V5/SC-002 语气组可区分数 `/3`、首个文字耗时 p50 ms、V7 转写命中数 `/N`）。
  5. `mm-probe tts --driver <driverID> --text <string> (--all-emotions | --emotion <EmotionTag>) --out <dir> [--voice <id>] [--endpoint <url>] [--model <id>] [--mapping <json-path>] [--key-env <VAR>] [--secondary-env <VAR>]`
     - 默认凭证环境变量：`MM_TTS_KEY` + 可选 `MM_TTS_SECONDARY_SECRET`；
     - 逐情绪合成并写 `<out>/<emotion.rawValue>.wav`（`WAVCodec.writeWAV`），打印每个情绪的 TTFB ms、时长 s、块数、时间戳数及 TTFB p50 ms（V6）。
  6. `mm-probe record-fixture --driver <driverID> --input <path.wav> --out <path.jsonl> [--endpoint <url>] [--model <id>] [--key-env <VAR>] [--secondary-env <VAR>] [--chunk-ms <100>] [--silence-ms <1200>] [--pace <1.0>] [--timeout-s <30>]`
     - 将 `RecordingWebSocketTransport`（自动剥离所有 HTTP 头 + 脱敏 + `outboundFilter` 过滤上行原始音频帧）注入 `ProviderRegistry.makeRealtimeSession(...)`，跑完 1 轮后将脱敏 JSONL 写至 `--out`（自动创建父目录）。
- **退出码契约**：`0` 成功；`2` 参数错误 / 未知驱动 / 缺必填环境变量 / 输入文件缺失；`1` 运行期会话/合成错误（经 `SecretRedactor` 脱敏输出 `stderr`）。

#### 5.5 iOS App 设置页（`SettingsView.swift` & `ProviderProfileEditorSheet.swift`）
- **页面结构（两类用途，清晰引导）**：
  - Section 1：**「实时语音理解（对话大脑）」** + Footer 显示 `ProviderRole.realtimeBrain.purposeDescription` + 已配置列表（支持点击行切换 Active、编辑按钮、滑动删除）+ `"添加对话大脑配置"` 按钮；
  - Section 2：**「情感语音合成（小瓜声音）」** + Footer 显示 `ProviderRole.emotionalTTS.purposeDescription` + 已配置列表 + `"添加声音合成配置"` 按钮；
  - Section 3：**「诊断」** + `NavigationLink("能力探测") { DiagnosticsView() }`。
- **编辑弹窗字段（最小完备集合）**：
  1. `自定义名称`（必填 `TextField`）
  2. `协议驱动`（`Picker`，动态绑定 `composition.providerRegistry.descriptors(for: role)`，严禁写死枚举；下方展示驱动 `summary`）
  3. `主凭证 / API Key`（`SecureField`，仅写 Keychain；编辑已有配置时永不回显旧明文，placeholder 展示当前脱敏末 4 位状态，留空保持不变，附 `"清除凭证"` 按钮；若驱动 `requiresPrimarySecret == false` 注明可选）
  4. `附加凭证（可选）`（`SecureField`，如 AppID / Secret，仅写 Keychain，永不回显明文）
  5. `高级自定义（可选，留空走驱动默认）`：`自定义 Endpoint`、`模型 / 资源名`、`音色 ID`（`.emotionalTTS` 优先展示）。
- **原子保存与错误处理**：
  - 新建配置时若 `profileStore.save` 成功但 `credentialStore.save` 失败，立即调用 `profileStore.delete(id: profile.id)` 回滚，向用户展示经 `SecretRedactor` 脱敏的错误提示；
  - 删除配置时先 `credentialStore.delete(for: profile.id)` 再 `profileStore.delete(id: profile.id)`，防止 Keychain 残留孤立凭证；
  - 弹窗关闭时立即清空内存中的明文草稿状态。

---

### 6. 原子化施工步骤（自底向上）

- **Step 1：同步 `AGENTS.md` 隐私红线与更新工程配置**
  - 改动文件：`AGENTS.md`、`Packages/MiniMateKit/Package.swift`、`App/MiniMate.xcodeproj/project.pbxproj`
  - 改动要点：在 `AGENTS.md` 新增开发/Debug 隐私红线并更新 `mm-probe` 示例命令为 `--driver`；更新 `Package.swift`（`MMConversation` 加 `linkerSettings: [.linkedLibrary("z")]`，新增 `MMProbeCore` 目标，调整 `MMProbeCLI` 依赖；`MMConversationTests` 的 `resources: [.copy("Fixtures")]` 留至 Step 5 放夹具时一并启用，避免空目录告警）；在 `project.pbxproj` 中为 `MiniMate` target 链接 `MMAudio` 与 `MMConversation`。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && swift package dump-package >/dev/null
    ```

- **Step 2：重构 `MMSecurity`（删除 `VendorID` + 新增 `ProviderRole` / `ProviderProfile` / `ProviderProfileStore` + 升级 `CredentialStore`）并重写 `MMSecurityTests`**
  - 改动文件：删除 `MMSecurity/VendorID.swift`；新增 `ProviderRole.swift`、`ProviderProfile.swift`、`ProviderProfileStore.swift`；修改 `CredentialStore.swift`；重写 `MMSecurityTests/CredentialStoreTests.swift`
  - 改动要点：按宪章 V 先更新测试覆盖 §7.1 全部安全与持久化用例，再落地实现（此时 `MMConversation` 中 `EmotionMapping.swift` 将在 Step 4 同步适配，本步先单独测试 `MMSecurityTests`）。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && swift test --filter MMSecurityTests
    ```

- **Step 3：实现 `MMAudio/WAVCodec.swift` 与 `MMAudioTests/WAVCodecTests.swift`（先写测试）**
  - 改动文件：`Tests/MMAudioTests/WAVCodecTests.swift`、`Sources/MMAudio/WAVCodec.swift`
  - 改动要点：先写单测再实现 WAV 编解码、多块写盘、`AVAudioFile` + `PCMConverter` 重采样加载与 `PCMByteAligner`。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && swift test --filter WAVCodecTests
    ```

- **Step 4：泛化 `TTSEmotionMapping`、实现 `MMConversation/Transport/`、`FakeRealtimeTextSession` 与 `ProviderRegistry`**
  - 改动文件：`Sources/MMConversation/TTS/EmotionMapping.swift`、`Transport/{SecretRedactor,WebSocketTransport,HTTPStreamingTransport,FixtureRecordingTransport,GzipCodec}.swift`、`Realtime/FakeRealtimeTextSession.swift`、`Registry/{ProviderDriverDescriptor,ProviderRegistry,BuiltInMockDrivers}.swift`、`Tests/MMConversationTests/FoundationalTests.swift`（仅迁移第 167–220 行）
  - 改动要点：彻底去除 `VendorID` 与任何具体厂商字面量，完整实现通用传输/脱敏/GZIP/录制层、注册表与内置离线 `mock-realtime` / `mock-tts` 驱动。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && swift test --filter "FoundationalTests|TagParserTests|SentenceSplitterTests"
    ```

- **Step 5：实现插件化 `MMProbeCore` + `MMProbeCLI`、补齐脱敏合成夹具与 `ProviderInfrastructureTests`**
  - 改动文件：`Package.swift`（`MMConversationTests` 增 `resources: [.copy("Fixtures")]`）、`Sources/MMProbeCore/{ProbeArguments,ProbeReport,ProbeRunner}.swift`、`Sources/MMProbeCLI/main.swift`、`Tests/MMConversationTests/Fixtures/mock-realtime-sample.jsonl`、`Tests/MMConversationTests/ProviderInfrastructureTests.swift`
  - 改动要点：实现全部 CLI 子命令（零硬编码厂商名）与 §7.1 全量离线测试矩阵，并用内置 `mock-realtime` / `mock-tts` 跑通全部 CLI 冒烟验证。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && swift test
    ```

- **Step 6：重构 App 组合根与设置页（`AppComposition`、`SettingsView`、`ProviderProfileEditorSheet`）并执行全量门禁与零厂商残留扫描**
  - 改动文件：`App/MiniMate/AppComposition.swift`、`App/MiniMate/Screens/SettingsView.swift`、`App/MiniMate/Screens/ProviderProfileEditorSheet.swift`
  - 改动要点：完成两类用途分区、动态 1..N 管理、Active 切换、动态驱动 Picker 与 Keychain 安全编辑保存/回滚；执行 §7.2 全部 6 项门禁命令（含 iOS 编译、App 模拟器构建、CLI 端到端冒烟与自动化零厂商残留扫描）。
  - 最小验证命令：见 §7.2 完整门禁命令清单。

---

### 7. 确定性测试矩阵与验收门禁

#### 7.1 测试矩阵（严禁非确定性断言）
| 目标测试文件 | 覆盖类别 | 测试场景 | 必须写死的断言底线（禁止弱断言） |
| :--- | :--- | :--- | :--- |
| `MMSecurityTests/CredentialStoreTests.swift` | 正例 | `InMemoryCredentialStore` 按 `UUID` 存取主+副凭证、覆盖更新、删除与不同 `profileID` 隔离 | `load` 返回精确 `ProviderCredentials`；`status.isPrimaryConfigured == true`、`primarySuffix == "1234"`、`isSecondaryConfigured == true`、`secondarySuffix == "5678"`；删除后 `load == nil` 且 `status.isConfigured == false` |
| `MMSecurityTests/CredentialStoreTests.swift` | 安全反例 | `ProviderCredentials` 与 `CredentialStatus` 的 `description`/`debugDescription` 脱敏 + 短凭证（≤ 4 字符）遮罩 | 均**严禁包含**完整主/副凭证；长度为 3 或 4 的凭证 `suffix == "****"`；空白主凭证抛 `CredentialStoreError.emptyPrimarySecret` |
| `MMSecurityTests/CredentialStoreTests.swift` | 正例 / 边界 | `JSONFileProviderProfileStore` 写入临时目录并重新实例化读取；首个配置自动 Active；多配置切换 Active；删除当前 Active 自动回退首条；两类 `ProviderRole` 严格隔离 | 重建实例后 `profiles(for:)` 与 `activeProfileID(for:)` 完全一致；磁盘 JSON 文件中**不含任何密钥字段**；删除唯一配置后 `activeProfileID == nil` |
| `MMSecurityTests/CredentialStoreTests.swift` | 异常反例 | 空白 `name`/`driverID`、非法 URL Scheme（如 `ftp://` 或无 host）、跨 `role` 覆写同 `id`、`setActive` 指向不存在 `id` 或错类 `role` | 分别精确抛出 `ProviderProfileError.emptyName` / `.emptyDriverID` / `.invalidEndpoint` / `.roleMismatch` / `.profileNotFound` |
| `MMAudioTests/WAVCodecTests.swift` | 正例 / 边界 / 异常 | `encodeWAV`↔`decodePCM16MonoWAV` 往返；含 `JUNK`/`LIST` 子块 WAV 解析；48 kHz 写盘后 `loadAudioFile(targetSampleRate: 16_000)`；`PCMByteAligner` 3B+5B→4 完整样本；截断头/双声道/缺失文件 | 样本逐元素相等；重采样后 `sampleRate == 16_000` 且样本数在 16,000 ±2% 内；`PCMByteAligner` 不丢字节；非法输入精确抛 `WAVCodecError.invalidHeader` / `.unsupportedFormat` / `.ioError` |
| `MMConversationTests/FoundationalTests.swift` | 兼容回归 | 既有 180 条基础测试（含迁移后的 `TTSEmotionMapping` 往返、缺失情绪回退 `.neutral`、空 `driverID`/空 `voice`/未知键/缺 `neutral`/缺内置资源抛错） | 全量通过；`TTSEmotionMapping.loadBundled(for: "mock-tts")` 抛 `.resourceNotFound("mock-tts")` |
| `MMConversationTests/ProviderInfrastructureTests.swift` | 正例 | `ProviderRegistry.makeDefault()` 注册表查询、自定义驱动注册、按 `ProviderProfile` 构造会话与 TTS；重复注册/未知 ID/错 role/缺必填主凭证 | `descriptors(for: .realtimeBrain)` 含 `"mock-realtime"`、`descriptors(for: .emotionalTTS)` 含 `"mock-tts"`；重复 ID 抛 `.duplicateDriverID`，缺主凭证抛 `.missingPrimarySecret`，未注册 ID 抛 `.driverNotFound` |
| `MMConversationTests/ProviderInfrastructureTests.swift` | 正例 / 异常（RS-4） | `FakeRealtimeTextSession` 经 `LoopbackMockWebSocketTransport` 完整握手→推流→VAD→转写→标签文字→结束→`cancelResponse`→`clearInputBuffer`→`close`；未连接与关闭后 `send` | `output` 按序产出 `.speechStarted`、`.userTranscript`、`.speechEnded`、`.textDelta`、`.responseDone`，经 `TagParser` 解出 `<user>`/`<emo>`/`<act>`；未连接/关闭后 `send` 精确抛 `RealtimeError.notConnected` |
| `MMConversationTests/ProviderInfrastructureTests.swift` | 安全 / 回放（RS-1 / RS-5） | `RecordingWebSocketTransport` 录制带敏感 Header、敏感文本与上行音频帧的会话；`SecretRedactor` 脱敏；从 `Bundle.module` 加载 `Fixtures/mock-realtime-sample.jsonl` 回放 | 导出 JSONL **完全不含**任何握手头值、`Bearer` 明文、`sk-` 明文或被过滤的上行音频帧；回放 `mock-realtime-sample.jsonl` 产出精确 `[RealtimeOutput]`、未知事件计数与 V4 意外音频计数 |
| `MMConversationTests/ProviderInfrastructureTests.swift` | 正例 / 异常 | `GzipCodec` 压缩解压往返（空数据、中文 JSON、16 KB 负载）与 `maxOutputBytes` 上限拦截 | 往返字节 100% 相等；超上限精确抛 `GzipError.sizeLimitExceeded`；损坏输入抛 `GzipError.zlibFailed` / `.invalidData` |
| `MMConversationTests/ProviderInfrastructureTests.swift` | 正例 / 边界 / 异常 | `MMProbeCore`：`ProbeArguments` 解析 5 子命令与非法参数报错；`ProbeRunner` 用内置 `mock-realtime` / `mock-tts` 在临时目录离线跑通 `list-drivers`、`realtime`、`tone-suite`（9 条临时合成 WAV）、`tts --all-emotions`（生成 8 个可解码 WAV）、`record-fixture`（生成可回放脱敏 JSONL） | 退出码精确为 `0`（成功）/ `2`（参数或缺失文件错误）；`tone-suite` Markdown 含 p50 与 V4/V5/V7 汇总；`tts` 目录下 8 个 `.wav` 均可被 `WAVCodec.decodePCM16MonoWAV` 解码且样本非空；`record-fixture` 产出 JSONL 不含测试密钥且可被 `RecordingWebSocketTransport.decodeJSONLines` 解析 |

#### 7.2 完整门禁命令清单
```bash
# 1. Swift Package 全量单测（沙盒内可加 CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache 与 --disable-sandbox）
cd Packages/MiniMateKit && swift test

# 2. mm-probe CLI 构建与离线全子命令冒烟（零网络、零外部 Key）
cd Packages/MiniMateKit && swift build --product mm-probe \
  && swift run mm-probe --help \
  && swift run mm-probe list-drivers \
  && swift run mm-probe tts --driver mock-tts --text "你好呀" --all-emotions --out /tmp/minimate-probe-smoke-tts \
  && ls /tmp/minimate-probe-smoke-tts/happy.wav /tmp/minimate-probe-smoke-tts/neutral.wav \
  && swift run mm-probe realtime --driver mock-realtime --input /tmp/minimate-probe-smoke-tts/happy.wav --pace 0 \
  && swift run mm-probe record-fixture --driver mock-realtime --input /tmp/minimate-probe-smoke-tts/happy.wav --pace 0 --out /tmp/minimate-probe-smoke.jsonl \
  && (! swift run mm-probe realtime --driver nonexistent --input /tmp/minimate-probe-smoke-tts/happy.wav 2>/dev/null) \
  && rm -rf /tmp/minimate-probe-smoke-tts /tmp/minimate-probe-smoke.jsonl

# 3. iOS 目标平台条件编译验证（覆盖 MMSecurity / MMAudio / MMConversation 含 zlib 链接）
cd Packages/MiniMateKit \
  && xcodebuild -scheme MMSecurity -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO \
  && xcodebuild -scheme MMAudio -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO \
  && xcodebuild -scheme MMConversation -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

# 4. iOS App 模拟器无签名构建验证（覆盖 SettingsView / ProviderProfileEditorSheet / AppComposition）
xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# 5. 代码库零厂商残留自动化门禁（App/ 与 Packages/MiniMateKit/ 必须严格返回 0 命中！）
! git grep -inE "aliyun|阿里云|百炼|dashscope|qwen|通义|cosyvoice|longxiaoxia|longanyang|volcengine|火山引擎|doubao|豆包|bytedance|字节跳动|openspeech|seed-tts|openai|gpt-4o|whisper|anthropic|claude|gemini|deepseek|minimax|zhipu|智谱|baidu|百度|tencent|腾讯|iflytek|讯飞|bigtts|VendorID" App/ Packages/MiniMateKit/

# 6. 密钥安全与仓库状态核查（确认零密钥硬编码、零 .wav 个人样本、历史只读文档未改动）
! git grep -nE "sk-[A-Za-z0-9_-]{12,}|Bearer [A-Za-z0-9._-]{12,}" App/ Packages/
git status -s
```

---

### 8. 项目附加产出要求与 Phase 3b 扩展接入点规范

#### 8.1 验收收口时需同步的文档（待用户明确确认验收后落盘）
- `docs/CODEBASE_MAP.md`：
  - §1 模块表：更新 `MMSecurity`（`ProviderRole`、`ProviderProfile`、`ProviderProfileStore`、`CredentialStore` v2）、`MMAudio`（增 `WAVCodec` / `PCMByteAligner`）、`MMConversation`（增 `Transport/`、`Registry/`、`FakeRealtimeTextSession`、泛化 `TTSEmotionMapping`）、`MMProbeCore`、`MMProbeCLI` 及 `App/MiniMate/Screens/`（增 `ProviderProfileEditorSheet`，更新 `SettingsView` / `AppComposition`）；
  - §3 公共复用设施：增补 `ProviderRegistry`、`ProviderProfileStore`、`WAVCodec`/`PCMByteAligner`、`SecretRedactor`、`WebSocketTransport`/`HTTPStreamingTransport`/`RecordingWebSocketTransport`、`GzipCodec`；
  - §4 依赖方向：更新 `App/MiniMate`（追加 `MMAudio`、`MMConversation`）、新增 `MMProbeCore → MMCore, MMAudio, MMConversation, MMSecurity`、`MMProbeCLI → MMProbeCore`。
- `docs/HANDOFF_LEDGER.md`：
  - §2 补充 `import zlib` 需 `linkerSettings: [.linkedLibrary("z")]`、`.copy("Fixtures")` 需 `subdirectory: "Fixtures"`、`PCMByteAligner` 跨帧奇数字节对齐与短凭证遮罩规则；
  - §3 登记 `[003-m2-phase3a]` 厂商无关多供应商配置与插件化探针底座变更及最新单测基线。

#### 8.2 Phase 3a 为 Phase 3b 预留的标准扩展接入点（完全厂商无关）
后续在 Phase 3b 接入任意具体外部协议驱动时，**只需遵循以下 4 条接入规范，无需改动 `MMSecurity`、设置页 UI、`ProviderRegistry` 或 `mm-probe` 核心代码**：
1. **实现驱动协议**：
   - 实时会话类：实现 `RealtimeTextSession`（可选实现 `RealtimeSessionAuditable` 报告 V4 意外音频计数）+ 包装为 `RealtimeSessionDriver`；
   - 情感 TTS 类：实现 `TTSProvider`（遵循 TTS-1–TTS-6，使用 `TTSEmotionMapping` + `PCMByteAligner`）+ 包装为 `TTSProviderDriver`。
2. **复用通用基础设施**：网络层优先注入 `DriverBuildContext.webSocketTransport` / `httpTransport`（确保 `mm-probe record-fixture` 无缝生效且可离线单测），脱敏统一走 `SecretRedactor`，压缩走 `GzipCodec`。
3. **单点注册**：在组合根 / `ProviderRegistry` 注册入口调用 `registry.register(driver)`，设置页下拉框与 `mm-probe list-drivers` / `--driver <id>` 自动可见。
4. **隐私与验证纪律**：
   - 开发或 debug 期间严禁擅自读取用户配置的其他模型厂商任何信息（含名称），确需读取必须先向用户说明原因并获得明确同意；
   - 新驱动必须附带经 `record-fixture` 脱敏录制的回放解码单测（RS-5）与 V4–V7 / SC-002 评测记录。

---

### 9. 实施方偏差止损规则（固定条款）
- **可自决微调**：内部私有变量名、局部辅助函数拆分、SwiftUI 子视图微调与注释格式（不改变对外契约、安全红线、零厂商残留门禁与测试预期）。
- **必须立即停工上报（严禁擅自绕过）**：
  1. 发现既定签名/契约与仓库现状冲突（如 `RealtimeTextSession`、`TTSProvider` 或 `AppComposition` 既有调用方受影响）；
  2. 需要修改 §4.1 文件改动表之外的文件（尤其历史 `docs/handoffs/`、`specs/` 或无关业务模块）；
  3. 自动化零厂商残留门禁（§7.2 第 5 条）出现无法按表清零的命中；
  4. 需要放宽隐私红线、脱敏红线、零第三方依赖红线或改写既有 178 条未迁移测试的预期断言；
  5. 实测发现 Swift 6 并发、`zlib` iOS 链接或 Xcode `project.pbxproj` 解析阻断问题。

---

## 复审闭环记录（实施后由 task-review-loop 追加）

- **审查通道**：单节点独立只读 `reviewer`（`Gemini 4 Neon (High)` / `gemini-4-neon-high`，思考等级 `High`，已回收）
- **闭环轮次与结果**：共 **2 轮**，**一致通过（阻断项：0；非阻断建议：2）**，两轮复审后只读整树指纹 `T_CUR` 均 100% 匹配零修改。
- **Round 1（需修改：阻断 6 / 非阻断 5）**：
  - `B1` 未跟踪测试文件含 `sk-` 明文字面量会击穿静态密钥门禁 → 改用运行期数组拼接构造，含未跟踪文件 `grep` 0 命中；
  - `B2` `SecretRedactor` 3 条正则与 `RecordingWebSocketTransport` 握手头自动脱敏未独立被测 → 增 `secrets: []` 独立正则测试与 `EchoingMockWebSocketTransport` 握手头回显脱敏测试；
  - `B3` `URLSessionWebSocketTransport` / `URLSessionHTTPStreamingTransport` 的 `deinit` 会提前杀掉存活连接/流，且握手期不响应 Task 取消 → 连接与流强持 transport `owner`，握手包裹 `withTaskCancellationHandler`；
  - `B4` `FakeRealtimeTextSession` 底层异常断连挂死 `output` 且缺 `deinit` → 异常断连 `finish(throwing: RealtimeError.network(...))`，补 `deinit` 清理并加双回归单测；
  - `B5` `ProviderProfileEditorSheet` 仅改附加凭证静默丢弃、仅改主凭证误清附加凭证、编辑失败未回滚元数据 → 补 Keychain 合并保存、空主凭证显式报错、创建与编辑双路径失败回滚；
  - `B6` `ProbeRunner` 未校验 `--endpoint` 且异常路径漏取消 `collector` → 全子命令先经 `validatedAndNormalized()` 校验（非法返回退出码 `2`）并补 `defer { collector.cancel() }`；
  - 顺带修复非阻断建议 `N1–N4`（`SettingsView` `defer { refresh() }`、`JSONFileProviderProfileStore.delete` 无变动跳过写盘 + 损坏 JSON 不覆盖与 `setActive(nil)` 单测、`ProbeArguments` 仅选项键位识别 `-h`、`ProviderProfileEditorSheet` 未注册驱动提示一致性）。
- **Round 2（通过：阻断 0 / 非阻断 2）**：
  - 全部 `B1–B6` 与 `N1–N4` 复核通过；独立隔离目录实测 `swift test` **190/190（31 suites，0 skip）** 与 `mm-probe` 全子命令冒烟通过；
  - 保留 2 项低风险非阻断建议（`WebSocketTransport.connect` 前置 `try Task.checkCancellation()`、`FakeRealtimeTextSession.deinit` 顺带关闭底层 mock 连接），留作后续按需微调。
- **最终验收门禁证据（实测逐字一致）**：
  - `swift test`：**190/190（31 suites）全过**；
  - `mm-probe` 离线全子命令冒烟（`--help` / `list-drivers` / `tts --all-emotions` / `realtime` / `record-fixture` 录制 9 帧脱敏 JSONL / 非法参数与非法 `--endpoint` 退出码 `2`）：**PASS**；
  - iOS 单模块（`MMSecurity` / `MMAudio` / `MMConversation` 含系统 `libz`）与 iOS App 模拟器（`MiniMate`）无签名构建：**PASS**；
  - 全仓代码库（`App/` + `Packages/MiniMateKit/`，含未跟踪文件）零厂商残留扫描：**0 命中（PASS）**；
  - 全仓代码库（含未跟踪文件）密钥静态扫描：**0 命中（PASS）**。
