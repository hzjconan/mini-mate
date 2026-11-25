import Foundation
import os
import Testing
import MMCore
import MMPerception

private final class RecordingClock: MMCore.Clock, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<(now: Date, sleeps: [Duration])>
    private let shouldBlockOnSleep: Bool

    init(now: Date = Date(timeIntervalSinceReferenceDate: 1_000), shouldBlockOnSleep: Bool = false) {
        self.state = OSAllocatedUnfairLock(initialState: (now, []))
        self.shouldBlockOnSleep = shouldBlockOnSleep
    }

    var now: Date {
        state.withLock { $0.now }
    }

    var recordedSleeps: [Duration] {
        state.withLock { $0.sleeps }
    }

    func sleep(for duration: Duration) async throws {
        state.withLock { $0.sleeps.append(duration) }
        if shouldBlockOnSleep {
            try await Task.sleep(for: .seconds(10))
        }
    }
}

@Suite("ScriptedPerceptionSource")
struct ScriptedPerceptionSourceTests {

    private func sampleFrames() -> [PerceptionFeatures] {
        [
            PerceptionFeatures(
                timestamp: 100.0,
                isFaceTracked: true,
                rawBlendShapes: ["jawOpen": 0.25, "mouthSmileLeft": 0.6],
                signals: FaceSignals(smile: 0.5, frown: 0.1, surprise: 0.0, activeExpression: .smiling),
                facePosition: SIMD3<Float>(0.12, -0.05, 0.52),
                isLookingAtScreen: true,
                gesture: nil
            ),
            PerceptionFeatures(
                timestamp: 100.4,
                isFaceTracked: false,
                rawBlendShapes: [:],
                signals: FaceSignals(),
                facePosition: nil,
                isLookingAtScreen: false,
                gesture: nil
            ),
            PerceptionFeatures(
                timestamp: 101.0,
                isFaceTracked: true,
                rawBlendShapes: ["eyeBlinkLeft": 0.8],
                signals: FaceSignals(),
                facePosition: SIMD3<Float>(-0.08, 0.04, 0.45),
                isLookingAtScreen: true,
                gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 101.0)
            ),
        ]
    }

    @Test("encodeJSONLines 与 decodeJSONLines 往返及 immediate 回放逐字段相等")
    func roundTripJSONLinesAndImmediateReplay() async throws {
        let frames = sampleFrames()
        let encoded = try ScriptedPerceptionSource.encodeJSONLines(frames)
        let decoded = try ScriptedPerceptionSource.decodeJSONLines(encoded)
        #expect(decoded == frames)

        let emptyEncoded = try ScriptedPerceptionSource.encodeJSONLines([])
        #expect(emptyEncoded.isEmpty)

        let source = try ScriptedPerceptionSource(jsonLinesData: encoded, replayMode: .immediate)
        let stream = source.features
        try await source.start()

        var received: [PerceptionFeatures] = []
        for await item in stream {
            received.append(item)
        }
        #expect(received == frames)
    }

    @Test("空行与 CRLF 正常跳过，坏行精准抛出 invalidLine 及 1-based 行号")
    func blankLinesCRLFAndInvalidLineHandling() throws {
        let frames = sampleFrames()
        let encoded = try ScriptedPerceptionSource.encodeJSONLines(Array(frames.prefix(2)))
        let text = try #require(String(data: encoded, encoding: .utf8))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let withBlanks = "\r\n  \r\n\(lines[0])\r\n\r\n   \n\(lines[1])\r\n"
        let decoded = try ScriptedPerceptionSource.decodeJSONLines(Data(withBlanks.utf8))
        #expect(decoded == Array(frames.prefix(2)))

        let broken = "\(lines[0])\n{not-valid-json}\n\(lines[1])\n"
        do {
            _ = try ScriptedPerceptionSource.decodeJSONLines(Data(broken.utf8))
            Issue.record("预期抛出 ScriptedPerceptionError.invalidLine")
        } catch let error as ScriptedPerceptionError {
            switch error {
            case .invalidLine(let lineNumber, let message):
                #expect(lineNumber == 2)
                #expect(!message.isEmpty)
            default:
                Issue.record("预期 invalidLine，实际得到 \(error)")
            }
        }
    }

    @Test("timed(speed: 2.0) 按帧间时间差除以 speed 调用注入时钟 sleep")
    func timedReplayUsesInjectedClockScaledBySpeed() async throws {
        let frames = sampleFrames() // timestamps: 100.0, 100.4 (dt=0.4), 101.0 (dt=0.6)
        let clock = RecordingClock()
        let source = ScriptedPerceptionSource(
            frames: frames,
            replayMode: .timed(speed: 2.0),
            clock: clock
        )
        let stream = source.features
        try await source.start()

        var received: [PerceptionFeatures] = []
        for await item in stream {
            received.append(item)
        }
        #expect(received == frames)

        let sleeps = clock.recordedSleeps.map(durationSeconds)
        #expect(sleeps.count == 2)
        #expect(abs(sleeps[0] - 0.2) < 1e-6)
        #expect(abs(sleeps[1] - 0.3) < 1e-6)
    }

    @Test("回放中途调用 stop() 提前结束流")
    func stopCancelsActiveReplayAndFinishesStream() async throws {
        let frames = sampleFrames()
        let clock = RecordingClock(shouldBlockOnSleep: true)
        let source = ScriptedPerceptionSource(
            frames: frames,
            replayMode: .timed(speed: 1.0),
            clock: clock
        )
        let stream = source.features
        try await source.start()

        var received: [PerceptionFeatures] = []
        for await item in stream {
            received.append(item)
            if received.count == 1 {
                source.stop()
            }
        }
        #expect(received.count == 1)
        #expect(received[0] == frames[0])
    }

    @Test("重复调用 start() 时旧任务取消收尾不会误杀新订阅流")
    func restartDoesNotFinishNewStreamFromCancelledPreviousRun() async throws {
        let frames = sampleFrames()
        let clock = RecordingClock(shouldBlockOnSleep: false)
        let source = ScriptedPerceptionSource(
            frames: frames,
            replayMode: .timed(speed: 100.0),
            clock: clock
        )

        // 连续两次 start()：旧任务被取消，新订阅流应完整收到全部 3 帧
        let firstStream = source.features
        try await source.start()
        try await source.start()

        var received: [PerceptionFeatures] = []
        for await item in firstStream {
            received.append(item)
        }
        // 新一轮至少完整送出全部 3 帧（末尾 3 帧必与 frames 完全一致）
        #expect(received.count >= frames.count)
        #expect(Array(received.suffix(frames.count)) == frames)
    }

    private func durationSeconds(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) + Double(c.attoseconds) * 1e-18
    }
}
