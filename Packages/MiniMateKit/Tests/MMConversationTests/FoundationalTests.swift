import Foundation
import os
import Testing
import MMAudio
import MMCore
import MMSecurity
@testable import MMConversation

private final class StepManualClock: MMCore.Clock, @unchecked Sendable {
    private struct State {
        var now: Date
        var sleepers: [CheckedContinuation<Void, any Error>] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(seconds: TimeInterval = 0) {
        self.state = OSAllocatedUnfairLock(initialState: State(now: Date(timeIntervalSinceReferenceDate: seconds)))
    }

    var now: Date {
        state.withLock { $0.now }
    }

    var sleeperCount: Int {
        state.withLock { $0.sleepers.count }
    }

    func sleep(for duration: Duration) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let cancelledImmediately = state.withLock { s -> Bool in
                    if Task.isCancelled {
                        return true
                    }
                    s.sleepers.append(continuation)
                    return false
                }
                if cancelledImmediately {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let pending = state.withLock { s -> [CheckedContinuation<Void, any Error>] in
                let list = s.sleepers
                s.sleepers.removeAll()
                return list
            }
            for cont in pending {
                cont.resume(throwing: CancellationError())
            }
        }
    }

    func wakeAll(advanceSeconds: TimeInterval = 0.05) {
        let pending = state.withLock { s -> [CheckedContinuation<Void, any Error>] in
            s.now = s.now.addingTimeInterval(advanceSeconds)
            let list = s.sleepers
            s.sleepers.removeAll()
            return list
        }
        for cont in pending {
            cont.resume()
        }
    }
}

@Suite("MMConversation Foundational（Persona / TTSEmotionMapping / FakeTTS / Realtime）")
struct FoundationalTests {

    // MARK: - Persona

    @Test("Persona.loadBundled 加载内置 persona.md 并解析全部字段")
    func personaLoadBundled() throws {
        let persona = try Persona.loadBundled()
        #expect(persona.name == "小瓜")
        #expect(persona.addressUserAs == "你")
        #expect(!persona.description.isEmpty)
        #expect(persona.rules.count >= 5)
    }

    @Test("Persona.parse 拒绝缺失必填节的畸形 Markdown")
    func personaParseRejectsMalformedMarkdown() {
        let missingName = """
        - 称呼用户：你
        ## 性格与说话风格
        俏皮
        ## 规则
        - 简短
        """
        #expect(throws: PersonaError.self) {
            _ = try Persona.parse(markdown: missingName)
        }

        let missingAddress = """
        # 小瓜
        ## 性格与说话风格
        俏皮
        ## 规则
        - 简短
        """
        #expect(throws: PersonaError.self) {
            _ = try Persona.parse(markdown: missingAddress)
        }

        let missingRules = """
        # 小瓜
        - 称呼用户：你
        ## 性格与说话风格
        俏皮
        """
        #expect(throws: PersonaError.self) {
            _ = try Persona.parse(markdown: missingRules)
        }

        let missingStyle = """
        # 小瓜
        - 称呼用户：你
        ## 性格与说话风格
        ## 规则
        - 简短
        """
        do {
            _ = try Persona.parse(markdown: missingStyle)
            Issue.record("预期抛出 PersonaError.invalidFormat")
        } catch let error as PersonaError {
            if case .invalidFormat = error {
                // ok
            } else {
                Issue.record("预期 invalidFormat，实际：\(error)")
            }
        } catch {
            Issue.record("未预期错误类型：\(error)")
        }
    }

    @Test("Persona.makeInstructions 包含全部枚举值、语气优先、按开关控制第 6 条与追加 extraInstructions")
    func personaMakeInstructions() throws {
        let persona = try Persona.loadBundled()

        let full = persona.makeInstructions(extraInstructions: "用户偏好简短回答。")
        #expect(full.contains("小瓜"))
        #expect(full.contains("以语气为准"))
        #expect(full.contains("用户偏好简短回答。"))

        for u in UserEmotion.allCases {
            #expect(full.contains(u.rawValue))
        }
        for e in EmotionTag.allCases {
            #expect(full.contains(e.rawValue))
        }
        for a in ActionTag.allCases {
            #expect(full.contains(a.rawValue))
        }
        for c in AssistantCommand.allCases {
            #expect(full.contains("<cmd:\(c.rawValue)>"))
        }

        // includeCommandInstructions == false 时不包含 <cmd:
        let withoutCmd = persona.makeInstructions(extraInstructions: "   \n  ", includeCommandInstructions: false)
        #expect(!withoutCmd.contains("<cmd:"))
        #expect(withoutCmd.contains("以语气为准"))
    }

    // MARK: - TTSEmotionMapping

    @Test("TTSEmotionMapping JSON 对象解编码（含 string/number/bool）与缺失情绪回退 neutral（TTS-2）")
    func emotionMappingRoundTripAndFallback() throws {
        let json = """
        {
          "vendor": "aliyun",
          "voice": "longxiaoxia",
          "map": {
            "neutral": { "style": "neutral", "rate": 1.0, "warm": false },
            "happy": { "style": "cheerful", "rate": 1.15, "warm": true }
          }
        }
        """
        let mapping = try TTSEmotionMapping.load(from: Data(json.utf8))
        #expect(mapping.vendor == .aliyun)
        #expect(mapping.voice == "longxiaoxia")

        let happy = mapping.params(for: .happy)
        #expect(happy.string("style") == "cheerful")
        #expect(happy.number("rate") == 1.15)
        #expect(happy.bool("warm") == true)

        // TTS-2：未配置的 .shy 回退到 .neutral
        let shyFallback = mapping.params(for: .shy)
        #expect(shyFallback == mapping.params(for: .neutral))
        #expect(shyFallback.string("style") == "neutral")
        #expect(shyFallback.bool("warm") == false)

        // 编码后再解码为 JSON 对象往返相等
        let encoded = try JSONEncoder().encode(mapping)
        let decoded = try TTSEmotionMapping.load(from: encoded)
        #expect(decoded == mapping)
    }

    @Test("TTSEmotionMapping 拒绝空 voice、未知情绪键、缺 neutral 与缺失内置文件")
    func emotionMappingValidationErrors() {
        let emptyVoice = #"{"vendor":"aliyun","voice":"   ","map":{"neutral":{}}}"#
        #expect(throws: TTSEmotionMappingError.emptyVoice) {
            _ = try TTSEmotionMapping.load(from: Data(emptyVoice.utf8))
        }

        let unknownKey = #"{"vendor":"aliyun","voice":"v1","map":{"neutral":{},"excited":{"rate":1.2}}}"#
        #expect(throws: TTSEmotionMappingError.unknownEmotionKey("excited")) {
            _ = try TTSEmotionMapping.load(from: Data(unknownKey.utf8))
        }

        let missingNeutral = #"{"vendor":"aliyun","voice":"v1","map":{"happy":{"rate":1.1}}}"#
        #expect(throws: TTSEmotionMappingError.missingNeutralMapping) {
            _ = try TTSEmotionMapping.load(from: Data(missingNeutral.utf8))
        }

        #expect(throws: TTSEmotionMappingError.resourceNotFound(.aliyun)) {
            _ = try TTSEmotionMapping.loadBundled(for: .aliyun)
        }
    }

    // MARK: - FakeTTSProvider

    @Test("FakeTTSProvider 按字数分块产出静音音频、空句 0 块、含字级 marks（TTS-3 / TTS-6）")
    func fakeTTSSynthesisAndWordMarks() async throws {
        let provider = FakeTTSProvider(
            outputFormat: .pcm24kMono,
            millisecondsPerCharacter: 100,
            chunkDurationMilliseconds: 100,
            includeWordMarks: true
        )

        // 3 个字 × 100 ms = 300 ms → 24,000 * 0.3 = 7,200 样本，按 2,400/块分 3 块
        var chunks: [AudioChunk] = []
        for try await chunk in provider.synthesize("你好呀", emotion: .happy) {
            chunks.append(chunk)
        }
        #expect(chunks.count == 3)
        let totalSamples = chunks.reduce(0) { $0 + $1.samples.count }
        #expect(totalSamples == 7_200)
        #expect(chunks.allSatisfy { $0.sampleRate == 24_000 })
        #expect(chunks.allSatisfy { $0.samples.allSatisfy { $0 == 0 } })

        let allMarks = chunks.flatMap(\.marks)
        #expect(allMarks.map(\.text) == ["你", "好", "呀"])
        #expect(allMarks.map(\.charOffset) == [0, 1, 2])
        #expect(abs(allMarks[1].offsetSeconds - 0.1) < 1e-6)

        // 空句 0 块
        var emptyChunks: [AudioChunk] = []
        for try await chunk in provider.synthesize("", emotion: .neutral) {
            emptyChunks.append(chunk)
        }
        #expect(emptyChunks.isEmpty)

        #expect(provider.recordedRequests == [
            FakeTTSProvider.Request(sentence: "你好呀", emotion: .happy),
            FakeTTSProvider.Request(sentence: "", emotion: .neutral),
        ])
    }

    @Test("FakeTTSProvider 失败规则立即抛错且产出 0 块（TTS-4）")
    func fakeTTSFailureRule() async {
        let provider = FakeTTSProvider { sentence, _ in
            sentence.contains("错") ? TTSError.synthesisFailed("boom") : nil
        }

        var received = 0
        do {
            for try await _ in provider.synthesize("出错了", emotion: .concerned) {
                received += 1
            }
            Issue.record("预期抛出 TTSError.synthesisFailed")
        } catch let error as TTSError {
            #expect(error == .synthesisFailed("boom"))
            #expect(received == 0)
        } catch {
            Issue.record("未预期的错误类型：\(error)")
        }
    }

    @Test("FakeTTSProvider cancelAll 后旧流立即终止且零后续产出，新请求正常（TTS-5）")
    func fakeTTSCancelAllLinearizability() async throws {
        let clock = StepManualClock()
        let provider = FakeTTSProvider(
            outputFormat: .pcm16kMono,
            millisecondsPerCharacter: 100,
            chunkDurationMilliseconds: 100,
            chunkDelay: .milliseconds(50),
            clock: clock
        )

        let oldStream = provider.synthesize("一二三四", emotion: .gentle)
        let consumer = Task { () throws -> Int in
            var count = 0
            for try await _ in oldStream {
                count += 1
            }
            return count
        }

        // 唤醒第 1 块，确认中途收到首块后再 cancelAll()
        while clock.sleeperCount == 0 {
            await Task.yield()
        }
        clock.wakeAll()

        // 等生产者进入第 2 块的 clock.sleep
        while clock.sleeperCount == 0 {
            await Task.yield()
        }

        await provider.cancelAll()
        #expect(provider.cancelCount == 1)
        // 再次唤醒不应导致旧流再产出任何块
        clock.wakeAll()

        // 旧流精确仅产出 1 块后立刻终止
        let oldCount = try await consumer.value
        #expect(oldCount == 1)

        // 新请求正常工作
        let newStream = provider.synthesize("好", emotion: .happy)
        let newConsumer = Task { () throws -> Int in
            var samples = 0
            for try await chunk in newStream {
                samples += chunk.samples.count
            }
            return samples
        }

        while clock.sleeperCount == 0 {
            await Task.yield()
        }
        clock.wakeAll()

        let newSamples = try await newConsumer.value
        #expect(newSamples == 1_600)
    }

    @Test("FakeTTSProvider 实例在流挂起中途释放时 deinit 立即结束流，不永久挂起")
    func fakeTTSDeinitTerminatesStreamsCleanly() async throws {
        let clock = StepManualClock()
        var ephemeral: FakeTTSProvider? = FakeTTSProvider(
            outputFormat: .pcm16kMono,
            millisecondsPerCharacter: 100,
            chunkDurationMilliseconds: 100,
            chunkDelay: .milliseconds(50),
            clock: clock
        )
        let stream = ephemeral!.synthesize("一二三", emotion: .neutral)

        // 确定性等待 producer 进入 clock.sleep 挂起状态，验证其未跨 await 强持有 self
        while clock.sleeperCount == 0 {
            await Task.yield()
        }

        // 在挂起中途释放 provider，deinit 应立刻取消 task 并 finish 流
        ephemeral = nil

        var count = 0
        for try await _ in stream {
            count += 1
        }
        #expect(count == 0)
    }

    // MARK: - RealtimeOutput / RealtimeError

    @Test("RealtimeOutput 与 RealtimeError Equatable 区分不同载荷")
    func realtimeTypesEquatable() {
        #expect(RealtimeError.authFailed != .rateLimited)
        #expect(RealtimeError.server(code: "500", message: "a") != .server(code: "500", message: "b"))
        #expect(RealtimeOutput.userTranscript("hi", isFinal: false) != .userTranscript("hi", isFinal: true))
        #expect(RealtimeOutput.error(.notConnected) == .error(.notConnected))
    }
}
