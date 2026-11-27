# 002-m1-presence Phase 8: Polish（T048–T050）执行单

- **状态**：已完成并验收收口
- **Git 基线**：`main` @ `55d5f40`
- **关键基线**：Swift 6.4（`swiftlang-6.4.0.34.1`）/ Xcode 27.0（`27A266a`）/ macOS 27.2.0 / 参考真机 iPhone 16 Pro Max（`iPhone17,2`，国行 CH/A，iOS 27.2）/ 现行单测基线 **138/138（23 suites）** / 打包资产 `App/MiniMate/Resources/Avatar/minimate.usdz`（13 MB，39,032 三角面）+ `minimate.actions.json`（651 B）
- **拍板决议摘要**：全按推荐项 `1A 2A 3A 4A` 拍板定稿（防自动锁屏永久绑定于 `AvatarScreen` 形象页活跃期，退页/退后台自动恢复；下篇已为无条件分支终态，无需修订正文）

> **红线声明**
> - 严禁违反 `.specify/memory/constitution.md` 核心原则：陪伴而非镜像（除视线外禁止绕过状态机驱动渲染）、感知在本地永不经 LLM、度量先于假设（验收报告必须给出实测 p50/p90，禁止估算或编造数据）、纯逻辑测试先行（`MMCore` 新增纯逻辑须先写 Swift Testing 用例）、不引入第三方依赖。
> - 严禁读取、修改或上传 `Assets/voice-samples/*.wav`；严禁修改只读原始参考素材 `Assets/avatar/VRoid_V110_Female_v1.1.3.vrm`、`Assets/avatar/reference/`；严禁移动、重命名或删除 `docs/handoffs/` 下的历史执行单；API Key 绝不入仓、不写入日志或测试夹具。
> - 设计阶段仅创建本执行单，严禁改动任何业务代码、测试、配置或任务清单；实施完成后须先通过 `task-review-loop` 独立复审闭环，且**未经用户明确确认验收，严禁勾选 `tasks.md` / `quickstart.md` 清单、严禁 `git commit`、严禁 `git push`**。

---

## 上篇：面向用户决策

### 1. 任务目标与选择理由
- **本次任务**：完成 `002-m1-presence` Phase 8: Polish（`T048`、`T049`、`T050`），实现 M1 里程碑闭环——补齐真机 10 分钟稳定性观测与防自动锁屏、完成 SC-006（10 分钟帧率/内存/热状态/人脸追踪连续性）与 SC-007（主观验收）以及历次 US2–US5 缺口量化指标的真机实测采集、将完整 M1 实测数据回写 `specs/002-m1-presence/research.md`，并对照实测结论修订 `docs/tech-selection.md`（升至 v3.7）。
- **选择理由**：`002-m1-presence` Phase 1–7（`T001`–`T047`，含 `T012a`、`T044a`）已全部 `[x]` 完成，收尾 `T048`–`T050` 即可完整闭环 M1 里程碑（`003-m2-voice-conversation` 与 `005-voice-photo` 延后）。经逐项核验前置依赖，全量单测 `138/138` 通过、真机 3D 资产与部署脚本就位，**无前置依赖缺失或阻断冲突**。
- **摸底关键发现**：
  1. **10 分钟真机压测（SC-006）存在 3 处观测与运行缺口**：① App 内目前完全没有 FPS、物理内存（`task_vm_info.phys_footprint`）、热状态变迁时间线及 `ARSession` 中断次数统计（仅 `AvatarScene` 暴露瞬时 `thermalState`），若用 `./scripts/deploy-ios.sh` 脱离 Xcode 运行无法看 Debug Navigator，挂 Xcode 人工盯 10 分钟也难以准确采集 FPS 分布与完整热轨迹；② 全仓未设置 `UIApplication.shared.isIdleTimerDisabled`，支架免触屏运行 10 分钟大概率触发系统自动熄屏锁屏导致 `ARSession` 中断；③ `ARKitPerceptionSource` 的 12 Hz Vision 推理闭包缺少显式 `autoreleasepool`，10 分钟累计约 7,200 次 `VNImageRequestHandler` 调用值得补上零风险释放保护。
  2. **`specs/002-m1-presence/research.md` 存在多项定量数据缺口，且历史 `M_track` 导出值曾未达标**：当前 `research.md` 中 SC-002（`M_track` p50/p90）与 SC-003（`M_reflex` 命中率与 p50/p90）均标“待补填”、SC-004 缺真机精确 `|r|`、SC-005 缺 10 次定量计数与 1 分钟误触数、US5 与 `M_feedback` 完全缺行、SC-006 待填、SC-007 缺失；另仓内 2026-11-25 历史导出文件 `debug/指标-E284638ACD60-1.txt` 显示早期 `M_track` 为 `p50=102.7 ms / p90=204.8 ms`（略超 `< 100 ms / < 150 ms` 门槛），必须在当前合入 US3–US5 后的同一稳定版本上重新量化验证。
  3. **`docs/tech-selection.md`（v3.6）有明确的 M1 实测回写与格式修补需求**：§9.2 待验证表因 M0 实测段落穿插导致 V4–V12 表格断裂；V10 仍挂待测未回写已通过结论；M1 实测推翻/修正了多项早期假设（多动作改单条 `SkelAnimation` 时间线 + `actions.json` + 运行时 `trimmed` 裁剪、头部改 `ModelEntity.jointTransforms` 直驱、MToon→PBR 调灯光/贴图即可满足暂无需 `ShaderGraphMaterial`、ARKit 键名 `_L`/`_R` 规范化、单/双手比心规则法达标、D5 阈值实测下调）。
  4. **台账纠偏**：`HANDOFF_LEDGER.md` §1 所记 `AvatarScene.canMeasureTrackLatency 可按需追加 && !isDebugPanelPresented` 经源码核实**早已实现**（`AvatarScreen.swift:111-113`）；`issue-001`（偶发左下低头）可在 10 分钟压测中自然观测，若复现直接用内置「录制感知」抓 20 s JSONL 取证。

### 2. 待用户拍板的决策清单

1. **SC-006（10 分钟稳定性压测）的观测方式与 App 内轻量化遥测范围**
   - **1A（推荐）**：在 `MMCore` 按测试先行新增纯逻辑 `StabilitySessionRecorder` + `ProcessMemory`（1 Hz 读取 `task_vm_info.phys_footprint`），在 `ARKitPerceptionSource` 补齐 `sessionInterruptionCount` 与 Vision `autoreleasepool`，在 `AvatarScreen` / `AvatarDebugPanel` 接入防自动锁屏（`isIdleTimerDisabled`）、10 分钟一键压测、顶部运行态轻量胶囊与 Markdown/CSV 一键导出。可脱机直跑（零调试器开销）并能与 Xcode Debug Navigator 同源交叉比对。
   - **1B**：零业务代码改动（靠手动将手机系统“自动锁定”临时改为“永不”），全程连线 Xcode ⌘R 挂机 10 分钟人工抄录 Debug Navigator 的 FPS/内存与调试面板热状态。
     - *差量：若选 1B，需删除下篇 §4.1 中全部 Swift 源码与测试文件条目（`StabilitySessionRecorder.swift`、`StabilitySessionRecorderTests.swift`、`ARKitPerceptionSource.swift`、`AvatarScreen.swift`、`AvatarDebugPanel.swift`），将 §5 精简为 §5.4–§5.5 文档与实测口径契约，§6 删除 Step 1–Step 4 直接从真机压测与文档回写开始，§7.1 仅保留既有 138 项单测回归校验，§8 删除 `CODEBASE_MAP.md` 新增设施条目。*

2. **历次 US2–US5 缺口定量数据（SC-002 / SC-003 / SC-004 / SC-005 / US5 `M_feedback`）的补齐口径**
   - **2A（推荐）**：本次真机收尾在同一稳定版本上统一执行“US2–US5 量化补采（约 5 分钟）+ SC-006 10 分钟压测 + SC-007 主观验收”，补齐 `specs/002-m1-presence/research.md` 中全部缺失的精确 p50/p90、命中率、`|r|` 与手势计数（严格满足宪章 III）。
   - **2B**：仅执行 T048（SC-006 10 分钟压测）与 SC-007 主观验收，SC-002/SC-003/SC-004/SC-005 维持 `research.md` 现有的定性通过记录，不重跑补采。
     - *差量：若选 2B，需调整下篇 §5.4 将 SC-002/SC-003/SC-004/SC-005 改为“保留既有定性结论”，§6 Step 5 删除“阶段 1：US2–US5 量化补采”子步骤，仅保留 SC-006 10 分钟压测与 SC-007 主观评语采集。*

3. **T050 对 `docs/tech-selection.md`（升至 v3.7）的修订深度**
   - **3A（推荐）**：精准回写 M1 实测事实与 V10 验证结论、修复 §9.2 表格断裂、同步 §2.2 热约束 / §4.1 / §4.2 / §4.11 与附录 B；第 5 章仅在顶部补充 1 行说明“本章为选型期概念草图，现行准确签名以 `specs/*/contracts/` 为准”，不逐行重写第 5 章代码段（避免与 `specs/` 双处维护漂移）。
   - **3B**：除 3A 全部改动外，同步重写 `docs/tech-selection.md` 第 5 章接口草图代码以完全匹配当前真实源码签名。
     - *差量：若选 3B，需在下篇 §5.5 追加“第 5 章全部协议/结构体/枚举代码段逐字段对齐 `PerceptionSource`、`PerceptionFeatures`、`ConversationEvent`、`EmotionStateMachine`、`AvatarRenderer` 现行定义”，并在 §6 Step 6 增加第 5 章代码段编译/符号核对项。*

4. **T048 / 复测出现不达标（如 FPS < 55、内存 ≥ 1 GB、`M_track` 超标、或复现 `issue-001`）时的处置边界**
   - **4A（推荐）**：遵循宪章 III“度量先于假设”——本轮不提前降画质/降面数/降手势默认频率；若真机实测出现 SC-006 或 SC-002 未达标（或复现 `issue-001`），**立即停工并附实测报告/JSONL 证据上报**，由用户拍板定向优化方案后再实施。
   - **4B**：预授权实施方在真机不达标时自动执行轻量运行时优化（如手势默认频率 12 Hz → 10 Hz、合并 `perceptionTask` 与 `tick()` 重复 `pose(at:)`、或微调 `OneEuroFilter3D` 参数）并复测，仅在需要修改 `minimate.usdz` 贴图/面数时停工上报。
     - *差量：若选 4B，需调整下篇 §4.1（预开放 `AvatarScreen.swift` 帧同步合并与 `ARKitPerceptionSource.swift` 滤波/默认帧率微调权限）及 §9 偏差止损规则（将“手势默认帧率/帧同步轻量调优”移出停工条件，仅保留 3D 资产修改与测试预期修改为停工条件）。*

---

## 下篇：面向实施方的零歧义施工图

### 3. 现状锚点与环境陷阱预警

#### 3.1 现有代码与文档锚点
| 模块/符号 | 精确位置 | 职责与复用/约束说明 |
| :--- | :--- | :--- |
| `MMCore.Clock` / `SystemClock` | `Packages/MiniMateKit/Sources/MMCore/MMCore.swift:4-18` | 统一时间抽象；源码与测试引用必须显式写 `any MMCore.Clock` |
| `LatencyRecorder` | `Packages/MiniMateKit/Sources/MMCore/Metrics/LatencyRecorder.swift:4-80` | `M_track` / `M_reflex` / `M_feedback` 采集与 nearest-rank 百分位口径；`StabilitySessionRecorder` 沿用同一 nearest-rank 算法与 CSV 转义风格 |
| `ThermalGesturePolicy` | `Packages/MiniMateKit/Sources/MMPerception/ThermalGesturePolicy.swift:4-33` | 热状态手势上限映射（`.nominal/.fair -> 15`, `.serious -> 5`, `.critical -> 0`, `@unknown -> 5`） |
| `ARKitPerceptionSource` | `Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift:16-660` | `#if os(iOS)` 隔离；`MutableState` 位于 `22-42`、`start()` 位于 `132-216`、`stop()` 位于 `218-250`、Vision `gestureQueue.async` 位于 `381-425`、`handleSessionWasInterrupted` 位于 `472-491`；全仓仅 `AppComposition.swift:24` 与 `AvatarScreen.swift:411` 直接引用 |
| `AvatarScene` | `App/MiniMate/Screens/AvatarScreen.swift:11-980` | `@MainActor @Observable`；感知与热状态属性 `63-74`、`canMeasureTrackLatency` 已含 `!isDebugPanelPresented`（`111-113`）、`startPerception()` `237-303`、`stopPerception()` `305-332`、`handleBackground()` `334-367`、`setDebugPanelPresented(_:)` `369-371`、`handleIncomingFeatures(_:)` `400-446`、`tick()` `866-967` |
| `AvatarScreen` | `App/MiniMate/Screens/AvatarScreen.swift:982-1113` | 顶部状态胶囊 overlay 位于 `1023-1058`（参考 `isRunningMirrorCheck` 样式）；`isShowingDebugPanel` 切换回调 `1079-1084` |
| `AvatarDebugPanel` | `App/MiniMate/Screens/Debug/AvatarDebugPanel.swift:8-691` | `Section("镜像检测（SC-004，30 s）")` 位于 `256-322`、`Section("指标（M_track / M_reflex / M_feedback）")` 位于 `356-382`；`formatThermalRate` 位于 `662-674` |
| `DiagnosticsView` | `App/MiniMate/Screens/DiagnosticsView.swift:48-56` | `ShareLink(item: report.markdown())` 导出范式参考 |
| `specs/002-m1-presence/research.md` | `specs/002-m1-presence/research.md:1-71` | D1–D3「需确认」(`12, 18, 26`)、待实测表 (`49-55`)、实测结果表 (`57-71`，其中 `66, 67, 70` 为待补填，缺失 US5 与 SC-007 行) |
| `specs/002-m1-presence/quickstart.md` | `specs/002-m1-presence/quickstart.md:47-68` | 第六节 SC-006 流程与验收清单（验收确认前严禁勾选） |
| `docs/tech-selection.md` | `docs/tech-selection.md:1-504` | v3.6；需更新行：`1, 5`（版本/状态）、`45`（热约束）、`81-91`（感知层）、`93-125`（状态机）、`253, 258-264`（渲染与 V10）、`275`（第 5 章说明）、`415-439`（§9.2 表格修复 + V10 实测结论）、`492-504`（附录 B 升 v3.7） |
| `docs/issues/001-periodic-bottom-left-head-drop.md` | `docs/issues/001-periodic-bottom-left-head-drop.md:62-81` | 偶发左下低头取证指南与处置记录 |
| `scripts/deploy-ios.sh` | `scripts/deploy-ios.sh:1-160` | 支持 `--configuration Debug|Release` 真机一键构建、安装与启动 |

#### 3.2 环境与第三方依赖实测陷阱
- **Swift 6.4 `Darwin.task_info` + `mach_task_self_` 严格并发实测**：已在当前工具链（Swift 6.4，`-swift-version 6 -warnings-as-errors`）实测通过 `task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)` 读取 `info.phys_footprint`，零警告、零错误，与 Xcode Debug Navigator Memory Gauge 同源。
- **沙盒内 `swift test` Clang Module Cache 权限**：沙盒执行 `swift test` 默认缓存目录不可写 → 必须带环境变量 `CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox`（常规本机终端直接 `swift test`）。
- **Swift 6.4 `Swift.Clock` 命名冲突**：所有新增/修改代码引用时钟协议必须显式写 `any MMCore.Clock`，严禁裸写 `any Clock`。
- **Swift 6 `@MainActor` 类 `deinit` 隔离限制**：`AvatarScene` 为 `@MainActor final class`，严禁在 `deinit` 中直接访问 `UIApplication.shared.isIdleTimerDisabled`（会触发 Swift 6 并发隔离报错）→ 必须严格在 `startPerception()`（开启）与 `stopPerception()` / `handleBackground()`（关闭）成对维护。
- **全屏 `AvatarDebugPanel` 推入时底层 `RealityView` `tick()` 暂停**：打开调试面板启动压测或中途查看面板时 `tick()` 暂停数秒，若直接按墙钟间隔除帧数会污染产生假 0 fps → 必须在 `setDebugPanelPresented(_:)` 中调用 `stabilityRecorder.pause(at:)` / `resume(at:)`，且 `startStabilityTest()` 在面板打开态启动后立刻 `pause(at:)`，返回主界面后自动恢复计数。
- **R-5 主线程预算（`apply` < 2 ms）**：`ProcessMemory.physicalFootprintMB()` 属于 Mach 内核调用，严禁在 60 Hz `tick()` 每帧调用 → `recordFrame` 必须通过惰性闭包 `memoryMBProvider` **仅在每秒产出 1 条采样时调用 1 次（1 Hz）**，且 `@Observable` 压测 UI 属性仅在 1 Hz 采样落地时刷新，避免 60 Hz SwiftUI 重绘。
- **`ARKitPerceptionSource` 仅限 iOS 编译**：该文件被 `#if os(iOS)` 包裹，macOS `swift test` 不编译它 → 改动后必须运行 `xcodebuild -scheme MMPerception -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` 与 App 模拟器无签名构建验证。

---

### 4. 改动范围表与明确不做清单（Non-Goals）

#### 4.1 文件改动表
| 文件路径 | 操作 | 精确职责 |
| :--- | :--- | :--- |
| `Packages/MiniMateKit/Tests/MMCoreTests/StabilitySessionRecorderTests.swift` | 新增 | 先行编写 `StabilitySessionRecorder` 与 `ProcessMemory` 的确定性 Swift Testing 单测（正例、边界、异常反例、暂停防污染、Markdown/CSV 输出） |
| `Packages/MiniMateKit/Sources/MMCore/Metrics/StabilitySessionRecorder.swift` | 新增 | 纯逻辑 SC-006 10 分钟稳定性聚合器（`StabilityThermalLevel`、`StabilitySample`、`ThermalTransition`、`StabilityReport`、`StabilitySessionRecorder`）与 `ProcessMemory`（`task_vm_info.phys_footprint`） |
| `Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift` | 微调 | 新增只读 `sessionInterruptionCount: Int`（`start()`/`stop()` 归零，`handleSessionWasInterrupted` 递增）；`gestureQueue.async` 内 Vision 推理与关节点提取套 `autoreleasepool` |
| `App/MiniMate/Screens/AvatarScreen.swift` | 修改 | 接入 `isIdleTimerDisabled` 成对管理、SC-006 10 分钟稳定性采样/中断计数/面板暂停恢复、`tick()` 1 Hz 采集与主界面顶部运行态轻量胶囊 |
| `App/MiniMate/Screens/Debug/AvatarDebugPanel.swift` | 修改 | 新增 `Section("稳定性压测（SC-006，10 分钟）")`：启停控制、实时值、SC-006 判定与摘要、Markdown/CSV `ShareLink` 导出与清空 |
| `specs/002-m1-presence/research.md` | 修改 | 清除 D1–D3 与待实测表过时「需确认」、补齐 SC-001–SC-007 与 US5（含 `M_track`、`M_reflex`、`M_feedback` 精确 p50/p90、SC-004 真机 `|r|`、SC-005 定量计数、SC-006 10 分钟实测、SC-007 主观评语）及冷却默认值差异说明 |
| `docs/tech-selection.md` | 修改 | 升至 v3.7：修复 §9.2 表格断裂、回写 V10 实测通过结论与管线/骨骼/材质修正、同步 §2.2/§4.1/§4.2/§4.11/§5 说明与附录 B 修订记录 |
| `docs/issues/001-periodic-bottom-left-head-drop.md` | 按需微调 | 10 分钟压测期间未复现时，仅在 §5 追加一条观察记录；若复现则停工取证上报 |

#### 4.2 明确不做清单（Non-Goals）
- **严禁修改 3D 资产与构建管线**：不动 `App/MiniMate/Resources/Avatar/minimate.usdz`、`minimate.actions.json` 及 `Assets/avatar/auto-build/scripts/*`（含 `validate_phase1.py` 仅校验第 15 帧的历史备忘，继续留待改动作轨道时处理）。
- **严禁修改 `PerceptionSource` / `EmotionStateMachine` / `AvatarRenderer` 协议与核心算法参数**：不提前改 `OneEuroFilter3D`、`FaceSignalDeriver`、`HandGestureClassifier`、`RuleBasedEmotionStateMachine`、`RealityKitAvatarRenderer` 逻辑或默认手势频率（先度量再决策）。
- **严禁顺手重构无关代码**：不做 `AvatarDebugPanel` 表情预设导出 JSON 缓存（对主界面零影响）；不重写 `docs/tech-selection.md` 第 5 章接口草图代码。
- **严禁触碰 003 / 004 / 005 源码或规格文件**，严禁修改 `debug/` 既有文件或历史执行单 `docs/handoffs/*.md`。
- **验收确认前严禁改动追踪与台账文件**：未经用户明确确认验收，不得勾选 `specs/002-m1-presence/tasks.md`、`specs/002-m1-presence/quickstart.md`，不得更新 `docs/CODEBASE_MAP.md` / `docs/HANDOFF_LEDGER.md`，不得 `git commit` / `git push`。

---

### 5. 精确接口与行为契约

#### 5.1 `ProcessMemory` 与 `StabilitySessionRecorder`（`MMCore`）
- **位置**：`Packages/MiniMateKit/Sources/MMCore/Metrics/StabilitySessionRecorder.swift`
- **精确签名**：
```swift
import Darwin
import Foundation

/// 当前进程物理内存查询工具（与 Xcode Debug Navigator Memory Gauge 同源）。
public enum ProcessMemory: Sendable {
    /// 读取 `task_vm_info.phys_footprint`（字节）；失败返回 `nil`。
    public static func physicalFootprintBytes() -> UInt64?

    /// 读取 `task_vm_info.phys_footprint`（MiB，`1 MiB = 1_048_576 bytes`）；失败返回 `nil`。
    public static func physicalFootprintMB() -> Double?
}

/// 平台无关的热状态档位（可比较、可序列化）。
public enum StabilityThermalLevel: String, CaseIterable, Sendable, Codable, Equatable, Comparable {
    case nominal
    case fair
    case serious
    case critical

    public init(_ state: ProcessInfo.ThermalState)
    public static func < (lhs: StabilityThermalLevel, rhs: StabilityThermalLevel) -> Bool
}

/// 单个聚合采样点（默认每秒 1 条）。
public struct StabilitySample: Sendable, Equatable {
    public let elapsed: TimeInterval
    public let fps: Double
    public let memoryMB: Double
    public let thermalLevel: StabilityThermalLevel
    public let effectiveGestureRateHz: Double
    public let isFaceTracked: Bool

    public init(
        elapsed: TimeInterval,
        fps: Double,
        memoryMB: Double,
        thermalLevel: StabilityThermalLevel,
        effectiveGestureRateHz: Double,
        isFaceTracked: Bool
    )
}

/// 热状态变迁事件（初始基线记录 `from == nil`）。
public struct ThermalTransition: Sendable, Equatable {
    public let elapsed: TimeInterval
    public let from: StabilityThermalLevel?
    public let to: StabilityThermalLevel

    public init(elapsed: TimeInterval, from: StabilityThermalLevel?, to: StabilityThermalLevel)
}

/// SC-006 稳定性压测汇总报告。
public struct StabilityReport: Sendable, Equatable {
    public static let minRequiredFps: Double = 55.0
    public static let maxAllowedMemoryMB: Double = 1024.0

    public let targetDuration: TimeInterval
    public let duration: TimeInterval
    public let sampleCount: Int
    public let avgFps: Double
    public let p50Fps: Double
    public let p10Fps: Double
    public let minFps: Double
    public let avgMemoryMB: Double
    public let maxMemoryMB: Double
    public let peakThermalLevel: StabilityThermalLevel
    public let thermalTransitions: [ThermalTransition]
    public let thermalDurationSeconds: [StabilityThermalLevel: TimeInterval]
    public let sessionInterruptionCount: Int
    public let thermalSessionInterruptionCount: Int
    public let faceTrackedRatio: Double

    public var passedDuration: Bool { duration + 1e-9 >= targetDuration }
    public var passedFps: Bool { sampleCount > 0 && avgFps >= Self.minRequiredFps && p10Fps >= Self.minRequiredFps }
    public var passedMemory: Bool { sampleCount > 0 && maxMemoryMB < Self.maxAllowedMemoryMB }
    public var passedThermalTracking: Bool { thermalSessionInterruptionCount == 0 }
    public var passed: Bool { passedDuration && passedFps && passedMemory && passedThermalTracking }

    /// 可直接粘贴至 `specs/002-m1-presence/research.md` 的 Markdown 汇总文本。
    public func summaryMarkdown() -> String

    /// 逐秒明细 CSV：`elapsed_s,fps,memory_mb,thermal_state,gesture_hz,face_tracked\n`。
    public func csv() -> String
}

/// 纯逻辑 SC-006 稳定性采样聚合器（无时钟/UI 依赖，由调用方注入时间戳）。
public struct StabilitySessionRecorder: Sendable {
    public let targetDuration: TimeInterval
    public let sampleInterval: TimeInterval
    public let maxSamples: Int

    public private(set) var isRunning: Bool
    public private(set) var isPaused: Bool
    public private(set) var elapsed: TimeInterval
    public private(set) var samples: [StabilitySample]
    public private(set) var thermalTransitions: [ThermalTransition]
    public private(set) var sessionInterruptionCount: Int
    public private(set) var thermalSessionInterruptionCount: Int
    public var latestSample: StabilitySample? { samples.last }

    public init(
        targetDuration: TimeInterval = 600.0,
        sampleInterval: TimeInterval = 1.0,
        maxSamples: Int = 3600
    )

    public mutating func start(
        at timestamp: TimeInterval,
        initialThermalLevel: StabilityThermalLevel = .nominal
    )

    /// 暂停采样计时（例如打开全屏调试面板时），丢弃当前未满窗口的局部帧计数，防止恢复后产生假 0 fps。
    public mutating func pause(at timestamp: TimeInterval)

    /// 恢复采样计时，下一帧 `recordFrame` 重新锚定采样窗口起点。
    public mutating func resume(at timestamp: TimeInterval)

    /// 每帧渲染回调调用；仅在达到 `sampleInterval` 时调用一次 `memoryMBProvider` 并产出 `StabilitySample`。
    @discardableResult
    public mutating func recordFrame(
        at timestamp: TimeInterval,
        thermalLevel: StabilityThermalLevel,
        effectiveGestureRateHz: Double,
        isFaceTracked: Bool,
        memoryMBProvider: () -> Double?
    ) -> StabilitySample?

    /// 记录一次 `ARSession` 被系统中断的事件；若中断发生时 `thermalLevel >= .serious`，同时计入 `thermalSessionInterruptionCount`。
    public mutating func recordSessionInterruption(
        at timestamp: TimeInterval,
        thermalLevel: StabilityThermalLevel
    )

    /// 生成当前实时快照报告（不改变运行状态）。
    public func makeReport() -> StabilityReport

    /// 结束本次压测并返回最终报告。
    public mutating func finish() -> StabilityReport

    /// 重置全部状态与已收集样本。
    public mutating func reset()
}
```
- **复用与算法约束**：
  - `StabilityThermalLevel.init(_ state:)`：`@unknown default` 映射为 `.serious`（与 `ThermalGesturePolicy.maxRate` 保持保守一致）。
  - 百分位计算沿用 `LatencyRecorder.percentile` 的 nearest-rank 公式：`rank = Int((p * Double(sorted.count)).rounded(.up))`，`index = min(max(rank - 1, 0), sorted.count - 1)`。`p10Fps` 取 `p = 0.10`，`p50Fps` 取 `p = 0.50`。
  - `init` 参数防御：`targetDuration` 非有限或 `< 1.0` 时按 `600.0`（有限 `< 1.0` 夹紧至 `1.0`）；`sampleInterval` 非有限按 `1.0`（有限 `< 0.2` 夹紧至 `0.2`）；`maxSamples` 夹紧至 `>= 1`。
  - `start(at:initialThermalLevel:)`：若 `!timestamp.isFinite` 则静默返回且保持未运行；否则清空历史状态、`isRunning = true`、`isPaused = false`、`elapsed = 0`、记录初始 `ThermalTransition(elapsed: 0, from: nil, to: initialThermalLevel)`，并置 `lastThermalLevel = initialThermalLevel`。
  - `recordFrame` 边界与防御：
    - 未运行（`!isRunning`）、已暂停（`isPaused`）或 `!timestamp.isFinite`：直接返回 `nil` 且**不调用 `memoryMBProvider`**；
    - 窗口未锚定（首次调用或刚 `resume`）：设置 `windowStartAt = timestamp`、`lastFrameAt = timestamp`、`windowFrameCount = 0`，检查热状态变迁后返回 `nil`（不调用 `memoryMBProvider`）；
    - 时间回退（`timestamp < lastFrameAt`）：忽略并返回 `nil`；
    - 正常推进：`dt = timestamp - lastFrameAt`、`elapsed += dt`、`lastFrameAt = timestamp`、`windowFrameCount += 1`、检查热状态变迁（若 `thermalLevel != lastThermalLevel` 则追加 `ThermalTransition(elapsed: elapsed, from: lastThermalLevel, to: thermalLevel)` 并更新 `lastThermalLevel`）；
    - 当 `let windowDuration = timestamp - windowStartAt`, `windowDuration + 1e-9 >= sampleInterval`：
      - 调用 `memoryMBProvider()`，取非有限/负值兜底为 `0.0`；`effectiveGestureRateHz` 非有限/负值兜底为 `0.0`；
      - `fps = Double(windowFrameCount) / windowDuration`；
      - 累加 `thermalDurationSeconds[thermalLevel, default: 0] += windowDuration`；
      - 构造 `StabilitySample`；若 `samples.count < maxSamples` 则追加；重置 `windowStartAt = timestamp`、`windowFrameCount = 0`，返回该 `StabilitySample`。
  - `recordSessionInterruption`：仅 `isRunning && !isPaused && timestamp.isFinite` 生效；先检查热状态变迁，再 `sessionInterruptionCount += 1`，若 `thermalLevel >= .serious` 则 `thermalSessionInterruptionCount += 1`。
  - 空样本报告：`sampleCount == 0` 时所有 FPS/内存/占比字段为 `0.0`（绝不出现 `NaN` / `Infinity`），`passed == false`。
  - `StabilityReport` 须持有 `samples`（或生成 CSV 所需内部存储）以便 `csv()` 输出完整逐秒明细；`Equatable` 比较所有公开指标字段。
  - `summaryMarkdown()` 必须包含：判定结果（通过/未通过）、时长、样本数、FPS（avg / p50 / p10 / min）、内存（avg / max MiB）、热状态峰值与变迁轨迹、ARSession 中断（总计 / 热降频态）、人脸追踪占比。
- **兼容性约束**：纯新增文件，零影响 `LatencyRecorder` 及既有 138 项单测。

#### 5.2 `ARKitPerceptionSource` 轻量增强（`MMPerception`）
- **位置**：`Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift`（`#if os(iOS)` 内）
- **精确新增**：
  1. `MutableState`（`41` 行后）新增 `var sessionInterruptionCount: Int = 0`；
  2. 只读计算属性（`114` 行后）：
     ```swift
     /// 本次感知会话期间 `ARSession` 被系统中断的累计次数（供 SC-006 稳定性观测）。
     public var sessionInterruptionCount: Int {
         state.withLock { $0.sessionInterruptionCount }
     }
     ```
  3. `start()`（`202` 行）与 `stop()`（`237` 行）重置 `s.sessionInterruptionCount = 0`；
  4. `handleSessionWasInterrupted(_:)`（`476` 行）在 `guard` 之后递增 `s.sessionInterruptionCount += 1`；
  5. `gestureQueue.async`（`394-409` 行）中 Vision 请求创建、执行与关节点提取外层包裹 `autoreleasepool`：
     ```swift
     let handFrames: [HandPoseFrame]? = autoreleasepool {
         let request = VNDetectHumanHandPoseRequest()
         request.maximumHandCount = 2
         let handler = VNImageRequestHandler(
             cvPixelBuffer: boxedPixelBuffer.value,
             orientation: orientation,
             options: [:]
         )
         do {
             try handler.perform([request])
         } catch {
             return nil
         }
         return Self.extractHandFrames(from: request.results ?? [])
     }
     guard let handFrames else { return }
     ```
- **兼容性约束**：不改 `PerceptionSource` 协议、不改构造器与现有方法签名；`defer` 释放 `isVisionInFlight = false` 保持在 `autoreleasepool` 之外，失败路径语义与既有实现完全一致。

#### 5.3 `AvatarScene` / `AvatarScreen` / `AvatarDebugPanel` 接线与防锁屏契约
- **防自动锁屏（`App/MiniMate/Screens/AvatarScreen.swift`）**：
  - 顶部新增 `#if os(iOS)` `import UIKit` `#endif`；
  - `AvatarScene` 新增私有辅助方法：
    ```swift
    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
    ```
  - 生命周期配对：
    - `startPerception()` 成功建立 `perceptionTask` 后（`280` 行附近）调用 `setIdleTimerDisabled(true)`；
    - `stopPerception()`（`305` 行）与 `handleBackground()`（`334` 行）调用 `setIdleTimerDisabled(false)`；
    - 严禁在 `deinit` 中直接调用 `UIApplication.shared`。
- **SC-006 稳定性压测控制与 1 Hz 采样（`App/MiniMate/Screens/AvatarScreen.swift`）**：
  - `AvatarScene` 新增属性与方法：
    - `private(set) var isRunningStabilityTest: Bool = false`
    - `private(set) var stabilityElapsed: TimeInterval = 0`
    - `let stabilityTargetDuration: TimeInterval = 600.0`
    - `private(set) var stabilitySampleCount: Int = 0`
    - `private(set) var currentFps: Double = 0`
    - `private(set) var currentMemoryMB: Double = 0`
    - `private(set) var lastStabilityReport: StabilityReport?`
    - `func startStabilityTest()`、`func stopStabilityTest()`、`func clearStabilityTest()`
  - 行为约束：
    - `startStabilityTest()`：用 `clock.now.timeIntervalSinceReferenceDate` 与 `StabilityThermalLevel(thermalState)` 启动 `stabilityRecorder`；同步记录当前 `ARKitPerceptionSource.sessionInterruptionCount`（若非 ARKit 源为 `0`）至 `lastObservedSessionInterruptions`；若此时 `isDebugPanelPresented == true`，立即 `stabilityRecorder.pause(at: now)`；清空 `lastStabilityReport` 并归零 UI 显示值，`isRunningStabilityTest = true`。
    - `setDebugPanelPresented(_ presented: Bool)`：在 `isRunningStabilityTest == true` 时，推入面板（`true`）调用 `stabilityRecorder.pause(at: now)`，返回主界面（`false`）调用 `stabilityRecorder.resume(at: now)`。
    - `handleIncomingFeatures(_:)`：在 `#if os(iOS)` 分支比对 `arkitSource.sessionInterruptionCount` 与 `lastObservedSessionInterruptions`；若出现增量 `delta > 0`，当 `isRunningStabilityTest` 时循环 `delta` 次调用 `stabilityRecorder.recordSessionInterruption(at: features.timestamp, thermalLevel: StabilityThermalLevel(thermalState))`，并更新 `lastObservedSessionInterruptions`。
    - `tick()`：在 `renderer.apply(pose)` 之后，若 `isRunningStabilityTest && !isDebugPanelPresented`，调用 `stabilityRecorder.recordFrame(at: now, thermalLevel: StabilityThermalLevel(thermalState), effectiveGestureRateHz: effectiveGestureRateHz, isFaceTracked: isFaceTracked, memoryMBProvider: { ProcessMemory.physicalFootprintMB() })`；**仅在返回非 nil `sample` 时**更新 `currentFps`、`currentMemoryMB`、`stabilityElapsed`、`stabilitySampleCount`；若 `stabilityRecorder.elapsed + 1e-9 >= stabilityTargetDuration`，立即调用 `stopStabilityTest()`。
    - `stopPerception()` 与 `handleBackground()`：若 `isRunningStabilityTest`，调用 `stopStabilityTest()` 以保存已采集报告不丢数据。
  - `AvatarScreen` 顶部 overlay（`1023-1058` 行）：在 `isRunningMirrorCheck` 胶囊下方新增 `if scene.isRunningStabilityTest` 紧凑胶囊（显示 `稳定性 MM:SS / 10:00 · XX.X fps · XXX MB · <thermal>` 与 `[结束]` 按钮）。
- **调试面板分区（`App/MiniMate/Screens/Debug/AvatarDebugPanel.swift`）**：
  - 在 `Section("镜像检测（SC-004，30 s）")` 与 `Section("录制感知")` 之间（或紧邻「指标」分区之后）新增 `Section("稳定性压测（SC-006，10 分钟）")`：
    - 「开始 10 分钟压测」/「停止压测」按钮 + 进度（`MM:SS / 10:00 · N 采样`）；
    - 运行中提示文案：“返回主界面正常交互 10 分钟（屏幕自动保持常亮），满 10 分钟自动停止并生成报告。”；
    - 运行中或有样本时展示当前 FPS / 物理内存（MiB）/ 热状态与有效手势率；
    - `if let report = scene.lastStabilityReport` 展示通过/未通过徽章、时长、FPS（avg/p50/p10/min）、内存（avg/max MiB）、热状态峰值与变迁摘要、ARSession 中断（总计/热降频态）、人脸追踪占比、两个 `ShareLink`（「导出稳定性报告 (Markdown)」「导出逐秒明细 (CSV)」）与「清空压测结果」按钮。

#### 5.4 `specs/002-m1-presence/research.md` 事实口径契约（T049）
- **实测数据真实性铁律**：所有填表数值必须来自真实 iPhone 16 Pro Max 实测与导出结果，严禁估算、编造或沿用过时未达标数据。
- **必改项清单**：
  1. `D1`（12 行）、`D2`（18 行）、`D3`（26 行）的「需确认」改为已实测闭环说明并指向「实测结果」节；
  2. 「待实测项」表（49–55 行）全部 3 项补注 `✅ 已实测` 状态；
  3. 「实测结果」表（57–71 行）补齐并校验以下全部条目，同时在节首注明测试设备（`iPhone 16 Pro Max / iPhone17,2`）、系统版本与构建配置（`Debug` / `Release`）：
     - `SC-002 M_track p50/p90`：填入最新实测精确 `p50`、`p90`（ms）与样本数 `n`（验证 `p50 < 100 ms, p90 < 150 ms`）；
     - `SC-003 M_reflex 区间命中率`：填入最新实测 `p50`、`p90`（ms）与 300–800 ms 命中率 `xx.x% (hits/n)`（验证 `≥ 90%`，`n ≥ 10`）；
     - `SC-004 相关系数`：保留自动化回放结论，补填真机 30 s 实测 `maxAbsCorrelation`（含通道名）、`meanAbsCorrelation` 与帧数（验证 `|r| < 0.3`）；
     - `SC-005 手势准确率 / 误触发`：保留调优细节，补填定量尝试结果（挥手 `x/10`、比心 `x/10`、点赞 `x/10`、1 分钟日常动作误触发 `y` 次，验证均 `≥ 8/10` 且 `≤ 1` 次）；
     - **新增行 `US5 对话态与 M_feedback`**：记录 Listening → Thinking → `<user:sad>` → Speaking(gentle) → Attending、Speaking 期间微笑不打断、`assistantCue` EM-1–EM-5 及 `M_feedback` 精确 `p50` / `p90` / `n`（验证 `< 100 ms`）；
     - `SC-006 帧率 / 内存 / 温度`：填入 10 分钟实测 `avgFps` / `p50Fps` / `p10Fps` / `minFps`、`avgMemoryMB` / `maxMemoryMB`、`thermalState` 变迁时间线与各档位耗时、`effectiveGestureRateHz` 变化、`ARSession` 中断次数（总计 / 热降频态）、是否与 Xcode Debug Navigator 核对及 `issue-001` 观测结论；
     - **新增行 `SC-007 主观验收`**：如实记录用户在完整 quickstart 场景下的主观评价与验收结论；
     - `调参后的 D5 阈值`：补注 `ReactionRules.cooldown` 源码默认 `8 s` 与 App 调试面板默认 `5 s`（`3–8 s` 可调）的分工说明。

#### 5.5 `docs/tech-selection.md`（v3.6 → v3.7）修订契约（T050）
- **精确修改点**：
  1. Line 1 & Line 5：版本号升为 `v3.7`，文档状态补充 `v3.7 回写 M1（002）真机实测与 V10 验证结论`；
  2. Line 45（§2.2 硬约束 · 热）：补充 M1 视觉负载 10 分钟实测温控/帧率/内存结论摘要（指向 `specs/002-m1-presence/research.md`）；
  3. Line 81–91（§4.1 感知层）：补充 ARKit 真机 `BlendShapeLocation.rawValue` 返回 `_L`/`_R` 后缀须规范化映射；补充手势规则法已实测覆盖挥手、双手/单手比心与点赞并达成 SC-005（无需 CreateML 退路）；
  4. Line 93–125（§4.2 情绪状态机）：补充 M1 实测阈值/冷却注记（frown/surprise 下调至 0.38/0.22，App 默认冷却 5 s）与 005 增补的 `assistantCue` 非对话提示已落地；
  5. Line 253 & Line 258–264（§4.11 形象渲染）：移除 `BlendShapeWeightsComponent` 的「需确认」；将素材管线风险（V10）更新为已通过并明文记录三项实测修正（单条 `SkelAnimation` 时间线 + `actions.json` + 运行时 `trimmed` 裁剪；头部改 `ModelEntity.jointTransforms` 直驱消除闪烁；MToon→PBR 经灯光/贴图对比度调优已可用，暂无需 `ShaderGraphMaterial`）；
  6. Line 275（§5 接口设计节首）：新增 1 行说明“本章为选型期概念接口草图，现行准确契约（含跨平台 `rawBlendShapes` 字典、`pose(at:)` 按时间求值及 005 `assistantCue` 扩展）以 `specs/002-m1-presence/contracts/` 与 `data-model.md` 为准”；**不重写第 5 章 Swift 代码块**；
  7. Line 415–439（§9.2 待验证项）：**修复 V3 与 V4 之间的 Markdown 表格断裂**（让 V1–V12 保持一张连续完整的 Markdown 表格，将 M0 与 M1 实测结论统一移至表格下方以小节列出），并将 **V10** 标为 `✅ 已测` 并附实测结论摘要；
  8. Line 504 之后（附录 B 修订记录）：追加 `v3.7` 修订记录条目。

---

### 6. 原子化施工步骤（自底向上）

- **Step 1：测试先行——编写 `StabilitySessionRecorderTests`**
  - 改动文件：`Packages/MiniMateKit/Tests/MMCoreTests/StabilitySessionRecorderTests.swift`（新增）
  - 改动要点：按 §7.1 测试矩阵编写全部 Swift Testing 用例（正例、边界、异常反例、暂停防污染、1 Hz 惰性内存回调次数验证、热状态变迁与热中断判定、Markdown/CSV 格式断言），先运行确认编译失败（Red，符合宪章 V）。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter StabilitySessionRecorder
    ```

- **Step 2：实现 `ProcessMemory` 与 `StabilitySessionRecorder`**
  - 改动文件：`Packages/MiniMateKit/Sources/MMCore/Metrics/StabilitySessionRecorder.swift`（新增）
  - 改动要点：严格按 §5.1 实现全部类型、方法、边界防御、nearest-rank 百分位、`summaryMarkdown()` 与 `csv()`，使 Step 1 全部测试转绿（Green）。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter "StabilitySessionRecorder|LatencyRecorder"
    ```

- **Step 3：`ARKitPerceptionSource` 增加中断计数与 Vision `autoreleasepool`**
  - 改动文件：`Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift`（微调）
  - 改动要点：严格按 §5.2 增补 `sessionInterruptionCount` 与 `autoreleasepool`，不改协议与既有方法签名。
  - 最小验证命令：
    ```bash
    cd Packages/MiniMateKit && xcodebuild -scheme MMPerception -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
    ```

- **Step 4：`AvatarScreen` 与 `AvatarDebugPanel` 接线防锁屏与 SC-006 稳定性观测**
  - 改动文件：`App/MiniMate/Screens/AvatarScreen.swift`、`App/MiniMate/Screens/Debug/AvatarDebugPanel.swift`（修改）
  - 改动要点：严格按 §5.3 接入 `isIdleTimerDisabled` 成对维护、`StabilitySessionRecorder` 1 Hz 采样（`memoryMBProvider` 仅每秒触发一次）、面板推入暂停/返回恢复、中断增量采集、主界面顶部运行态胶囊与调试面板「稳定性压测（SC-006，10 分钟）」分区。
  - 最小验证命令：
    ```bash
    xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
    ```

- **Step 5：真机部署、全量量化补采（US2–US5）+ 10 分钟 SC-006 压测（T048）+ SC-007 主观验收（T049）**
  - 操作步骤（需连接真机 iPhone 16 Pro Max，支架竖放 30–80 cm 正常照明）：
    1. 运行 `./scripts/deploy-ios.sh --configuration Release` 部署并启动（可选另做一轮 Xcode Debug Navigator 抽查交叉核对 `phys_footprint` / FPS，并在报告中注明构建配置）；
    2. **阶段 1（US2–US5 量化补采，约 5 分钟）**：调试面板清零指标与手势计数 → ① 回到主界面左右/上下移头采集 ≥ 20 个 `M_track` 样本（核对 p50 < 100 ms、p90 < 150 ms）；② 微笑/皱眉/惊讶累计 ≥ 10 次采集 `M_reflex`（核对 300–800 ms 命中率 ≥ 90%）；③ 运行 30 s 镜像检测导出报告（核对 `|r| < 0.3`）；④ 挥手/比心/点赞各 10 次 + 1 分钟日常动作误触统计（核对 ≥ 8/10、≤ 1 次）；⑤ 开启悬浮对话调试条走完 US5 全链路并触发 ≥ 5 次 `userSpeechEnded` 采集 `M_feedback`（核对 < 100 ms）；导出指标 CSV 与镜像报告；
    3. **阶段 2（SC-006 10 分钟稳定性压测，T048）**：进入调试面板点击「开始 10 分钟压测」→ 返回主界面正常交互连续运行满 10 分钟（期间屏幕保持常亮，同时留意 `issue-001` 是否复现；若复现立即用「录制感知」抓 20 s JSONL 并停工上报）→ 满 10 分钟自动停止后在调试面板核对通过徽章并导出稳定性报告 Markdown（及逐秒 CSV）；
    4. **阶段 3（SC-007 主观验收，T049）**：请用户确认完整体验是否满足“它在看我，且在回应我，而不是在模仿我”并记录主观评语。
  - **门禁止损**：若 SC-006 任一项（`avgFps / p10Fps < 55`、`maxMemoryMB >= 1024`、`thermalSessionInterruptionCount > 0`）或 SC-002（`M_track`）未达标，立即停止进入 Step 6，带完整实测报告上报用户决策优化方案。

- **Step 6：回写 `specs/002-m1-presence/research.md`、`docs/tech-selection.md` 与 `issue-001` 观察记录（T049 / T050）**
  - 改动文件：`specs/002-m1-presence/research.md`、`docs/tech-selection.md`、按需 `docs/issues/001-periodic-bottom-left-head-drop.md`
  - 改动要点：严格按 §5.4 与 §5.5 将 Step 5 真实导出数据回写至 `research.md`，将 M1 实测结论与 V10 验证回写至 `tech-selection.md`（v3.7）并修复 §9.2 表格断裂；若 10 分钟压测未复现 `issue-001`，在 `docs/issues/001-periodic-bottom-left-head-drop.md` §5 追加一条未复现观察记录。
  - 最小验证命令：
    ```bash
    git diff --stat && git status --short
    ```

---

### 7. 确定性测试矩阵与验收门禁

#### 7.1 测试矩阵（严禁非确定性断言）
| 目标测试文件 | 覆盖类别 | 测试场景 | 必须写死的断言底线（禁止弱断言） |
| :--- | :--- | :--- | :--- |
| `Packages/MiniMateKit/Tests/MMCoreTests/StabilitySessionRecorderTests.swift` | 正例 | 60 Hz 连续运行 10 分钟（36,000 帧），内存 260→310 MiB，热状态 `nominal -> fair`，全程人脸追踪 | `sampleCount == 600`、`abs(duration - 600.0) < 1e-6`、`abs(avgFps - 60.0) < 1e-6`、`abs(p50Fps - 60.0) < 1e-6`、`abs(p10Fps - 60.0) < 1e-6`、`abs(maxMemoryMB - 310.0) < 1e-6`、`peakThermalLevel == .fair`、`thermalTransitions.count == 2`（含初始 `nil -> .nominal` 与 `.nominal -> .fair`）、`faceTrackedRatio == 1.0`、`passed == true` |
| `Packages/MiniMateKit/Tests/MMCoreTests/StabilitySessionRecorderTests.swift` | 正例 | `memoryMBProvider` 仅在 1 Hz 采样窗口触发时调用（60 帧仅调 1 次） | 输入 121 帧（`t = 0.0` 到 `t = 2.0`，步长 `1/60`）后 `providerCallCount == 2`、`sampleCount == 2` |
| `Packages/MiniMateKit/Tests/MMCoreTests/StabilitySessionRecorderTests.swift` | 正例 | 调试面板推入/返回：`pause(at:)` 暂停 5 秒后 `resume(at:)` 再跑 2 秒 60 Hz | 暂停 5 秒期间 `recordFrame` 返回 `nil` 且 `providerCallCount` 不增；恢复后两秒样本 `fps == 60.0`（绝不出现 0.2 fps 假掉帧），`abs(duration - 2.0) < 1e-6` |
| `Packages/MiniMateKit/Tests/MMCoreTests/StabilitySessionRecorderTests.swift` | 边界 | SC-006 四项独立不达标判据逐一触发 | ① 时长不足（`duration < targetDuration`）→ `passedDuration == false && passed == false`；② 某批窗口掉至 50 fps 使 `p10Fps < 55` → `passedFps == false && passed == false`；③ 单次 `memoryMB == 1024.0` → `passedMemory == false && passed == false`；④ `.serious` 态发生 1 次中断 → `thermalSessionInterruptionCount == 1 && passedThermalTracking == false && passed == false`；⑤ `.nominal`/`.fair` 态中断不计入 `thermalSessionInterruptionCount`（`sessionInterruptionCount == 1 && thermalSessionInterruptionCount == 0 && passedThermalTracking == true`） |
| `Packages/MiniMateKit/Tests/MMCoreTests/StabilitySessionRecorderTests.swift` | 边界 | `maxSamples` 上限保护与空样本/单样本 `finish()` | 超过 `maxSamples` 后 `samples.count == maxSamples`；空样本 `finish()` 返回 `sampleCount == 0`、`avgFps == 0`、`maxMemoryMB == 0`、`passed == false`（全字段 `.isFinite`） |
| `Packages/MiniMateKit/Tests/MMCoreTests/StabilitySessionRecorderTests.swift` | 异常反例 | 非有限时间戳（`NaN`/`+Inf`）、时间戳回退、非有限/负 `memoryMB` 与 `gestureHz`、非法构造参数 | 非有限时间戳 `start` 不启动；回退帧返回 `nil` 且不污染 `elapsed`；负/NaN 内存与手势率按 `0.0` 落盘；非有限构造参数回退安全默认值 |
| `Packages/MiniMateKit/Tests/MMCoreTests/StabilitySessionRecorderTests.swift` | 正例 | `summaryMarkdown()` 与 `csv()` 格式契约、`ProcessMemory.physicalFootprintBytes()` | `csv()` 首行为精确表头 `elapsed_s,fps,memory_mb,thermal_state,gesture_hz,face_tracked`，行数等于 `sampleCount + 1`；`summaryMarkdown()` 含精确判定、FPS/内存/热状态/中断关键行；macOS 下 `ProcessMemory.physicalFootprintBytes()` 返回非 `nil` 且 `> 0` |
| `Packages/MiniMateKit/Tests/*`（全量） | 兼容回归 | 全量 138 项既有单测零破坏 | 全量测试全部通过（138 + 新增用例，0 失败） |

#### 7.2 完整门禁命令清单
```bash
# 1. 目标单测（MMCore）
cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox --filter "StabilitySessionRecorder|LatencyRecorder|MMCoreContract"

# 2. 全量纯逻辑测试（macOS）
cd Packages/MiniMateKit && CLANG_MODULE_CACHE_PATH=/tmp/minimate-clang-cache SWIFT_DRIVER_SWIFT_SCAN_LIB_CACHE=/tmp/minimate-swift-cache swift test --disable-sandbox

# 3. 包内 iOS 条件编译验证（含 ARKitPerceptionSource）
cd Packages/MiniMateKit && xcodebuild -scheme MMPerception -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

# 4. App 模拟器无签名编译验证（含 AvatarScreen / AvatarDebugPanel）
xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# 5. 仓库状态与只读基线校验
git status --short
```

---

### 8. 项目附加产出要求（仅在用户明确确认验收进入收口时同步）
- **`specs/002-m1-presence/tasks.md`**：勾选 `T048`、`T049`、`T050`。
- **`specs/002-m1-presence/quickstart.md`**：勾选第 59–68 行验收清单（SC-001–SC-007 + `research.md`）。
- **`docs/CODEBASE_MAP.md`**：
  - §2 外部入口清单：`AvatarScreen.swift` 补充“防自动锁屏与 10 分钟 SC-006 稳定性压测导出”；
  - §3 公共复用设施：新增 `稳定性压测采样聚合与物理内存工具` → `Packages/MiniMateKit/Sources/MMCore/Metrics/StabilitySessionRecorder.swift`（`StabilitySessionRecorder` / `ProcessMemory`）。
- **`docs/HANDOFF_LEDGER.md`**：
  - §1 移除已完成的 `[002-m1-presence]` Phase 8 收尾待办，并移除已核实落地的过时条目 `AvatarScene.canMeasureTrackLatency 可按需追加 && !isDebugPanelPresented`；
  - §2 增补 `AvatarScene` `@MainActor deinit` 禁调 `UIApplication.shared` 与调试面板暂停 `tick()` 对 FPS 采样的防污染约定；
  - §3 追加 `[002-m1-polish]` 收口契约记录（M1 全量收口、`StabilitySessionRecorder`、`tech-selection.md` v3.7 与最新全量单测基线）。

---

### 9. 实施方偏差止损规则（固定条款）
- **可自决微调**：内部私有变量名、局部辅助函数拆分、调试面板视觉排版、注释与格式调整（不改变对外契约、Markdown/CSV 必需字段与测试预期）。
- **必须立即停工上报（严禁擅自绕过）**：
  1. 发现既定签名/契约与仓库现状冲突；
  2. 需要修改文件改动表（§4.1）之外的文件；
  3. 需要改写既有测试的预期断言；
  4. 需要放宽安全、只读、隐私或隔离红线；
  5. 实测发现新的工具链或环境阻断问题；
  6. 真机实测出现 SC-006 不达标（FPS < 55 / 内存 ≥ 1 GB / 热降频导致人脸中断）、SC-002（`M_track`）不达标，或 10 分钟压测期间复现 `issue-001`（此时必须先抓取完整报告/20 s JSONL 并停工上报，**严禁伪造或估算数据，严禁擅自修改 `minimate.usdz` 或放宽验收标准**）。

---

## 复审闭环记录（实施后由 task-review-loop 追加）

- **闭环结论**：一致通过（共 **2 轮**，阻断项 = `0`）
- **审查通道**：单节点独立只读 `reviewer`（`gemini-4-neon-high` / `Gemini 4 Neon (High)`，思考等级：`High`）
- **Round 1（2026-11-27）**：发现 2 项阻断项 + 2 项非阻断测试建议，零修改指纹核验 100% 吻合：
  1. `AvatarScreen.swift` 退后台后回前台时 `startPerception()` 因 `perceptionTask != nil` 早退导致 `isIdleTimerDisabled` 失效（及 `start()` 挂起期退后台竞态）→ 引入 `isSceneActive` 与 `handleForeground()` 根因闭环；
  2. `ARKitPerceptionSource` 中断期间停帧导致 SC-006 持续中断漏记或降温恢复后误判热态中断 → 在 `ARKitPerceptionSource` 锁内中断瞬间直接记录 `thermalSessionInterruptionCount` 并暴露 `isSessionInterrupted`，`AvatarScene` 新增 `syncARKitStabilityState(at:)`（带值相等短路）统一在 `handleIncomingFeatures`、`tick()` 与 `stopStabilityTest()` 同步；
  3. 采纳 2 项测试建议：补充 `StabilitySessionRecorderTests.midWindowPauseDropsPartialFramesWithoutPollutingFps` 与 `AttentionTransitionTests` 近距小位移反例。
- **Round 2（2026-11-27）**：**通过（阻断项 = 0）**，零修改指纹 100% 吻合；遗留 1 条低优非阻断建议（`AvatarScreen.swift:491` `nonThermalDelta` 可用 `min(currentThermal, .fair)` 替代 `.nominal`）。
- **最终门禁实测证据**：
  - macOS 全量纯逻辑单测（`swift test --disable-sandbox`）：**146/146 tests（24 suites）全部通过**（0 failed）；
  - `MMPerception` iOS 真机目标编译（`xcodebuild -scheme MMPerception -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO`）：**BUILD SUCCEEDED**；
  - `MiniMate` App iOS 模拟器编译（`xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`）：**BUILD SUCCEEDED**；
  - iPhone 16 Pro Max（Release）真机实测：SC-006 10 分钟 `avg 59.95 fps / max 518.2 MiB / 全程 nominal / 0 中断`、US5 `M_feedback 16.5/48.0 ms`、SC-007 主观合格、`issue-001` 未复现。
- **验收收口待办（待用户明确确认验收后落盘）**：
  - 勾选 `specs/002-m1-presence/tasks.md` `T048`–`T050` 与 `specs/002-m1-presence/quickstart.md` 验收清单；
  - 同步 `docs/CODEBASE_MAP.md`（§2 `AvatarScreen.swift` 防自动锁屏与 SC-006 压测导出；§3 新增 `StabilitySessionRecorder` / `ProcessMemory`）；
  - 同步 `docs/HANDOFF_LEDGER.md`（§1 移除已完成 Phase 8 收尾待办与过时 `canMeasureTrackLatency` 备忘，按需记录 `AvatarScreen.swift:491` 非热态中断传参极轻备忘；§2 增补 `AvatarScene` `@MainActor deinit` 与面板暂停 `tick()` 约定；§3 追加 `[002-m1-polish]` 收口记录与 `146/146` 单测基线）。
