import Foundation
import MMCore

/// A single capability check. Implementations live under `Probes/`.
public protocol CapabilityProbe: Sendable {
    var id: CapabilityID { get }
    /// Runs the check; thrown errors are normalised to `.error` by the runner.
    func run() async throws -> CapabilityResult
}

/// Runs all probes concurrently, each bounded by `timeout`; one probe's failure
/// never affects the others (FR-004).
public struct DiagnosticsRunner: Sendable {
    public let probes: [any CapabilityProbe]
    public let timeout: Duration
    private let clock: any Clock

    public init(
        probes: [any CapabilityProbe],
        timeout: Duration = .seconds(3),
        clock: any Clock = SystemClock()
    ) {
        self.probes = probes
        self.timeout = timeout
        self.clock = clock
    }

    /// Results in the declaration order of `probes`, not completion order.
    public func run() async -> [CapabilityResult] {
        await withTaskGroup(of: (Int, CapabilityResult).self) { group in
            for (index, probe) in probes.enumerated() {
                group.addTask { (index, await self.runOne(probe)) }
            }
            var ordered = [CapabilityResult?](repeating: nil, count: probes.count)
            for await (index, result) in group {
                ordered[index] = result
            }
            return ordered.compactMap { $0 }
        }
    }

    /// Races the probe against the timeout; the loser is cancelled.
    private func runOne(_ probe: any CapabilityProbe) async -> CapabilityResult {
        await withTaskGroup(of: CapabilityResult?.self) { group in
            group.addTask {
                let start = self.clock.now
                do {
                    var result = try await probe.run()
                    result = CapabilityResult(
                        id: probe.id,
                        status: result.status,
                        detail: result.detail,
                        duration: .nanoseconds(Int64(self.clock.now.timeIntervalSince(start) * 1e9))
                    )
                    return result
                } catch {
                    return CapabilityResult(
                        id: probe.id,
                        status: .error(message: String(describing: error)),
                        detail: nil,
                        duration: .nanoseconds(Int64(self.clock.now.timeIntervalSince(start) * 1e9))
                    )
                }
            }
            group.addTask {
                try? await self.clock.sleep(for: self.timeout)
                return nil
            }
            defer { group.cancelAll() }
            for await outcome in group {
                if let outcome {
                    return outcome
                }
                return CapabilityResult(
                    id: probe.id,
                    status: .error(message: "探测超时（>\(timeout.asSeconds)s）"),
                    detail: nil,
                    duration: timeout
                )
            }
            return CapabilityResult(
                id: probe.id,
                status: .error(message: "探测未返回结果"),
                detail: nil,
                duration: .zero
            )
        }
    }
}

/// The standard probe set, in CapabilityID declaration order.
public enum DiagnosticsProbes {
    public static func makeAll() -> [any CapabilityProbe] {
        [
            FoundationModelsProbe(),
            FoundationModelsChineseProbe(),
            SpeechTranscriberProbe(),
            SpeechDetectorProbe(),
            NLEmbeddingProbe(),
            ARKitProbe(),
        ]
    }
}

extension Duration {
    fileprivate var asSeconds: String {
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return String(format: "%.0f", seconds)
    }
}
