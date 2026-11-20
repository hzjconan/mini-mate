# Contract: 离线引擎与意图

**Module**: `MMConversation`（`OfflineConversationEngine`、`IntentMatcher`、`EngineSwitcher`） | **Feature**: `004-m3-memory-offline`

## OfflineConversationEngine

实现 003 的 `ConversationEngine` 协议，事件顺序与在线一致：

```
userSpeechStarted → userSpeechEnded → userTranscript(final)
→ [assistantSpeechStarted → assistantEmotion → assistantAction? → assistantAudioLevel* → assistantSpeechEnded]
```

| 编号 | 约定 |
|---|---|
| O-1 | 不发出 `userEmotion`（离线无法判断语气） |
| O-2 | 收音闸门、回声消除、打断沿用 003 实现 |
| O-3 | 输出音频优先使用预合成短句；无可用缓存时用 `AVSpeechSynthesizer`（`SystemTTSProvider`） |
| O-4 | 端侧转写不可用时（001 结论），不发出语音相关事件，仅保持感知反应；进入离线时提示一次 |

## IntentMatcher

```swift
public protocol IntentMatcher: Sendable {
    func match(_ text: String) -> IntentMatch
}

public struct IntentMatch: Sendable {
    public let intentID: String          // 未命中时为 "fallback"
    public let layer: Layer              // .keyword / .embedding / .none
    public let score: Double?
}
```

| 编号 | 约定 |
|---|---|
| I-1 | 先关键词层，命中即返回 |
| I-2 | 再 `NLEmbedding` 层（可用时），最近示例距离 < 阈值才命中 |
| I-3 | 匹配前去除标点与语气词（"呀""吧""嘛""呢"） |

## 初版意图

| id | 示例说法 | 动作 | 回应类别 |
|---|---|---|---|
| `greet` | 你好、嗨、早上好、我回来了 | `wave` | `greet` |
| `bye` | 再见、拜拜、我走了、晚安 | `wave` | `bye` |
| `praise` | 你真可爱、好棒、喜欢你 | `shyCover` | `praise` |
| `smile` | 笑一个、笑一下、开心点 | — | `action.smile`（表情 `happy`） |
| `spin` | 转个圈、转一下、绕一圈看看 | `spin` | `action.spin` |
| `nod` | 点点头、点个头 | `nod` | `action.nod` |
| `wave` | 挥挥手、招招手 | `wave` | `action.wave` |
| `heart` | 比个心、比心 | `heart` | `action.heart` |
| `fallback` | （未命中） | — | `offlineFallback` |

## EngineSwitcher

见 plan.md"在线 / 离线切换"表。

| 编号 | 约定 |
|---|---|
| SW-1 | 切换时不重启 `AudioIO` |
| SW-2 | 进行中的一轮被切换打断时，旧引擎发出 `assistantSpeechEnded` 后再切换 |
| SW-3 | `probing` 失败后的重试间隔 30 s；`NWPathMonitor` 报告网络变化时立即重试 |
| SW-4 | 切到离线时播放 `offlineNotice`；切回在线时播放 `reconnected` 并触发 `notice` 动作 |
