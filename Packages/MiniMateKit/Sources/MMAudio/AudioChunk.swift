import Foundation

/// PCM 音频格式描述。
public struct AudioFormatDescription: Sendable, Equatable, Codable {
    public let sampleRate: Int
    public let channels: Int
    public let bitsPerSample: Int

    public init(sampleRate: Int, channels: Int = 1, bitsPerSample: Int = 16) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
    }

    public static let pcm16kMono = AudioFormatDescription(sampleRate: 16_000, channels: 1, bitsPerSample: 16)
    public static let pcm24kMono = AudioFormatDescription(sampleRate: 24_000, channels: 1, bitsPerSample: 16)
    public static let pcm48kMono = AudioFormatDescription(sampleRate: 48_000, channels: 1, bitsPerSample: 16)
}

/// TTS 字级 / 音素级时间戳（contracts/tts-provider.md TTS-6）。
public struct AudioTimeMark: Sendable, Equatable, Codable {
    public let text: String
    public let offsetSeconds: TimeInterval
    public let charOffset: Int?

    public init(text: String, offsetSeconds: TimeInterval, charOffset: Int? = nil) {
        self.text = text
        self.offsetSeconds = max(0, offsetSeconds.isFinite ? offsetSeconds : 0)
        self.charOffset = charOffset
    }
}

/// PCM 16-bit 单声道音频块。
public struct AudioChunk: Sendable, Equatable {
    public let samples: [Int16]
    public let sampleRate: Int
    public let hostTime: UInt64
    public let marks: [AudioTimeMark]

    public init(
        samples: [Int16],
        sampleRate: Int,
        hostTime: UInt64 = 0,
        marks: [AudioTimeMark] = []
    ) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.hostTime = hostTime
        self.marks = marks
    }

    /// 从小端 16-bit signed PCM 字节流构造；若存在尾部多余的 1 个奇数字节则忽略该不完整字节。
    public init(
        pcmData: Data,
        sampleRate: Int,
        hostTime: UInt64 = 0,
        marks: [AudioTimeMark] = []
    ) {
        let sampleCount = pcmData.count / MemoryLayout<Int16>.size
        var decoded = [Int16]()
        decoded.reserveCapacity(sampleCount)
        pcmData.withUnsafeBytes { raw in
            for i in 0..<sampleCount {
                let offset = i * 2
                let lo = UInt16(raw[offset])
                let hi = UInt16(raw[offset + 1])
                decoded.append(Int16(bitPattern: lo | (hi << 8)))
            }
        }
        self.init(samples: decoded, sampleRate: sampleRate, hostTime: hostTime, marks: marks)
    }

    /// 小端 16-bit signed PCM 字节流（供 WebSocket / HTTP 传输）。
    public var pcmData: Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let bits = UInt16(bitPattern: sample).littleEndian
            data.append(UInt8(truncatingIfNeeded: bits))
            data.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        return data
    }

    /// 音频块时长（秒）；`sampleRate <= 0` 时返回 `0`。
    public var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / Double(sampleRate)
    }

    /// PCM 字节数（`samples.count * 2`）。
    public var byteCount: Int {
        samples.count * MemoryLayout<Int16>.size
    }
}
