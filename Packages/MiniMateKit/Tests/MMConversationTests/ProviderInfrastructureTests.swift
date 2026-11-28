import Foundation
import os
import Testing
@testable import MMAudio
@testable import MMCore
@testable import MMConversation
@testable import MMProbeCore
@testable import MMSecurity

@Suite("Provider Infrastructure, Transport, Registry & MMProbeCore")
struct ProviderInfrastructureTests {
    // MARK: - Helpers

    private struct SecretRequiringRealtimeDriver: RealtimeSessionDriver {
        let descriptor = ProviderDriverDescriptor(
            id: "custom-secret-realtime",
            role: .realtimeBrain,
            displayName: "Custom Secret Realtime",
            summary: "Requires a primary secret.",
            requiresPrimarySecret: true,
            supportsSecondarySecret: true,
            isBuiltInMock: false
        )

        func makeSession(
            profile: ProviderProfile,
            credentials: ProviderCredentials?,
            context: DriverBuildContext
        ) throws -> any RealtimeTextSession {
            FakeRealtimeTextSession(scriptedOutputs: [.responseDone])
        }
    }

    /// Mock transport that echoes handshake header values and sensitive JSON fields back in inbound text frames
    /// so we can prove `RecordingWebSocketTransport` redacts handshake headers automatically.
    private final class EchoingMockWebSocketTransport: WebSocketTransport, Sendable {
        private final class Connection: WebSocketConnection, Sendable {
            private let inbound: OSAllocatedUnfairLock<[WebSocketMessage]>

            init(inbound: [WebSocketMessage]) {
                self.inbound = OSAllocatedUnfairLock(initialState: inbound)
            }

            func send(_ message: WebSocketMessage) async throws {}

            func receive() async throws -> WebSocketMessage {
                let next = inbound.withLock { list -> WebSocketMessage? in
                    guard !list.isEmpty else { return nil }
                    return list.removeFirst()
                }
                if let next {
                    return next
                }
                throw WebSocketTransportError.connectionClosed(code: 1000, reason: "eof")
            }

            func close(code: Int, reason: String?) async {}
        }

        func connect(url: URL, headers: [String: String]) async throws -> any WebSocketConnection {
            let customAuth = headers["X-Custom-Auth"] ?? ""
            let echoed = #"{"type":"text.delta","delta":"echo \#(customAuth)","api_key":"inline-json-secret"}"#
            return Connection(inbound: [
                .text(echoed),
                .text(#"{"type":"response.done"}"#),
            ])
        }
    }

    /// Mock transport whose connection throws a transport failure immediately on `receive()`.
    private final class FailingReceiveMockWebSocketTransport: WebSocketTransport, Sendable {
        private final class Connection: WebSocketConnection, Sendable {
            func send(_ message: WebSocketMessage) async throws {}
            func receive() async throws -> WebSocketMessage {
                throw WebSocketTransportError.transportFailure("simulated socket reset")
            }
            func close(code: Int, reason: String?) async {}
        }

        func connect(url: URL, headers: [String: String]) async throws -> any WebSocketConnection {
            Connection()
        }
    }

    private func makeSineWAV(
        amplitude: Double,
        durationSeconds: Double = 0.3,
        sampleRate: Int = 16_000,
        at url: URL
    ) throws {
        let count = Int(Double(sampleRate) * durationSeconds)
        let samples: [Int16] = (0..<count).map { i in
            let phase = 2.0 * Double.pi * 440.0 * Double(i) / Double(sampleRate)
            return Int16(max(-32767, min(32767, sin(phase) * amplitude * 32767.0)))
        }
        try WAVCodec.writeWAV(
            chunks: [AudioChunk(samples: samples, sampleRate: sampleRate)],
            sampleRate: sampleRate,
            to: url
        )
    }

    // MARK: - ProviderRegistry

    @Test func registryDefaultDescriptorsCustomRegistrationAndErrorGuards() throws {
        let registry = ProviderRegistry.makeDefault()

        #expect(registry.descriptors(for: .realtimeBrain).map(\.id) == ["mock-realtime"])
        #expect(registry.descriptors(for: .emotionalTTS).map(\.id) == ["mock-tts"])

        // Duplicate registration throws duplicateDriverID.
        #expect(throws: ProviderRegistryError.duplicateDriverID("mock-realtime")) {
            try registry.register(MockRealtimeDriver())
        }

        // Register custom secret-requiring driver.
        try registry.register(SecretRequiringRealtimeDriver())
        #expect(registry.descriptors(for: .realtimeBrain).map(\.id) == ["mock-realtime", "custom-secret-realtime"])

        // Missing required primary secret throws missingPrimarySecret.
        let secretProfile = ProviderProfile(
            role: .realtimeBrain,
            name: "Secret Brain",
            driverID: "custom-secret-realtime"
        )
        #expect(throws: ProviderRegistryError.missingPrimarySecret(driverID: "custom-secret-realtime")) {
            _ = try registry.makeRealtimeSession(profile: secretProfile, credentials: nil)
        }

        // Valid secret succeeds.
        _ = try registry.makeRealtimeSession(
            profile: secretProfile,
            credentials: ProviderCredentials(primarySecret: "demo-token-123456")
        )

        // Unknown driver throws driverNotFound.
        let unknownProfile = ProviderProfile(role: .realtimeBrain, name: "Missing", driverID: "nonexistent")
        #expect(throws: ProviderRegistryError.driverNotFound("nonexistent")) {
            _ = try registry.makeRealtimeSession(profile: unknownProfile, credentials: nil)
        }

        // Wrong role throws roleMismatch.
        let wrongRoleProfile = ProviderProfile(role: .emotionalTTS, name: "Wrong", driverID: "mock-realtime")
        #expect(throws: ProviderRegistryError.roleMismatch(expected: .realtimeBrain, actual: .emotionalTTS)) {
            _ = try registry.makeRealtimeSession(profile: wrongRoleProfile, credentials: nil)
        }
    }

    // MARK: - FakeRealtimeTextSession (RS-4 + Full Lifecycle + Disconnect/Deinit)

    @Test func fakeRealtimeTextSessionLifecycleAndRS4NotConnectedGuard() async throws {
        let session = FakeRealtimeTextSession(transport: LoopbackMockWebSocketTransport(silenceTriggerMs: 200))

        // RS-4: send before connect throws notConnected.
        await #expect(throws: RealtimeError.notConnected) {
            try await session.send(AudioChunk(samples: [100, 200], sampleRate: 16_000))
        }

        try await session.connect(instructions: "test instructions")

        let collector = Task<[RealtimeOutput], Error> {
            var events: [RealtimeOutput] = []
            for try await event in session.output {
                events.append(event)
                if event == .responseDone {
                    break
                }
            }
            return events
        }

        // Send loud speech then silence to trigger VAD.
        let speechSamples = [Int16](repeating: 12_000, count: 1600)
        let silenceSamples = [Int16](repeating: 0, count: 1600)
        try await session.send(AudioChunk(samples: speechSamples, sampleRate: 16_000))
        try await session.send(AudioChunk(samples: silenceSamples, sampleRate: 16_000))
        try await session.send(AudioChunk(samples: silenceSamples, sampleRate: 16_000))

        let events = try await collector.value
        #expect(events.first == .speechStarted)
        #expect(events.contains(.speechEnded))
        #expect(events.contains(where: { if case .userTranscript(_, true) = $0 { return true }; return false }))
        #expect(events.last == .responseDone)

        let deltas = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }
        var parser = TagParser()
        var segments: [TaggedSegment] = []
        for delta in deltas {
            segments.append(contentsOf: parser.feed(delta))
        }
        segments.append(contentsOf: parser.finish())
        #expect(segments.contains(where: { if case .userEmotion(.happy) = $0 { return true }; return false }))
        #expect(segments.contains(where: { if case .emotion(.happy) = $0 { return true }; return false }))
        #expect(segments.contains(where: { if case .action(.wave) = $0 { return true }; return false }))

        await session.cancelResponse()
        await session.clearInputBuffer()
        #expect(session.cancelCount == 1)
        #expect(session.clearCount == 1)

        await session.close()

        // RS-4: send after close throws notConnected.
        await #expect(throws: RealtimeError.notConnected) {
            try await session.send(AudioChunk(samples: [100, 200], sampleRate: 16_000))
        }
    }

    @Test func fakeRealtimeTextSessionPropagatesUnexpectedDisconnectAndFinishesOnDeinit() async throws {
        // 1. Unexpected disconnect terminates output stream with RealtimeError.network instead of hanging.
        let failingSession = FakeRealtimeTextSession(transport: FailingReceiveMockWebSocketTransport())
        try await failingSession.connect(instructions: "test")
        var caughtNetworkError = false
        do {
            for try await _ in failingSession.output {}
        } catch RealtimeError.network(let message) {
            caughtNetworkError = message.contains("simulated socket reset")
        }
        #expect(caughtNetworkError)

        // 2. Releasing session without calling close() terminates output cleanly instead of hanging.
        let stream: AsyncThrowingStream<RealtimeOutput, Error>
        do {
            let ephemeral = FakeRealtimeTextSession(transport: LoopbackMockWebSocketTransport())
            try await ephemeral.connect(instructions: "ephemeral")
            stream = ephemeral.output
        }
        var count = 0
        for try await _ in stream {
            count += 1
        }
        #expect(count == 0)
    }

    // MARK: - SecretRedactor, RecordingWebSocketTransport & Fixture Replay (RS-1 / RS-5)

    @Test func secretRedactorRegexRulesWorkIndependentlyOfExplicitSecrets() {
        let syntheticSK = ["sk", "regex", "testtoken", "12345678"].joined(separator: "-")
        let bearerToken = ["tok", "bearer", "9876543210"].joined(separator: "_")
        let raw = #"Header: Bearer \#(bearerToken), Key: \#(syntheticSK), JSON: {"api_key":"json-api-secret","authorization":"auth-secret-val","ok":true}"#

        // Pass secrets: [] to prove regex rules themselves perform redaction.
        let redacted = SecretRedactor.redact(raw, secrets: [])
        #expect(!redacted.contains(bearerToken))
        #expect(!redacted.contains(syntheticSK))
        #expect(!redacted.contains("json-api-secret"))
        #expect(!redacted.contains("auth-secret-val"))
        #expect(redacted.contains("Bearer [REDACTED]"))
        #expect(redacted.contains(#""api_key":"[REDACTED]""#))
        #expect(redacted.contains(#""authorization":"[REDACTED]""#))
    }

    @Test func recordingTransportRedactsHandshakeHeadersFiltersOutboundAudioAndReplaysBundledFixture() async throws {
        let headerSecret = ["hdr", "secret", "value", "abcdef99"].joined(separator: "-")

        // 1. Prove RecordingWebSocketTransport injects handshake header values into redaction set even when init(secrets: []) is empty.
        let echoRecorder = RecordingWebSocketTransport(
            underlying: EchoingMockWebSocketTransport(),
            secrets: []
        )
        let echoSession = FakeRealtimeTextSession(
            transport: echoRecorder,
            headers: ["X-Custom-Auth": headerSecret]
        )
        try await echoSession.connect(instructions: "hello")
        for try await event in echoSession.output {
            if event == .responseDone { break }
        }
        await echoSession.close()

        let echoJSONL = String(decoding: try echoRecorder.encodeJSONLines(), as: UTF8.self)
        #expect(!echoJSONL.contains(headerSecret))
        #expect(!echoJSONL.contains("inline-json-secret"))
        #expect(echoJSONL.contains("[REDACTED]"))

        // 2. Prove outbound audio frames are filtered out on loopback session.
        let loopbackRecorder = RecordingWebSocketTransport(
            underlying: LoopbackMockWebSocketTransport(silenceTriggerMs: 200),
            secrets: []
        )
        let loopbackSession = FakeRealtimeTextSession(
            transport: loopbackRecorder,
            headers: ["X-Custom-Auth": headerSecret]
        )
        try await loopbackSession.connect(instructions: "hello")
        let doneTask = Task {
            for try await event in loopbackSession.output {
                if event == .responseDone { break }
            }
        }
        try await loopbackSession.send(AudioChunk(samples: [Int16](repeating: 4_000, count: 1600), sampleRate: 16_000))
        try await loopbackSession.send(AudioChunk(samples: [Int16](repeating: 0, count: 3200), sampleRate: 16_000))
        try await doneTask.value
        await loopbackSession.close()

        let loopbackJSONL = try loopbackRecorder.encodeJSONLines()
        let loopbackText = String(decoding: loopbackJSONL, as: UTF8.self)
        #expect(!loopbackText.contains("audio.chunk"))
        #expect(!loopbackText.contains(headerSecret))
        #expect(!(try RecordingWebSocketTransport.decodeJSONLines(loopbackJSONL)).isEmpty)

        // 3. Replay bundled fixture from Bundle.module Fixtures subdirectory.
        let fixtureURL = try #require(
            Bundle.module.url(forResource: "mock-realtime-sample", withExtension: "jsonl", subdirectory: "Fixtures")
        )
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixtureRecords = try RecordingWebSocketTransport.decodeJSONLines(fixtureData)
        let replay = MockRealtimeProtocol.replayFixture(fixtureRecords)

        #expect(replay.outputs.first == .speechStarted)
        #expect(replay.outputs.contains(.userTranscript("我今天还行吧", isFinal: true)))
        #expect(replay.outputs.contains(.speechEnded))
        #expect(replay.outputs.last == .responseDone)
        #expect(replay.unexpectedAudioCount == 1)
        #expect(replay.ignoredTypes == ["server.heartbeat"])
    }

    // MARK: - GzipCodec

    @Test func gzipCodecRoundTripsAndEnforcesMaxOutputBytes() throws {
        // Empty payload
        let emptyCompressed = try GzipCodec.compress(Data())
        #expect(try GzipCodec.decompress(emptyCompressed) == Data())

        // Chinese JSON payload
        let chineseJSON = Data(#"{"text":"你好呀，今天过得怎么样？","tags":["happy","nod"]}"#.utf8)
        let compressedJSON = try GzipCodec.compress(chineseJSON)
        #expect(try GzipCodec.decompress(compressedJSON) == chineseJSON)

        // 16 KB payload + bomb limit check
        let largePayload = Data(repeating: 0x41, count: 16_384)
        let compressedLarge = try GzipCodec.compress(largePayload)
        #expect(try GzipCodec.decompress(compressedLarge) == largePayload)

        #expect(throws: GzipError.sizeLimitExceeded(1024)) {
            _ = try GzipCodec.decompress(compressedLarge, maxOutputBytes: 1024)
        }

        // Corrupted input throws invalidData or zlibFailed.
        var threwCorrupt = false
        do {
            _ = try GzipCodec.decompress(Data([0x1F, 0x8B, 0xFF, 0x00, 0x01]))
        } catch GzipError.invalidData, GzipError.zlibFailed {
            threwCorrupt = true
        }
        #expect(threwCorrupt)
    }

    // MARK: - MMProbeCore CLI End-to-End (All 5 Subcommands Offline)

    @Test func probeArgumentsValidationAndRunnerOfflineEndToEnd() async throws {
        // Argument errors
        #expect(throws: ProbeArgumentError.missingSubcommand) {
            _ = try ProbeArguments.parse([])
        }
        #expect(throws: ProbeArgumentError.unknownSubcommand("bad-cmd")) {
            _ = try ProbeArguments.parse(["bad-cmd"])
        }
        #expect(throws: ProbeArgumentError.conflictingOptions("Cannot pass both --all-emotions and --emotion.")) {
            _ = try ProbeArguments.parse([
                "tts", "--driver", "mock-tts", "--text", "hi", "--all-emotions", "--emotion", "happy", "--out", "/tmp/x",
            ])
        }
        // Option value "-h" must not be misinterpreted as help flag.
        let dashHText = try ProbeArguments.parse([
            "tts", "--driver", "mock-tts", "--text", "-h", "--emotion", "happy", "--out", "/tmp/x",
        ])
        if case .tts(let opts) = dashHText {
            #expect(opts.text == "-h")
        } else {
            Issue.record("Expected .tts command when --text value is '-h'")
        }

        let runner = ProbeRunner(registry: .makeDefault())

        // 1. list-drivers
        let listResult = await runner.run(arguments: ["list-drivers"])
        #expect(listResult.exitCode == 0)
        #expect(listResult.stdout.contains("mock-realtime"))
        #expect(listResult.stdout.contains("mock-tts"))

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimate-probe-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 2. tts --all-emotions -> 8 valid WAV files
        let ttsOutDir = tempDir.appendingPathComponent("tts-out", isDirectory: true)
        let ttsResult = await runner.run(arguments: [
            "tts", "--driver", "mock-tts", "--text", "你好呀", "--all-emotions", "--out", ttsOutDir.path,
        ])
        #expect(ttsResult.exitCode == 0)
        #expect(ttsResult.stdout.contains("V6 TTFB p50"))
        for emotion in EmotionTag.allCases {
            let wavURL = ttsOutDir.appendingPathComponent("\(emotion.rawValue).wav")
            let data = try Data(contentsOf: wavURL)
            let decoded = try WAVCodec.decodePCM16MonoWAV(data)
            #expect(!decoded.samples.isEmpty)
        }

        // 3. realtime single sample
        let sampleWAV = tempDir.appendingPathComponent("single.wav")
        try makeSineWAV(amplitude: 0.4, at: sampleWAV)
        let realtimeResult = await runner.run(arguments: [
            "realtime", "--driver", "mock-realtime", "--input", sampleWAV.path, "--pace", "0",
        ])
        #expect(realtimeResult.exitCode == 0)
        #expect(realtimeResult.stdout.contains("V4 Text-Only Audit**: PASS"))
        #expect(realtimeResult.stdout.contains("happy"))

        // 4. tone-suite with 9 synthetic WAVs of distinct energy levels per group -> 3/3 distinguishable
        let samplesDir = tempDir.appendingPathComponent("voice-samples", isDirectory: true)
        let toneAmplitudes: [(String, Double)] = [
            ("fine-happy.wav", 0.50), ("fine-flat.wav", 0.15), ("fine-sad.wav", 0.04),
            ("ok-happy.wav", 0.50), ("ok-flat.wav", 0.15), ("ok-sad.wav", 0.04),
            ("done-happy.wav", 0.50), ("done-tired.wav", 0.15), ("done-angry.wav", 0.04),
        ]
        for (fileName, amp) in toneAmplitudes {
            try makeSineWAV(amplitude: amp, at: samplesDir.appendingPathComponent(fileName))
        }
        let suiteResult = await runner.run(arguments: [
            "tone-suite", "--driver", "mock-realtime", "--samples-dir", samplesDir.path, "--pace", "0",
        ])
        #expect(suiteResult.exitCode == 0)
        #expect(suiteResult.stdout.contains("V5 / SC-002 Distinguishable Tone Groups**: 3/3"))
        #expect(suiteResult.stdout.contains("First Text Latency p50"))
        #expect(suiteResult.stdout.contains("V7 User Transcript Hits**: 9/9"))

        // 5. record-fixture produces sanitized JSONL without secret or outbound audio
        let fixtureOut = tempDir.appendingPathComponent("recorded.jsonl")
        let secretEnvVal = ["sk", "unit", "test", "secret", "000111222"].joined(separator: "-")
        let recordResult = await runner.run(
            arguments: [
                "record-fixture", "--driver", "mock-realtime",
                "--input", sampleWAV.path, "--out", fixtureOut.path, "--pace", "0",
            ],
            environment: ["MM_REALTIME_KEY": secretEnvVal]
        )
        #expect(recordResult.exitCode == 0)
        let recordedData = try Data(contentsOf: fixtureOut)
        let recordedText = String(decoding: recordedData, as: UTF8.self)
        #expect(!recordedText.contains(secretEnvVal))
        #expect(!recordedText.contains("audio.chunk"))
        let parsedRecords = try RecordingWebSocketTransport.decodeJSONLines(recordedData)
        #expect(!parsedRecords.isEmpty)

        // 6. Unknown driver, missing input, and invalid --endpoint exit with code 2.
        let badDriver = await runner.run(arguments: [
            "realtime", "--driver", "nonexistent", "--input", sampleWAV.path,
        ])
        #expect(badDriver.exitCode == 2)

        let missingFile = await runner.run(arguments: [
            "realtime", "--driver", "mock-realtime", "--input", tempDir.appendingPathComponent("nope.wav").path,
        ])
        #expect(missingFile.exitCode == 2)

        let badEndpoint = await runner.run(arguments: [
            "realtime", "--driver", "mock-realtime", "--input", sampleWAV.path, "--endpoint", "ftp://bad",
        ])
        #expect(badEndpoint.exitCode == 2)
    }
}
