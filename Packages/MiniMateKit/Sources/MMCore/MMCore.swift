import Foundation

/// Wall-clock abstraction so tests can inject deterministic time.
public protocol Clock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

/// Default clock backed by the system clock.
public struct SystemClock: Clock {
    public init() {}

    public var now: Date { Date() }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
