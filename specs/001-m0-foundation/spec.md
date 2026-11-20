# Feature Specification: M0 工程基座与能力探测

**Feature Branch**: `001-m0-foundation`

**Created**: 2026-11-20

**Status**: Draft

**Input**: `docs/tech-selection.md` v3.1 第 7 章 M0："免费账号签名、真机跑通空工程；一次性能力探测"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 在自己的 iPhone 上装上并持续使用 App (Priority: P1)

我用免费 Apple ID 把 MiniMate 装到 iPhone 16 Pro Max 上；7 天签名到期后，我能按一份固定步骤在几分钟内重签，App 内的数据不丢。

**Why this priority**：签名是最大的现实门槛（tech-selection 第 1 章第 8 条）。装不上或每周重签很痛苦，后面一切都无从谈起。

**Independent Test**：在真机安装空工程，写入一条测试数据；等签名过期（或手动删除描述文件模拟），按 quickstart 重签，确认 App 可启动且测试数据仍在。

**Acceptance Scenarios**:

1. **Given** 一台已开启开发者模式的 iPhone 和一个免费 Apple ID，**When** 按 quickstart 在 Xcode 中构建运行，**Then** App 在真机启动并显示首页。
2. **Given** 签名已过期、App 无法打开，**When** 按 quickstart 的重签步骤操作，**Then** App 可再次打开，之前写入的本地数据仍在。
3. **Given** 工程已建好，**When** 在 Mac 上执行 `swift test`，**Then** 共享 Swift Package 的测试可以运行并通过。

---

### User Story 2 - 一次看清设备具备哪些关键能力 (Priority: P1)

我打开 App 的"能力探测"页面，一次性看到后续里程碑依赖的系统能力是否可用，并能导出结果，作为 M1–M4 的选型依据。

**Why this priority**：Foundation Models、`SpeechTranscriber` 中文、`SpeechDetector`、`NLEmbedding` 中文都是"需确认"项（V1–V3），结果会改变 M2–M4 的方案。成本极低，越早知道越好。

**Independent Test**：在真机打开探测页，所有探测项都给出"可用 / 不可用 / 原因"，并能导出为文本。

**Acceptance Scenarios**:

1. **Given** App 已安装，**When** 打开能力探测页，**Then** 页面列出每一项探测的结果与原因（如"Apple Intelligence 未开启"）。
2. **Given** 探测完成，**When** 点击导出，**Then** 得到一份可粘贴进 `research.md` 的文本报告，包含设备型号、系统版本、时间与各项结果。
3. **Given** 某一项探测失败或抛错，**When** 探测运行，**Then** 其他项照常完成，失败项显示错误信息，App 不崩溃。

---

### User Story 3 - 安全地保存 API Key (Priority: P2)

我在 App 的设置页填入云厂商的 API Key，它只保存在本机 Keychain 中；之后可以查看是否已配置、替换或删除，但界面上不会完整显示 Key。

**Why this priority**：M2 起需要调用云端；先把密钥存储做对，避免后面临时硬编码。

**Independent Test**：填入一个假 Key，重启 App 后状态显示"已配置（末 4 位 xxxx）"；删除后显示"未配置"；全仓库搜索不到该 Key。

**Acceptance Scenarios**:

1. **Given** 未配置 Key，**When** 在设置页输入并保存，**Then** 显示"已配置"及末 4 位，重启后状态保持。
2. **Given** 已配置 Key，**When** 点击删除，**Then** Keychain 中的条目被移除，状态变为"未配置"。

---

### Edge Cases

- 设备未开启开发者模式，或首次安装时未在"设置 > 通用 > VPN 与设备管理"中信任开发者证书。
- 免费账号 7 天内创建的 App ID 数量已达上限。
- Apple Intelligence 未开启、仍在下载模型、或因地区/语言不可用——探测须区分这几种原因。
- `SpeechTranscriber` 支持 zh-CN，但对应语言资源尚未下载。
- `NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)` 返回 nil。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**：工程 MUST 由一个 iOS App target 与一个本地 Swift Package（`MiniMateKit`）组成；不依赖设备的模块 MUST 能在 macOS 上 `swift test`。
- **FR-002**：App MUST 能用免费 Apple ID 签名安装到真机，且不声明任何免费账号不支持的 capability。
- **FR-003**：App MUST 提供能力探测页，至少包含：Foundation Models 可用性（含不可用原因）、`SpeechTranscriber` 是否支持 zh-CN 及资源是否已安装、`SpeechDetector` 是否可用、`NLEmbedding` 中文句向量是否可用、ARKit 人脸追踪是否支持、设备型号与系统版本。
- **FR-004**：每一项探测 MUST 相互独立，单项失败不影响其他项，结果包含状态与原因。
- **FR-005**：探测结果 MUST 可导出为纯文本（Markdown 表格）。
- **FR-006**：App MUST 提供 API Key 的保存、状态查看（仅显示末 4 位）、替换与删除；Key 只存 Keychain。
- **FR-007**：仓库 MUST 有 `.gitignore`，排除 Xcode 用户数据、构建产物与任何本地密钥文件。
- **FR-008**：仓库 MUST 提供重签操作文档（quickstart）。

### Key Entities

- **CapabilityReport**：一次探测的结果集合，含设备信息、时间与多条 CapabilityResult。
- **CapabilityResult**：单项探测，含能力标识、状态（可用 / 不可用 / 出错）、原因说明。
- **CredentialStatus**：某个厂商密钥的配置状态与末 4 位。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**：从签名过期到 App 重新可用，按 quickstart 操作 ≤ 5 分钟，且本地数据不丢。
- **SC-002**：能力探测在 5 秒内完成全部项（不含系统模型下载）。
- **SC-003**：探测报告已写入 `specs/001-m0-foundation/research.md`，V1–V3 均有明确结论。
- **SC-004**：`swift test` 在 Mac 上通过，且至少包含一个真实测试（`CapabilityReport` 的 Markdown 导出）。
- **SC-005**：全仓库检索不到任何 API Key 明文。

## Assumptions

- 开发机为 Apple Silicon Mac，安装 Xcode 26；设备为 iPhone 16 Pro Max、iOS 26。
- 使用免费 Apple ID；不购买开发者账号。
- 本阶段不接任何云端服务，API Key 只做存储，不发起调用。
- 探测页是开发用的诊断界面，后续保留在设置中，不追求视觉设计。
