import Foundation
import os
import MMAudio
import MMCore

/// 线程安全测试用 TTS 假实现（contracts/tts-provider.md TTS-3–TTS-6）。
public final class FakeTTSProvider: TTSProvider, @unchecked Sendable {
    public struct Request: Sendable, Equatable {
        public let sentence: String
        public let emotion: EmotionTag

        public init(sentence: String, emotion: EmotionTag) {
            self.sentence = sentence
            self.emotion = emotion
        }
    }

    private struct ActiveStream {
        var continuation: AsyncThrowingStream<AudioChunk, Error>.Continuation
        var task: Task<Void, Never>?
    }

    private struct State {
        var recordedRequests: [Request] = []
        var cancelCount: Int = 0
        var activeStreams: [UUID: ActiveStream] = [:]
    }

    public let outputFormat: AudioFormatDescription

    private let millisecondsPerCharacter: Double
    private let chunkDurationMilliseconds: Int
    private let chunkDelay: Duration
    private let clock: any MMCore.Clock
    private let includeWordMarks: Bool
    private let failureRule: (@Sendable (String, EmotionTag) -> (any Error)?)?
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(
        outputFormat: AudioFormatDescription = .pcm24kMono,
        millisecondsPerCharacter: Double = 120,
        chunkDurationMilliseconds: Int = 100,
        chunkDelay: Duration = .zero,
        clock: any MMCore.Clock = SystemClock(),
        includeWordMarks: Bool = false,
        failureRule: (@Sendable (String, EmotionTag) -> (any Error)?)? = nil
    ) {
        self.outputFormat = outputFormat
        self.millisecondsPerCharacter = (millisecondsPerCharacter.isFinite && millisecondsPerCharacter > 0)
            ? millisecondsPerCharacter
            : 120
        self.chunkDurationMilliseconds = chunkDurationMilliseconds > 0 ? chunkDurationMilliseconds : 100
        self.chunkDelay = chunkDelay
        self.clock = clock
        self.includeWordMarks = includeWordMarks
        self.failureRule = failureRule
    }

    /// 已收到的全部合成请求（按调用顺序，线程安全）。
    public var recordedRequests: [Request] {
        state.withLock { $0.recordedRequests }
    }

    /// `cancelAll()` 调用次数（线程安全）。
    public var cancelCount: Int {
        state.withLock { $0.cancelCount }
    }

    public func synthesize(_ sentence: String, emotion: EmotionTag) -> AsyncThrowingStream<AudioChunk, Error> {
        state.withLock {
            $0.recordedRequests.append(Request(sentence: sentence, emotion: emotion))
        }

        if let error = failureRule?(sentence, emotion) {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        if sentence.isEmpty {
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 24_000
        let msPerChar = self.millisecondsPerCharacter
        let chunkMs = self.chunkDurationMilliseconds
        let totalSamples = max(1, Int((Double(sentence.count) * msPerChar / 1000.0 * Double(sampleRate)).rounded()))
        let samplesPerChunk = max(1, Int((Double(chunkMs) / 1000.0 * Double(sampleRate)).rounded()))
        let delay = self.chunkDelay
        let clock = self.clock
        let emitMarks = self.includeWordMarks

        let allMarks: [AudioTimeMark] = emitMarks
            ? sentence.enumerated().map { idx, ch in
                AudioTimeMark(
                    text: String(ch),
                    offsetSeconds: Double(idx) * msPerChar / 1000.0,
                    charOffset: idx
                )
            }
            : []

        let streamID = UUID()

        return AsyncThrowingStream { continuation in
            state.withLock {
                $0.activeStreams[streamID] = ActiveStream(continuation: continuation, task: nil)
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                let task = self.state.withLock { s -> Task<Void, Never>? in
                    s.activeStreams.removeValue(forKey: streamID)?.task
                }
                task?.cancel()
            }

            let producer = Task { [weak self] in
                var emittedSamples = 0
                var markCursor = 0

                while emittedSamples < totalSamples {
                    // 严禁跨越 await 强持有 self，确保挂起中途释放 FakeTTSProvider 时 deinit 能立即触发并结束流
                    guard self != nil else {
                        continuation.finish()
                        return
                    }

                    if delay > .zero {
                        do {
                            try await clock.sleep(for: delay)
                        } catch {
                            break
                        }
                    }

                    let remaining = totalSamples - emittedSamples
                    let count = min(samplesPerChunk, remaining)
                    let blockEndSeconds = Double(emittedSamples + count) / Double(sampleRate)

                    var blockMarks: [AudioTimeMark] = []
                    if emitMarks {
                        let isLastBlock = (emittedSamples + count) >= totalSamples
                        while markCursor < allMarks.count {
                            if isLastBlock || allMarks[markCursor].offsetSeconds < blockEndSeconds {
                                blockMarks.append(allMarks[markCursor])
                                markCursor += 1
                            } else {
                                break
                            }
                        }
                    }

                    let chunk = AudioChunk(
                        samples: [Int16](repeating: 0, count: count),
                        sampleRate: sampleRate,
                        hostTime: 0,
                        marks: blockMarks
                    )

                    // TTS-5 线性化关键点：在持锁区内确认未取消并同步 yield
                    guard let strongSelf = self else {
                        continuation.finish()
                        return
                    }
                    let didYield = strongSelf.state.withLock { s -> Bool in
                        guard !Task.isCancelled, let entry = s.activeStreams[streamID] else {
                            return false
                        }
                        entry.continuation.yield(chunk)
                        return true
                    }
                    guard didYield else { return }

                    emittedSamples += count
                }

                if let strongSelf = self {
                    let finishedContinuation = strongSelf.state.withLock { s -> AsyncThrowingStream<AudioChunk, Error>.Continuation? in
                        s.activeStreams.removeValue(forKey: streamID)?.continuation
                    }
                    finishedContinuation?.finish()
                } else {
                    continuation.finish()
                }
            }

            let shouldCancelImmediately = state.withLock { s -> Bool in
                if s.activeStreams[streamID] != nil {
                    s.activeStreams[streamID]?.task = producer
                    return false
                }
                return true
            }
            if shouldCancelImmediately {
                producer.cancel()
            }
        }
    }

    public func cancelAll() async {
        let active = state.withLock { s -> [ActiveStream] in
            s.cancelCount += 1
            let list = Array(s.activeStreams.values)
            s.activeStreams.removeAll()
            return list
        }
        for entry in active {
            entry.task?.cancel()
            entry.continuation.finish()
        }
    }

    deinit {
        let active = state.withLock { s -> [ActiveStream] in
            let list = Array(s.activeStreams.values)
            s.activeStreams.removeAll()
            return list
        }
        for entry in active {
            entry.task?.cancel()
            entry.continuation.finish()
        }
    }
}
