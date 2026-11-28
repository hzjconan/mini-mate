import Foundation
import Testing
@testable import MMAudio

@Suite("WAVCodec & PCMByteAligner")
struct WAVCodecTests {
    @Test func encodeDecodePCM16MonoRoundTrip() throws {
        let samples: [Int16] = [0, 1234, -5678, Int16.max, Int16.min, 42, -1]
        let original = AudioChunk(samples: samples, sampleRate: 16_000)

        let wav = try WAVCodec.encodeWAV(original)
        #expect(wav.count == 44 + samples.count * 2)

        let decoded = try WAVCodec.decodePCM16MonoWAV(wav)
        #expect(decoded.sampleRate == 16_000)
        #expect(decoded.samples == samples)
    }

    @Test func decodeSkipsJunkAndListSubchunks() throws {
        let samples: [Int16] = [100, -200, 300, -400]
        let baseWAV = try WAVCodec.encodeWAV(AudioChunk(samples: samples, sampleRate: 24_000))

        // Extract fmt (bytes 12..36) and data (bytes 36...) and insert JUNK (odd length 5 -> padded to 6) + LIST (4).
        let fmtChunk = baseWAV.subdata(in: 12..<36)
        let dataChunk = baseWAV.subdata(in: 36..<baseWAV.count)

        var junkChunk = Data("JUNK".utf8)
        var junkSize = UInt32(5).littleEndian
        withUnsafeBytes(of: &junkSize) { junkChunk.append(contentsOf: $0) }
        junkChunk.append(contentsOf: [1, 2, 3, 4, 5, 0]) // 5 bytes + 1 pad byte

        var listChunk = Data("LIST".utf8)
        var listSize = UInt32(4).littleEndian
        withUnsafeBytes(of: &listSize) { listChunk.append(contentsOf: $0) }
        listChunk.append(contentsOf: "INFO".utf8)

        let body = fmtChunk + junkChunk + listChunk + dataChunk
        var extended = Data("RIFF".utf8)
        var riffSize = UInt32(4 + body.count).littleEndian
        withUnsafeBytes(of: &riffSize) { extended.append(contentsOf: $0) }
        extended.append(contentsOf: "WAVE".utf8)
        extended.append(body)

        let decoded = try WAVCodec.decodePCM16MonoWAV(extended)
        #expect(decoded.sampleRate == 24_000)
        #expect(decoded.samples == samples)
    }

    @Test func writeAndLoadAudioFileResamples48kTo16k() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimate-wav-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let wavURL = dir.appendingPathComponent("tone-48k.wav")

        // Generate 1 second of 440 Hz sine wave at 48 kHz.
        let sampleRate = 48_000
        let samples: [Int16] = (0..<sampleRate).map { i in
            let phase = 2.0 * Double.pi * 440.0 * Double(i) / Double(sampleRate)
            return Int16(sin(phase) * 12_000.0)
        }
        try WAVCodec.writeWAV(
            chunks: [
                AudioChunk(samples: Array(samples.prefix(24_000)), sampleRate: sampleRate),
                AudioChunk(samples: Array(samples.dropFirst(24_000)), sampleRate: sampleRate),
            ],
            sampleRate: sampleRate,
            to: wavURL
        )

        let loaded = try WAVCodec.loadAudioFile(at: wavURL, targetSampleRate: 16_000)
        #expect(loaded.sampleRate == 16_000)
        #expect(abs(loaded.samples.count - 16_000) <= 320) // within ±2%
    }

    @Test func pcmByteAlignerCombinesOddSizedChunksWithoutDroppingBytes() {
        var aligner = PCMByteAligner()
        let expectedSamples: [Int16] = [0x0102, 0x0304, -1234, 0x7F01]
        let fullBytes = AudioChunk(samples: expectedSamples, sampleRate: 16_000).pcmData
        #expect(fullBytes.count == 8)

        let part1 = aligner.append(fullBytes.subdata(in: 0..<3))
        #expect(part1.count == 2)
        #expect(aligner.hasPendingByte)

        let part2 = aligner.append(fullBytes.subdata(in: 3..<8))
        #expect(part2.count == 6)
        #expect(!aligner.hasPendingByte)

        let combined = AudioChunk(pcmData: part1 + part2, sampleRate: 16_000)
        #expect(combined.samples == expectedSamples)

        _ = aligner.append(Data([0xAA]))
        #expect(aligner.hasPendingByte)
        aligner.reset()
        #expect(!aligner.hasPendingByte)
    }

    @Test func malformedWAVAndMissingFileThrowTypedErrors() throws {
        // Truncated header
        #expect(throws: WAVCodecError.invalidHeader("WAV data shorter than 44 bytes (10)")) {
            _ = try WAVCodec.decodePCM16MonoWAV(Data(repeating: 0, count: 10))
        }

        // Stereo WAV rejected
        var stereo = try WAVCodec.encodeWAV(AudioChunk(samples: [1, 2], sampleRate: 16_000))
        stereo[22] = 2 // numChannels = 2
        #expect(throws: WAVCodecError.unsupportedFormat("Expected mono WAV, got 2 channels")) {
            _ = try WAVCodec.decodePCM16MonoWAV(stereo)
        }

        // Missing file throws ioError
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).wav")
        var threwIOError = false
        do {
            _ = try WAVCodec.loadAudioFile(at: missing, targetSampleRate: 16_000)
        } catch WAVCodecError.ioError {
            threwIOError = true
        }
        #expect(threwIOError)
    }
}
