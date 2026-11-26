# Contract: 音频会话、收音闸门与打断

**Module**: `MMAudio` | **Feature**: `003-m2-voice-conversation`

## AudioIO（iOS）

```swift
public protocol AudioIO: Sendable {
    /// 采集流（已开启系统语音处理 / 回声消除），硬件采样率。
    var input: AsyncStream<AudioChunk> { get }
    /// 播放一段音频，排在当前队列之后。interruptible == false 的缓冲不会被 flush() 清除（005）。
    func enqueue(_ chunk: AudioChunk, turnID: UUID, interruptible: Bool) async
    /// 立即停止并清除全部可打断的缓冲（对话打断使用）。
    func flush() async
    /// 立即停止并移除指定 turn 的全部缓冲，不论是否可打断（005）。
    func cancel(turnID: UUID) async
    /// 播放电平，≥ 30 Hz。
    var outputLevel: AsyncStream<Float> { get }
    /// 当前是否正在播放。
    var isPlaying: Bool { get async }
    func start() async throws
    func stop() async
}
```

| 编号 | 约定 |
|---|---|
| IO-1 | `AVAudioSession`：category `.playAndRecord`，mode `.voiceChat`，options `.defaultToSpeaker`、蓝牙 |
| IO-2 | `inputNode.setVoiceProcessingEnabled(true)`；播放 MUST 经同一引擎的 `AVAudioPlayerNode` |
| IO-3 | 处理 `interruptionNotification`：开始时暂停并发出事件，结束后自动恢复 |
| IO-4 | 处理 `routeChangeNotification`：耳机插拔后保持外放 / 耳机的系统默认行为，引擎重启不丢失状态 |
| IO-5 | `flush()` 后 50 ms 内可打断的播放停止；`cancel(turnID:)` 后 50 ms 内该 turn 的播放停止 |
| AF-1 | 005：`enqueue(_:turnID:interruptible:)` 的 `interruptible` 默认 true（协议扩展提供默认值） |
| AF-2 | 005：`flush()` 只清除可打断的缓冲；不可打断的缓冲（拍照倒数短句、快门音效）继续播放 |
| AF-3 | 005：`cancel(turnID:)` 立即停止并移除该 turn 的全部缓冲，不论是否可打断 |
| AF-4 | 005：拍照短句与快门音效播放期间，人声闸门同样使用"播放期间"的提高阈值（G-3） |

## VoiceActivityGate（纯逻辑）

```swift
public protocol VoiceActivityGate: Sendable {
    mutating func process(_ chunk: AudioChunk, threshold: GateThreshold) -> GateDecision
}

public enum GateDecision: Sendable {
    case stayClosed
    case open(preRoll: [AudioChunk])   // 打开，附带预缓冲
    case forward                        // 保持打开，转发当前块
    case close                          // 拖尾结束，关闭
}
```

| 编号 | 约定 |
|---|---|
| G-1 | 连续人声 ≥ 120 ms 才打开；打开时返回最近 400 ms 预缓冲 |
| G-2 | 打开后静音持续 800 ms 才关闭（拖尾） |
| G-3 | `threshold` 为 `raised` / `playback` 时，判定阈值提高 6 dB |
| G-4 | 实现：`EnergyVoiceGate`（能量 + 过零率，可在 macOS 测试）；`SpeechDetectorGate`（若 V3 通过） |

## GazeGatePolicy（纯逻辑）

| 输入 | 输出 |
|---|---|
| 在看屏幕 | `normal` |
| 有人脸但不看屏幕 ≥ 3 s | `raised` |
| 无人脸 ≥ 30 s | `paused`（引擎断开会话） |
| `paused` 后人脸出现且看屏幕 ≥ 200 ms | `normal`（引擎重建会话） |

## BargeInDetector（纯逻辑）

| 编号 | 约定 |
|---|---|
| B-1 | 仅在 `isPlaying == true` 时工作 |
| B-2 | 使用 `playback` 阈值，连续人声 ≥ 250 ms 判定打断 |
| B-3 | 服务端 `speechStarted` 事件在播放期间到达，同样判定打断；两者取先到者，同一次插话只触发一次 |
| B-4 | 判定后引擎依次执行：`AudioIO.flush()`（只清可打断缓冲，AF-2）→ `TTSProvider.cancelAll()` → `RealtimeTextSession.cancelResponse()` → 取消旧 turn → 新一轮开始 |

## 隐私不变式

| 编号 | 不变式 |
|---|---|
| PV-1 | `GateState` 不为 `open` 时，`RealtimeTextSession.send` 调用次数为 0 |
| PV-2 | `muted` 与 `paused` 状态下不建立实时会话 |
