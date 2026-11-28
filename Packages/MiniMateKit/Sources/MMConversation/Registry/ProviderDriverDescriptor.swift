import Foundation
import MMCore
import MMSecurity

/// Metadata describing a registered protocol driver (used dynamically by Settings UI and `mm-probe`).
public struct ProviderDriverDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let role: ProviderRole
    public let displayName: String
    public let summary: String
    public let requiresPrimarySecret: Bool
    public let supportsSecondarySecret: Bool
    public let isBuiltInMock: Bool

    public init(
        id: String,
        role: ProviderRole,
        displayName: String,
        summary: String,
        requiresPrimarySecret: Bool = true,
        supportsSecondarySecret: Bool = false,
        isBuiltInMock: Bool = false
    ) {
        self.id = id
        self.role = role
        self.displayName = displayName
        self.summary = summary
        self.requiresPrimarySecret = requiresPrimarySecret
        self.supportsSecondarySecret = supportsSecondarySecret
        self.isBuiltInMock = isBuiltInMock
    }
}

/// Shared runtime dependencies injected into drivers when constructing a session or TTS provider.
/// External drivers MUST prefer `webSocketTransport` / `httpTransport` here so `record-fixture`
/// and offline unit tests work transparently.
public struct DriverBuildContext: Sendable {
    public let clock: any MMCore.Clock
    public let webSocketTransport: any WebSocketTransport
    public let httpTransport: any HTTPStreamingTransport
    public let emotionMappingOverride: TTSEmotionMapping?

    public init(
        clock: any MMCore.Clock = SystemClock(),
        webSocketTransport: any WebSocketTransport = URLSessionWebSocketTransport(),
        httpTransport: any HTTPStreamingTransport = URLSessionHTTPStreamingTransport(),
        emotionMappingOverride: TTSEmotionMapping? = nil
    ) {
        self.clock = clock
        self.webSocketTransport = webSocketTransport
        self.httpTransport = httpTransport
        self.emotionMappingOverride = emotionMappingOverride
    }
}

/// Factory protocol for registering a realtime speech-to-text-with-tags driver.
public protocol RealtimeSessionDriver: Sendable {
    var descriptor: ProviderDriverDescriptor { get }
    func makeSession(
        profile: ProviderProfile,
        credentials: ProviderCredentials?,
        context: DriverBuildContext
    ) throws -> any RealtimeTextSession
}

/// Factory protocol for registering an emotional TTS driver.
public protocol TTSProviderDriver: Sendable {
    var descriptor: ProviderDriverDescriptor { get }
    func makeProvider(
        profile: ProviderProfile,
        credentials: ProviderCredentials?,
        context: DriverBuildContext
    ) throws -> any TTSProvider
}
