import Foundation
import os

public enum WebSocketMessage: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

public enum WebSocketTransportError: Error, Sendable, Equatable {
    case httpRejected(statusCode: Int, message: String)
    case connectionClosed(code: Int, reason: String)
    case transportFailure(String)
}

public protocol WebSocketConnection: Sendable {
    func send(_ message: WebSocketMessage) async throws
    func receive() async throws -> WebSocketMessage
    func close(code: Int, reason: String?) async
}

public protocol WebSocketTransport: Sendable {
    func connect(url: URL, headers: [String: String]) async throws -> any WebSocketConnection
}

/// Default `URLSessionWebSocketTask`-backed WebSocket transport with HTTP handshake status extraction.
public final class URLSessionWebSocketTransport: WebSocketTransport, Sendable {
    private let delegate: WebSocketSessionDelegate
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        let delegate = WebSocketSessionDelegate()
        self.delegate = delegate
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func connect(url: URL, headers: [String: String]) async throws -> any WebSocketConnection {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let secrets = Array(headers.values)
        let task = session.webSocketTask(with: request)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.register(task: task, secrets: secrets, continuation: continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }

        // Connection retains `self` so the underlying URLSession stays alive for the lifetime of the connection.
        return URLSessionWebSocketConnection(task: task, secrets: secrets, owner: self)
    }
}

private final class URLSessionWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let secrets: [String]
    private let owner: URLSessionWebSocketTransport

    init(task: URLSessionWebSocketTask, secrets: [String], owner: URLSessionWebSocketTransport) {
        self.task = task
        self.secrets = secrets
        self.owner = owner
    }

    func send(_ message: WebSocketMessage) async throws {
        let wsMessage: URLSessionWebSocketTask.Message = switch message {
        case .text(let string): .string(string)
        case .binary(let data): .data(data)
        }
        do {
            try await task.send(wsMessage)
        } catch {
            throw WebSocketTransportError.transportFailure(
                SecretRedactor.sanitizedErrorMessage(error, secrets: secrets)
            )
        }
    }

    func receive() async throws -> WebSocketMessage {
        do {
            let incoming = try await task.receive()
            switch incoming {
            case .string(let string):
                return .text(string)
            case .data(let data):
                return .binary(data)
            @unknown default:
                throw WebSocketTransportError.transportFailure("Unknown WebSocket message type")
            }
        } catch let error as WebSocketTransportError {
            throw error
        } catch {
            if task.closeCode != .invalid {
                let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                throw WebSocketTransportError.connectionClosed(
                    code: task.closeCode.rawValue,
                    reason: SecretRedactor.redact(reason, secrets: secrets)
                )
            }
            throw WebSocketTransportError.transportFailure(
                SecretRedactor.sanitizedErrorMessage(error, secrets: secrets)
            )
        }
    }

    func close(code: Int, reason: String?) async {
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure
        task.cancel(with: closeCode, reason: reason.map { Data($0.utf8) })
    }
}

private final class WebSocketSessionDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private struct PendingHandshake {
        let continuation: CheckedContinuation<Void, Error>
        let secrets: [String]
    }

    private let pending = OSAllocatedUnfairLock(initialState: [Int: PendingHandshake]())

    func register(
        task: URLSessionWebSocketTask,
        secrets: [String],
        continuation: CheckedContinuation<Void, Error>
    ) {
        pending.withLock { $0[task.taskIdentifier] = PendingHandshake(continuation: continuation, secrets: secrets) }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        let entry = pending.withLock { $0.removeValue(forKey: webSocketTask.taskIdentifier) }
        entry?.continuation.resume()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        guard let entry = pending.withLock({ $0.removeValue(forKey: webSocketTask.taskIdentifier) }) else {
            return
        }
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        entry.continuation.resume(throwing: WebSocketTransportError.connectionClosed(
            code: closeCode.rawValue,
            reason: SecretRedactor.redact(reasonText, secrets: entry.secrets)
        ))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let entry = pending.withLock({ $0.removeValue(forKey: task.taskIdentifier) }) else {
            return
        }
        if let httpResponse = task.response as? HTTPURLResponse, httpResponse.statusCode != 101 {
            let message = error.map { SecretRedactor.sanitizedErrorMessage($0, secrets: entry.secrets) }
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            entry.continuation.resume(throwing: WebSocketTransportError.httpRejected(
                statusCode: httpResponse.statusCode,
                message: message
            ))
            return
        }
        let message = error.map { SecretRedactor.sanitizedErrorMessage($0, secrets: entry.secrets) }
            ?? "WebSocket connection failed before opening"
        entry.continuation.resume(throwing: WebSocketTransportError.transportFailure(message))
    }
}
