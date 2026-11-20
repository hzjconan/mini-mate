# Data Model: M0 工程基座与能力探测

**Feature**: `001-m0-foundation`

所有类型位于 `MiniMateKit`，均为值类型并遵循 `Sendable`。

## CapabilityID（`MMDiagnostics`）

能力标识枚举。

| case | 含义 |
|---|---|
| `foundationModels` | Apple Foundation Models 可用性 |
| `foundationModelsChinese` | Foundation Models 是否支持简体中文 |
| `speechTranscriberChinese` | `SpeechTranscriber` 是否支持 zh-CN（含资源是否已安装） |
| `speechDetector` | `SpeechDetector` 是否可用 |
| `nlEmbeddingChinese` | `NLEmbedding` 简体中文句向量是否可用 |
| `arFaceTracking` | ARKit 人脸追踪是否支持 |

## CapabilityStatus

| case | 含义 |
|---|---|
| `available` | 可用 |
| `unavailable(reason: String)` | 系统明确返回不可用，附中文原因 |
| `error(message: String)` | 探测本身抛错或超时 |

## CapabilityResult

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `CapabilityID` | |
| `status` | `CapabilityStatus` | |
| `detail` | `String?` | 补充信息，如支持的 locale 列表、近义句距离 |
| `duration` | `Duration` | 单项耗时 |

## CapabilityReport

| 字段 | 类型 | 说明 |
|---|---|---|
| `deviceModel` | `String` | 如 `iPhone17,2` |
| `systemVersion` | `String` | 如 `26.1` |
| `createdAt` | `Date` | |
| `results` | `[CapabilityResult]` | 按 `CapabilityID` 声明顺序排列 |

**行为**：`markdown() -> String` 输出一个 Markdown 表格（项 / 结果 / 原因 / 耗时），可直接粘贴到 `research.md`。

## CredentialStatus（`MMSecurity`）

| 字段 | 类型 | 说明 |
|---|---|---|
| `vendor` | `VendorID` | 厂商标识（`aliyun`、`volcengine`、`openai`；M2a 后按实际厂商增删） |
| `isConfigured` | `Bool` | |
| `suffix` | `String?` | Key 末 4 位，未配置时为 nil |

**约束**：任何类型的 `description` / `debugDescription` MUST NOT 包含完整 Key。
