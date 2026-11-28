import Foundation
import MMCore
import os

/// One redacted WebSocket frame stored in a JSONL replay fixture (RS-5).
public struct FixtureFrameRecord: Codable, Sendable, Equatable {
    public enum Direction: String, Codable, Sendable {
        case inbound = "in"
        case outbound = "out"
    }

    public enum Kind: String, Codable, Sendable {
        case text
        case binary
    }

    public let seq: Int
    public let direction: Direction
    public let kind: Kind
    public let timestampMs: Int
    public let text: String?
    public let base64: String?

    public init(
        seq: Int,
        direction: Direction,
        kind: Kind,
        timestampMs: Int,
        text: String? = nil,
        base64: String? = nil
    ) {
        self.seq = seq
        self.direction = direction
        self.kind = kind
        self.timestampMs = timestampMs
        self.text = text
        self.base64 = base64
    }
}

/// WebSocketTransport decorator that records sanitized JSONL replay fixtures.
/// - Never records any HTTP handshake headers.
/// - Automatically adds all handshake header values (len >= 4) to the redaction secret set.
/// - Uses `outboundFilter` (defaults to skipping raw audio frames) to prevent personal voice recordings from entering fixtures.
public final class RecordingWebSocketTransport: WebSocketTransport, Sendable {
    private struct State {
        var nextSeq: Int = 1
        var records: [FixtureFrameRecord] = []
        var secrets: [String]
        var startDate: Date?
    }

    private let underlying: any WebSocketTransport
    private let clock: any MMCore.Clock
    private let outboundFilter: @Sendable (WebSocketMessage) -> Bool
    private let state: OSAllocatedUnfairLock<State>

    /// Default filter skips outbound binary frames and outbound text frames that look like raw audio uploads.
    public static let defaultOutboundFilter: @Sendable (WebSocketMessage) -> Bool = { message in
        switch message {
        case .binary:
            return false
        case .text(let text):
            let lower = text.lowercased()
            if lower.contains("\"audio\"") || lower.contains("audio_buffer.append") || lower.contains("audio.chunk") {
                return false
            }
            return true
        }
    }

    public init(
        underlying: any WebSocketTransport,
        secrets: [String] = [],
        clock: any MMCore.Clock = SystemClock(),
        outboundFilter: @escaping @Sendable (WebSocketMessage) -> Bool = RecordingWebSocketTransport.defaultOutboundFilter
    ) {
        self.underlying = underlying
        self.clock = clock
        self.outboundFilter = outboundFilter
        self.state = OSAllocatedUnfairLock(initialState: State(secrets: secrets))
    }

    public func connect(url: URL, headers: [String: String]) async throws -> any WebSocketConnection {
        let headerValues = headers.values.filter { $0.count >= 4 }
        state.withLock { s in
            s.secrets.append(contentsOf: headerValues)
            if s.startDate == nil {
                s.startDate = clock.now
            }
        }
        // Never record headers; forward directly to underlying transport.
        let connection = try await underlying.connect(url: url, headers: headers)
        return RecordingWebSocketConnection(underlying: connection, recorder: self)
    }

    public var records: [FixtureFrameRecord] {
        state.withLock { $0.records }
    }

    public func encodeJSONLines() throws -> Data {
        let snapshot = records
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var output = Data()
        for record in snapshot {
            let lineData = try encoder.encode(record)
            output.append(lineData)
            output.append(0x0A)
        }
        return output
    }

    public static func decodeJSONLines(_ data: Data) throws -> [FixtureFrameRecord] {
        let text = String(decoding: data, as: UTF8.self)
        let decoder = JSONDecoder()
        var result: [FixtureFrameRecord] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let record = try decoder.decode(FixtureFrameRecord.self, from: Data(trimmed.utf8))
            result.append(record)
        }
        return result
    }

    fileprivate func record(direction: FixtureFrameRecord.Direction, message: WebSocketMessage) {
        if direction == .outbound, !outboundFilter(message) {
            return
        }
        let now = clock.now
        state.withLock { s in
            let start = s.startDate ?? now
            if s.startDate == nil {
                s.startDate = start
            }
            let elapsedMs = max(0, Int((now.timeIntervalSince(start) * 1000.0).rounded()))
            let seq = s.nextSeq
            s.nextSeq += 1

            let record: FixtureFrameRecord
            switch message {
            case .text(let rawText):
                let sanitized = SecretRedactor.redact(rawText, secrets: s.secrets)
                record = FixtureFrameRecord(
                    seq: seq,
                    direction: direction,
                    kind: .text,
                    timestampMs: elapsedMs,
                    text: sanitized,
                    base64: nil
                )
            case .binary(let rawData):
                record = FixtureFrameRecord(
                    seq: seq,
                    direction: direction,
                    kind: .binary,
                    timestampMs: elapsedMs,
                    text: nil,
                    base64: rawData.base64EncodedString()
                )
            }
            s.records.append(record)
        }
    }
}

private final class RecordingWebSocketConnection: WebSocketConnection, Sendable {
    private let underlying: any WebSocketConnection
    private let recorder: RecordingWebSocketTransport

    init(underlying: any WebSocketConnection, recorder: RecordingWebSocketTransport) {
        self.underlying = underlying
        self.recorder = recorder
    }

    func send(_ message: WebSocketMessage) async throws {
        recorder.record(direction: .outbound, message: message)
        try await underlying.send(message)
    }

    func receive() async throws -> WebSocketMessage {
        let message = try await underlying.receive()
        recorder.record(direction: .inbound, message: message)
        return message
    }

    func close(code: Int, reason: String?) async {
        await underlying.close(code: code, reason: reason)
    }
}
