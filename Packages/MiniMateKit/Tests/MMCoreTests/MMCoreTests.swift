import Foundation
import Testing
@testable import MMCore

@Suite("MMCore US5 共享契约类型测试")
struct MMCoreContractTests {

    @Test("AssistantCommand rawValue、CaseIterable 与 Codable 往返")
    func assistantCommandRoundTrip() throws {
        #expect(AssistantCommand.allCases == [.photo, .photoReady, .photoCancel])
        #expect(AssistantCommand.photo.rawValue == "photo")
        #expect(AssistantCommand.photoReady.rawValue == "photoReady")
        #expect(AssistantCommand.photoCancel.rawValue == "photoCancel")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for command in AssistantCommand.allCases {
            let data = try encoder.encode(command)
            let decoded = try decoder.decode(AssistantCommand.self, from: data)
            #expect(decoded == command)
        }
    }

    @Test("AvatarCue 默认参数、Equatable 与 Codable 往返")
    func avatarCueDefaultsAndCodable() throws {
        let defaultCue = AvatarCue(emotion: .happy)
        #expect(defaultCue.emotion == .happy)
        #expect(defaultCue.action == nil)
        #expect(defaultCue.hold == false)

        let fullCue = AvatarCue(emotion: .playful, action: .lookAround, hold: true)
        #expect(fullCue.emotion == .playful)
        #expect(fullCue.action == .lookAround)
        #expect(fullCue.hold == true)
        #expect(defaultCue != fullCue)

        let sameAsFull = AvatarCue(emotion: .playful, action: .lookAround, hold: true)
        #expect(fullCue == sameAsFull)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try encoder.encode(fullCue)
        let decoded = try decoder.decode(AvatarCue.self, from: encoded)
        #expect(decoded == fullCue)
    }

    @Test("PlaybackResult 枚举值与 Codable 往返")
    func playbackResultRoundTrip() throws {
        #expect(PlaybackResult.allCases == [.completed, .stopped])
        #expect(PlaybackResult.completed.rawValue == "completed")
        #expect(PlaybackResult.stopped.rawValue == "stopped")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for result in PlaybackResult.allCases {
            let data = try encoder.encode(result)
            let decoded = try decoder.decode(PlaybackResult.self, from: data)
            #expect(decoded == result)
        }
    }

    @Test("ConversationEvent 新增 case 的 Equatable 区分不同载荷")
    func conversationEventNewCasesEquality() {
        #expect(ConversationEvent.assistantCommand(.photo) == .assistantCommand(.photo))
        #expect(ConversationEvent.assistantCommand(.photo) != .assistantCommand(.photoCancel))

        let cueA = AvatarCue(emotion: .playful, action: .lookAround, hold: true)
        let cueB = AvatarCue(emotion: .happy, action: .heart, hold: false)
        #expect(ConversationEvent.assistantCue(cueA) == .assistantCue(cueA))
        #expect(ConversationEvent.assistantCue(cueA) != .assistantCue(cueB))

        #expect(ConversationEvent.assistantCueEnded == .assistantCueEnded)
        #expect(ConversationEvent.assistantCueEnded != .assistantSpeechEnded)
    }

    @Test("ConnectionState、GateState 与 ConversationEvent M2 扩展的语义与 Equatable")
    func connectionAndGateStateContracts() throws {
        // GateThreshold 全枚举与 Codable 往返
        #expect(GateThreshold.allCases == [.normal, .raised, .playback])
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for threshold in GateThreshold.allCases {
            let data = try encoder.encode(threshold)
            #expect(try decoder.decode(GateThreshold.self, from: data) == threshold)
        }

        // GateState isUploading & threshold
        #expect(GateState.open(threshold: .playback).isUploading == true)
        #expect(GateState.open().isUploading == true)
        #expect(GateState.muted.isUploading == false)
        #expect(GateState.paused.isUploading == false)
        #expect(GateState.closed().isUploading == false)
        #expect(GateState.closed(threshold: .raised).isUploading == false)

        #expect(GateState.muted.threshold == nil)
        #expect(GateState.paused.threshold == nil)
        #expect(GateState.closed().threshold == .normal)
        #expect(GateState.closed(threshold: .raised).threshold == .raised)
        #expect(GateState.open(threshold: .playback).threshold == .playback)

        // Equatable 精确区分不同载荷
        #expect(ConnectionState.reconnecting(attempt: 1) == .reconnecting(attempt: 1))
        #expect(ConnectionState.reconnecting(attempt: 1) != .reconnecting(attempt: 2))
        #expect(ConnectionState.connecting != .connected)
        #expect(ConnectionState.connected != .lost)

        #expect(GateState.closed(threshold: .normal) == .closed())
        #expect(GateState.closed(threshold: .normal) != .closed(threshold: .raised))
        #expect(GateState.open(threshold: .normal) != .open(threshold: .playback))

        #expect(
            ConversationEvent.connectionStateChanged(.reconnecting(attempt: 1))
                != .connectionStateChanged(.reconnecting(attempt: 2))
        )
        #expect(
            ConversationEvent.gateStateChanged(.closed(threshold: .normal))
                != .gateStateChanged(.closed(threshold: .raised))
        )
    }
}
