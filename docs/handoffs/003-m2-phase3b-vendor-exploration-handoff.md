# 003-m2 Phase 3b（US1 M2a 开放式云端驱动探索、接入与实测选型）执行单

- **状态**：已拍板定稿（待实施）
- **Git 基线**：`main` @ `7262f0f`（Phase 3a 厂商无关底座已验收提交）
- **关键基线**：Swift 6.2（严格并发）/ Xcode 26 / iOS 26+ / macOS 26+；`Packages/MiniMateKit` 全量纯逻辑单测基线 **190/190（31 suites）**；零第三方 Swift Package 依赖（`MMConversation` 仅链接 Apple 系统 `libz`）；仓库业务代码零具体厂商残留。
- **拍板决议摘要**：`1A`（实时大脑与情感 TTS 独立评估、允许跨厂混搭，保留所有已跑通可用驱动供设置页手动切换） / `2A`（Stage A 调研 3–4 家国内直连方案，拍板选 2 家进 Stage B 编码实测） / `3A`（若方案 B 门槛 V4/V5 全数未达标则如实记录并停步报回用户拍板是否转方案 C）

> **红线声明（本执行单全程适用，绝对不可突破）**
> 1. **开发 / Debug 隐私红线（来自 `AGENTS.md`）**：在开发、调研或 debug 期间，模型与工具**严禁擅自读取用户本机或环境变量中已配置的其他模型厂商的任何信息（连厂商名称都不行）**；若确实需要读取，必须每次先向用户说明原因并获得用户明确同意。
> 2. **密钥安全红线（宪章 VII / RS-1）**：API Key 及副凭证仅通过当前终端环境变量传入（`MM_REALTIME_KEY` / `MM_TTS_KEY` 或 `--key-env` / `--secondary-env`），**严禁写入仓库、代码、日志、错误消息、命令行明文参数或测试夹具**；所有错误文本必须经 `SecretRedactor.sanitizedErrorMessage` 清洗。
> 3. **个人声音隐私红线**：`Assets/voice-samples/*.wav` 含用户个人声音（已被 `.gitignore:25` 排除），**严禁 `git add` 提交、严禁写入 JSONL 测试夹具、严禁上传至非用户拍板的目标测试接口**。
> 4. **零第三方依赖与架构红线（宪章 IV / VI）**：仅使用 Apple 系统框架（`URLSession` WebSocket / HTTP、`AVFoundation`、系统 `zlib`）与仓内现有模块；云端 URL、鉴权与协议帧细节必须完全收敛在对应驱动实现内部；Swift 6 严格并发；引用 `MMCore` 时钟必须显式写 `any MMCore.Clock`。
> 5. **流程红线**：设计阶段仅编写本执行单，不改动任何代码或配置；实施完成后向用户汇报验收前，必须先按 `task-review-loop` skill 完成独立只读复审闭环；**未经用户明确确认验收，不得勾选 `tasks.md`、不得 `git commit`、不得 `git push`**。

---

## 上篇：面向用户决策

### 1. 任务目标与选择理由

- **本次任务**：完成 `003-m2-voice-conversation` Phase 3b（US1 / M2a 开放式云端驱动探索、接入与实测选型）——面向独立实施模型提供**“厂商与协议完全开放探索，但两步门禁、接口契约、脱敏红线与验收标尺完全锁死”**的自包含施工图，完成 ≥ 2 家国内直连可用云端方案的调研、接入、脱敏夹具回放与 V4–V7 / SC-001 / SC-002 量化实测，并按多配置可切换原则保留全部已跑通可用驱动。
- **选择理由**：Phase 3a（`main @ 7262f0f`）已把厂商无关多供应商配置、Keychain v2、通用传输/脱敏/夹具录制层、`ProviderRegistry` 与 5 子命令 `mm-probe` 底座全部验收落地；当前 US1（M2a）是后续 US2–US6（免唤醒对话闭环）的唯一前置阻塞门禁（见 `specs/003-m2-voice-conversation/tasks.md:181`），前置依赖已核验满足。
- **产品背景与选型依据（仓库规范精准坐标，严禁脱离规范自行编造标准）**：
  - 核心用户故事、FR-001–FR-003 与 SC-001/SC-002：`specs/003-m2-voice-conversation/spec.md:9-27`、`141-146`、`192-193`
  - 方案 B/C 决策 D1–D5、V4–V7 通过标准与 9 条语音样本名录：`specs/003-m2-voice-conversation/research.md:7-66`
  - 项目最高原则（原则 II/III/IV/V/VI/VII）：`.specify/memory/constitution.md`
  - 标签、实时会话与 TTS 协议契约：`specs/003-m2-voice-conversation/contracts/tag-protocol.md`、`contracts/realtime-session.md`、`contracts/tts-provider.md`
  - 小瓜人格设定与指令拼装源：`Packages/MiniMateKit/Sources/MMConversation/Resources/persona.md`

> **覆盖声明**：上述历史文档中列举的具体厂商名与 `--vendor` 示例仅为早期参考，Phase 3b 不受其限制，请按当前最新能力与资费自由调研；接入方式与命令一律以 3a 落地的 `ProviderRegistry` 与 `--driver` 为准（同时 `TTSEmotionMapping` JSON 顶层字段名以真实代码 `EmotionMapping.swift:95-99` 的 `"driverID"` 为准，取代旧契约文档中的 `"vendor"`）。

- **摸底关键发现（基于 `main @ 7262f0f` 源码核实）**：
  1. **既有单测对默认注册表存在精确相等断言**：`AppComposition.swift:22`、`SettingsView.swift:208` 与 `ProbeRunner.swift:37` 均统一使用 `ProviderRegistry.makeDefault()`，因此新云端驱动应单点注册到 `ProviderRegistry.makeDefault()` 实现 App 设置页与 `mm-probe` 自动发现；但 `ProviderInfrastructureTests.swift:108-109, 118` 当前硬断言列表精确等于 `["mock-realtime"]` / `["mock-tts"]`，实施阶段需同步将其调整为包含断言（不削弱原覆盖语义）。
  2. **通用传输层与录制过滤器存在两项真实边界**：① `HTTPStreamingTransport`（`HTTPStreamingTransport.swift:24-26`）目前仅提供 UTF-8 逐行文本流 `streamLines(for:)`，若候选 TTS 仅提供 HTTP 原始二进制字节流而无 WebSocket / SSE / NDJSON，严禁误用 `streamLines` 破坏音频或绕过 transport 裸建 `URLSession`，必须在 Stage A 标明并经用户拍板走偏差止损；② `RecordingWebSocketTransport.defaultOutboundFilter`（`FixtureRecordingTransport.swift:59-70`）过滤全部 `.binary` 上行帧，但对 `.text` 仅按固定关键字过滤，若新协议用其他 JSON 字段名上传 base64 音频，录制后必须人工/脚本审计 `.jsonl` 确认零个人声音残留。
  3. **`mm-probe` 发送采样率固定 16 kHz 且 V4 审计为可选协议**：`ProbeRunner.swift:488` 统一把样本重采样为 16 kHz Int16 单声道分块发送；若新实时协议要求其他采样率（如 24 kHz），必须在驱动 `send(_:)` 内复用 `MMAudio.PCMConverter` 转换；且新实时会话必须实现 `RealtimeSessionAuditable`（`FakeRealtimeTextSession.swift:8-10`）并在收到服务端语音结束事件时发出 `.speechEnded`，`mm-probe` 的 V4 审计与首字耗时统计才会生效。

### 2. 待用户拍板的决策清单

1. **实时大脑（`realtimeBrain`）与情感 TTS（`emotionalTTS`）的组合方式**
   - **1A（推荐）**：允许实时语音理解与情感 TTS **独立评估、自由混搭**（例如方案 1 的实时大脑 + 方案 2 的情感 TTS），并保留所有已跑通可用驱动供 App 设置页随时手动切换。
   - **1B**：强制同一厂商提供成对的实时语音理解与情感 TTS（单账号单账单管理）。*差量：若选 1B，需对下篇 §5.1 Stage A 开放筛选条件新增“同一厂商须同时提供实时语音与情感 TTS”硬约束，并在 §6 Step B5 仅按同厂成对组合汇总结论。*
2. **Stage A 调研范围与 Stage B 实测候选数量**
   - **2A（推荐）**：Stage A 联网调研并对比 **3–4 家**国内直连可用候选方案；由用户从中拍板选定 **2 家**进入 Stage B 开通账号、编写驱动并完成全套 V4–V7 / SC-001 / SC-002 实测（满足 FR-003 / SC-001 至少两家国内厂商底线，兼顾开发与测试成本）。
   - **2B**：由用户从 Stage A 调研表中选定 **≥ 3 家**（或允许纳入 1 家海外备选）全部接入编码并实测对比。*差量：若选 2B，需对下篇 §5.1 放宽“仅限国内直连”硬约束（纳入海外方案须注明代理网络前提），并在 §6 Stage B 按实际选定家数重复 Step B1–B5。*
3. **方案 B 核心门槛（V4 只出文字 / V5 语气）若全数未达标时的止损策略**
   - **3A（推荐）**：若所有实测候选在 V4（只出文字且无音频输出计费）或 V5（SC-002 ≥ 2/3 组语气可辨）上均未达标，立即在 `research.md` 如实记录数据并给出“调整 instructions 复测”或“转方案 C（US7）”建议，**停步交由用户拍板**，不在 Phase 3b 顺手实现方案 C 引擎。
   - **3B**：若某家实时接口不支持纯文本输出（仅出语音），允许在 Phase 3b 同步扩展 `mm-probe` 做方案 C 探测原型。*差量：若选 3B，需从下篇 §4.2 Non-Goals 移除“不改动 `MMProbeCore` 与不做方案 C 原型”限制，并在 §6 Step B5 后增补方案 C 探测子步骤。*

---

## 下篇：面向实施方的零歧义施工图

> **致执行本单的独立模型**：本下篇已按全部推荐项（1A / 2A / 3A）写成无条件分支终态。你**不需要**也不应依赖任何历史对话记忆；请严格遵守“先 Stage A 调研提交用户拍板 → 获批且环境变量就绪后再进 Stage B 编码实测”的两步门禁，以及全部接口契约与红线。

### 3. 现状锚点与环境陷阱预警

#### 3.1 现有代码锚点（3a 底座复用指南，`main @ 7262f0f` 实测核对）

| 模块 / 符号 | 精确位置 | 职责与复用 / 约束说明 |
| :--- | :--- | :--- |
| `ProviderDriverDescriptor`、`DriverBuildContext`、`RealtimeSessionDriver`、`TTSProviderDriver` | `Packages/MiniMateKit/Sources/MMConversation/Registry/ProviderDriverDescriptor.swift:6-74` | 驱动元数据与工厂协议唯一定义；`DriverBuildContext:37-54` 注入 `clock`、`webSocketTransport`、`httpTransport`、`emotionMappingOverride`，**所有新驱动必须通过该上下文发起网络请求** |
| `ProviderRegistry` | `Packages/MiniMateKit/Sources/MMConversation/Registry/ProviderRegistry.swift:19-127` | 线程安全单点注册表；`register:31-57` 校验 role 匹配与 ID 唯一；`makeRealtimeSession:80-102` / `makeTTSProvider:104-126` 自动强制校验 `requiresPrimarySecret` 非空 |
| `MockRealtimeDriver`、`MockTTSDriver`、`ProviderRegistry.makeDefault()` | `Packages/MiniMateKit/Sources/MMConversation/Registry/BuiltInMockDrivers.swift:6-86` | 照猫画虎参考模板与**全局唯一默认注册入口**（`makeDefault():78-86`）；`AppComposition.swift:22`、`SettingsView.swift:208`、`ProbeRunner.swift:37` 均直接调用它 |
| `RealtimeError`、`RealtimeOutput`、`RealtimeTextSession` | `Packages/MiniMateKit/Sources/MMConversation/Realtime/RealtimeTextSession.swift:5-36` | 实时语音会话协议与错误/输出枚举；未连接时 `send(_:)` 必须抛 `RealtimeError.notConnected`（RS-4） |
| `RealtimeSessionAuditable`、`MockRealtimeProtocol`、`FakeRealtimeTextSession` | `Packages/MiniMateKit/Sources/MMConversation/Realtime/FakeRealtimeTextSession.swift:8-10, 26-87, 307-509` | **新实时驱动照猫画虎主范本**：`RealtimeSessionAuditable:8-10` 暴露 `unexpectedAudioEventCount` 供 V4 审计；`MockRealtimeProtocol:26-87` 演示纯函数解帧与 `replayFixture`；`FakeRealtimeTextSession:351-498` 演示 `OSAllocatedUnfairLock` 状态管理、`AsyncThrowingStream` 断线报错与 `deinit` 安全收尾 |
| `TTSError`、`TTSProvider` | `Packages/MiniMateKit/Sources/MMConversation/TTS/TTSProvider.swift:6-19` | 情感 TTS 协议与错误枚举 |
| `FakeTTSProvider` | `Packages/MiniMateKit/Sources/MMConversation/TTS/FakeTTSProvider.swift:7-227` | **新 TTS 驱动照猫画虎主范本**：参考 `163-175`（持锁确认未取消再同步 `yield`）、`203-214`（`cancelAll()` 原子摘除并 cancel/finish）与 `216-226`（`deinit` 清理防挂起），严格满足 TTS-5 |
| `JSONScalar`、`EmotionParameterSet`、`TTSEmotionMapping` | `Packages/MiniMateKit/Sources/MMConversation/TTS/EmotionMapping.swift:5-177` | TTS 情绪参数映射表与校验器；顶层 JSON 键为 `driverID` / `voice` / `map`（`95-99`）；`loadBundled(for:):135-145` 从 `Bundle.module` 根目录加载 `tts-emotion-<driverID>.json`；`params(for:):108-110` 自动实现 TTS-2 缺失回退 `.neutral` |
| `WebSocketTransport`、`URLSessionWebSocketTransport` | `Packages/MiniMateKit/Sources/MMConversation/Transport/WebSocketTransport.swift:4-182` | 通用 WebSocket 传输协议（支持 `.text` 与 `.binary` 双向帧），内置 HTTP 握手非 101 状态码提取（`.httpRejected(statusCode:message:)`）与错误脱敏 |
| `HTTPStreamingTransport`、`URLSessionHTTPStreamingTransport` | `Packages/MiniMateKit/Sources/MMConversation/Transport/HTTPStreamingTransport.swift:3-110` | 通用 HTTP 逐行 UTF-8 流式传输协议（适用 SSE / NDJSON），流终止时自动取消底层读取 `Task` |
| `FixtureFrameRecord`、`RecordingWebSocketTransport` | `Packages/MiniMateKit/Sources/MMConversation/Transport/FixtureRecordingTransport.swift:6-191` | 自动不记录握手头、自动将长度 ≥ 4 的握手头值加入脱敏集、默认过滤 `.binary` 上行帧与含特定音频关键词的 `.text` 帧；提供 `decodeJSONLines:114-125` 供离线测试回放 |
| `SecretRedactor` | `Packages/MiniMateKit/Sources/MMConversation/Transport/SecretRedactor.swift:5-65` | `redact(_:secrets:):23-50` 与 `sanitizedErrorMessage(_:secrets:):52-55`，用于清洗全部日志与错误关联值 |
| `GzipCodec` | `Packages/MiniMateKit/Sources/MMConversation/Transport/GzipCodec.swift:11-126` | 基于系统 `zlib` 的 RFC 1952 GZIP 编解码（带防解压炸弹上限 `defaultMaxOutputBytes = 16 MiB`），适合需要二进制压缩帧的协议 |
| `PCMByteAligner`、`WAVCodec` | `Packages/MiniMateKit/Sources/MMAudio/WAVCodec.swift:12-39, 41-235` | `PCMByteAligner:12-39` 处理流式 16-bit PCM 跨帧奇数字节拼接防声道错位；`WAVCodec` 提供 WAV 编解码与 `loadAudioFile` |
| `PCMConverter` | `Packages/MiniMateKit/Sources/MMAudio/PCMConverter.swift:13-199` | 基于 `AVAudioConverter` 的流式 / 一次性 16-bit 单声道重采样（含 `flush()` 排空 FIR 尾帧） |
| `AudioFormatDescription`、`AudioTimeMark`、`AudioChunk` | `Packages/MiniMateKit/Sources/MMAudio/AudioChunk.swift:4-94` | 音频块模型，`AudioChunk(pcmData:sampleRate:marks:):53-71` 支持从偶数字节小端 PCM 直接构造；`marks` 用于透传字级时间戳（TTS-6） |
| `Persona` | `Packages/MiniMateKit/Sources/MMConversation/Persona.swift:93-159` | `Persona.loadBundled().makeInstructions()` 已被 `ProbeRunner.swift:489` 自动调用并传入 `session.connect(instructions:)`，驱动直接透传即可 |
| `ProbeRunner`、`ProbeArguments`、`ProbeReport` | `Packages/MiniMateKit/Sources/MMProbeCore/ProbeRunner.swift:20-662`、`ProbeArguments.swift:97-110`、`ProbeReport.swift:54-172` | 插件化 CLI 核心；自动按 `--driver <id>` 寻址，支持 `--endpoint` / `--model` / `--voice` / `--mapping` / `--key-env` / `--secondary-env` / `--chunk-ms` / `--silence-ms` / `--pace` / `--timeout-s` |
| `ProviderProfile`、`ProviderRole` | `Packages/MiniMateKit/Sources/MMSecurity/ProviderProfile.swift:14-94`、`ProviderRole.swift:4-27` | 非敏感配置元数据（`customEndpoint`、`modelName`、`voiceID`），CLI 参数与 App 设置页字段均经此结构透传给驱动工厂 |
| `FoundationalTests`（映射兼容红线） | `Packages/MiniMateKit/Tests/MMConversationTests/FoundationalTests.swift:200-225` | 第 222–224 行硬断言 `TTSEmotionMapping.loadBundled(for: "mock-tts")` 抛 `.resourceNotFound("mock-tts")`，**严禁为 `"mock-tts"` 添加资源 JSON** |
| `ProviderInfrastructureTests`（注册表兼容点） | `Packages/MiniMateKit/Tests/MMConversationTests/ProviderInfrastructureTests.swift:105-147` | 第 108–109、118 行当前对 `ProviderRegistry.makeDefault()` 的 ID 列表做精确相等断言；在 `makeDefault()` 注册新驱动时须同步放宽为包含断言（见 §5.2 兼容性约束） |

#### 3.2 环境与协议接入实测陷阱

1. **Swift 6.4 `Swift.Clock` 命名冲突**：裸写 `any Clock` 会与标准库 `Swift.Clock` 冲突报错 → 新驱动与测试中引用时钟必须显式写 `any MMCore.Clock`。
2. **沙盒内 `swift test` Clang Module Cache 权限**：若在受限沙盒中运行 `swift test` 出现 `ModuleCache` 不可写，必须附环境变量与参数：
   ```bash
   CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache \
   SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache \
   swift test --disable-sandbox
   ```
   （常规本机终端联网测试时直接 `swift test` / `swift run mm-probe ...` 即可。）
3. **SwiftPM 资源路径扁平化 vs 保留目录**：
   - `MMConversation` 使用 `.process("Resources")`（`Package.swift:33`）：`Resources/tts-emotion-<driverID>.json` 会被扁平化到 `Bundle.module` 根目录 → 必须经 `TTSEmotionMapping.loadBundled(for: driverID)` 加载，**严禁传 `subdirectory: "Resources"`**；
   - `MMConversationTests` 使用 `.copy("Fixtures")`（`Package.swift:53`）：测试夹具保留子目录 → 加载夹具必须传 `subdirectory: "Fixtures"`（参照 `ProviderInfrastructureTests.swift:307`）。
4. **`ProbeRunner` 固定 16 kHz 发送与服务端 VAD 触发时机**：`ProbeRunner.swift:488, 578-601` 统一将输入音频重采样为 16 kHz Int16 单声道分块调用 `session.send(_:)`，随后自动追加 `--silence-ms`（默认 1200 ms）静音块触发服务端 VAD，不会发送额外手工提交信号 → 若某实时协议要求 24 kHz（或其他采样率），驱动必须在 `send(_:)` 内部维护 `MMAudio.PCMConverter` 流式重采样；若某协议服务端 VAD 静音判定阈值大于 1200 ms，在命令行加 `--silence-ms 2000` 即可，勿改 `ProbeRunner`。
5. **`ProbeRunner` 首字耗时与 V4 审计依赖**：`ProbeRunner.swift:522-541` 仅在同时收到 `.speechEnded` 与 `.textDelta` 时计算 `firstTextLatencyMs`；`ProbeRunner.swift:610` 仅在会话对象遵守 `RealtimeSessionAuditable` 时统计 `unexpectedAudioCount` → 新实时会话**必须**遵守 `RealtimeSessionAuditable` 并在服务端判定语音结束时发出 `.speechEnded`。
6. **`RecordingWebSocketTransport` 上行音频过滤盲区**：`FixtureRecordingTransport.swift:59-70` 默认过滤所有 `.binary` 上行帧，但对 `.text` 帧仅过滤包含 `"\"audio\""` / `"audio_buffer.append"` / `"audio.chunk"` 的文本。若某协议通过 WebSocket JSON 文本上传音频且字段名不命中上述关键词，录制 `.jsonl` 时会夹带用户个人声音 base64 → 每次执行 `mm-probe record-fixture` 后**必须检查产出的 `.jsonl`**，确保不存在任何上行个人音频载荷或长 base64 音频块；若命中盲区，按 §9 止损规则上报或请示是否补充过滤器关键词，严禁将含个人声音的 `.jsonl` 留存在仓库中。
7. **`HTTPStreamingTransport` 仅支持 UTF-8 行流**：`HTTPStreamingTransport.swift:24-26, 70-87` 按 `0x0A` 切分 UTF-8 文本行，适合 SSE / NDJSON / 行分隔 JSON 协议，**不能用于直接下载原始二进制 PCM/MP3 流**（会被 `0x0A` 切碎并损坏非 UTF-8 字节）→ Stage A 调研情感 TTS 时应优先选择支持 WebSocket（文本/二进制）或 HTTP SSE/NDJSON 的接口；若用户拍板的候选 TTS **仅提供 HTTP 原始二进制字节流**，必须在 Stage A 报告中显式标注，经用户拍板后再扩展 `HTTPStreamingTransport`（严禁裸建 `URLSession` 或强行用 `streamLines` 读二进制）。
8. **流式 TTS 奇数字节跨帧对齐**：网络分片到达的 16-bit PCM 字节流可能出现奇数长度分片；直接调 `AudioChunk(pcmData:)` 会丢弃尾部 1 字节导致后续全部采样错位炸音 → 流式解析原始 PCM 字节时**必须**经过 `MMAudio.PCMByteAligner`（`WAVCodec.swift:12-39`）。
9. **`TTSEmotionMapping` 真实 JSON 格式与校验**：必须包含非空 `"driverID"`、非空 `"voice"`、且 `"map"` 必须包含 `"neutral"` 键；`"map"` 的键仅允许 `EmotionTag.allCases` 的 `rawValue`（`happy`、`gentle`、`sad`、`surprised`、`shy`、`playful`、`concerned`、`neutral`），否则 `TTSEmotionMapping.load` 直接抛 `.unknownEmotionKey`。

---

### 4. 改动范围表与明确不做清单（Non-Goals）

#### 4.1 文件改动表

> **阶段门禁**：Stage A 完成并获用户书面拍板前，**改动文件数为 0**（仅在对话中向用户输出调研对比表与开通建议）。以下改动表仅在进入 **Stage B** 后按用户选定的驱动列表执行。

| 文件路径 | 操作 | 精确职责 |
| :--- | :--- | :--- |
| `Packages/MiniMateKit/Sources/MMConversation/Realtime/<DriverName>RealtimeSession.swift`（每个拍板实时候选 1 份） | 新增 | 实现 `RealtimeTextSession`、`RealtimeSessionAuditable`、`RealtimeSessionDriver` 及纯函数帧解码器（支持离线夹具回放） |
| `Packages/MiniMateKit/Sources/MMConversation/TTS/<DriverName>TTSProvider.swift`（每个拍板 TTS 候选 1 份） | 新增 | 实现 `TTSProvider` 与 `TTSProviderDriver`（复现 `TTSEmotionMapping` 加载、同音色约束、流式产出与 `cancelAll()` 线性化） |
| `Packages/MiniMateKit/Sources/MMConversation/Resources/tts-emotion-<driverID>.json`（每个保留 TTS 驱动 1 份） | 新增 | 对应驱动的固定音色与 8 种 `EmotionTag` 情绪参数映射表（经 `mm-probe tts --all-emotions` 试听校准） |
| `Packages/MiniMateKit/Sources/MMConversation/Registry/BuiltInMockDrivers.swift` | 微调 | 仅在 `ProviderRegistry.makeDefault()`（第 80–85 行）中为保留的已跑通云端驱动追加 `try? registry.register(...)`；不改内置 Mock 行为 |
| `Packages/MiniMateKit/Tests/MMConversationTests/Fixtures/<driverID>-sample.jsonl`（每个保留实时驱动 1 份） | 新增 | 由 `mm-probe record-fixture` 录制并经人工+脚本脱敏审计（零密钥、零个人语音）的离线回放夹具 |
| `Packages/MiniMateKit/Tests/MMConversationTests/RealtimeDecodingTests.swift` | 新增 | 基于脱敏夹具回放验证全部实时驱动解码映射、RS-1/RS-3/RS-4/RS-5、V4 音频审计，以及全部 TTS 驱动映射加载、协议帧解析、TTS-1–TTS-6 与 `cancelAll()` 线性化 |
| `Packages/MiniMateKit/Tests/MMConversationTests/ProviderInfrastructureTests.swift` | 微调 | 仅更新第 108–109、118 行对 `ProviderRegistry.makeDefault()` 驱动 ID 列表的断言（由“仅含 mock 精确相等”改为“包含 mock 与新增注册驱动”），严禁改动其余测试断言 |
| `specs/003-m2-voice-conversation/contracts/realtime-session.md` | 修改 | 用实测跑通的保留驱动更新文末「厂商附录」（Endpoint、鉴权方式、模型名、纯文本配置、输入音频格式、VAD、取消消息、用户转写事件） |
| `specs/003-m2-voice-conversation/research.md` | 修改 | 填写「M2a 厂商对比」量化表（V4–V7、SC-001/SC-002、首个文字耗时 p50、TTS 首包 p50）与「选型结论」（主力组合 + 可切换备选组合 + 方案 B/C 结论与理由） |
| `docs/tech-selection.md` | 按需修改 | 仅当 M2a 实测数据推翻 `docs/tech-selection.md`（v3.7）既有结论时，同步修订对应章节并在附录 B 登记修订记录（宪章 Development Workflow 第 5 条） |

#### 4.2 明确不做清单（Non-Goals）

- **严禁修改 3a 已锁定的基础设施与 App UI**：禁止改动 `Packages/MiniMateKit/Sources/MMSecurity/`、`App/MiniMate/Screens/SettingsView.swift`、`App/MiniMate/Screens/ProviderProfileEditorSheet.swift`、`App/MiniMate/AppComposition.swift`、`ProviderRegistry.swift` 公共协议、`ProviderDriverDescriptor.swift`、`MMProbeCore/` 框架与 `MMProbeCLI/`（除非命中 §9 偏差止损条款经用户明确批准）。
- **严禁改动既有契约测试预期**：禁止破坏 `FoundationalTests.swift:222-224`（严禁新增 `tts-emotion-mock-tts.json`）；禁止削弱 `TagParserTests.swift`、`SentenceSplitterTests.swift` 或 `ProviderInfrastructureTests.swift` 中的安全与 CLI 回归断言。
- **严禁越界实现后续阶段**：不实现 US2 对话引擎（`RealtimeTextConversationEngine`、`TurnCoordinator`、`AudioIO`、`VoiceActivityGate`），不实现 Phase 9 方案 C（US7）引擎，不改动 3D 形象与感知状态机代码。
- **严禁写死或泄露任何隐私/密钥信息**：不添加第三方依赖；不提交 `Assets/voice-samples/*.wav`；不擅自探测用户本机已配置的其他厂商信息。

---

### 5. 精确接口与行为契约

#### 5.1 Stage A：开放式联网调研契约与用户拍板门禁

实施方在编写任何一行代码之前，必须先执行联网调研并向用户交付 **Stage A 调研对比报告**，满足以下硬约束：

1. **开放筛选约束（不预设具体厂商，按当前最新能力与资费客观筛选）**：
   - **网络可达**：国内常规家庭 Wi-Fi / 5G 网络直连可用（不依赖代理）；
   - **开通门槛**：个人开发者可自助注册开通并获取 API 凭证（无需企业营业执照或人工商务审批）；
   - **文档公开**：具备官方公开的接口/协议文档（明确鉴权方式、请求/响应帧格式、音频格式与错误码）；
   - **协议可行**：仅凭 Apple 系统 `URLSession`（WebSocket / HTTP）+ 系统 `zlib` 即可零第三方 SDK 接入；
   - **能力对标**：
     - 实时语音理解（`realtimeBrain`）：支持流式 PCM 语音输入、服务端 VAD、会话级 `instructions`、流式文字增量输出、取消当前回答，优先支持**只输出文字且无音频输出计费（A-1 / V4）**，并核查是否返回用户输入转写（A-6 / V7）；
     - 情感 TTS（`emotionalTTS`）：支持**同一预置音色**下通过情感参数或指令切换多种情绪（目标至少 4 种情绪可辨，对应 `EmotionTag` 8 类映射）、流式输出 PCM（首包目标 < 500 ms，V6），并核查是否返回字级/音素级时间戳（TTS-6）。
2. **调研对比表必填维度（覆盖 3–4 家候选，按 `realtimeBrain` 与 `emotionalTTS` 两个角色清晰列出，允许同厂或跨厂独立评估）**：
   - 候选名称与官方文档链接（注明核查日期）；
   - 接口协议类型（WebSocket 文本 JSON / WebSocket 二进制帧+GZIP / HTTP SSE / HTTP NDJSON / HTTP 原始二进制流——**若仅提供 HTTP 原始二进制流，必须显式标红预警**）；
   - 实时大脑专属项：支持纯文本输出无语音计费（是/否/待实测）、支持服务端 VAD 与取消打断、支持输入音频采样率、是否提供用户转写（V7）；
   - 情感 TTS 专属项：同音色多情绪控制方式（参数字段 / 自然语言指令）、支持的原生情绪数、输出音频格式与采样率、是否提供字级时间戳（TTS-6）；
   - 个人自助开通流程与实名/充值门槛；
   - 当前官方资费与免费额度；
   - 鉴权凭证结构（单主凭证 vs 主+副双凭证，对应 `ProviderDriverDescriptor.requiresPrimarySecret` / `supportsSecondarySecret` 与 `MM_*_KEY` / `MM_*_SECONDARY_SECRET`）；
   - 协议实现复杂度评估（低/中/高）与已知风险。
3. **Stage A 硬门禁（停步等待拍板）**：
   - 给出推荐开通的 **2 家实时大脑 + 2 家情感 TTS**（可同厂也可跨厂）清单及各自建议的 `driverID` 命名（纯小写字母/数字/连字符，例如 `<short-name>-realtime`、`<short-name>-tts`，清晰辨识且不与 `mock-realtime` / `mock-tts` 冲突）；
   - **暂停施工，等待用户明确回复**：① 拍板开通哪几家候选；② 确认账号已开通且对应环境变量已在用户本机终端导出（注意：用户只需告知环境变量名，**不要让用户在对话中粘贴明文 Key**）。

#### 5.2 实时语音驱动最小接入契约（`RealtimeTextSession` + `RealtimeSessionAuditable` + `RealtimeSessionDriver`）

每个选定的实时语音驱动必须同时实现以下三部分，并复用 `DriverBuildContext`：

- **位置与签名**：`Packages/MiniMateKit/Sources/MMConversation/Realtime/<DriverName>RealtimeSession.swift`
  ```swift
  public protocol RealtimeTextSession: Sendable {
      func connect(instructions: String) async throws
      func send(_ audio: AudioChunk) async throws
      func cancelResponse() async
      func clearInputBuffer() async
      var output: AsyncThrowingStream<RealtimeOutput, Error> { get }
      func close() async
  }

  public protocol RealtimeSessionAuditable: Sendable {
      var unexpectedAudioEventCount: Int { get }
  }

  public protocol RealtimeSessionDriver: Sendable {
      var descriptor: ProviderDriverDescriptor { get }
      func makeSession(
          profile: ProviderProfile,
          credentials: ProviderCredentials?,
          context: DriverBuildContext
      ) throws -> any RealtimeTextSession
  }
  ```
- **依赖注入与复用约束**：
  1. 网络连接**必须**通过 `context.webSocketTransport.connect(url:headers:)`（或适用时的 `context.httpTransport`）建立，严禁在驱动内新建 `URLSession`；
  2. 优先使用 `profile.customEndpoint` / `profile.modelName` 覆盖默认值；留空时使用该驱动文档核实的默认 Endpoint 与默认模型名；
  3. 若协议要求二进制压缩帧，必须复用 `GzipCodec`（`GzipCodec.swift:11-126`）；
  4. 若协议要求输入采样率与传入 `audio.sampleRate` 不一致（例如 `ProbeRunner` 传入 16 kHz 而协议要求 24 kHz），必须在会话内部复用 `MMAudio.PCMConverter`（`PCMConverter.swift:13-98`）流式重采样，`clearInputBuffer()` / `close()` 时同步 `reset()`；
  5. **必须拆出纯函数/纯类型解码器**（参照 `MockRealtimeProtocol`，`FakeRealtimeTextSession.swift:26-87`），支持将 `[FixtureFrameRecord]` 直接回放为 `[RealtimeOutput]`、`unexpectedAudioCount` 与 `ignoredTypes`，以满足 RS-5 离线确定性测试。
- **行为与异常口径**：
  - **A-1 / V4 审计**：建连配置显式请求**只输出文字**；若服务端仍下发音频事件/音频载荷，递增 `unexpectedAudioEventCount`（线程安全）且不误发为 `.textDelta`；
  - **A-2 / 耗时统计**：服务端语音开始发 `.speechStarted`，语音结束发 `.speechEnded`（`ProbeRunner` 依赖它计算首字耗时），流式文字增量发 `.textDelta`，回答完成发 `.responseDone`，用户转写（若有）发 `.userTranscript(text, isFinal:)`；
  - **RS-1 脱敏**：鉴权仅放握手头或建连首条鉴权消息；所有映射为 `RealtimeError` 的错误文本必须经过 `SecretRedactor.sanitizedErrorMessage(error, secrets: ...)` 或 `SecretRedactor.redact(..., secrets: ...)`；HTTP 401/403 映射为 `.authFailed`，429 映射为 `.rateLimited`，不支持只出文字等配置拒绝映射为 `.unsupportedConfiguration(...)`；
  - **RS-2 / RS-3**：原始协议字段全部在驱动内部消化；未识别消息类型忽略并仅以低级别记录类型名（不记录内容与音频）；
  - **RS-4**：未 `connect` 或已 `close` 后调用 `send(_:)` 必须直接抛 `RealtimeError.notConnected`，不得缓存；
  - **生命周期防泄漏**：参照 `FakeRealtimeTextSession.swift:351-498`，非正常断线必须以 `RealtimeError.network(...)` 终止 `output` 流；`close()` 与 `deinit` 必须取消接收 `Task` 并 `finish()` 输出流，严禁悬空挂起；
  - **单点注册与兼容性**：在 `BuiltInMockDrivers.swift:80-85` 的 `ProviderRegistry.makeDefault()` 注册新驱动；同步将 `ProviderInfrastructureTests.swift:108-109, 118` 从精确相等断言改为包含断言（保留“默认含 `mock-realtime`/`mock-tts`、自定义注册追加到末尾且顺序可验证”的原语义）。

#### 5.3 情感 TTS 驱动最小接入契约（`TTSProvider` + `TTSEmotionMapping` + `TTSProviderDriver`）

每个选定的情感 TTS 驱动必须实现以下契约：

- **位置与签名**：`Packages/MiniMateKit/Sources/MMConversation/TTS/<DriverName>TTSProvider.swift`
  ```swift
  public protocol TTSProvider: Sendable {
      func synthesize(_ sentence: String, emotion: EmotionTag) -> AsyncThrowingStream<AudioChunk, Error>
      var outputFormat: AudioFormatDescription { get }
      func cancelAll() async
  }

  public protocol TTSProviderDriver: Sendable {
      var descriptor: ProviderDriverDescriptor { get }
      func makeProvider(
          profile: ProviderProfile,
          credentials: ProviderCredentials?,
          context: DriverBuildContext
      ) throws -> any TTSProvider
  }
  ```
- **依赖注入、映射与复用约束**：
  1. 网络请求**必须**通过 `context.webSocketTransport` 或 `context.httpTransport` 发起，严禁裸建 `URLSession`；
  2. 情绪映射加载优先级：**`context.emotionMappingOverride` > `TTSEmotionMapping.loadBundled(for: driverID)` > 驱动内置兜底默认映射**；音色解析优先级：**`profile.voiceID`（若非空） > 映射表中的 `mapping.voice`**（满足 TTS-1：同一实例全程固定同一音色，绝不按 `emotion` 切换音色）；
  3. 映射 JSON 资源文件位于 `Packages/MiniMateKit/Sources/MMConversation/Resources/tts-emotion-<driverID>.json`，必须严格遵守 `EmotionMapping.swift:90-126` Schema（顶层键 `"driverID"`、`"voice"`、`"map"`，且 `"map"` 覆盖全部 8 种 `EmotionTag` 或至少含 `"neutral"`，支持厂商不支持的情绪就近映射）；
  4. 若服务端返回原始流式 16-bit PCM 字节块，必须经 `MMAudio.PCMByteAligner`（`WAVCodec.swift:12-39`）拼接对齐后再构造 `AudioChunk(pcmData:sampleRate:marks:)`；若服务端返回 WAV 容器头，仅剥离首块头或校验格式后产出 PCM；
  5. 若服务端返回字级/音素级时间戳，按 `AudioTimeMark(text:offsetSeconds:charOffset:)` 透传至 `AudioChunk.marks`（TTS-6）；无则为空数组。
- **行为与异常口径**：
  - **空句防御**：`sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` 时直接结束流（产出 0 块），不发无效网络请求；
  - **TTS-3 流式首包**：收到首个有效音频块立即 `yield`，不等整句合成完成；
  - **TTS-4 错误上抛与脱敏**：网络/鉴权/协议错误以 `TTSError.synthesisFailed(SecretRedactor.sanitizedErrorMessage(...))` 或 `.invalidConfiguration(...)` 结束流，绝不静默吞错、绝不泄露密钥；
  - **TTS-5 取消线性化（强约束）**：必须参照 `FakeTTSProvider.swift:163-175, 203-226` 在 `OSAllocatedUnfairLock` 保护下管理进行中的请求表，**在持锁区内确认未取消再同步 `yield`**；`cancelAll()` 与 `deinit` 必须原子移除所有活动流、取消对应网络任务/关闭连接并 `finish()`，确保 `cancelAll()` 返回后已取消流绝不再产出任何后续音频块。

#### 5.4 多厂商保留与收口清理契约（更新 `tasks.md` 原 T025 口径）

- **产品约束更新**：产品成型后需支持用户在 App 设置页（`SettingsView` 已支持双用途 1..N 动态配置与 Active 切换）随时手动切换多个已接通的供应商配置，以平衡资费与免费额度。
- **Phase 3b 收口保留规则**：
  - **保留**所有已跑通且通过测试/实测验收的候选驱动代码、`ProviderRegistry.makeDefault()` 注册条目、`Resources/tts-emotion-<driverID>.json`、`Fixtures/<driverID>-sample.jsonl`、`RealtimeDecodingTests.swift` 对应回放用例以及 `contracts/realtime-session.md` 附录条目；
  - **仅清理**验证彻底失败、被放弃或不再维护的实验性驱动代码、夹具与映射文件；
  - 在 `specs/003-m2-voice-conversation/research.md` 中明确写出：**推荐主力组合（实时大脑驱动 + 情感 TTS 驱动）**、**保留的可切换备选组合**、以及 **方案 B / 方案 C 决策结论与理由**。

---

### 6. 原子化施工步骤（两步门禁，自底向上）

#### Stage A：开放式调研与方案拍板（严禁改代码）

- **Step A1：联网调研候选方案并输出决策对比表**
  - 改动文件：无（严格只读）
  - 改动要点：
    1. 读取 §1 列出的规范文档坐标与 3a 关键锚点确认验收口径；
    2. 联网检索当前（最新）满足 §5.1 开放筛选约束的 **3–4 家**国内直连云端实时语音 / 情感 TTS 服务官方文档与资费页；
    3. 按 §5.1 第 2 条必填维度整理清晰对比表，标注风险（如是否仅支持 HTTP 原始二进制流、是否可能无纯文本模式、凭证结构等），给出推荐的 **2 家实时大脑 + 2 家情感 TTS** 开通组合与建议 `driverID`；
    4. **立即停止并提交用户审阅拍板**，明确请用户确认：① 选定开通哪些候选；② 用户在本地终端配置好对应环境变量名（不贴明文 Key）。
  - 最小验证命令：`git status --short`（必须为空，确认 Stage A 未触碰任何文件）。

> **【硬门禁】未收到用户对 Stage A 候选清单的明确拍板与环境变量就绪确认，严禁进入 Stage B。**

#### Stage B：编码接入、录制夹具、实测选型与文档回写

- **Step B1：实现选定的实时语音驱动并注册**
  - 改动文件：`Sources/MMConversation/Realtime/<DriverName>RealtimeSession.swift`（按拍板家数）、`Sources/MMConversation/Registry/BuiltInMockDrivers.swift`、`Tests/MMConversationTests/ProviderInfrastructureTests.swift`（仅第 108–109、118 行断言兼容更新）
  - 改动要点：
    1. 按 §5.2 实现纯函数帧解码器、`RealtimeTextSession` + `RealtimeSessionAuditable` 与 `RealtimeSessionDriver`（全部走 `context.webSocketTransport`，内置采样率自适应、RS-1 脱敏、RS-3 忽略未知类型、RS-4 未连接抛错、V4 意外音频计数与 `deinit` 清理）；
    2. 在 `BuiltInMockDrivers.swift` 的 `ProviderRegistry.makeDefault()` 注册新驱动；
    3. 更新 `ProviderInfrastructureTests.swift:108-109, 118` 断言使其兼容已注册新驱动（且仍断言包含 `"mock-realtime"`、`"mock-tts"` 与自定义驱动追加行为）。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && swift test --filter ProviderInfrastructureTests && swift run mm-probe list-drivers --role realtime
    ```

- **Step B2：实现选定的情感 TTS 驱动与初版情绪映射资源**
  - 改动文件：`Sources/MMConversation/TTS/<DriverName>TTSProvider.swift`（按拍板家数）、`Sources/MMConversation/Resources/tts-emotion-<driverID>.json`、`Sources/MMConversation/Registry/BuiltInMockDrivers.swift`
  - 改动要点：
    1. 按 §5.3 实现 `TTSProvider` 与 `TTSProviderDriver`（走 `context.webSocketTransport` / `context.httpTransport`、经 `PCMByteAligner` 对齐、锁内线性化 `cancelAll()`、按 `TTSEmotionMapping` 透传同音色与情绪参数、透传 `AudioTimeMark`）；
    2. 按官方文档编写初版 `Resources/tts-emotion-<driverID>.json`（`driverID`、`voice`、8 种 `EmotionTag` 含 `neutral`）；
    3. 在 `ProviderRegistry.makeDefault()` 注册新 TTS 驱动。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && swift test --filter "FoundationalTests|ProviderInfrastructureTests" && swift run mm-probe list-drivers
    ```

- **Step B3：准备 9 条个人语音样本、单条联调并录制脱敏夹具**
  - 改动文件：`Tests/MMConversationTests/Fixtures/<driverID>-sample.jsonl`（按拍板实时驱动家数；**`Assets/voice-samples/*.wav` 绝不加入 Git**）
  - 改动要点：
    1. 检查 `Assets/voice-samples/` 是否已存在 `specs/003-m2-voice-conversation/research.md:58-66` 规定的 9 条样本（`fine-{happy,flat,sad}.wav`、`ok-{happy,flat,sad}.wav`、`done-{happy,tired,angry}.wav`，16 kHz 或 24 kHz、16-bit、单声道）。若尚未录制，向用户给出清晰录制与 `afconvert` 转换命令指引（例如将 QuickTime `.m4a` 转为 16 kHz 16-bit mono WAV：`afconvert -f WAVE -d LEI16@16000 -c 1 input.m4a Assets/voice-samples/ok-sad.wav`），待用户录好后继续；
    2. 使用用户已导出的环境变量运行单条冒烟与夹具录制（通过 `--key-env` / `--secondary-env` 指定变量名，禁止把 Key 写进命令行）：
       ```bash
       cd Packages/MiniMateKit
       swift run mm-probe realtime --driver <realtime-driver-id> \
         --input ../../Assets/voice-samples/ok-sad.wav \
         --key-env <KEY_ENV_NAME> [--secondary-env <SECONDARY_ENV_NAME>]

       swift run mm-probe record-fixture --driver <realtime-driver-id> \
         --input ../../Assets/voice-samples/ok-sad.wav \
         --out Tests/MMConversationTests/Fixtures/<realtime-driver-id>-sample.jsonl \
         --key-env <KEY_ENV_NAME> [--secondary-env <SECONDARY_ENV_NAME>]
       ```
    3. **强制安全与隐私审计**：人工并脚本检查每份 `.jsonl` 夹具，确认 **0 条密钥/鉴权明文、0 条上行个人音频载荷、可被 `RecordingWebSocketTransport.decodeJSONLines` 完整解析**。
  - 最小验证命令：见 §7.3 静态脱敏扫描命令 + `git status --short` 确认未跟踪 `Assets/voice-samples/`。

- **Step B4：编写离线确定性解码与驱动单元测试 `RealtimeDecodingTests.swift`**
  - 改动文件：`Packages/MiniMateKit/Tests/MMConversationTests/RealtimeDecodingTests.swift`
  - 改动要点：按 §7.1 测试矩阵，为每个接入的实时驱动与 TTS 驱动编写完整的离线确定性测试（从 `Bundle.module` 加载 `Fixtures/<driverID>-sample.jsonl` 回放验证 RS-5，使用注入 Mock Transport 测试握手头/认证失败/限流/RS-3/RS-4/V4 审计/TTS-1–TTS-6/`cancelAll()` 线性化/`deinit` 防挂起与 `TTSEmotionMapping.loadBundled`）。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && swift test --filter RealtimeDecodingTests
    ```

- **Step B5：运行完整 M2a 实测套件（V4–V7 / SC-001 / SC-002）并校准 TTS 映射**
  - 改动文件：`Packages/MiniMateKit/Sources/MMConversation/Resources/tts-emotion-<driverID>.json`（按试听结果精修）
  - 改动要点：
    1. 对每个实时驱动运行完整 9 样本 `tone-suite`（如需调整静音尾长，可通过 `--silence-ms` 控制）：
       ```bash
       cd Packages/MiniMateKit
       swift run mm-probe tone-suite --driver <realtime-driver-id> \
         --key-env <KEY_ENV_NAME> [--secondary-env <SECONDARY_ENV_NAME>]
       ```
    2. 对每个情感 TTS 驱动运行 8 情绪全量合成并保存至 `/tmp/tts-<tts-driver-id>`，邀请用户试听确认“同一音色 + 至少 4 种情绪可辨”，按需微调 `tts-emotion-<driverID>.json` 并复测：
       ```bash
       cd Packages/MiniMateKit
       swift run mm-probe tts --driver <tts-driver-id> \
         --text "今天累坏了吧？先歇会儿，我陪着你。" \
         --all-emotions --out /tmp/tts-<tts-driver-id> \
         --key-env <KEY_ENV_NAME> [--secondary-env <SECONDARY_ENV_NAME>]
       ```
    3. 核对 V4–V7 与 SC-002 实测指标：若全数候选均未达到 V4 或 SC-002，立即按决策 3A 停步整理证据上报用户，不顺手实现方案 C。
  - 最小验证命令：重跑 `swift test --filter "FoundationalTests|RealtimeDecodingTests"` 验证精修后的 `tts-emotion-<driverID>.json` 合法加载。

- **Step B6：回写选型结论与附录、清理失败实验代码并跑全量门禁**
  - 改动文件：`specs/003-m2-voice-conversation/research.md`、`specs/003-m2-voice-conversation/contracts/realtime-session.md`（按需修订 `docs/tech-selection.md`）
  - 改动要点：
    1. 按 §5.4 清理验证彻底失败/放弃的实验代码，**保留全部已跑通可用的候选驱动**及其映射 JSON、脱敏夹具与测试；
    2. 将完整量化实测表（V4 只出文字、V5 语气组通过数、首个文字耗时 p50、V6 情绪可辨数、TTS 首包 p50、V7 用户转写、是否含字级时间戳）与选型结论（主力组合 + 可切换备选组合 + 方案 B/C 判定理由）写入 `specs/003-m2-voice-conversation/research.md`；
    3. 将保留驱动的协议摘要填入 `specs/003-m2-voice-conversation/contracts/realtime-session.md` 附录（不含任何密钥）；
    4. 若实测数据推翻 `docs/tech-selection.md` 既有结论，按宪章同步修订并记录修订日志；
    5. 运行 §7.3 全部门禁命令，并按 `AGENTS.md` 走 `task-review-loop` 独立复审闭环后再向用户汇报验收（**验收确认前严禁 commit 或勾选 `tasks.md`**）。
  - 最小验证命令：见 §7.3 完整门禁命令清单。

---

### 7. 确定性测试矩阵与验收门禁

#### 7.1 离线确定性测试矩阵（严禁非确定性断言、严禁依赖真网）

| 目标测试文件 | 覆盖类别 | 测试场景 | 必须写死的断言底线（禁止弱断言） |
| :--- | :--- | :--- | :--- |
| `MMConversationTests/RealtimeDecodingTests.swift` | 正例 / 回放（RS-5） | 从 `Bundle.module` 加载每个保留实时驱动的 `Fixtures/<driverID>-sample.jsonl` 执行离线回放 | 成功解码为非空 `[RealtimeOutput]`，精确包含 `.speechStarted`、`.speechEnded`、至少 1 条 `.textDelta` 与 `.responseDone`；拼合文字经 `TagParser` 可解析出标签；`unexpectedAudioCount == 0`（对达标方案） |
| `MMConversationTests/RealtimeDecodingTests.swift` | 正例 / 审计（V4 / RS-3） | 注入合成服务端音频事件帧与未知事件类型帧 | 音频事件帧使 `unexpectedAudioEventCount` 精确 `+1` 且不产出 `.textDelta`；未知事件类型静默忽略且记入 `ignoredTypes`，不抛错不中断流 |
| `MMConversationTests/RealtimeDecodingTests.swift` | 边界（采样率 / 控制消息） | 向需重采样的实时驱动发送 16 kHz `AudioChunk`，调用 `cancelResponse()` 与 `clearInputBuffer()` | 捕获发往 Mock `WebSocketConnection` 的帧，验证上行载荷长度匹配目标采样率且发出精确的取消/清缓冲控制帧 |
| `MMConversationTests/RealtimeDecodingTests.swift` | 异常反例（RS-1 / RS-4） | 未连接或 `close()` 后调用 `send(_:)`；Mock Transport 模拟 HTTP 401/403、HTTP 429、异常断线且错误含密钥文本；`deinit` 释放 | 未连接/已关闭 `send(_:)` 精确抛 `RealtimeError.notConnected`；401/403 精确映射 `.authFailed`，429 映射 `.rateLimited`；断线错误消息**完全不含**传入密钥明文；未显式 `close()` 释放实例时 `output` 流正常结束不挂起 |
| `MMConversationTests/RealtimeDecodingTests.swift` | 脱敏安全（RS-1） | 扫描全部 `Fixtures/*.jsonl` 文件内容 | 不含 `"Bearer "` 非 `[REDACTED]` 明文、不含 `"sk-"` 密钥样式、不含未脱敏鉴权头名值、不含异常超长上行音频 base64 帧 |
| `MMConversationTests/RealtimeDecodingTests.swift` | 正例 / 边界（TTS-1–TTS-3 / TTS-6） | 加载每个保留 TTS 驱动的内置 `TTSEmotionMapping.loadBundled(for:)`；注入 Mock Transport 模拟分片奇数字节流式 PCM（含可选时间戳）与空句输入 | `loadBundled` 返回非空 `voice` 且包含 `.neutral`；同一实例合成不同 `EmotionTag` 时请求载荷中音色始终等于同一 `voice`（TTS-1）而情感参数按映射变化（TTS-2）；奇数字节跨帧经 `PCMByteAligner` 还原精确采样值；空句产出 0 块且发起 0 次网络请求 |
| `MMConversationTests/RealtimeDecodingTests.swift` | 异常反例（TTS-4 / TTS-5） | Mock Transport 模拟上游失败（带密钥错误文本）与合成中途调用 `cancelAll()` | 上游失败抛 `TTSError.synthesisFailed` 且错误文本不含密钥明文；`cancelAll()` 返回后已取消流不再产出任何后续 `AudioChunk`，且新发起的 `synthesize` 请求正常完成 |
| `MMConversationTests/ProviderInfrastructureTests.swift` | 兼容回归 | `ProviderRegistry.makeDefault()` 注册表查询、自定义驱动注册、错误守卫与 5 个 CLI 子命令离线端到端 | `descriptors` 包含 `"mock-realtime"`、`"mock-tts"` 及全部保留的云端驱动 ID；注册 `SecretRequiringRealtimeDriver` 后数量精确 `+1`；既有重复 ID / 缺主凭证 / 未知驱动 / 错 role 与 5 子命令测试全部通过 |
| `MMConversationTests/FoundationalTests.swift` | 兼容回归 | 既有基础契约测试全集 | 全量通过，特别验证 `TTSEmotionMapping.loadBundled(for: "mock-tts")` 仍精确抛 `.resourceNotFound("mock-tts")` |

#### 7.2 联网实测量化验收标准（V4–V7 / SC-001 / SC-002）

| 验收项 | 实测命令 | 达标门槛 | 记录位置 |
| :--- | :--- | :--- | :--- |
| **V4（只出文字）** | `mm-probe realtime` / `tone-suite` | `V4 Audio` 意外音频事件 = `0`，且确认无音频输出计费 | `research.md` M2a 对比表 |
| **V5 / SC-002（语气理解）** | `mm-probe tone-suite`（9 样本，3 组 × 3 语气） | ≥ 2/3 组的 `<user:…>` 与回答内容可辨识地不同，且记录首个文字耗时 p50 | `research.md` M2a 对比表 |
| **V6（情感 TTS）** | `mm-probe tts --all-emotions` | 同一音色下人工试听至少 4 种情绪可辨；首包 TTFB p50 < 500 ms；记录是否支持字级时间戳 | `research.md` M2a 对比表 + `Resources/tts-emotion-<driverID>.json` |
| **V7（用户转写）** | `mm-probe tone-suite` + 文档核实 | 明确记录“有 / 无”及命中率（`X/9`），供 004 记忆模块决策 | `research.md` M2a 对比表 |
| **SC-001（选型结论）** | 汇总 ≥ 2 家国内实测结果 | 明确写出主力组合、保留可切换备选组合、方案 B/C 判定与理由 | `research.md` 选型结论 + `contracts/realtime-session.md` 附录 |

#### 7.3 完整门禁命令清单

```bash
# 1. 目标新增与注册表单测
cd Packages/MiniMateKit && swift test --filter "RealtimeDecodingTests|ProviderInfrastructureTests|FoundationalTests"

# 2. 全量纯逻辑单元测试（须全部通过，且用例总数 > 190）
#    注：受限沙盒内请加 CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox
cd Packages/MiniMateKit && swift test

# 3. CLI 驱动发现冒烟（确认保留的云端驱动与内置 mock 均可见）
cd Packages/MiniMateKit && swift run mm-probe list-drivers

# 4. iOS App 模拟器无签名编译（验证 iOS 平台下 MMConversation / App 零编译错误与并发告警）
xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# 5. 静态安全与隐私红线扫描（覆盖未跟踪文件：严禁密钥明文、严禁跟踪个人语音样本、严禁绕过 Transport 裸建 URLSession）
grep -rnE "sk-[A-Za-z0-9_\-]{8,}|Bearer [A-Za-z0-9._\-]{8,}" \
  Packages/MiniMateKit/Sources Packages/MiniMateKit/Tests specs/003-m2-voice-conversation/ || true
grep -rn "URLSession(" Packages/MiniMateKit/Sources/MMConversation/Realtime Packages/MiniMateKit/Sources/MMConversation/TTS || true
git ls-files Assets/voice-samples/

# 6. 仓库状态校验（确认无个人语音、无临时输出、无越界改动）
git status
```

> **验收前强制流程**：上述命令全部绿灯后，实施方**必须**按 `task-review-loop` skill 完成独立只读复审闭环，确认无未解缺陷后再向用户汇报验收（含 `research.md` 实测汇总表与全套门禁证据）。

---

### 8. 项目附加产出要求

1. **实时协议附录回写**：更新 `specs/003-m2-voice-conversation/contracts/realtime-session.md` 文末附录，记录全部保留实时驱动的真实 Endpoint、鉴权方式、模型名、纯文本配置、输入音频格式、VAD、取消消息与用户转写事件。
2. **M2a 实测与选型结论回写**：更新 `specs/003-m2-voice-conversation/research.md` 的「M2a 厂商对比」表与「选型结论」（含主力组合、可切换备选组合与方案 B/C 判定）。
3. **情感映射资源落盘**：为每个保留的 TTS 驱动提交经试听校准的 `Packages/MiniMateKit/Sources/MMConversation/Resources/tts-emotion-<driverID>.json`。
4. **选型文档按需同步**：若实测数据推翻 `docs/tech-selection.md`（v3.7）中的结论，同步修订并追加附录 B 修订记录。
5. **验收收口同步条目（待用户明确确认验收后执行）**：
   - 更新 `docs/CODEBASE_MAP.md` §1 `MMConversation` 模块条目（补列保留的云端驱动与情绪映射资源）；
   - 更新 `docs/HANDOFF_LEDGER.md` §2（若有新实测协议陷阱）与 §3 近期关键契约变更；
   - 更新 `specs/003-m2-voice-conversation/tasks.md` Phase 3 对应任务状态（注明按多配置保留策略调整原 T025）。

---

### 9. 实施方偏差止损规则（固定条款）

- **可自决微调**：驱动内部私有辅助类型/变量命名、JSON 编解码内部结构拆分、注释与代码格式化（不改变对外协议签名、脱敏红线与测试预期）。
- **必须立即停工上报（严禁擅自绕过）**：
  1. Stage A 调研尚未获用户明确拍板，或环境变量尚未由用户配置就绪；
  2. 选定的候选 TTS **仅提供 HTTP 原始二进制流**（需要扩展 `HTTPStreamingTransport`）或选定实时协议使用非标准文本字段上传音频（需要扩展 `RecordingWebSocketTransport.defaultOutboundFilter`），确需修改 3a 通用传输层；
  3. 发现既有接口签名/契约与仓库现状冲突，或需要修改 §4.1 文件改动表之外的文件（尤其是 `MMSecurity`、`SettingsView`、`MMProbeCore`）；
  4. 需要改写既有测试的预期断言（除 §4.1 明确授权的 `ProviderInfrastructureTests.swift:108-109, 118` 三行外）；
  5. 需要放宽安全、脱敏、隐私（含开发/Debug 隐私红线）或零第三方依赖红线；
  6. 实测所有候选均未达到 V4 或 V5（SC-002）门槛，需用户决定是否调整指令复测或转入方案 C（US7）。

---

## 复审闭环记录（实施后由 task-review-loop 追加）
<!-- 留空，待实现完成后由 task-review-loop 写入每轮复审结果、验收证据与验收收口台账待办 -->
