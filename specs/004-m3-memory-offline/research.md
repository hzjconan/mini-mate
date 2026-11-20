# Research: M3 记忆、离线与预置短句

**Feature**: `004-m3-memory-offline` | **Date**: 2026-11-20

## 决策

### D1. 本地存储用 SwiftData

- **Decision**：SwiftData `@Model`，单个 `ModelContainer`。
- **Rationale**：系统框架，iOS 26 成熟；数据量小；测试可用内存容器。
- **Alternatives considered**：SQLite 手写（工作量大）；文件 JSON（并发与查询不便）。

### D2. 不做向量检索，按类别 + 时间截断

- **Decision**：长期事实全部候选，按"未过时 → 最近确认时间 → 类别优先级"排序，在 500 token 预算内截断。
- **Rationale**：个人用量下事实条目预计在数百条以内，排序截断足够；避免引入向量库与 embedding 调用（宪章 VI）。
- **触发重新评估**：事实超过约 300 条，或 SC-001 回忆率下降。

### D3. 摘要与事实抽取一次调用、JSON 输出

- **Decision**：会话结束后用同厂商文本模型一次调用，输出 `{summary, facts[], obsolete[]}`（contracts/memory-extraction.md）。
- **Rationale**：非流式场景 JSON 最便于解析；一次调用减少延迟与费用。

### D4. token 估算按字符

- **Decision**：中文字符按 1 token / 字、ASCII 按 1 token / 4 字符估算，留 10% 余量。
- **Rationale**：各厂商分词不同，精确计数收益低；预算本身是经验值。

### D5. 离线识别依 001 结论

| 001 结论 | 离线转写 | 离线意图匹配 |
|---|---|---|
| `SpeechTranscriber` zh-CN 可用 | `SpeechTranscriber` | 关键词 + `NLEmbedding`（若可用） |
| 不可用 | `SFSpeechRecognizer`（`requiresOnDeviceRecognition`） | 同上 |
| 两者都不可用 | 无 | 只响应手势与表情 |

若 001 结论为 Foundation Models 可用且支持中文，可把意图匹配升级为 `@Generable` 分类（M4 前的可选改进，不在本 feature 范围）。

### D6. 垫场阈值 1.2 s

- **Decision**：首个文字超过 1.2 s 未到达才播放垫场。
- **Rationale**：003 的 M_answer 预算中"端点 + 首个文字"常态约 0.6–1.4 s；1.2 s 能覆盖慢的轮次又不会每轮都播。以 003 实测的首个文字 p75 为准调整。

## 待实测项

| 问题 | 验证方式 |
|---|---|
| 摘要与事实抽取质量 | SC-001 回忆测试；人工检查 10 次会话的抽取结果 |
| `NLEmbedding` 意图匹配阈值 | 每个意图 5 种说法 + 20 条负样本，选取阈值；001 冒烟测试显示区分度弱（近义 0.37–0.49，3 组中 1 组颠倒），若误命中率过高则去掉该层 |
| 垫场阈值是否合适 | 对照 003 的首个文字耗时分布，统计触发率 |
| 预合成短句音色一致性 | 与在线回答主观对比 |

## 实测结果

| 项 | 结果 | 备注 |
|---|---|---|
| SC-001 回忆正确数 / 10 | 待填 | |
| SC-002 摘要耗时 | 待填 | |
| SC-004 离线指令正确数 / 10 | 待填 | |
| SC-005 恢复在线耗时 | 待填 | |
| SC-006 短句播放延迟 | 待填 | |
| SC-007 垫场触发情况 | 待填 | |
| `NLEmbedding` 阈值 | 待填 | |
| SC-009 快速指令 p50（可选） | 待填 | |
