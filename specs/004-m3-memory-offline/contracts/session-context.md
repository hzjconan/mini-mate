# Contract: SessionContextBuilder

**Module**: `MMMemory` | **Feature**: `004-m3-memory-offline`

## 接口

```swift
public struct SessionContextBuilder: Sendable {
    public init(budget: ContextBudget, estimator: TokenEstimator)

    public func build(
        persona: Persona,
        facts: [MemoryFactSnapshot],
        summaries: [SummarySnapshot],
        moodTrend: MoodTrend?,
        now: Date
    ) -> BuiltContext
}

public struct BuiltContext: Sendable {
    public let context: SessionContext          // 003 定义，extraInstructions 填入下方模板
    public let estimatedTokens: [Section: Int]
    public let droppedFactIDs: [UUID]           // 因预算被截掉的事实（调试用）
}
```

## 组装规则

| 编号 | 规则 |
|---|---|
| C-1 | 人格 + 标签协议原样放入，超过 800 视为配置错误（测试断言） |
| C-2 | 事实只取 `isObsolete == false`；排序：`lastConfirmedAt` 降序，同时间按类别 `profile > relationship > preference > event > other`；逐条加入直到达到 500 |
| C-3 | 摘要：本会话 `rolling`（若有）优先，其次最近 2 次 `final`；按时间倒序加入直到 500 |
| C-4 | 情绪趋势只在 `dominant != nil` 时加入一句 |
| C-5 | 各段为空时省略整段标题 |
| C-6 | 相同输入 MUST 产生完全相同的输出（便于厂商前缀缓存） |

## extraInstructions 模板

```
【关于用户你已经知道的事】
- {fact.content}
- ...

【最近的对话回顾】
{summary.text}
...

【用户最近的状态】
最近几次聊天中，用户的情绪多为{dominant 中文}。开场时自然地关心一下，不要直接点破。

使用这些信息时要自然，像老朋友一样提起；不要一次性复述，不要编造没有的信息。
```

## 会话重建（≥ 20 轮或断线重连）

注入 = 上述完整上下文（C-3 中包含本会话最新 `rolling` 摘要）+ 最近 4 轮原文（以"用户：… / 你：…"格式附在 extraInstructions 末尾，计入摘要预算之外的独立 300 token 上限）。

## 测试要求

- C-1 至 C-6 每条至少一个用例
- 预算边界：恰好达到、超过 1 字、单条事实本身超过预算（跳过该条，继续下一条）
