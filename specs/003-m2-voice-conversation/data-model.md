# Data Model: M2 语音对话

**Feature**: `003-m2-voice-conversation`

复用 002 中 `MMCore` 的 `EmotionTag`、`ActionTag`、`UserEmotion`、`ConversationEvent`。本 feature 为 `ConversationEvent` 增加两个 case：

| case | 说明 |
|---|---|
| `connectionStateChanged(ConnectionState)` | `connecting` / `connected` / `reconnecting(attempt)` / `lost` |
| `gateStateChanged(GateState)` | 收音闸门状态变化（驱动静音姿态与调试显示） |

## MMAudio

### AudioChunk

| 字段 | 类型 | 说明 |
|---|---|---|
| `samples` | `[Int16]` 或 `Data` | PCM 16-bit 单声道 |
| `sampleRate` | `Int` | 采集为硬件采样率；送云端前转换为厂商要求 |
| `hostTime` | `UInt64` | 采集时刻，用于指标 |

### GateState

| case | 含义 | 是否上传音频 |
|---|---|---|
| `muted` | 用户静音 | 否 |
| `paused` | 无人脸 > 30 s，会话已断开 | 否 |
| `closed` | 正常监听，未检测到人声 | 否 |
| `open` | 检测到人声，正在推送 | 是 |

附加属性 `threshold: GateThreshold`（`normal` / `raised` / `playback`）。

### GazeGateDecision（`GazeGatePolicy` 输出）

`normal` · `raised`（不看屏幕 > 3 s）· `paused`（无人脸 > 30 s）

### VoiceGateParams（初值）

| 参数 | 初值 |
|---|---|
| 预缓冲 | 400 ms |
| 打开：连续人声 | 120 ms |
| 关闭拖尾 | 800 ms |
| `raised` 阈值增量 | +6 dB |
| 打断：播放期阈值增量 | +6 dB |
| 打断：连续人声 | 250 ms |

## MMConversation

### Persona

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | `String` | "小瓜" |
| `description` | `String` | 性格与说话风格 |
| `addressUserAs` | `String` | 对用户的称呼 |
| `rules` | `[String]` | 如"每次回答 1–3 句""不使用表情符号" |

源文件 `Resources/persona.md`；与标签协议说明一起组成会话 instructions。

### RealtimeOutput（`RealtimeTextSession` 输出）

| case | 说明 |
|---|---|
| `speechStarted` / `speechEnded` | 服务端 VAD 事件 |
| `userTranscript(String, isFinal: Bool)` | 用户输入转写（若厂商提供） |
| `textDelta(String)` | 回答文字增量（含标签） |
| `responseDone` | 本次回答结束 |
| `error(RealtimeError)` | |

### TaggedSegment（`TagParser` 输出）

| case | 说明 |
|---|---|
| `userEmotion(UserEmotion)` | |
| `emotion(EmotionTag)` | |
| `action(ActionTag)` | |
| `text(String)` | 已去除标签的文字 |

### Sentence（`SentenceSplitter` 输出）

| 字段 | 类型 | 说明 |
|---|---|---|
| `turnID` | `UUID` | |
| `index` | `Int` | 本轮内序号 |
| `text` | `String` | 送入 TTS 的纯文字 |
| `emotion` | `EmotionTag` | 该句情绪（沿用上一个值） |
| `actions` | `[(ActionTag, charOffset: Int)]` | 句内动作及其字符位置 |

### TTSEmotionMapping

| 字段 | 类型 | 说明 |
|---|---|---|
| `vendor` | `VendorID` | |
| `voice` | `String` | 音色 ID |
| `map` | `[EmotionTag: VendorEmotionParams]` | 厂商不支持的情绪就近映射 |

以 JSON 资源保存：`Resources/tts-emotion-<vendor>.json`。

### TurnMetrics

| 字段 | 说明 |
|---|---|
| `turnID` | |
| `userStoppedAt` | 本地闸门检测到停止发声（指标起点） |
| `thinkingShownAt` | 状态机进入 Thinking → M_feedback |
| `serverSpeechEndAt` | 服务端端点事件 |
| `firstTextAt` | 首个文字增量 |
| `firstSentenceAt` | 首句完成分句 |
| `firstAudioChunkAt` | TTS 首包到达 |
| `firstAudioPlayedAt` | 首包开始播放 → M_answer |
| `bargeInDetectedAt` / `playbackStoppedAt` | → M_bargein |
| `vendor` / `isPeakHour` | 对比用 |
