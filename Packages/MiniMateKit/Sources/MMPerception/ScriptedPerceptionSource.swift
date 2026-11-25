import Foundation
import os
import MMCore

public enum ScriptedPerceptionError: Error, Sendable, Equatable {
    case invalidUTF8
    case invalidLine(lineNumber: Int, message: String)
}

/// 脚本/JSON Lines 回放感知源，用于单元测试与离线复现真机录制数据。
public final class ScriptedPerceptionSource: PerceptionSource, @unchecked Sendable {
    public enum ReplayMode: Sendable, Equatable {
        /// 立即按顺序推送所有帧并结束流（单元测试默认模式）。
        case immediate
        /// 按相邻帧 timestamp 差值除以 speed 调用 clock.sleep 推送。
        case timed(speed: Double = 1.0)
    }

    private struct State {
        var continuations: [UUID: AsyncStream<PerceptionFeatures>.Continuation] = [:]
        var activeRunID: UUID?
        var replayTask: Task<Void, Never>?
        var gestureRateHz: Double = 12.0
    }

    public let frames: [PerceptionFeatures]
    public let replayMode: ReplayMode

    private let clock: any MMCore.Clock
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(
        frames: [PerceptionFeatures],
        replayMode: ReplayMode = .immediate,
        clock: any MMCore.Clock = SystemClock()
    ) {
        self.frames = frames
        self.replayMode = replayMode
        self.clock = clock
    }

    public convenience init(
        jsonLinesData: Data,
        replayMode: ReplayMode = .immediate,
        clock: any MMCore.Clock = SystemClock()
    ) throws {
        let decoded = try Self.decodeJSONLines(jsonLinesData)
        self.init(frames: decoded, replayMode: replayMode, clock: clock)
    }

    public convenience init(
        fileURL: URL,
        replayMode: ReplayMode = .immediate,
        clock: any MMCore.Clock = SystemClock()
    ) throws {
        let data = try Data(contentsOf: fileURL)
        try self.init(jsonLinesData: data, replayMode: replayMode, clock: clock)
    }

    public var features: AsyncStream<PerceptionFeatures> {
        let id = UUID()
        return AsyncStream { continuation in
            state.withLock { $0.continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    public func start() async throws {
        let runID = UUID()
        let previousTask = state.withLock { s -> Task<Void, Never>? in
            let old = s.replayTask
            s.replayTask = nil
            s.activeRunID = runID
            return old
        }
        previousTask?.cancel()

        let framesToPlay = frames
        let mode = replayMode
        let clock = clock

        let task = Task { [weak self] in
            guard let self else { return }
            var previousTimestamp: TimeInterval?

            for frame in framesToPlay {
                if Task.isCancelled || !self.isActiveRun(runID) { return }

                if case .timed(let rawSpeed) = mode, let prevTs = previousTimestamp {
                    let speed = rawSpeed.isFinite ? max(rawSpeed, 1e-3) : 1.0
                    let dt = frame.timestamp - prevTs
                    if dt > 0 {
                        let scaled = dt / speed
                        do {
                            try await clock.sleep(for: .seconds(scaled))
                        } catch {
                            return
                        }
                    }
                }
                if Task.isCancelled || !self.isActiveRun(runID) { return }

                previousTimestamp = frame.timestamp
                self.yield(frame, for: runID)
            }

            if !Task.isCancelled {
                self.finishAllContinuations(ifActive: runID)
            }
        }

        state.withLock { s in
            if s.activeRunID == runID {
                s.replayTask = task
            }
        }
    }

    public func stop() {
        let (task, continuations) = state.withLock { s -> (Task<Void, Never>?, [AsyncStream<PerceptionFeatures>.Continuation]) in
            let t = s.replayTask
            s.replayTask = nil
            s.activeRunID = nil
            let c = Array(s.continuations.values)
            s.continuations.removeAll()
            return (t, c)
        }
        task?.cancel()
        for continuation in continuations {
            continuation.finish()
        }
    }

    public func setGestureRate(_ hz: Double) {
        let clamped = hz.isFinite ? min(max(hz, 0), 15) : 0
        state.withLock { $0.gestureRateHz = clamped }
    }

    /// 解码 JSON Lines（跳过纯空白行，支持 \n 与 \r\n；坏行抛出 invalidLine，1-based 行号）。
    public static func decodeJSONLines(_ data: Data) throws -> [PerceptionFeatures] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ScriptedPerceptionError.invalidUTF8
        }
        let decoder = JSONDecoder()
        let rawLines = text.components(separatedBy: "\n")
        var result: [PerceptionFeatures] = []
        result.reserveCapacity(rawLines.count)

        for (index, rawLine) in rawLines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            do {
                let frame = try decoder.decode(PerceptionFeatures.self, from: Data(trimmed.utf8))
                result.append(frame)
            } catch {
                throw ScriptedPerceptionError.invalidLine(
                    lineNumber: index + 1,
                    message: String(describing: error)
                )
            }
        }
        return result
    }

    /// 编码 JSON Lines（每帧一行紧凑 JSON + "\n"；空数组返回空 Data）。
    public static func encodeJSONLines(_ frames: [PerceptionFeatures]) throws -> Data {
        guard !frames.isEmpty else { return Data() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var output = Data()
        let newline = Data([0x0A])
        for frame in frames {
            let lineData = try encoder.encode(frame)
            output.append(lineData)
            output.append(newline)
        }
        return output
    }

    private func isActiveRun(_ runID: UUID) -> Bool {
        state.withLock { $0.activeRunID == runID }
    }

    private func yield(_ frame: PerceptionFeatures, for runID: UUID) {
        let continuations = state.withLock { s -> [AsyncStream<PerceptionFeatures>.Continuation] in
            guard s.activeRunID == runID else { return [] }
            return Array(s.continuations.values)
        }
        for continuation in continuations {
            continuation.yield(frame)
        }
    }

    private func finishAllContinuations(ifActive runID: UUID) {
        let continuations = state.withLock { s -> [AsyncStream<PerceptionFeatures>.Continuation] in
            guard s.activeRunID == runID else { return [] }
            let c = Array(s.continuations.values)
            s.continuations.removeAll()
            s.replayTask = nil
            s.activeRunID = nil
            return c
        }
        for continuation in continuations {
            continuation.finish()
        }
    }
}
