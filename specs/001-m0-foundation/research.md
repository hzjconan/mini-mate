# Research: M0 工程基座与能力探测

**Feature**: `001-m0-foundation` | **Date**: 2026-11-20

本文件记录本 feature 的技术决策与实测结果。"实测结果"一节在真机探测后填写。

## 决策

### D1. 工程结构：App + 本地 Swift Package

- **Decision**：一个 iOS App target 作为组合根；业务代码全部在 `Packages/MiniMateKit` 的多个 target 中。
- **Rationale**：宪章 V 要求纯逻辑可在 macOS 上 `swift test`；Package target 天然隔离模块依赖，避免循环引用。
- **Alternatives considered**：全部放在 App target（无法在 macOS 测试）；XcodeGen / Tuist 生成工程（新增工具依赖，单人项目收益低）。

### D2. 签名：开发者账号（2026-11-20 修订）

- **Decision**：付费个人开发者账号签名；App 不声明 Push、iCloud、App Groups 等 capability。
- **Rationale**：原计划用免费 Apple ID；真机安装当天遇到"设备注册名额已满"（免费账号的 iPhone 名额是跨项目共享的硬上限，且无法在线删除），购入个人付费会员。付费签名约一年有效，每周重签的负担消除。
- **Alternatives considered**：免费 Apple ID（7 天签名、无付费能力）——仍可用作回退路径；本 App 不依赖任何付费 capability，换免费账号只需重新签名安装。

### D3. 测试框架：Swift Testing

- **Decision**：使用 Swift Testing（`import Testing`、`@Test`、`#expect`）。
- **Rationale**：Xcode 26 默认，语法简洁，支持参数化测试，适合解析器与状态机。
- **Alternatives considered**：XCTest（保留用于未来可能的 UI 测试）。

### D4. 密钥存储

- **Decision**：Keychain generic password，`AfterFirstUnlockThisDeviceOnly`。
- **Rationale**：宪章 VII；不随备份迁移到其他设备。
- **Alternatives considered**：`UserDefaults` / plist（明文，不可接受）。

## 待实测项（对应 tech-selection 第 9.2 节）

| # | 问题 | 探测方式 | 影响 |
|---|---|---|---|
| V1 | Foundation Models 是否可用、是否支持中文 | `SystemLanguageModel.default.availability` + 中文 locale 检查 | 不可用 → M4 走 MLX；离线意图匹配只用 `NLEmbedding` |
| V2 | `SpeechTranscriber` 是否支持 zh-CN | `supportedLocales` / `installedLocales` | 不可用 → 离线识别用 `SFSpeechRecognizer` |
| V3 | `SpeechDetector` 能否用作人声闸门 | 能否构造；效果在 003 中实测 | 不可用 → 能量阈值 + 过零率 |
| — | `NLEmbedding` 中文句向量 | 是否非 nil（含重试 / 按 revision 加载）+ 3 组近/远义句距离 | 不可用 → 关键词 + CreateML 分类器 |
| — | `NLContextualEmbedding` 中文 | 能否 `load()` + 均值池化后同样 3 组距离 | 作为 `NLEmbedding` 的备选 |
| — | ARKit 人脸追踪 | `ARFaceTrackingConfiguration.isSupported` | 参考设备预期为支持 |

## 实测结果

探测设备：iPhone 16 Pro Max（iPhone17,2，型号 CH/A 国行）、iOS 27.2、2026-11-20。单项均 < 1 s，SC-002 达标。

导出报告原文（首次探测；NLEmbedding 一行已被后文"NLEmbedding 复核"推翻）：

```markdown
- 设备：iPhone17,2
- 系统：27.2
- 时间：2026-11-20T08:12:40Z

| 项 | 结果 | 原因 | 耗时 |
| --- | --- | --- | --- |
| V1 Foundation Models | 不可用 | 设备不支持 Apple Intelligence | 0.56 s |
| V1 中文支持 | 不可用 | Foundation Models 不可用 | 0.56 s |
| V2 SpeechTranscriber zh-CN | 可用 | 简体支持 zh_CN；中文支持：zh_TW, zh_HK, zh_CN；已安装：zh_TW, zh_CN | 0.64 s |
| V3 SpeechDetector | 可用 | — | 0.00 s |
| NLEmbedding 中文 | 不可用 | 无简体中文句向量 | 0.59 s |
| ARKit 人脸追踪 | 可用 | — | 0.00 s |
```

| 项 | 结果 | 原因 / 备注 | 对后续的影响 |
|---|---|---|---|
| 设备 / 系统 | iPhone17,2 / iOS 27.2 | iPhone 16 Pro Max，型号号码 CH/A（国行） | — |
| V1 Foundation Models | ❌ 不可用 | `deviceNotEligible`——国行型号硬屏蔽 Apple Intelligence（A18 Pro 硬件本身支持，与语言/账号设置无关） | M4 若启动只能走 MLX；依赖 FM 的功能（如将来的看图）在本机不可用 |
| V1 中文支持 | ❌ 不可用 | FM 整体不可用，中文支持无从谈起 | 同上 |
| V2 SpeechTranscriber zh-CN | ✅ 可用 | zh_CN 支持且资源已安装（zh_TW/HK/CN 均支持，已装 zh_TW、zh_CN） | 端侧/并行转写可用简体（003 V7、004 离线转写前提成立） |
| V3 SpeechDetector | ✅ 可用 | 可构造并加入 `SpeechAnalyzer` | 人声闸门可用；误开率/效果仍待 003 M2b 实测 |
| NLEmbedding 中文 | ✅ 可用（复核修正） | 首次探测记为 nil 是误判，见下文"NLEmbedding 复核"；640 维，近<远 2/3 | 离线意图匹配仍以关键词 + CreateML 为主；004 的 I-2 embedding 层可作辅助，阈值须重新实测 |
| NLContextualEmbedding 中文 | ✅ 可用（首次失败后重试） | 模型已在设备上，512 维；进程内首次 `load()` 失败（`hasAvailableAssets=false`），50–100 ms 后重试即成功；先等 300 ms 再首次调用仍失败（5/5），详见下文 A/B | 与 NLEmbedding 同为辅助候选；第 1 组区分度更好，另两组同样偏弱 |
| ARKit 人脸追踪 | ✅ 可用 | `ARFaceTrackingConfiguration.isSupported = true` | 按预期，TrueDepth 可用 |
| 重签耗时（SC-001） | ✅ ~30 s | ⌘R 原地重签（付费账号 Xcode Managed Profile），@AppStorage 计数器保留（5→5） | 达标（≤5 min）|

### NLEmbedding 复核（2026-11-20，同一台设备，系统语言 `zh-Hans-CN`）

首次探测的"无简体中文句向量"是误判。用临时诊断构建在真机上跑了 3 次（代码已移除），之后又用修正后的探测器跑了 5 次：

- **首次调用返回 nil**：`NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)` 在同一进程内的第一次调用返回 nil，紧接着第二次调用就非 nil。先等 4 s 再调用，第一次照样是 nil，所以不是等待时间的问题。看起来是进程里第一次调用 sentence embedding 都会失败，与语言无关（某次运行先调中文失败、再调英文成功）。偶尔前两次都是 nil，这时直接调 `sentenceEmbedding(for:revision: currentSentenceEmbeddingRevision(for:))` 可以加载成功。`supportedSentenceEmbeddingRevisions(.simplifiedChinese) = [1]`；日语为空，确实不支持。
- **没有公开的下载 API**：iOS 27 SDK 中 `NLEmbedding` 没有请求资源的接口（网上流传的 `requestEmbeddingAssets` 并不存在）。`NLTagger.requestAssets(for: .simplifiedChinese, tagScheme: .lemma)` 2 分钟以上不返回。
- **`NLContextualEmbedding`**：资源已在设备上，加载 ~0.05 s，12 句 ~0.1 s，512 维。进程内首次 `load()` 会失败（`hasAvailableAssets = false`，`Failed to locate embedding model`），但这不是“需要预先延迟”：2026-11-20 真机 A/B（见下）显示，先等 300 ms 再首次调用仍 5/5 失败；首次调用失败后 50–100 ms 重试即成功。探测器已改为首次失败后每 100 ms 重试、2 s 截止；不使用 `requestAssets()`（首次实测 5.5 s，可能触发资源检查/下载，且超过 runner 的 3 s 超时）。
- **区分度**（余弦距离，越小越近；探测器详情里的"近<远"即这 3 组）：

| 锚句 → 近义 / 无关 | NLEmbedding 句向量 | NLContextualEmbedding（均值池化） |
|---|---|---|
| 今天天气很好 → 今天天气不错 / 我昨天睡得很晚 | 0.372 / 0.443 ✅ | 0.091 / 0.239 ✅ |
| 我想听首歌 → 放点音乐吧 / 帮我关灯 | 0.486 / 0.605 ✅ | 0.371 / 0.385 勉强 |
| 我有点难过 → 心情不太好 / 明天要开会 | 0.469 / 0.401 ❌ | 0.365 / 0.350 ❌ |

结论：句向量可用，但只有 3 组冒烟测试，且其中 1 组排序颠倒，近义句距离也都在 0.37 以上 → 不能单独用于意图匹配。004 的 embedding 层只作辅助，阈值须用真实意图样本另测（004 plan 中的初值 0.35 在这组数据下一句都匹配不上）。凡在 App 中调用 `NLEmbedding.sentenceEmbedding`，都要按 `NLEmbeddingProbe.loadSentenceEmbedding` 的方式处理首次调用返回 nil 的情况。

复核后探测器导出（2026-11-20T09:44:34Z，节选；另一次运行中 NLEmbedding 前两次都返回 nil，按 revision 1 加载成功）：

```markdown
| NLEmbedding 中文 | 可用 | 首次调用返回 nil，重试成功；近<远 2/3：0.372<0.443，0.486<0.605，0.469>0.401 | 0.08 s |
| NLContextualEmbedding 中文 | 可用 | 第 1 次 hasAvailableAssets=false，load 失败：Failed to locate embedding model；第 2 次加载成功（hasAvailableAssets=true，距首次 395 ms）；维度 512；近<远 2/3：0.091<0.239，0.371<0.385，0.365>0.350 | 0.57 s |
```

### NLContextualEmbedding 真机 A/B（2026-11-20）

用独立 Bundle ID 的临时探针 App（`ai.minimate.app.m0probe`，已卸载）在同一台 iPhone 17,2 / iOS 27.2 上跑了 5 轮 × 8 个场景；每次都是全新进程，跑完直接 `exit(0)`。结论：首次 `load()` 失败是“每个进程第一次查询触发 NaturalLanguage 资源初始化”的一次性状态，**不需要预先等待 300 ms**。

| 场景 | 结果 |
|---|---|
| 首次调用前先等 300 ms | 5/5 失败（`hasAvailableAssets=false`，`Failed to locate embedding model`，~11–15 ms） |
| 首次失败后 50 ms 重试 | 5/5 第 2 次成功，总耗时 88–104 ms |
| 首次失败后 100 ms 重试 | 4/5 第 2 次成功、1/5 第 1 次成功；总 38–167 ms |
| 现有 300 ms × 3 | 5/5 第 2 次成功，总 378–400 ms |
| 先 `requestAssets()` 再 `load()` | 5/5 成功；首次 5.5 s，之后 4–15 ms |
| 与 `NLEmbedding` 并发 | 5/5 成功（3 次第 2 次、2 次第 1 次）；并发不是失败原因 |
| 先调 `NLEmbedding` 再 `load()` | 5/5 第 1 次成功（NLEmbedding 首次调用会预热共享资源） |

补充观察：

- 首次失败后，`hasAvailableAssets` 在约 50 ms 内翻为 true；但有 2 次首次 `load()` 成功时该值仍为 false，所以**不能把 `hasAvailableAssets` 当作是否重试的 gate**，应以 `load()` 结果为准。
- `requestAssets()` 首次调用实测 5.5 s（后续 4–15 ms），可能触发资源检查/下载；超过 `DiagnosticsRunner` 的 3 s 超时，不适合放在诊断探测里。
- 因此探测器改为：首次立即尝试；失败后每 100 ms 重试，截止 2 s；记录尝试次数与首次耗时。正常路径约 140 ms 内完成，比原来的 300 ms 重试快 ~250 ms。
- 上表旧导出中的“距首次 395 ms”来自旧的 300 ms 重试版本；新探测器导出的文案会显示实际尝试次数与耗时。

> 注（2026-11-20 实测）：付费账号下"签名到期、App 打不开"的状态无法模拟——iOS 设置无描述文件管理入口（付费证书在信任链内，不像免费账号有信任条目）；Xcode 27 的 Window 菜单也已移除设备描述文件管理；吊销 Apple Development 证书后 App 仍可正常启动，说明 iOS 启动校验是本地的（内嵌 profile + 签名链），不做吊销检查。真正的到期→重签全链路只能等 11 个月后自然到期或换回免费账号时验证。
