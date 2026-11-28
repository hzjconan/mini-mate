import Foundation

public struct HTTPStreamingResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let lines: AsyncThrowingStream<String, Error>

    public init(
        statusCode: Int,
        headers: [String: String] = [:],
        lines: AsyncThrowingStream<String, Error>
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.lines = lines
    }
}

public enum HTTPStreamingTransportError: Error, Sendable, Equatable {
    case invalidResponse
    case transportFailure(String)
}

public protocol HTTPStreamingTransport: Sendable {
    func streamLines(for request: URLRequest) async throws -> HTTPStreamingResponse
}

/// Default `URLSession.bytes(for:)` line-streaming HTTP transport.
/// Splits UTF-8 lines on `0x0A` (`\n`), strips trailing `\r`, flushes final line at EOF,
/// and cancels the reader task immediately on stream termination.
public final class URLSessionHTTPStreamingTransport: HTTPStreamingTransport, Sendable {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        self.session = URLSession(configuration: configuration)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func streamLines(for request: URLRequest) async throws -> HTTPStreamingResponse {
        let secrets = Array((request.allHTTPHeaderFields ?? [:]).values)
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw HTTPStreamingTransportError.transportFailure(
                SecretRedactor.sanitizedErrorMessage(error, secrets: secrets)
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPStreamingTransportError.invalidResponse
        }

        var normalizedHeaders: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            normalizedHeaders[String(describing: key)] = String(describing: value)
        }

        let owner = self
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let readerTask = Task {
                // Keep transport/URLSession alive until line streaming completes or is cancelled.
                defer { _ = owner }
                var buffer = Data()
                do {
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A { // '\n'
                            if buffer.last == 0x0D { // '\r'
                                buffer.removeLast()
                            }
                            continuation.yield(String(decoding: buffer, as: UTF8.self))
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(byte)
                        }
                    }
                    if !Task.isCancelled && !buffer.isEmpty {
                        if buffer.last == 0x0D {
                            buffer.removeLast()
                        }
                        continuation.yield(String(decoding: buffer, as: UTF8.self))
                    }
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: HTTPStreamingTransportError.transportFailure(
                            SecretRedactor.sanitizedErrorMessage(error, secrets: secrets)
                        ))
                    }
                }
            }
            continuation.onTermination = { _ in
                readerTask.cancel()
            }
        }

        return HTTPStreamingResponse(
            statusCode: httpResponse.statusCode,
            headers: normalizedHeaders,
            lines: stream
        )
    }
}
