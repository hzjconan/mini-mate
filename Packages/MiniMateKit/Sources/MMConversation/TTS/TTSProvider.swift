import Foundation
import MMAudio
import MMCore

/// TTS 合成错误。
public enum TTSError: Error, Sendable, Equatable {
    case cancelled
    case synthesisFailed(String)
    case invalidConfiguration(String)
}

/// 情感 TTS 提供方协议（contracts/tts-provider.md）。
public protocol TTSProvider: Sendable {
    /// 流式合成一句话。返回的音频格式由 `outputFormat` 给出。
    func synthesize(_ sentence: String, emotion: EmotionTag) -> AsyncThrowingStream<AudioChunk, Error>
    var outputFormat: AudioFormatDescription { get }
    /// 取消所有进行中的合成（打断，TTS-5）。
    func cancelAll() async
}
