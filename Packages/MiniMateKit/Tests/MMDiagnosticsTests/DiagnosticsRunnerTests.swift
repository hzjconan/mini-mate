import Foundation
import Testing
@testable import MMCore
@testable import MMDiagnostics

// MARK: - Fakes

/// Clock whose sleep only returns when the task is cancelled — disables the timeout branch.
struct NeverFiringClock: MMCore.Clock {
    var now: Date { Date(timeIntervalSince1970: 0) }
    func sleep(for duration: Duration) async throws {
        while !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

struct StubProbe: CapabilityProbe {
    let id: CapabilityID
    let result: CapabilityResult

    func run() async throws -> CapabilityResult { result }
}

struct ThrowingProbe: CapabilityProbe {
    struct Boom: Error {}
    let id: CapabilityID

    func run() async throws -> CapabilityResult { throw Boom() }
}

/// Probe that suspends until cancelled, never producing a result.
struct HangingProbe: CapabilityProbe {
    let id: CapabilityID

    func run() async throws -> CapabilityResult {
        try await Task.sleep(for: .seconds(3600))
        return CapabilityResult(id: id, status: .available, detail: nil, duration: .zero)
    }
}

/// Records start/end of each probe so tests can assert intervals overlap.
actor IntervalRecorder {
    private var starts: [CapabilityID: Date] = [:]
    private(set) var intervals: [CapabilityID: (start: Date, end: Date)] = [:]

    func start(_ id: CapabilityID) { starts[id] = Date() }
    func end(_ id: CapabilityID) {
        if let start = starts[id] { intervals[id] = (start, Date()) }
    }
}

struct TimedProbe: CapabilityProbe {
    let id: CapabilityID
    let delay: Duration
    let recorder: IntervalRecorder

    func run() async throws -> CapabilityResult {
        await recorder.start(id)
        try? await Task.sleep(for: delay)
        await recorder.end(id)
        return CapabilityResult(id: id, status: .available, detail: nil, duration: delay)
    }
}

// MARK: - Tests

@Suite("DiagnosticsRunner")
struct DiagnosticsRunnerTests {
    private func availableResult(_ id: CapabilityID) -> CapabilityResult {
        CapabilityResult(id: id, status: .available, detail: nil, duration: .zero)
    }

    @Test func probesRunConcurrently() async {
        let recorder = IntervalRecorder()
        let runner = DiagnosticsRunner(
            probes: [
                TimedProbe(id: .foundationModels, delay: .milliseconds(150), recorder: recorder),
                TimedProbe(id: .arFaceTracking, delay: .milliseconds(150), recorder: recorder),
            ],
            clock: NeverFiringClock()
        )

        let results = await runner.run()

        #expect(results.count == 2)
        let intervals = await recorder.intervals
        let a = try! #require(intervals[.foundationModels])
        let b = try! #require(intervals[.arFaceTracking])
        #expect(a.start < b.end && b.start < a.end, "probes did not overlap")
    }

    @Test func timedOutProbeBecomesError() async {
        // Real clock + short timeout: instant probe always wins, hanging probe always loses.
        let runner = DiagnosticsRunner(
            probes: [
                HangingProbe(id: .speechDetector),
                StubProbe(id: .foundationModels, result: availableResult(.foundationModels)),
            ],
            timeout: .milliseconds(50)
        )

        let results = await runner.run()

        let timedOut = try! #require(results.first { $0.id == .speechDetector })
        guard case .error(let message) = timedOut.status else {
            Issue.record("expected .error, got \(timedOut.status)")
            return
        }
        #expect(message.contains("超时"))
        #expect(results.first { $0.id == .foundationModels }?.status == .available)
    }

    @Test func thrownErrorDoesNotAffectOtherProbes() async {
        let runner = DiagnosticsRunner(
            probes: [
                StubProbe(id: .foundationModels, result: availableResult(.foundationModels)),
                ThrowingProbe(id: .speechDetector),
                StubProbe(id: .arFaceTracking, result: availableResult(.arFaceTracking)),
            ],
            clock: NeverFiringClock()
        )

        let results = await runner.run()

        #expect(results.count == 3)
        guard case .error = results.first(where: { $0.id == .speechDetector })?.status else {
            Issue.record("throwing probe did not produce .error")
            return
        }
        #expect(results.first { $0.id == .foundationModels }?.status == .available)
        #expect(results.first { $0.id == .arFaceTracking }?.status == .available)
    }

    @Test func resultsFollowProbeDeclarationOrder() async {
        let runner = DiagnosticsRunner(
            probes: [
                TimedProbe(id: .arFaceTracking, delay: .milliseconds(5), recorder: IntervalRecorder()),
                TimedProbe(id: .foundationModels, delay: .milliseconds(50), recorder: IntervalRecorder()),
            ],
            clock: NeverFiringClock()
        )

        let results = await runner.run()

        #expect(results.map(\.id) == [.arFaceTracking, .foundationModels])
    }
}
