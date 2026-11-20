# Data Model: M3 记忆、离线与预置短句

**Feature**: `004-m3-memory-offline`

## SwiftData 模型（`MMMemory/Models`）

### ConversationSession

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `UUID` | |
| `startedAt` | `Date` | |
| `endedAt` | `Date?` | 被杀进程时为 nil，冷启动时补齐为最后一轮时间 |
| `vendor` | `String` | |
| `mode` | `String` | `online` / `offline` |
| `isSummarized` | `Bool` | |
| `turns` | `[Turn]` | 级联删除 |
| `summaries` | `[SessionSummary]` | 级联删除 |

### Turn

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `UUID` | 与 003 的 `turnID` 一致 |
| `index` | `Int` | 会话内序号 |
| `startedAt` / `endedAt` | `Date` | |
| `userText` | `String` | 用户转写（实时接口或端侧） |
| `userEmotion` | `String?` | `UserEmotion.rawValue` |
| `assistantText` | `String` | 去标签后的回答 |
| `assistantEmotions` | `[String]` | 本轮出现过的 `EmotionTag` |
| `wasInterrupted` | `Bool` | |
| `answerLatencyMs` | `Int?` | M_answer |

### SessionSummary

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `UUID` | |
| `kind` | `String` | `final`（会话结束）/ `rolling`（会话内中间摘要） |
| `text` | `String` | ≤ 300 字 |
| `coversTurnRange` | `ClosedRange<Int>` 编码为两个 `Int` | |
| `createdAt` | `Date` | |

### MemoryFact

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `UUID` | |
| `category` | `String` | `profile`（基本信息）/ `preference`（喜好）/ `relationship`（人与宠物）/ `event`（近期事件）/ `other` |
| `key` | `String` | 归一化主题键，如 `pet.cat.name`，用于合并 |
| `content` | `String` | 一句话事实，如"用户养了一只叫团子的猫" |
| `sourceSessionID` | `UUID` | |
| `createdAt` | `Date` | |
| `lastConfirmedAt` | `Date` | 再次被提及时更新 |
| `isObsolete` | `Bool` | |

**合并规则（`FactMerger`）**

| 情况 | 处理 |
|---|---|
| 新事实 `key` 不存在 | 插入 |
| `key` 存在且内容一致 | 更新 `lastConfirmedAt` |
| `key` 存在且内容不同 | 旧条目 `isObsolete = true`，插入新条目 |
| 抽取结果的 `obsolete` 列出某 `key` | 对应条目 `isObsolete = true` |

## 非持久化类型

### MoodTrend

| 字段 | 类型 | 说明 |
|---|---|---|
| `sessions` | `Int` | 统计的会话数（≤ 3） |
| `distribution` | `[UserEmotion: Int]` | |
| `dominant` | `UserEmotion?` | 占比 ≥ 50% 时给出 |

### ContextBudget

| 段 | 预算（估算 token） |
|---|---|
| 人格 + 标签协议 | ≤ 800 |
| 长期事实 | ≤ 500 |
| 摘要（最近 2 次 `final` + 本会话 `rolling`） | ≤ 500 |
| 情绪趋势 | ≤ 50 |

## 资源文件

### PresetPhrase（`Resources/preset-phrases.json`）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `String` | 如 `greet.01` |
| `category` | `String` | `greet` / `backchannel` / `filler` / `offlineNotice` / `offlineFallback` / `reconnected` / `action.<ActionTag>` / `bye` / `praise` |
| `text` | `String` | |
| `emotion` | `EmotionTag` | 合成时使用的情绪 |

清单级字段：`catalogVersion: Int`。

### PresetCacheManifest（缓存目录内 `manifest.json`）

| 字段 | 说明 |
|---|---|
| `vendor` / `voice` / `catalogVersion` | 任一与当前不符即失效（FR-014） |
| `entries` | `id → 文件名、时长` |

### OfflineIntent（`Resources/offline-intents.json`）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `String` | 如 `spin` |
| `patterns` | `[String]` | 关键词 / 正则 |
| `examples` | `[String]` | 用于 `NLEmbedding` 匹配的示例说法 |
| `action` | `ActionTag?` | |
| `emotion` | `EmotionTag` | |
| `replyCategory` | `String` | 对应 `PresetPhrase.category` |
