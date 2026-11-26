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

    /// 005：暂缓回应的播放（RH-1）。
    func holdReplies()
    /// 005：释放暂缓的回应；用户语音开始时刻早于 t 的回应被丢弃（RH-2）。
    func releaseReplies(discardingTurnsStartedBefore t: TimeInterval)

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
  assistantCommand(…)*                      # 005：解析到即发出（C-1）
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

## 指令事件（005 增补）

| 编号 | 约定 |
|---|---|
| C-1 | `assistantCommand` 在解析到时立即发出，不等待音频播放；位于同一轮的 `userSpeechEnded` 之后、`assistantSpeechEnded` 之前 |
| C-2 | 被打断的一轮（E-2）中，打断之前已发出的 `assistantCommand` 不撤回；打断之后旧一轮不再发出任何指令；已收到的指令是否仍然有效由消费方决定 |
| C-3 | 回答中没有可播文字（如只有 `<user:happy><cmd:photo>`）时，MUST 在回答结束时依次发出 `assistantSpeechStarted`、`assistantSpeechEnded`；暂缓期间这两个事件推迟到释放后，被丢弃的回答不发出 |
| C-4 | `OfflineConversationEngine`（004）不发出 `assistantCommand` |

## 暂缓回应（005 增补）

| 编号 | 约定 |
|---|---|
| RH-1 | `holdReplies()` 之后，新到达的回答照常解析并发出 `assistantCommand` / `assistantText`，但不播放 TTS、不发出 `assistantSpeech*` / `assistantEmotion` / `assistantAction` / `assistantAudioLevel` |
| RH-2 | `releaseReplies(discardingTurnsStartedBefore: t)`：用户语音开始时刻早于 `t` 的暂缓回答全部丢弃（取消 TTS，不再发出任何事件）；其余按顺序正常播放；之后的回答恢复正常 |
| RH-3 | 被丢弃的回答仍保留在会话历史中 |
| RH-4 | `holdReplies` 不嵌套；未暂缓时调用 `releaseReplies` 无效果 |
| RH-5 | 暂缓期间插话判定照常运行，但只能清除可打断的播放（audio-gating.md AF-2） |
