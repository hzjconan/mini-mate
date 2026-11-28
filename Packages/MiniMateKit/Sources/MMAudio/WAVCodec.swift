import AVFoundation
import Foundation

public enum WAVCodecError: Error, Sendable, Equatable {
    case invalidHeader(String)
    case unsupportedFormat(String)
    case ioError(String)
}

/// Cross-frame byte aligner for streaming 16-bit little-endian PCM.
/// Keeps a trailing odd byte until the next frame arrives so sample boundaries never shift.
public struct PCMByteAligner: Sendable {
    private var pendingByte: UInt8?

    public init() {}

    public var hasPendingByte: Bool { pendingByte != nil }

    public mutating func append(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data() }

        var combined = Data()
        combined.reserveCapacity(data.count + (pendingByte == nil ? 0 : 1))
        if let pending = pendingByte {
            combined.append(pending)
            pendingByte = nil
        }
        combined.append(data)

        if combined.count % 2 == 1 {
            pendingByte = combined.removeLast()
        }
        return combined
    }

    public mutating func reset() {
        pendingByte = nil
    }
}

public enum WAVCodec {
    public static func encodeWAV(_ chunk: AudioChunk) throws -> Data {
        guard chunk.sampleRate > 0 else {
            throw WAVCodecError.unsupportedFormat("Invalid sample rate: \(chunk.sampleRate)")
        }
        let pcm = chunk.pcmData
        let byteCount = pcm.count
        guard byteCount <= Int(UInt32.max) - 36 else {
            throw WAVCodecError.unsupportedFormat("PCM payload too large for standard RIFF/WAV")
        }

        let sampleRate = UInt32(chunk.sampleRate)
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(byteCount)
        let riffSize = UInt32(36) + dataSize

        var wav = Data(capacity: 44 + byteCount)
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendLE(riffSize, to: &wav)
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        appendLE(UInt32(16), to: &wav)                   // PCM fmt chunk size
        appendLE(UInt16(1), to: &wav)                    // PCM format
        appendLE(numChannels, to: &wav)
        appendLE(sampleRate, to: &wav)
        appendLE(byteRate, to: &wav)
        appendLE(blockAlign, to: &wav)
        appendLE(bitsPerSample, to: &wav)

        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendLE(dataSize, to: &wav)
        wav.append(pcm)
        return wav
    }

    public static func writeWAV(chunks: [AudioChunk], sampleRate: Int, to url: URL) throws {
        guard sampleRate > 0 else {
            throw WAVCodecError.unsupportedFormat("Invalid target sample rate: \(sampleRate)")
        }
        var combinedSamples: [Int16] = []
        for chunk in chunks where !chunk.samples.isEmpty {
            if chunk.sampleRate == sampleRate {
                combinedSamples.append(contentsOf: chunk.samples)
            } else {
                do {
                    let converted = try PCMConverter.convertComplete(chunk, toSampleRate: sampleRate)
                    combinedSamples.append(contentsOf: converted.samples)
                } catch {
                    throw WAVCodecError.unsupportedFormat("Failed to resample chunk: \(error)")
                }
            }
        }
        let wavData = try encodeWAV(AudioChunk(samples: combinedSamples, sampleRate: sampleRate))
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try wavData.write(to: url, options: .atomic)
        } catch {
            throw WAVCodecError.ioError("Failed to write WAV at \(url.path): \(error.localizedDescription)")
        }
    }

    public static func decodePCM16MonoWAV(_ data: Data) throws -> AudioChunk {
        guard data.count >= 44 else {
            throw WAVCodecError.invalidHeader("WAV data shorter than 44 bytes (\(data.count))")
        }
        guard asciiTag(in: data, offset: 0) == "RIFF",
              asciiTag(in: data, offset: 8) == "WAVE"
        else {
            throw WAVCodecError.invalidHeader("Missing RIFF/WAVE signature")
        }

        var offset = 12
        var foundFmt = false
        var audioFormat: UInt16 = 0
        var numChannels: UInt16 = 0
        var sampleRate: UInt32 = 0
        var bitsPerSample: UInt16 = 0
        var pcmSlice: Data?

        while offset + 8 <= data.count {
            let chunkID = asciiTag(in: data, offset: offset)
            let chunkSize = Int(readUInt32LE(in: data, offset: offset + 4))
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + chunkSize
            guard payloadEnd <= data.count else {
                throw WAVCodecError.invalidHeader("Truncated subchunk '\(chunkID)'")
            }

            if chunkID == "fmt " {
                guard chunkSize >= 16 else {
                    throw WAVCodecError.invalidHeader("fmt subchunk smaller than 16 bytes")
                }
                audioFormat = readUInt16LE(in: data, offset: payloadStart)
                numChannels = readUInt16LE(in: data, offset: payloadStart + 2)
                sampleRate = readUInt32LE(in: data, offset: payloadStart + 4)
                bitsPerSample = readUInt16LE(in: data, offset: payloadStart + 14)
                foundFmt = true
            } else if chunkID == "data" {
                pcmSlice = data.subdata(in: payloadStart..<payloadEnd)
            }

            // RIFF chunks are word-aligned (even byte boundary).
            offset = payloadEnd + (chunkSize % 2)
        }

        guard foundFmt else {
            throw WAVCodecError.invalidHeader("Missing fmt subchunk")
        }
        guard audioFormat == 1 else {
            throw WAVCodecError.unsupportedFormat("Unsupported WAV audio format code: \(audioFormat)")
        }
        guard numChannels == 1 else {
            throw WAVCodecError.unsupportedFormat("Expected mono WAV, got \(numChannels) channels")
        }
        guard bitsPerSample == 16 else {
            throw WAVCodecError.unsupportedFormat("Expected 16-bit PCM WAV, got \(bitsPerSample)-bit")
        }
        guard sampleRate > 0 else {
            throw WAVCodecError.unsupportedFormat("Invalid WAV sample rate: \(sampleRate)")
        }
        guard let pcm = pcmSlice else {
            throw WAVCodecError.invalidHeader("Missing data subchunk")
        }

        return AudioChunk(pcmData: pcm, sampleRate: Int(sampleRate))
    }

    /// Reads an audio file from disk via `AVAudioFile` and resamples to mono Int16 at `targetSampleRate`
    /// using `PCMConverter` (including `flush()` to drain FIR tail frames).
    public static func loadAudioFile(at url: URL, targetSampleRate: Int) throws -> AudioChunk {
        guard targetSampleRate > 0 else {
            throw WAVCodecError.unsupportedFormat("Invalid target sample rate: \(targetSampleRate)")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WAVCodecError.ioError("Audio file not found: \(url.path)")
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw WAVCodecError.ioError("Unable to open audio file \(url.lastPathComponent): \(error.localizedDescription)")
        }

        let converter: PCMConverter
        do {
            converter = try PCMConverter(targetSampleRate: targetSampleRate)
        } catch {
            throw WAVCodecError.unsupportedFormat("Cannot create PCMConverter: \(error)")
        }

        let processingFormat = audioFile.processingFormat
        let readCapacity: AVAudioFrameCount = 4096
        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: readCapacity) else {
            throw WAVCodecError.ioError("Unable to allocate AVAudioPCMBuffer")
        }

        var outputSamples: [Int16] = []
        while audioFile.framePosition < audioFile.length {
            let remaining = audioFile.length - audioFile.framePosition
            let toRead = AVAudioFrameCount(min(Int64(readCapacity), remaining))
            readBuffer.frameLength = 0
            do {
                try audioFile.read(into: readBuffer, frameCount: toRead)
            } catch {
                throw WAVCodecError.ioError("Failed reading audio frames: \(error.localizedDescription)")
            }
            if readBuffer.frameLength == 0 {
                break
            }
            do {
                let converted = try converter.convert(readBuffer)
                outputSamples.append(contentsOf: converted.samples)
            } catch {
                throw WAVCodecError.unsupportedFormat("PCM conversion failed: \(error)")
            }
        }

        do {
            if let tail = try converter.flush() {
                outputSamples.append(contentsOf: tail.samples)
            }
        } catch {
            throw WAVCodecError.unsupportedFormat("PCMConverter flush failed: \(error)")
        }

        return AudioChunk(samples: outputSamples, sampleRate: targetSampleRate)
    }

    // MARK: - Helpers

    private static func appendLE(_ value: UInt16, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func appendLE(_ value: UInt32, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func readUInt16LE(in data: Data, offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        let b0 = UInt16(data[base])
        let b1 = UInt16(data[base + 1])
        return b0 | (b1 << 8)
    }

    private static func readUInt32LE(in data: Data, offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        let b0 = UInt32(data[base])
        let b1 = UInt32(data[base + 1])
        let b2 = UInt32(data[base + 2])
        let b3 = UInt32(data[base + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    private static func asciiTag(in data: Data, offset: Int) -> String {
        let base = data.startIndex + offset
        let slice = data[base..<(base + 4)]
        return String(decoding: slice, as: UTF8.self)
    }
}
