# Contract: 摘要与事实抽取

**Module**: `MMMemory`（`MemoryMaintenance`）、`MMConversation/Text`（`TextLLMProvider`） | **Feature**: `004-m3-memory-offline`

## TextLLMProvider

```swift
public protocol TextLLMProvider: Sendable {
    /// 非流式；要求模型输出 JSON。
    func completeJSON(system: String, user: String, timeout: Duration) async throws -> Data
}
```

实现使用 003 选定厂商的文本模型（与实时接口共用 Key）。

## 请求

**system**

```
你是对话记忆整理助手。根据给出的对话记录与已知事实，输出 JSON，不要输出任何其他内容。
规则：
1. summary：用第三人称概括这段对话，不超过 200 字，保留情绪与重要事件。
2. facts：只抽取关于用户本人的、之后可能有用的事实；每条一句话；为每条给出 category 与 key。
   category 只能是 profile / preference / relationship / event / other。
   key 用小写英文点分路径表示主题，如 pet.cat.name、study.exam。
3. obsolete：列出已知事实中，被这段对话明确否定或已经过时的 key。
4. 不要抽取关于助手自己的内容；不要猜测。
```

**user**

```
【已知事实】
- [key] content
...

【对话记录】
#1 用户（语气：tired）：……
#1 助手：……
#2 用户（语气：calm）：……
...
```

## 响应 schema

```json
{
  "summary": "string",
  "facts": [
    { "category": "relationship", "key": "pet.cat.name", "content": "用户养了一只叫团子的猫" }
  ],
  "obsolete": ["study.exam"]
}
```

## 行为约定

| 编号 | 约定 |
|---|---|
| M-1 | JSON 解析失败：重试 1 次（附"上次输出不是合法 JSON"提示）；仍失败则保留 `isSummarized = false`，下次在线时重试 |
| M-2 | 未知 `category` 归为 `other`；`key` 为空的事实丢弃 |
| M-3 | 触发时机：会话结束、App 进入后台（会话进行中则做 `rolling`）、冷启动发现未摘要会话 |
| M-4 | 会话内 `rolling` 摘要只更新 `summary`，不抽取事实（避免中途误抽） |
| M-5 | 请求内容只包含该会话的轮次与已知事实，不包含其他会话原文 |
| M-6 | 超时 30 s |
