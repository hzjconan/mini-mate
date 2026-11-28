import AVFoundation
import Foundation
import os

/// PCM 重采样错误。
public enum PCMConverterError: Error, Sendable, Equatable {
    case invalidSampleRate(Int)
    case unsupportedFormat(String)
    case conversionFailed(String)
}

/// 将输入音频重采样为目标采样率的 16-bit signed PCM 单声道 `AudioChunk`（默认支持 16 / 24 kHz）。
public final class PCMConverter: @unchecked Sendable {
    private struct FormatKey: Equatable {
        let sampleRate: Double
        let channels: AVAudioChannelCount
        let commonFormat: AVAudioCommonFormat
        let isInterleaved: Bool

        init(_ format: AVAudioFormat) {
            self.sampleRate = format.sampleRate
            self.channels = format.channelCount
            self.commonFormat = format.commonFormat
            self.isInterleaved = format.isInterleaved
        }
    }

    private struct State {
        var converter: AVAudioConverter?
        var inputFormatKey: FormatKey?
    }

    public let targetFormat: AudioFormatDescription

    private let outputAudioFormat: AVAudioFormat
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// `targetSampleRate` 必须 > 0，否则抛 `PCMConverterError.invalidSampleRate`。
    public init(targetSampleRate: Int) throws {
        guard targetSampleRate > 0 else {
            throw PCMConverterError.invalidSampleRate(targetSampleRate)
        }
        guard let avFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(targetSampleRate),
            channels: 1,
            interleaved: true
        ) else {
            throw PCMConverterError.unsupportedFormat("无法创建目标格式 Int16 mono \(targetSampleRate) Hz")
        }
        self.targetFormat = AudioFormatDescription(sampleRate: targetSampleRate, channels: 1, bitsPerSample: 16)
        self.outputAudioFormat = avFormat
    }

    /// 流式转换一个 `AudioChunk`：保留内部重采样滤波器状态以消除块间爆音；若输入与目标同采样率则零转换直通。
    public func convert(_ chunk: AudioChunk) throws -> AudioChunk {
        guard chunk.sampleRate > 0 else {
            throw PCMConverterError.invalidSampleRate(chunk.sampleRate)
        }
        if chunk.samples.isEmpty {
            return AudioChunk(samples: [], sampleRate: targetFormat.sampleRate, hostTime: chunk.hostTime, marks: chunk.marks)
        }
        if chunk.sampleRate == targetFormat.sampleRate {
            // 路由切换至同采样率直通时清空旧转换器状态，避免 flush() 吐出旧路由残留 FIR 帧或切回时复用脏滤波器
            state.withLock { s in
                s.converter = nil
                s.inputFormatKey = nil
            }
            return chunk
        }

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(chunk.sampleRate),
            channels: 1,
            interleaved: true
        ) else {
            throw PCMConverterError.unsupportedFormat("不支持的输入采样率 \(chunk.sampleRate) Hz")
        }

        let frameCount = AVAudioFrameCount(chunk.samples.count)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            throw PCMConverterError.conversionFailed("无法分配输入 AVAudioPCMBuffer")
        }
        inputBuffer.frameLength = frameCount
        if let dst = inputBuffer.int16ChannelData?[0] {
            chunk.samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    dst.update(from: base, count: chunk.samples.count)
                }
            }
        }

        let samples = try state.withLockUnchecked { s in
            try convertBufferLocked(inputBuffer, state: &s)
        }
        return AudioChunk(samples: samples, sampleRate: targetFormat.sampleRate, hostTime: chunk.hostTime, marks: chunk.marks)
    }

    /// 流式转换一个 `AVAudioPCMBuffer`（支持 Float32/Int16、单声道/多声道），输出目标采样率 Int16 单声道 `AudioChunk`。
    public func convert(_ buffer: AVAudioPCMBuffer, hostTime: UInt64 = 0) throws -> AudioChunk {
        let inputRate = buffer.format.sampleRate
        guard inputRate.isFinite && inputRate > 0 else {
            throw PCMConverterError.invalidSampleRate(Int(inputRate.isFinite ? inputRate : 0))
        }
        if buffer.frameLength == 0 {
            return AudioChunk(samples: [], sampleRate: targetFormat.sampleRate, hostTime: hostTime)
        }

        // 若输入已是精确目标采样率、单声道 Int16，清空旧转换器状态并直接零转换读取
        if inputRate == Double(targetFormat.sampleRate),
           buffer.format.channelCount == 1,
           buffer.format.commonFormat == .pcmFormatInt16,
           let ptr = buffer.int16ChannelData?[0]
        {
            state.withLock { s in
                s.converter = nil
                s.inputFormatKey = nil
            }
            let count = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: ptr, count: count))
            return AudioChunk(samples: samples, sampleRate: targetFormat.sampleRate, hostTime: hostTime)
        }

        let samples = try state.withLockUnchecked { s in
            try convertBufferLocked(buffer, state: &s)
        }
        return AudioChunk(samples: samples, sampleRate: targetFormat.sampleRate, hostTime: hostTime)
    }

    /// 排空流式转换器内部 FIR 尾部样本并重置转换器状态；无缓存转换器或无尾部样本时返回 `nil`。
    public func flush(hostTime: UInt64 = 0) throws -> AudioChunk? {
        let samples = try state.withLock { s -> [Int16] in
            guard let converter = s.converter else { return [] }
            defer { converter.reset() }
            var drained: [Int16] = []
            let chunkCapacity: AVAudioFrameCount = 1024

            while true {
                guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputAudioFormat, frameCapacity: chunkCapacity) else {
                    throw PCMConverterError.conversionFailed("无法分配 flush 输出缓冲")
                }
                var nsError: NSError?
                let status = converter.convert(to: outBuffer, error: &nsError) { _, outStatus in
                    outStatus.pointee = .endOfStream
                    return nil
                }

                if status == .error {
                    let message = nsError?.localizedDescription ?? "AVAudioConverter flush error"
                    throw PCMConverterError.conversionFailed(message)
                }

                let produced = Int(outBuffer.frameLength)
                if produced > 0, let ptr = outBuffer.int16ChannelData?[0] {
                    drained.append(contentsOf: UnsafeBufferPointer(start: ptr, count: produced))
                }

                if status == .endOfStream || produced == 0 {
                    break
                }
            }

            return drained
        }

        guard !samples.isEmpty else { return nil }
        return AudioChunk(samples: samples, sampleRate: targetFormat.sampleRate, hostTime: hostTime)
    }

    /// 重置内部重采样滤波器状态（路由切换或新一轮开始时调用）。
    public func reset() {
        state.withLock { s in
            s.converter?.reset()
        }
    }

    /// 一次性完整转换（等价于独立转换器 `convert` + `flush`，适合 WAV 文件整段重采样）。
    public static func convertComplete(_ chunk: AudioChunk, toSampleRate targetSampleRate: Int) throws -> AudioChunk {
        let converter = try PCMConverter(targetSampleRate: targetSampleRate)
        if chunk.sampleRate <= 0 {
            throw PCMConverterError.invalidSampleRate(chunk.sampleRate)
        }
        if chunk.samples.isEmpty || chunk.sampleRate == targetSampleRate {
            return try converter.convert(chunk)
        }

        let main = try converter.convert(chunk)
        var allSamples = main.samples
        if let tail = try converter.flush(hostTime: chunk.hostTime) {
            allSamples.append(contentsOf: tail.samples)
        }
        return AudioChunk(
            samples: allSamples,
            sampleRate: targetSampleRate,
            hostTime: chunk.hostTime,
            marks: chunk.marks
        )
    }

    private func convertBufferLocked(_ inputBuffer: AVAudioPCMBuffer, state s: inout State) throws -> [Int16] {
        let key = FormatKey(inputBuffer.format)
        let converter: AVAudioConverter
        if let existing = s.converter, s.inputFormatKey == key {
            converter = existing
        } else {
            guard let created = AVAudioConverter(from: inputBuffer.format, to: outputAudioFormat) else {
                throw PCMConverterError.unsupportedFormat(
                    "不支持的格式转换：\(inputBuffer.format) -> \(outputAudioFormat)"
                )
            }
            s.converter = created
            s.inputFormatKey = key
            converter = created
        }

        let ratio = outputAudioFormat.sampleRate / inputBuffer.format.sampleRate
        let expected = Int(ceil(Double(inputBuffer.frameLength) * ratio))
        let capacity = AVAudioFrameCount(max(expected + 512, 512))

        var outputSamples: [Int16] = []
        outputSamples.reserveCapacity(max(expected, 0))

        var provided = false
        while true {
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputAudioFormat, frameCapacity: capacity) else {
                throw PCMConverterError.conversionFailed("无法分配输出 AVAudioPCMBuffer")
            }

            var nsError: NSError?
            let status = converter.convert(to: outBuffer, error: &nsError) { _, outStatus in
                if !provided {
                    provided = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }

            if status == .error {
                let message = nsError?.localizedDescription ?? "AVAudioConverter error"
                throw PCMConverterError.conversionFailed(message)
            }

            let produced = Int(outBuffer.frameLength)
            if produced > 0, let ptr = outBuffer.int16ChannelData?[0] {
                outputSamples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: produced))
            }

            if status == .inputRanDry || status == .endOfStream || produced == 0 {
                break
            }
        }

        return outputSamples
    }
}
