# Contract: 预置短句与垫场

**Module**: `MMConversation/Presets`、`MMConversation/Filler` | **Feature**: `004-m3-memory-offline`

## PresetSynthesizer

```swift
public protocol PresetSynthesizer: Sendable {
    /// 当前缓存状态。
    func status() async -> PresetCacheStatus      // .ready / .stale(reason) / .missing / .partial(done, total)
    /// 用当前 TTS 音色批量合成全部短句；进度通过 AsyncStream 返回。
    func synthesizeAll() -> AsyncThrowingStream<Progress, Error>
}
```

| 编号 | 约定 |
|---|---|
| P-1 | 合成使用 003 的 `TTSProvider` 与 `TTSEmotionMapping`，与在线回答同一音色 |
| P-2 | 写入临时目录，全部成功后原子替换正式目录与 `manifest.json` |
| P-3 | `vendor`、`voice`、`catalogVersion` 任一不符 → `.stale` |
| P-4 | 音频以播放器原生格式保存（避免播放时转换），确保播放延迟 < 50 ms |

## PresetPlayer

```swift
public protocol PresetPlayer: Sendable {
    /// 从类别中随机选一条（避免与该类别上一次相同）并播放，返回实际播放的条目与是否完整播完。
    /// interruptible / emitsEmotion 为 005 增补，协议扩展提供默认值 true / true。
    func play(category: String, turnID: UUID, interruptible: Bool, emitsEmotion: Bool) async -> PresetPlayback?
    /// 005：停止指定 turn 的播放（经 AudioIO.cancel(turnID:)）。
    func stop(turnID: UUID) async
    func preload() async
}

public struct PresetPlayback: Sendable {
    public let phrase: PresetPhrase
    public let result: PlaybackResult          // MMCore：completed / stopped
}
```

| 编号 | 约定 |
|---|---|
| PP-1 | 启动时 `preload()` 把全部短句读入内存（约 40 条，体积可忽略） |
| PP-2 | 播放走 003 的 `AudioIO.enqueue`；`interruptible == true`（默认）时同样可被插话打断 |
| PP-3 | 播放期间发出 `assistantAudioLevel`；`emitsEmotion == true`（默认）时同样发出 `assistantEmotion` |
| PP-4 | 005：`emitsEmotion == false` 时不发出 `assistantEmotion`（表情由 `assistantCue` 负责）；`interruptible == false` 时不会被 `AudioIO.flush()` 清除 |
| PP-5 | 005：`stop(turnID:)` 立即停止该 turn，`play` 返回 `result == .stopped` |

## FillerPolicy（纯逻辑）

```swift
public struct FillerPolicy: Sendable {
    public var threshold: Duration = .milliseconds(1200)
    public var minTurnsBetween: Int = 3
    public func shouldPlay(userSpeechEndedAt: TimeInterval, now: TimeInterval,
                           firstTextArrived: Bool, currentTurn: Int, lastFillerTurn: Int?) -> Bool
}
```

| 编号 | 约定 |
|---|---|
| F-1 | 仅当 `!firstTextArrived && now - userSpeechEndedAt >= threshold && 距上次垫场 >= minTurnsBetween` 时为 true |
| F-2 | 每轮最多一次 |
| F-3 | 实质回答首句在垫场短句播完后入队，间隔 < 150 ms |

## 初版清单（`preset-phrases.json`，约 40 条）

| 类别 | 条数 | 示例 | 情绪 |
|---|---|---|---|
| `greet` | 4 | 你来啦～ / 嗨，又见面啦 | happy |
| `bye` | 3 | 拜拜，早点休息哦 | gentle |
| `backchannel` | 5 | 嗯嗯 / 对呀 / 原来是这样 | gentle |
| `filler` | 5 | 嗯…我想想 / 让我想一下哦 | neutral |
| `praise` | 3 | 哎呀，你这么说我会害羞的 | shy |
| `offlineNotice` | 2 | 网好像断了，不过我还在这儿陪你 | concerned |
| `offlineFallback` | 4 | 这个等网好了我们再聊好不好？ | gentle |
| `reconnected` | 2 | 网回来啦！ | happy |
| `action.*` | 每个 `ActionTag` 1–2 条，另加 `action.smile`（只有表情、无动作） | 看我转一圈～ / 比心！ | playful |
| `photo.*` | 005：问句、倒数四拍与提示，文本清单来自 005 的 `photo-phrases.json`（005 data-model.md `PhotoPhrase`） | 准备好了吗？/ 三 / 茄子～ | 见 005 |
