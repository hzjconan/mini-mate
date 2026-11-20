# Contract: ConversationEngine

**Module**: `MMConversation` | **Feature**: `003-m2-voice-conversation`

## 接口

```swift
public protocol ConversationEngine: Sendable {
    var events: AsyncStream<ConversationEvent> { get }

    /// 建立会话：注入人格、标签协议说明；004 起还包含长期事实与摘要。
    func start(context: SessionContext) async throws

    /// 视线软闸门的决策，由 App 根据感知结果调用。
    func setGazeDecision(_ decision: GazeGateDecision)

    /// 用户静音开关。
    func setMuted(_ muted: Bool)

    /// 主动打断当前回答（如 UI 操作）。插话打断由引擎内部检测。
    func interrupt()

    func stop() async
}

public struct SessionContext: Sendable {
    public var persona: Persona
    public var extraInstructions: String?   // 004：长期事实 + 摘要
}
```

## 实现

| 实现 | 说明 |
|---|---|
| `RealtimeTextConversationEngine` | 方案 B（默认） |
| `RealtimeVoiceConversationEngine` | 方案 C（条件实施，US7） |
| `ScriptedConversationEngine` | 测试与调试：按脚本发出事件 |
| `OfflineConversationEngine` | 004 |

## 事件顺序保证（同一轮内）

```
userSpeechStarted
  userTranscript(…, isFinal: false)*        # 若厂商提供
userSpeechEnded
  userTranscript(…, isFinal: true)?
  userEmotion(…)?                           # 必在第一个 assistantSpeechStarted 之前
  assistantText(…)*                         # 文字到达即发出，用于调试显示
  assistantSpeechStarted
    ( assistantEmotion(…)                   # 在该句音频开始播放时发出
      assistantAction(…)*                   # 在对应字符位置的音频播放时发出
      assistantAudioLevel(…)* )+            # ≥ 30 Hz
  assistantSpeechEnded
```

| 编号 | 约定 |
|---|---|
| E-1 | `userSpeechEnded` 在本地检测到停止发声或服务端端点事件到达时发出，取先到者；同一轮只发一次 |
| E-2 | 打断时：先发 `userSpeechStarted`（新一轮），再发旧一轮的 `assistantSpeechEnded`；旧一轮之后不再有任何事件 |
| E-3 | `assistantEmotion` 与对应句子的第一个音频缓冲开始播放的时间差 < 50 ms |
| E-4 | `gateStateChanged`、`connectionStateChanged` 可在任意时刻出现，不属于轮次 |
| E-5 | 事件中不包含 API Key 或厂商原始错误中的鉴权信息 |
