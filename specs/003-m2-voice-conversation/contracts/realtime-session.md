# Contract: RealtimeTextSession（厂商适配器）

**Module**: `MMConversation/Realtime` | **Feature**: `003-m2-voice-conversation`

## 接口

```swift
public protocol RealtimeTextSession: Sendable {
    /// 建立 WebSocket 并完成会话配置：只输出文字、服务端 VAD、instructions。
    func connect(instructions: String) async throws

    /// 推送一段音频（已转换为厂商要求的格式）。
    func send(_ audio: AudioChunk) async throws

    /// 取消当前正在生成的回答（打断）。
    func cancelResponse() async

    /// 清空服务端尚未处理的输入音频缓冲。
    func clearInputBuffer() async

    var output: AsyncThrowingStream<RealtimeOutput, Error> { get }

    func close() async
}

public enum RealtimeError: Error {
    case authFailed
    case rateLimited
    case unsupportedConfiguration(String)   // 如不支持只输出文字
    case network(underlying: String)
    case server(code: String, message: String)
}
```

## 适配器必须满足的能力

| 编号 | 能力 | 对应验证 |
|---|---|---|
| A-1 | 会话可配置为只输出文字（不生成语音） | V4 |
| A-2 | 支持服务端 VAD，并提供 speech started / stopped 事件 | — |
| A-3 | 支持流式文字增量输出 | — |
| A-4 | 支持取消当前回答 | 打断 |
| A-5 | 支持会话级 instructions | 人格与标签协议 |
| A-6 | （可选）提供用户输入转写 | V7 |

不满足 A-1 的厂商只能用于方案 C。

## 行为约定

| 编号 | 约定 |
|---|---|
| RS-1 | 鉴权信息只存在于请求头 / 首条消息中，MUST NOT 出现在日志、错误描述或测试夹具中 |
| RS-2 | 厂商原始消息到 `RealtimeOutput` 的映射在适配器内完成，上层不处理厂商 JSON |
| RS-3 | 未识别的消息类型忽略并以 debug 级别记录类型名（不记录内容） |
| RS-4 | `send` 在未连接时抛错，不缓存（重连由引擎负责） |
| RS-5 | 每个适配器 MUST 有基于录制夹具的解码测试 |

## 厂商附录

M2a 期间按各家最新文档填写；选定后删除未选中厂商的附录与适配器代码。

### 阿里百炼 Qwen-Omni realtime

| 项 | 值 |
|---|---|
| Endpoint | 待填 |
| 鉴权 | 待填 |
| 模型名 | 待填 |
| 只输出文字的配置 | 待填 |
| 输入音频格式 | 待填 |
| VAD 配置 | 待填 |
| 取消回答的消息 | 待填 |
| 用户转写事件 | 待填 |

### 火山引擎 豆包实时语音

（同上表）

### OpenAI Realtime（可选）

（同上表）
