import Foundation
import MMAudio
import MMSecurity

/// Built-in offline realtime driver for smoke tests, UI previews, and `mm-probe` offline runs.
public struct MockRealtimeDriver: RealtimeSessionDriver {
    public static let driverID = "mock-realtime"

    public let descriptor = ProviderDriverDescriptor(
        id: MockRealtimeDriver.driverID,
        role: .realtimeBrain,
        displayName: "本地模拟（离线演示）",
        summary: "无需联网或 API Key，用于在离线环境下验证对话协议、标签解析与夹具录制。",
        requiresPrimarySecret: false,
        supportsSecondarySecret: false,
        isBuiltInMock: true
    )

    public init() {}

    public func makeSession(
        profile: ProviderProfile,
        credentials: ProviderCredentials?,
        context: DriverBuildContext
    ) throws -> any RealtimeTextSession {
        let endpoint = profile.customEndpoint.flatMap(URL.init(string:))
            ?? URL(string: "wss://mock.local/realtime")!
        let transport: any WebSocketTransport
        if context.webSocketTransport is URLSessionWebSocketTransport {
            transport = LoopbackMockWebSocketTransport()
        } else {
            transport = context.webSocketTransport
        }
        var headers: [String: String] = [:]
        if let primary = credentials?.primarySecret, !primary.isEmpty {
            headers["Authorization"] = "Bearer \(primary)"
        }
        return FakeRealtimeTextSession(
            transport: transport,
            endpoint: endpoint,
            headers: headers
        )
    }
}

/// Built-in offline TTS driver wrapping `FakeTTSProvider` with 24 kHz mono PCM and word marks.
public struct MockTTSDriver: TTSProviderDriver {
    public static let driverID = "mock-tts"

    public let descriptor = ProviderDriverDescriptor(
        id: MockTTSDriver.driverID,
        role: .emotionalTTS,
        displayName: "本地模拟音色（离线演示）",
        summary: "无需联网或 API Key，生成 24 kHz 离线模拟音频与字级时间戳，用于验证 TTS 流程。",
        requiresPrimarySecret: false,
        supportsSecondarySecret: false,
        isBuiltInMock: true
    )

    public init() {}

    public func makeProvider(
        profile: ProviderProfile,
        credentials: ProviderCredentials?,
        context: DriverBuildContext
    ) throws -> any TTSProvider {
        FakeTTSProvider(
            outputFormat: .pcm24kMono,
            millisecondsPerCharacter: 100,
            chunkDurationMilliseconds: 100,
            chunkDelay: .zero,
            clock: context.clock,
            includeWordMarks: true
        )
    }
}

public extension ProviderRegistry {
    /// Returns a default registry pre-populated with built-in offline mock drivers.
    static func makeDefault() -> ProviderRegistry {
        let registry = ProviderRegistry()
        try? registry.register(MockRealtimeDriver())
        try? registry.register(MockTTSDriver())
        return registry
    }
}
