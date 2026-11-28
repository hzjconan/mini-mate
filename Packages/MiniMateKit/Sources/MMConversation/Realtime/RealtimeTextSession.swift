import Foundation
import MMAudio

/// 实时语音会话错误（RS-1：严禁在错误关联值中携带 API Key 或原始鉴权头）。
public enum RealtimeError: Error, Sendable, Equatable {
    case authFailed
    case rateLimited
    case unsupportedConfiguration(String)
    case notConnected
    case network(underlying: String)
    case server(code: String, message: String)
}

/// 实时语音会话输出事件。
public enum RealtimeOutput: Sendable, Equatable {
    case speechStarted
    case speechEnded
    case userTranscript(String, isFinal: Bool)
    case textDelta(String)
    case responseDone
    case error(RealtimeError)
}

/// 方案 B 实时语音输入、纯文字输出的会话抽象（contracts/realtime-session.md）。
public protocol RealtimeTextSession: Sendable {
    /// 建立 WebSocket 并完成会话配置：只输出文字、服务端 VAD、instructions。
    func connect(instructions: String) async throws
    /// 推送一段音频（已转换为厂商要求的格式）；未连接时抛 `RealtimeError.notConnected`（RS-4）。
    func send(_ audio: AudioChunk) async throws
    /// 取消当前正在生成的回答（打断）。
    func cancelResponse() async
    /// 清空服务端尚未处理的输入音频缓冲。
    func clearInputBuffer() async
    var output: AsyncThrowingStream<RealtimeOutput, Error> { get }
    func close() async
}
