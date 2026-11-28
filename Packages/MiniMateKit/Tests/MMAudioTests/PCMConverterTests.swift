import AVFoundation
import Foundation
import Testing
@testable import MMAudio

private func makeSineSamples(frequency: Double, sampleRate: Int, duration: Double, amplitude: Double = 16_000) -> [Int16] {
    let count = Int((Double(sampleRate) * duration).rounded())
    return (0..<count).map { i in
        let t = Double(i) / Double(sampleRate)
        let value = sin(2.0 * .pi * frequency * t) * amplitude
        return Int16(max(Double(Int16.min), min(Double(Int16.max), value.rounded())))
    }
}

private func rms(_ samples: [Int16]) -> Double {
    guard !samples.isEmpty else { return 0 }
    let sumSq = samples.reduce(0.0) { acc, s in
        let v = Double(s)
        return acc + v * v
    }
    return sqrt(sumSq / Double(samples.count))
}

private func singleFrequencyMagnitude(_ samples: [Int16], frequency: Double, sampleRate: Int) -> Double {
    guard !samples.isEmpty else { return 0 }
    var re = 0.0
    var im = 0.0
    let w = 2.0 * .pi * frequency / Double(sampleRate)
    for (n, s) in samples.enumerated() {
        let v = Double(s)
        let angle = w * Double(n)
        re += v * cos(angle)
        im -= v * sin(angle)
    }
    return hypot(re, im) / Double(samples.count)
}

@Suite("AudioChunk 与 PCMConverter 纯逻辑测试")
struct PCMConverterTests {

    @Test("AudioChunk pcmData 小端往返、极端值与奇数字节安全截断")
    func audioChunkPCMDataRoundTrip() {
        let samples: [Int16] = [Int16.min, -12345, -1, 0, 1, 12345, Int16.max]
        let chunk = AudioChunk(samples: samples, sampleRate: 16_000, hostTime: 42)
        let data = chunk.pcmData
        #expect(data.count == samples.count * 2)
        #expect(chunk.byteCount == samples.count * 2)
        #expect(abs(chunk.duration - Double(samples.count) / 16_000.0) < 1e-9)

        let decoded = AudioChunk(pcmData: data, sampleRate: 16_000, hostTime: 42)
        #expect(decoded == chunk)

        // 奇数字节安全截断（不崩溃，忽略最后 1 字节）
        var oddData = data
        oddData.append(0xAB)
        let decodedOdd = AudioChunk(pcmData: oddData, sampleRate: 16_000)
        #expect(decodedOdd.samples == samples)

        // 1 字节畸形输入与空输入
        #expect(AudioChunk(pcmData: Data([0xFF]), sampleRate: 16_000).samples.isEmpty)
        #expect(AudioChunk(pcmData: Data(), sampleRate: 0).duration == 0)
    }

    @Test("PCMConverter 同率直通逐位一致，空块直接返回空")
    func passthroughAndEmptyChunk() throws {
        let converter = try PCMConverter(targetSampleRate: 16_000)
        let mark = AudioTimeMark(text: "你", offsetSeconds: 0.1, charOffset: 0)
        let input = AudioChunk(samples: [100, -200, 300, -400], sampleRate: 16_000, hostTime: 99, marks: [mark])
        let output = try converter.convert(input)
        #expect(output == input)

        let empty = AudioChunk(samples: [], sampleRate: 48_000, hostTime: 7, marks: [mark])
        let emptyOut = try converter.convert(empty)
        #expect(emptyOut.samples.isEmpty)
        #expect(emptyOut.sampleRate == 16_000)
        #expect(emptyOut.hostTime == 7)
        #expect(emptyOut.marks == [mark])
    }

    @Test("PCMConverter 48k→16k、48k→24k、44.1k→16k、16k→24k 频率与 RMS 校验")
    func resampleMatrixAccuracy() throws {
        let cases: [(from: Int, to: Int)] = [
            (48_000, 16_000),
            (48_000, 24_000),
            (44_100, 16_000),
            (16_000, 24_000),
        ]

        for pair in cases {
            let inputSamples = makeSineSamples(frequency: 440, sampleRate: pair.from, duration: 1.0)
            let inputChunk = AudioChunk(samples: inputSamples, sampleRate: pair.from)
            let resampled = try PCMConverter.convertComplete(inputChunk, toSampleRate: pair.to)

            #expect(resampled.sampleRate == pair.to)
            let minFrames = Int(Double(pair.to) * 0.99)
            let maxFrames = Int(Double(pair.to) * 1.01)
            #expect(resampled.samples.count >= minFrames && resampled.samples.count <= maxFrames)

            // 取中间稳态区间（跳过首尾各 10% 滤波瞬态）验证 RMS 与单频纯度
            let margin = resampled.samples.count / 10
            let steady = Array(resampled.samples[margin..<(resampled.samples.count - margin)])
            let inputMargin = inputSamples.count / 10
            let inputSteady = Array(inputSamples[inputMargin..<(inputSamples.count - inputMargin)])

            let rmsRatio = abs(rms(steady) - rms(inputSteady)) / rms(inputSteady)
            #expect(rmsRatio < 0.05)

            let mag440 = singleFrequencyMagnitude(steady, frequency: 440, sampleRate: pair.to)
            let mag1000 = max(singleFrequencyMagnitude(steady, frequency: 1000, sampleRate: pair.to), 1e-9)
            let snrDB = 20.0 * log10(mag440 / mag1000)
            #expect(snrDB > 20.0)
        }
    }

    @Test("PCMConverter 10×100 ms 流式转换 + flush 排空 FIR 尾帧")
    func streamingChunksAndFlush() throws {
        let converter = try PCMConverter(targetSampleRate: 16_000)
        let full48k = makeSineSamples(frequency: 440, sampleRate: 48_000, duration: 1.0)
        var collected: [Int16] = []

        for blockIndex in 0..<10 {
            let start = blockIndex * 4_800
            let slice = Array(full48k[start..<(start + 4_800)])
            let out = try converter.convert(AudioChunk(samples: slice, sampleRate: 48_000, hostTime: UInt64(blockIndex)))
            #expect(out.sampleRate == 16_000)
            collected.append(contentsOf: out.samples)
        }
        if let tail = try converter.flush(hostTime: 10) {
            #expect(tail.sampleRate == 16_000)
            collected.append(contentsOf: tail.samples)
        }

        #expect(collected.count >= 15_950 && collected.count <= 16_050)
        // flush 后再次 flush 返回 nil
        #expect(try converter.flush() == nil)
    }

    @Test("PCMConverter 动态切换采样率（48k → 44.1k）与 Float32 AVAudioPCMBuffer 输入")
    func dynamicRateSwitchAndFloat32Buffer() throws {
        let converter = try PCMConverter(targetSampleRate: 16_000)

        let first = makeSineSamples(frequency: 440, sampleRate: 48_000, duration: 0.2)
        let out1 = try converter.convert(AudioChunk(samples: first, sampleRate: 48_000))
        #expect(!out1.samples.isEmpty)

        // 动态切换到 44.1 kHz
        let second = makeSineSamples(frequency: 440, sampleRate: 44_100, duration: 0.5)
        var out2Samples = try converter.convert(AudioChunk(samples: second, sampleRate: 44_100)).samples
        if let tail = try converter.flush() {
            out2Samples.append(contentsOf: tail.samples)
        }
        #expect(out2Samples.count >= 7_900 && out2Samples.count <= 8_100)

        // Float32 AVAudioPCMBuffer 输入（48 kHz 单声道 0.5 s）
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24_000) else {
            Issue.record("无法创建测试 AVAudioPCMBuffer")
            return
        }
        buffer.frameLength = 24_000
        if let channel = buffer.floatChannelData?[0] {
            for i in 0..<24_000 {
                channel[i] = Float(sin(2.0 * .pi * 440.0 * Double(i) / 48_000.0) * 0.5)
            }
        }
        var bufSamples = try converter.convert(buffer, hostTime: 123).samples
        if let tail = try converter.flush() {
            bufSamples.append(contentsOf: tail.samples)
        }
        #expect(bufSamples.count >= 7_900 && bufSamples.count <= 8_100)
        #expect(rms(bufSamples) > 8_000)
    }

    @Test("PCMConverter 非法采样率抛出 invalidSampleRate")
    func invalidSampleRatesThrow() throws {
        #expect(throws: PCMConverterError.invalidSampleRate(0)) {
            _ = try PCMConverter(targetSampleRate: 0)
        }
        #expect(throws: PCMConverterError.invalidSampleRate(-16_000)) {
            _ = try PCMConverter(targetSampleRate: -16_000)
        }
        let converter = try PCMConverter(targetSampleRate: 16_000)
        #expect(throws: PCMConverterError.invalidSampleRate(0)) {
            _ = try converter.convert(AudioChunk(samples: [1, 2], sampleRate: 0))
        }
    }

    @Test("PCMConverter 路由切换 48 kHz → 16 kHz 直通后 flush 返回 nil，不残留旧路由 FIR 样本")
    func routeSwitchToPassthroughClearsStaleConverterState() throws {
        let converter = try PCMConverter(targetSampleRate: 16_000)

        // 先喂入 48 kHz 音频，在内部缓存 48k→16k AVAudioConverter 及 FIR 尾帧
        let samples48k = makeSineSamples(frequency: 440, sampleRate: 48_000, duration: 0.1)
        let out48 = try converter.convert(AudioChunk(samples: samples48k, sampleRate: 48_000))
        #expect(!out48.samples.isEmpty)

        // 路由切换至蓝牙 HFP 16 kHz 直通
        let samples16k: [Int16] = [10, -20, 30, -40]
        let out16 = try converter.convert(AudioChunk(samples: samples16k, sampleRate: 16_000, hostTime: 55))
        #expect(out16.samples == samples16k)
        #expect(out16.hostTime == 55)

        // 直通路径已清理旧转换器，flush() 不得吐出旧 48 kHz 残留帧
        #expect(try converter.flush() == nil)
    }
}
