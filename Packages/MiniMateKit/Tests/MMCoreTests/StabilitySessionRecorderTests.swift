import Foundation
import Testing
@testable import MMCore

@Suite("StabilitySessionRecorder")
struct StabilitySessionRecorderTests {
    @Test func tenMinuteSixtyFpsNominalToFairPassesAllCriteria() {
        var recorder = StabilitySessionRecorder(targetDuration: 600.0, sampleInterval: 1.0, maxSamples: 3600)
        recorder.start(at: 1000.0, initialThermalLevel: .nominal)

        // 首帧锚定窗口起点 t = 1000.0；随后 36,000 帧步进至 t = 1600.0（600 秒 × 60 fps）
        let first = recorder.recordFrame(
            at: 1000.0,
            thermalLevel: .nominal,
            effectiveGestureRateHz: 12.0,
            isFaceTracked: true,
            memoryMBProvider: { 260.0 }
        )
        #expect(first == nil)

        var emittedCount = 0
        for frame in 1...36_000 {
            let elapsed = Double(frame) / 60.0
            let t = 1000.0 + elapsed
            let thermal: StabilityThermalLevel = elapsed >= 300.0 ? .fair : .nominal
            let mem = 260.0 + (elapsed / 600.0) * 50.0 // 260 -> 310 MiB
            if recorder.recordFrame(
                at: t,
                thermalLevel: thermal,
                effectiveGestureRateHz: 12.0,
                isFaceTracked: true,
                memoryMBProvider: { mem }
            ) != nil {
                emittedCount += 1
            }
        }

        let report = recorder.finish()
        #expect(emittedCount == 600)
        #expect(report.sampleCount == 600)
        #expect(abs(report.duration - 600.0) < 1e-6)
        #expect(abs(report.avgFps - 60.0) < 1e-6)
        #expect(abs(report.p50Fps - 60.0) < 1e-6)
        #expect(abs(report.p10Fps - 60.0) < 1e-6)
        #expect(abs(report.minFps - 60.0) < 1e-6)
        #expect(abs(report.maxMemoryMB - 310.0) < 1e-6)
        #expect(report.peakThermalLevel == .fair)
        #expect(report.thermalTransitions.count == 2)
        #expect(report.thermalTransitions[0] == ThermalTransition(elapsed: 0.0, from: nil, to: .nominal))
        #expect(report.thermalTransitions[1].from == .nominal)
        #expect(report.thermalTransitions[1].to == .fair)
        #expect(abs(report.thermalTransitions[1].elapsed - 300.0) < 1e-6)
        #expect(abs(report.faceTrackedRatio - 1.0) < 1e-9)
        #expect(report.sessionInterruptionCount == 0)
        #expect(report.thermalSessionInterruptionCount == 0)
        #expect(report.passedDuration)
        #expect(report.passedFps)
        #expect(report.passedMemory)
        #expect(report.passedThermalTracking)
        #expect(report.passed)
        #expect(!recorder.isRunning)
    }

    @Test func memoryProviderIsInvokedOnlyAtOneHertzSampleBoundary() {
        var recorder = StabilitySessionRecorder(targetDuration: 2.0, sampleInterval: 1.0)
        recorder.start(at: 0.0, initialThermalLevel: .nominal)

        var providerCallCount = 0
        // 121 帧：t = 0.0 到 t = 2.0，步长 1/60
        for i in 0...120 {
            let t = Double(i) / 60.0
            _ = recorder.recordFrame(
                at: t,
                thermalLevel: .nominal,
                effectiveGestureRateHz: 12.0,
                isFaceTracked: true,
                memoryMBProvider: {
                    providerCallCount += 1
                    return 280.0
                }
            )
        }

        #expect(providerCallCount == 2)
        #expect(recorder.samples.count == 2)
        #expect(abs(recorder.samples[0].fps - 60.0) < 1e-6)
        #expect(abs(recorder.samples[1].fps - 60.0) < 1e-6)
    }

    @Test func pauseAndResumePreventsFakeZeroFpsFromDebugPanelOverlay() {
        var recorder = StabilitySessionRecorder(targetDuration: 2.0, sampleInterval: 1.0)
        recorder.start(at: 10.0, initialThermalLevel: .nominal)

        // 先进入暂停态（模拟打开全屏调试面板暂停 5 秒）
        recorder.pause(at: 10.0)
        #expect(recorder.isPaused)

        var providerCallCount = 0
        for step in 1...5 {
            let sample = recorder.recordFrame(
                at: 10.0 + Double(step),
                thermalLevel: .nominal,
                effectiveGestureRateHz: 12.0,
                isFaceTracked: true,
                memoryMBProvider: {
                    providerCallCount += 1
                    return 250.0
                }
            )
            #expect(sample == nil)
        }
        #expect(providerCallCount == 0)
        #expect(recorder.elapsed == 0.0)

        // 5 秒后恢复，再跑 2 秒 60 Hz
        recorder.resume(at: 15.0)
        #expect(!recorder.isPaused)

        for i in 0...120 {
            let t = 15.0 + Double(i) / 60.0
            _ = recorder.recordFrame(
                at: t,
                thermalLevel: .nominal,
                effectiveGestureRateHz: 12.0,
                isFaceTracked: true,
                memoryMBProvider: {
                    providerCallCount += 1
                    return 250.0
                }
            )
        }

        let report = recorder.finish()
        #expect(providerCallCount == 2)
        #expect(report.sampleCount == 2)
        #expect(abs(report.duration - 2.0) < 1e-6)
        #expect(abs(recorder.samples[0].fps - 60.0) < 1e-6)
        #expect(abs(recorder.samples[1].fps - 60.0) < 1e-6)
        #expect(abs(report.minFps - 60.0) < 1e-6)
        #expect(report.passed)
    }

    @Test func midWindowPauseDropsPartialFramesWithoutPollutingFps() {
        var recorder = StabilitySessionRecorder(targetDuration: 2.0, sampleInterval: 1.0)
        recorder.start(at: 0.0, initialThermalLevel: .nominal)

        var providerCallCount = 0
        // 运行 0.5 秒（30 帧未满 1 秒窗口）
        for i in 0...30 {
            _ = recorder.recordFrame(
                at: Double(i) / 60.0,
                thermalLevel: .nominal,
                effectiveGestureRateHz: 12.0,
                isFaceTracked: true,
                memoryMBProvider: {
                    providerCallCount += 1
                    return 260.0
                }
            )
        }
        #expect(providerCallCount == 0)
        #expect(abs(recorder.elapsed - 0.5) < 1e-6)

        // 窗口中途暂停 5 秒再恢复，跑满 2 秒 60 Hz
        recorder.pause(at: 0.5)
        recorder.resume(at: 5.5)
        for i in 0...120 {
            _ = recorder.recordFrame(
                at: 5.5 + Double(i) / 60.0,
                thermalLevel: .nominal,
                effectiveGestureRateHz: 12.0,
                isFaceTracked: true,
                memoryMBProvider: {
                    providerCallCount += 1
                    return 260.0
                }
            )
        }

        let report = recorder.finish()
        #expect(providerCallCount == 2)
        #expect(report.sampleCount == 2)
        #expect(abs(report.duration - 2.5) < 1e-6)
        #expect(abs(report.avgFps - 60.0) < 1e-6)
        #expect(abs(report.minFps - 60.0) < 1e-6)
        #expect(report.passed)
    }

    @Test func independentFailureCriteriaTriggerAsExpected() {
        // 1) 时长不足 -> passedDuration == false && passed == false
        do {
            var r = StabilitySessionRecorder(targetDuration: 10.0, sampleInterval: 1.0)
            r.start(at: 0.0)
            for i in 0...120 {
                _ = r.recordFrame(at: Double(i) / 60.0, thermalLevel: .nominal, effectiveGestureRateHz: 12, isFaceTracked: true, memoryMBProvider: { 300.0 })
            }
            let rep = r.finish()
            #expect(!rep.passedDuration)
            #expect(rep.passedFps)
            #expect(rep.passedMemory)
            #expect(rep.passedThermalTracking)
            #expect(!rep.passed)
        }

        // 2) 某批窗口掉至 50 fps 使 p10Fps < 55 -> passedFps == false && passed == false
        do {
            var r = StabilitySessionRecorder(targetDuration: 10.0, sampleInterval: 1.0)
            r.start(at: 0.0)
            var t = 0.0
            _ = r.recordFrame(at: t, thermalLevel: .nominal, effectiveGestureRateHz: 12, isFaceTracked: true, memoryMBProvider: { 300.0 })
            for sec in 0..<10 {
                let fps = sec < 2 ? 50 : 60 // 2/10 窗口为 50 fps，nearest-rank p10 为第 1 个 = 50 < 55
                for _ in 0..<fps {
                    t += 1.0 / Double(fps)
                    _ = r.recordFrame(at: t, thermalLevel: .nominal, effectiveGestureRateHz: 12, isFaceTracked: true, memoryMBProvider: { 300.0 })
                }
            }
            let rep = r.finish()
            #expect(rep.passedDuration)
            #expect(abs(rep.p10Fps - 50.0) < 1e-6)
            #expect(!rep.passedFps)
            #expect(rep.passedMemory)
            #expect(rep.passedThermalTracking)
            #expect(!rep.passed)
        }

        // 3) 单次 memoryMB == 1024.0 -> passedMemory == false && passed == false
        do {
            var r = StabilitySessionRecorder(targetDuration: 2.0, sampleInterval: 1.0)
            r.start(at: 0.0)
            for i in 0...120 {
                let t = Double(i) / 60.0
                let mem = i == 120 ? 1024.0 : 300.0
                _ = r.recordFrame(at: t, thermalLevel: .nominal, effectiveGestureRateHz: 12, isFaceTracked: true, memoryMBProvider: { mem })
            }
            let rep = r.finish()
            #expect(rep.passedDuration)
            #expect(rep.passedFps)
            #expect(!rep.passedMemory)
            #expect(!rep.passed)
        }

        // 4) .serious 态发生 1 次中断 -> thermalSessionInterruptionCount == 1 && passedThermalTracking == false
        do {
            var r = StabilitySessionRecorder(targetDuration: 2.0, sampleInterval: 1.0)
            r.start(at: 0.0, initialThermalLevel: .serious)
            for i in 0...120 {
                _ = r.recordFrame(at: Double(i) / 60.0, thermalLevel: .serious, effectiveGestureRateHz: 5, isFaceTracked: true, memoryMBProvider: { 300.0 })
            }
            r.recordSessionInterruption(at: 1.5, thermalLevel: .serious)
            let rep = r.finish()
            #expect(rep.sessionInterruptionCount == 1)
            #expect(rep.thermalSessionInterruptionCount == 1)
            #expect(!rep.passedThermalTracking)
            #expect(!rep.passed)
        }

        // 5) .nominal / .fair 态中断不计入 thermalSessionInterruptionCount
        do {
            var r = StabilitySessionRecorder(targetDuration: 2.0, sampleInterval: 1.0)
            r.start(at: 0.0, initialThermalLevel: .fair)
            for i in 0...120 {
                _ = r.recordFrame(at: Double(i) / 60.0, thermalLevel: .fair, effectiveGestureRateHz: 12, isFaceTracked: true, memoryMBProvider: { 300.0 })
            }
            r.recordSessionInterruption(at: 1.0, thermalLevel: .fair)
            let rep = r.finish()
            #expect(rep.sessionInterruptionCount == 1)
            #expect(rep.thermalSessionInterruptionCount == 0)
            #expect(rep.passedThermalTracking)
            #expect(rep.passed)
        }
    }

    @Test func maxSamplesCapAndEmptyFinishAreSafe() {
        // 空样本 finish()
        var empty = StabilitySessionRecorder(targetDuration: 600.0)
        empty.start(at: 0.0)
        let emptyReport = empty.finish()
        #expect(emptyReport.sampleCount == 0)
        #expect(emptyReport.avgFps == 0.0)
        #expect(emptyReport.p50Fps == 0.0)
        #expect(emptyReport.p10Fps == 0.0)
        #expect(emptyReport.minFps == 0.0)
        #expect(emptyReport.avgMemoryMB == 0.0)
        #expect(emptyReport.maxMemoryMB == 0.0)
        #expect(emptyReport.faceTrackedRatio == 0.0)
        #expect(emptyReport.avgFps.isFinite && emptyReport.maxMemoryMB.isFinite && emptyReport.faceTrackedRatio.isFinite)
        #expect(!emptyReport.passed)

        // maxSamples 上限保护
        var capped = StabilitySessionRecorder(targetDuration: 5.0, sampleInterval: 1.0, maxSamples: 3)
        capped.start(at: 0.0)
        for i in 0...300 {
            _ = capped.recordFrame(at: Double(i) / 60.0, thermalLevel: .nominal, effectiveGestureRateHz: 12, isFaceTracked: true, memoryMBProvider: { 200.0 })
        }
        #expect(capped.samples.count == 3)
        let cappedReport = capped.finish()
        #expect(cappedReport.sampleCount == 3)
    }

    @Test func invalidInputsAndNonFiniteParametersAreDefended() {
        // 非有限构造参数回退安全默认值
        let sanitized = StabilitySessionRecorder(targetDuration: .nan, sampleInterval: .infinity, maxSamples: 0)
        #expect(sanitized.targetDuration == 600.0)
        #expect(sanitized.sampleInterval == 1.0)
        #expect(sanitized.maxSamples == 1)

        let clamped = StabilitySessionRecorder(targetDuration: 0.1, sampleInterval: 0.01, maxSamples: -5)
        #expect(clamped.targetDuration == 1.0)
        #expect(clamped.sampleInterval == 0.2)
        #expect(clamped.maxSamples == 1)

        // 非有限时间戳 start 不启动
        var notStarted = StabilitySessionRecorder()
        notStarted.start(at: .nan)
        #expect(!notStarted.isRunning)
        notStarted.start(at: .infinity)
        #expect(!notStarted.isRunning)

        // 回退时间戳忽略、负/NaN 内存与手势率按 0.0 落盘
        var rec = StabilitySessionRecorder(targetDuration: 1.0, sampleInterval: 1.0)
        rec.start(at: 100.0)
        #expect(rec.recordFrame(at: 100.0, thermalLevel: .nominal, effectiveGestureRateHz: 12, isFaceTracked: true, memoryMBProvider: { 100.0 }) == nil)
        #expect(rec.recordFrame(at: 99.5, thermalLevel: .nominal, effectiveGestureRateHz: 12, isFaceTracked: true, memoryMBProvider: { 100.0 }) == nil)
        #expect(rec.elapsed == 0.0)

        var sample: StabilitySample?
        for i in 1...60 {
            sample = rec.recordFrame(
                at: 100.0 + Double(i) / 60.0,
                thermalLevel: .nominal,
                effectiveGestureRateHz: -5.0,
                isFaceTracked: false,
                memoryMBProvider: { .nan }
            )
        }
        #expect(sample != nil)
        #expect(sample?.memoryMB == 0.0)
        #expect(sample?.effectiveGestureRateHz == 0.0)
        #expect(abs(rec.elapsed - 1.0) < 1e-6)
    }

    @Test func markdownCsvFormatAndProcessMemoryWork() {
        var rec = StabilitySessionRecorder(targetDuration: 2.0, sampleInterval: 1.0)
        rec.start(at: 0.0, initialThermalLevel: .nominal)
        for i in 0...120 {
            let t = Double(i) / 60.0
            let thermal: StabilityThermalLevel = i >= 61 ? .fair : .nominal
            _ = rec.recordFrame(
                at: t,
                thermalLevel: thermal,
                effectiveGestureRateHz: 12.0,
                isFaceTracked: i <= 60,
                memoryMBProvider: { 256.5 }
            )
        }
        let report = rec.finish()

        let csv = report.csv()
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }
        #expect(lines.first == "elapsed_s,fps,memory_mb,thermal_state,gesture_hz,face_tracked")
        #expect(lines.count == report.sampleCount + 1)

        let md = report.summaryMarkdown()
        #expect(md.contains("通过"))
        #expect(md.contains("FPS"))
        #expect(md.contains("内存"))
        #expect(md.contains("热状态"))
        #expect(md.contains("ARSession 中断"))
        #expect(md.contains("人脸追踪"))

        // macOS 下读取当前进程真实物理内存应非 nil 且 > 0
        let bytes = ProcessMemory.physicalFootprintBytes()
        let mb = ProcessMemory.physicalFootprintMB()
        #expect(bytes != nil)
        #expect((bytes ?? 0) > 0)
        #expect(mb != nil)
        #expect((mb ?? 0) > 0)
    }
}
