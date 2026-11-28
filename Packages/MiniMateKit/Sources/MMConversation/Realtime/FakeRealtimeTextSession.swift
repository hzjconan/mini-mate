import Foundation
import MMAudio
import MMCore
import os

/// Optional audit protocol for `RealtimeTextSession` implementations to report
/// unexpected server-generated audio frames during text-only (V4) verification.
public protocol RealtimeSessionAuditable: Sendable {
    var unexpectedAudioEventCount: Int { get }
}

/// Result of replaying a sanitized JSONL fixture through `MockRealtimeProtocol`.
public struct MockFixtureReplayResult: Sendable, Equatable {
    public let outputs: [RealtimeOutput]
    public let unexpectedAudioCount: Int
    public let ignoredTypes: [String]

    public init(outputs: [RealtimeOutput], unexpectedAudioCount: Int, ignoredTypes: [String]) {
        self.outputs = outputs
        self.unexpectedAudioCount = unexpectedAudioCount
        self.ignoredTypes = ignoredTypes
    }
}

/// Driver-agnostic mock JSON WebSocket protocol used for offline testing and fixture replay (RS-5).
public enum MockRealtimeProtocol {
    public static func decodeInboundFrame(_ text: String) -> (output: RealtimeOutput?, isUnexpectedAudio: Bool, ignoredType: String?) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else {
            return (nil, false, "malformed")
        }

        switch type {
        case "session.ready":
            return (nil, false, nil)
        case "speech.started":
            return (.speechStarted, false, nil)
        case "speech.ended":
            return (.speechEnded, false, nil)
        case "user.transcript":
            let transcript = object["text"] as? String ?? ""
            let isFinal = object["is_final"] as? Bool ?? true
            return (.userTranscript(transcript, isFinal: isFinal), false, nil)
        case "text.delta":
            let delta = object["delta"] as? String ?? ""
            return (.textDelta(delta), false, nil)
        case "response.done":
            return (.responseDone, false, nil)
        case "audio.delta":
            return (nil, true, nil)
        case "error":
            let code = object["code"] as? String ?? "unknown"
            let message = SecretRedactor.redact(object["message"] as? String ?? "")
            return (.error(.server(code: code, message: message)), false, nil)
        default:
            return (nil, false, type)
        }
    }

    public static func replayFixture(_ records: [FixtureFrameRecord]) -> MockFixtureReplayResult {
        var outputs: [RealtimeOutput] = []
        var unexpectedAudioCount = 0
        var ignoredTypes: [String] = []

        for record in records where record.direction == .inbound && record.kind == .text {
            guard let text = record.text else { continue }
            let decoded = decodeInboundFrame(text)
            if let output = decoded.output {
                outputs.append(output)
            }
            if decoded.isUnexpectedAudio {
                unexpectedAudioCount += 1
            }
            if let ignored = decoded.ignoredType {
                ignoredTypes.append(ignored)
            }
        }

        return MockFixtureReplayResult(
            outputs: outputs,
            unexpectedAudioCount: unexpectedAudioCount,
            ignoredTypes: ignoredTypes
        )
    }
}

/// Offline in-memory WebSocket transport simulating a text-only realtime speech server with VAD.
/// Deterministic: maps average speech RMS energy to distinct `<user:...>` tags so offline tone-suite tests work without network.
public final class LoopbackMockWebSocketTransport: WebSocketTransport, Sendable {
    private let silenceTriggerMs: Int
    private let emitUnexpectedAudio: Bool

    public init(silenceTriggerMs: Int = 400, emitUnexpectedAudio: Bool = false) {
        self.silenceTriggerMs = max(100, silenceTriggerMs)
        self.emitUnexpectedAudio = emitUnexpectedAudio
    }

    public func connect(url: URL, headers: [String: String]) async throws -> any WebSocketConnection {
        LoopbackMockWebSocketConnection(
            silenceTriggerMs: silenceTriggerMs,
            emitUnexpectedAudio: emitUnexpectedAudio
        )
    }
}

private final class LoopbackMockWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    private struct State {
        var closed = false
        var inSpeech = false
        var speechEnergySum: Double = 0
        var speechChunkCount: Int = 0
        var trailingSilenceMs: Int = 0
        var silentOnlyMs: Int = 0
        var turnIndex: Int = 0
        var inboundQueue: [WebSocketMessage] = []
        var waitingReceivers: [CheckedContinuation<WebSocketMessage, Error>] = []
    }

    private let silenceTriggerMs: Int
    private let emitUnexpectedAudio: Bool
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(silenceTriggerMs: Int, emitUnexpectedAudio: Bool) {
        self.silenceTriggerMs = silenceTriggerMs
        self.emitUnexpectedAudio = emitUnexpectedAudio
    }

    func send(_ message: WebSocketMessage) async throws {
        let (isClosed, toEnqueue) = state.withLock { s -> (Bool, [WebSocketMessage]) in
            if s.closed { return (true, []) }
            var outgoing: [WebSocketMessage] = []
            guard case .text(let text) = message,
                  let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String
            else {
                return (false, [])
            }

            switch type {
            case "session.configure":
                outgoing.append(.text(#"{"type":"session.ready","modalities":["text"]}"#))
            case "response.cancel", "input.clear":
                s.inSpeech = false
                s.speechEnergySum = 0
                s.speechChunkCount = 0
                s.trailingSilenceMs = 0
                s.silentOnlyMs = 0
            case "audio.chunk":
                let rms = json["rms"] as? Double ?? 0
                let durationMs = json["duration_ms"] as? Int ?? 100
                if rms >= 0.01 {
                    if !s.inSpeech {
                        s.inSpeech = true
                        outgoing.append(.text(#"{"type":"speech.started"}"#))
                    }
                    s.speechEnergySum += rms
                    s.speechChunkCount += 1
                    s.trailingSilenceMs = 0
                    s.silentOnlyMs = 0
                } else if s.inSpeech {
                    s.trailingSilenceMs += durationMs
                    if s.trailingSilenceMs >= silenceTriggerMs {
                        let avgRMS = s.speechChunkCount > 0 ? s.speechEnergySum / Double(s.speechChunkCount) : 0
                        s.turnIndex += 1
                        let turn = s.turnIndex
                        s.inSpeech = false
                        s.speechEnergySum = 0
                        s.speechChunkCount = 0
                        s.trailingSilenceMs = 0
                        s.silentOnlyMs = 0
                        Self.appendMockTurn(
                            turn: turn,
                            avgRMS: avgRMS,
                            emitUnexpectedAudio: emitUnexpectedAudio,
                            to: &outgoing
                        )
                    }
                } else {
                    // Fallback for pure-silence synthetic WAVs (e.g. from mock-tts): complete a turn once enough audio arrives.
                    s.silentOnlyMs += durationMs
                    if s.silentOnlyMs >= silenceTriggerMs + 600 {
                        s.turnIndex += 1
                        let turn = s.turnIndex
                        s.silentOnlyMs = 0
                        outgoing.append(.text(#"{"type":"speech.started"}"#))
                        Self.appendMockTurn(
                            turn: turn,
                            avgRMS: 0.12,
                            emitUnexpectedAudio: emitUnexpectedAudio,
                            to: &outgoing
                        )
                    }
                }
            default:
                break
            }
            return (false, outgoing)
        }

        if isClosed {
            throw WebSocketTransportError.connectionClosed(code: 1000, reason: "closed")
        }

        for item in toEnqueue {
            enqueue(item)
        }
    }

    func receive() async throws -> WebSocketMessage {
        try await withCheckedThrowingContinuation { continuation in
            enum Action {
                case deliver(WebSocketMessage)
                case fail
                case wait
            }
            let action = state.withLock { s -> Action in
                if !s.inboundQueue.isEmpty {
                    return .deliver(s.inboundQueue.removeFirst())
                }
                if s.closed {
                    return .fail
                }
                s.waitingReceivers.append(continuation)
                return .wait
            }
            switch action {
            case .deliver(let message):
                continuation.resume(returning: message)
            case .fail:
                continuation.resume(throwing: WebSocketTransportError.connectionClosed(code: 1000, reason: "closed"))
            case .wait:
                break
            }
        }
    }

    func close(code: Int, reason: String?) async {
        let waiters = state.withLock { s -> [CheckedContinuation<WebSocketMessage, Error>] in
            s.closed = true
            let list = s.waitingReceivers
            s.waitingReceivers.removeAll()
            return list
        }
        for waiter in waiters {
            waiter.resume(throwing: WebSocketTransportError.connectionClosed(code: code, reason: reason ?? ""))
        }
    }

    private func enqueue(_ message: WebSocketMessage) {
        let waiter = state.withLock { s -> CheckedContinuation<WebSocketMessage, Error>? in
            if !s.waitingReceivers.isEmpty {
                return s.waitingReceivers.removeFirst()
            }
            s.inboundQueue.append(message)
            return nil
        }
        waiter?.resume(returning: message)
    }

    private static func appendMockTurn(
        turn: Int,
        avgRMS: Double,
        emitUnexpectedAudio: Bool,
        to outgoing: inout [WebSocketMessage]
    ) {
        outgoing.append(.text(#"{"type":"user.transcript","text":"离线模拟语音输入第\#(turn)轮","is_final":true}"#))
        outgoing.append(.text(#"{"type":"speech.ended"}"#))
        if emitUnexpectedAudio {
            outgoing.append(.text(#"{"type":"audio.delta","base64":"AAAA"}"#))
        }

        let replyChunks: [String]
        if avgRMS >= 0.25 {
            replyChunks = [
                "<user:happy><emo:happy>",
                "听起来你今天超开心呀，",
                "<act:wave>我也跟着高兴起来啦！",
            ]
        } else if avgRMS >= 0.08 {
            replyChunks = [
                "<user:calm><emo:playful>",
                "收到啦，",
                "<act:nod>我在认真听你说话呢～",
            ]
        } else {
            replyChunks = [
                "<user:sad><emo:gentle>",
                "听你声音有点累，",
                "<act:nod>先歇一会儿吧，我陪着你。",
            ]
        }
        for chunk in replyChunks {
            if let encoded = try? JSONSerialization.data(
                withJSONObject: ["type": "text.delta", "delta": chunk]
            ), let str = String(data: encoded, encoding: .utf8) {
                outgoing.append(.text(str))
            }
        }
        outgoing.append(.text(#"{"type":"response.done"}"#))
    }
}

/// Offline, driver-agnostic `RealtimeTextSession` implementation for testing, demos, and `mm-probe` smoke runs.
public final class FakeRealtimeTextSession: RealtimeTextSession, RealtimeSessionAuditable, @unchecked Sendable {
    private enum Mode {
        case transport(any WebSocketTransport, URL, [String: String])
        case scripted([RealtimeOutput])
    }

    private struct State {
        var connected = false
        var closed = false
        var connection: (any WebSocketConnection)?
        var receiveTask: Task<Void, Never>?
        var unexpectedAudioCount = 0
        var cancelCount = 0
        var clearCount = 0
        var sentChunkCount = 0
    }

    private let mode: Mode
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let outputStream: AsyncThrowingStream<RealtimeOutput, Error>
    private let outputContinuation: AsyncThrowingStream<RealtimeOutput, Error>.Continuation

    public init(
        transport: any WebSocketTransport = LoopbackMockWebSocketTransport(),
        endpoint: URL = URL(string: "wss://mock.local/realtime")!,
        headers: [String: String] = [:]
    ) {
        self.mode = .transport(transport, endpoint, headers)
        var captured: AsyncThrowingStream<RealtimeOutput, Error>.Continuation!
        self.outputStream = AsyncThrowingStream { continuation in
            captured = continuation
        }
        self.outputContinuation = captured
    }

    public init(scriptedOutputs: [RealtimeOutput]) {
        self.mode = .scripted(scriptedOutputs)
        var captured: AsyncThrowingStream<RealtimeOutput, Error>.Continuation!
        self.outputStream = AsyncThrowingStream { continuation in
            captured = continuation
        }
        self.outputContinuation = captured
    }

    deinit {
        let task = state.withLock { s -> Task<Void, Never>? in
            s.connected = false
            s.closed = true
            let t = s.receiveTask
            s.receiveTask = nil
            s.connection = nil
            return t
        }
        task?.cancel()
        outputContinuation.finish()
    }

    public var output: AsyncThrowingStream<RealtimeOutput, Error> {
        outputStream
    }

    public var unexpectedAudioEventCount: Int {
        state.withLock { $0.unexpectedAudioCount }
    }

    public var cancelCount: Int {
        state.withLock { $0.cancelCount }
    }

    public var clearCount: Int {
        state.withLock { $0.clearCount }
    }

    public var sentChunkCount: Int {
        state.withLock { $0.sentChunkCount }
    }

    public func connect(instructions: String) async throws {
        switch mode {
        case .scripted(let outputs):
            state.withLock { s in
                s.connected = true
                s.closed = false
            }
            for item in outputs {
                outputContinuation.yield(item)
            }
        case .transport(let transport, let endpoint, let headers):
            let connection = try await transport.connect(url: endpoint, headers: headers)
            let configurePayload: [String: Any] = [
                "type": "session.configure",
                "modalities": ["text"],
                "instructions_length": instructions.count,
            ]
            let payloadData = try JSONSerialization.data(withJSONObject: configurePayload)
            let payloadText = String(decoding: payloadData, as: UTF8.self)
            try await connection.send(.text(payloadText))

            let continuation = outputContinuation
            let task = Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        let incoming = try await connection.receive()
                        guard case .text(let rawText) = incoming else { continue }
                        let decoded = MockRealtimeProtocol.decodeInboundFrame(rawText)
                        if decoded.isUnexpectedAudio {
                            self?.state.withLock { $0.unexpectedAudioCount += 1 }
                        }
                        if let event = decoded.output {
                            continuation.yield(event)
                        }
                    } catch {
                        let wasClosed = self?.state.withLock { s -> Bool in
                            s.connected = false
                            return s.closed
                        } ?? true
                        if wasClosed || Task.isCancelled {
                            continuation.finish()
                        } else {
                            continuation.finish(
                                throwing: RealtimeError.network(
                                    underlying: SecretRedactor.sanitizedErrorMessage(error, secrets: Array(headers.values))
                                )
                            )
                        }
                        break
                    }
                }
            }

            state.withLock { s in
                s.connection = connection
                s.receiveTask = task
                s.connected = true
                s.closed = false
            }
        }
    }

    public func send(_ audio: AudioChunk) async throws {
        let connection = try state.withLock { s -> (any WebSocketConnection)? in
            guard s.connected && !s.closed else {
                throw RealtimeError.notConnected
            }
            s.sentChunkCount += 1
            return s.connection
        }

        guard let connection else { return }
        let rms = Self.computeNormalizedRMS(samples: audio.samples)
        let durationMs = max(1, Int((audio.duration * 1000.0).rounded()))
        let frame: [String: Any] = [
            "type": "audio.chunk",
            "sample_rate": audio.sampleRate,
            "duration_ms": durationMs,
            "rms": rms,
            "audio": audio.pcmData.base64EncodedString(),
        ]
        let data = try JSONSerialization.data(withJSONObject: frame)
        try await connection.send(.text(String(decoding: data, as: UTF8.self)))
    }

    public func cancelResponse() async {
        let connection = state.withLock { s -> (any WebSocketConnection)? in
            s.cancelCount += 1
            return s.connected && !s.closed ? s.connection : nil
        }
        try? await connection?.send(.text(#"{"type":"response.cancel"}"#))
    }

    public func clearInputBuffer() async {
        let connection = state.withLock { s -> (any WebSocketConnection)? in
            s.clearCount += 1
            return s.connected && !s.closed ? s.connection : nil
        }
        try? await connection?.send(.text(#"{"type":"input.clear"}"#))
    }

    public func close() async {
        let (connection, task) = state.withLock { s -> ((any WebSocketConnection)?, Task<Void, Never>?) in
            s.connected = false
            s.closed = true
            let conn = s.connection
            let t = s.receiveTask
            s.connection = nil
            s.receiveTask = nil
            return (conn, t)
        }
        task?.cancel()
        await connection?.close(code: 1000, reason: "normal closure")
        outputContinuation.finish()
    }

    private static func computeNormalizedRMS(samples: [Int16]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sumSquares = 0.0
        for sample in samples {
            let normalized = Double(sample) / 32768.0
            sumSquares += normalized * normalized
        }
        return sqrt(sumSquares / Double(samples.count))
    }
}
