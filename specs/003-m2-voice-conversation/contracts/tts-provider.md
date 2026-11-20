# Contract: TTSProvider

**Module**: `MMConversation/TTS` | **Feature**: `003-m2-voice-conversation`

## 接口

```swift
public protocol TTSProvider: Sendable {
    /// 流式合成一句话。返回的音频格式由 `outputFormat` 给出。
    func synthesize(_ sentence: String, emotion: EmotionTag) -> AsyncThrowingStream<AudioChunk, Error>

    var outputFormat: AudioFormatDescription { get }

    /// 取消所有进行中的合成（打断）。
    func cancelAll() async
}
```

## 行为约定

| 编号 | 约定 |
|---|---|
| TTS-1 | 全程使用同一个音色（`TTSEmotionMapping.voice`），不得按情绪切换音色 |
| TTS-2 | `emotion` 经 `TTSEmotionMapping` 转为厂商参数；映射缺失时使用 `neutral` 的参数 |
| TTS-3 | 首个音频块到达即可交给播放器，不等整句合成完成 |
| TTS-4 | 合成失败抛错，由引擎跳过该句（spec Edge Cases） |
| TTS-5 | `cancelAll` 后，已取消请求的后续音频块 MUST NOT 再被产出 |
| TTS-6 | 若厂商返回字级 / 音素时间戳，通过 `AudioChunk.marks` 透传（用于将来精确口型与动作对齐）；没有则为空 |

## 情感映射表格式（`Resources/tts-emotion-<vendor>.json`）

```json
{
  "vendor": "aliyun",
  "voice": "待 M2a 选定",
  "map": {
    "happy":     { "待填": "厂商情感参数" },
    "gentle":    {},
    "sad":       {},
    "surprised": {},
    "shy":       {},
    "playful":   {},
    "concerned": {},
    "neutral":   {}
  }
}
```

M2a 用 `mm-probe tts --all-emotions` 逐一试听后填写；厂商不支持的情绪就近映射（如 `shy` → 温柔、`concerned` → 温柔偏低沉）。

## 实现

| 实现 | 说明 |
|---|---|
| `CosyVoiceTTSProvider` | 阿里百炼 |
| `DoubaoTTSProvider` | 火山引擎 |
| `SystemTTSProvider` | `AVSpeechSynthesizer`，004 断网兜底 |
| `FakeTTSProvider` | 测试：按字数生成静音 PCM，可注入延迟与失败 |
