import Foundation
import Testing
import simd
import MMPerception

@Suite("OneEuroFilter")
struct OneEuroFilterTests {

    @Test("静止常值叠加噪声时输出标准差严格小于输入 40% 且末段收敛")
    func stationarySignalWithNoiseConvergesAndDampsVariance() {
        var filter = OneEuroFilter(minCutoff: 1.0, beta: 0.0, dCutoff: 1.0)
        let target = 0.5
        let dt = 1.0 / 60.0
        let totalFrames = 120 // 2 s @ 60 Hz

        var inputs: [Double] = []
        var outputs: [Double] = []
        inputs.reserveCapacity(totalFrames)
        outputs.reserveCapacity(totalFrames)

        for i in 0..<totalFrames {
            let t = Double(i) * dt
            let noise = 0.05 * sin(2.0 * .pi * 12.0 * t) + 0.02 * (i.isMultiple(of: 2) ? 1.0 : -1.0)
            let sample = target + noise
            inputs.append(sample)
            outputs.append(filter.filter(sample, at: t))
        }

        // 取后半段（稳定期）计算标准差与收敛误差
        let steadyIn = Array(inputs.dropFirst(30))
        let steadyOut = Array(outputs.dropFirst(30))
        let inStd = standardDeviation(steadyIn)
        let outStd = standardDeviation(steadyOut)

        #expect(outStd < inStd * 0.4)
        for value in outputs.suffix(30) {
            #expect(abs(value - target) <= 0.02)
        }
    }

    @Test("阶跃输入时高 beta 在 100ms 内达到 90% 且快于 beta == 0")
    func stepResponseIsFastWithHighBeta() {
        var lowBeta = OneEuroFilter(minCutoff: 1.0, beta: 0.0, dCutoff: 1.0)
        var highBeta = OneEuroFilter(minCutoff: 1.0, beta: 1.5, dCutoff: 1.0)
        let dt = 1.0 / 60.0

        // 稳定在 0.0（10 帧）
        for i in 0..<10 {
            let t = Double(i) * dt
            _ = lowBeta.filter(0.0, at: t)
            _ = highBeta.filter(0.0, at: t)
        }

        let stepStartTime = 10.0 * dt
        var lowBetaReach90Time: TimeInterval?
        var highBetaReach90Time: TimeInterval?

        for i in 10..<130 {
            let t = Double(i) * dt
            let lowOut = lowBeta.filter(1.0, at: t)
            let highOut = highBeta.filter(1.0, at: t)

            if lowBetaReach90Time == nil, lowOut >= 0.9 {
                lowBetaReach90Time = t - stepStartTime
            }
            if highBetaReach90Time == nil, highOut >= 0.9 {
                highBetaReach90Time = t - stepStartTime
            }
        }

        let highLatency = try! #require(highBetaReach90Time)
        let lowLatency = try! #require(lowBetaReach90Time)
        #expect(highLatency < 0.100)
        #expect(highLatency < lowLatency)
    }

    @Test("无效参数夹紧与非法时间戳或非有限值不污染状态")
    func invalidParametersAndInputsAreHandledSafely() {
        var filter = OneEuroFilter(minCutoff: -2.0, beta: -1.0, dCutoff: 0.0)
        #expect(filter.minCutoff >= 1e-4)
        #expect(filter.beta >= 0)
        #expect(filter.dCutoff >= 1e-4)

        let nanFilter = OneEuroFilter(minCutoff: .nan, beta: .infinity, dCutoff: -.infinity)
        #expect(nanFilter.minCutoff == 1.0)
        #expect(nanFilter.beta == 0.0)
        #expect(nanFilter.dCutoff == 1.0)

        // 无历史时传入 NaN 返回 0 且不污染状态
        #expect(filter.filter(.nan, at: 0.0) == 0.0)
        #expect(filter.filter(1.0, at: .infinity) == 0.0)

        // 首帧正常
        let first = filter.filter(2.0, at: 1.0)
        #expect(first == 2.0)

        // 重复或倒退时间戳返回上一有效值
        #expect(filter.filter(10.0, at: 1.0) == 2.0)
        #expect(filter.filter(10.0, at: 0.5) == 2.0)

        // 后续 NaN / Inf 返回上一有效值且不污染状态
        #expect(filter.filter(.nan, at: 1.1) == 2.0)
        #expect(filter.filter(.infinity, at: 1.2) == 2.0)
        let next = filter.filter(3.0, at: 1.3)
        #expect(next.isFinite)
        #expect(next > 2.0 && next <= 3.0)

        // reset 后首帧原样返回新值
        filter.reset()
        #expect(filter.filter(-5.0, at: 0.2) == -5.0)
    }

    @Test("OneEuroFilter3D 三轴独立收敛且防御非有限值")
    func filter3DConvergesIndependentlyAndGuardsNonFinite() {
        var filter3D = OneEuroFilter3D(minCutoff: 1.5, beta: 0.4, dCutoff: 1.0)
        let target = SIMD3<Float>(0.2, -0.15, 0.55)
        let dt = 1.0 / 60.0

        var last = SIMD3<Float>.zero
        for i in 0..<120 {
            let t = Double(i) * dt
            let jitter = Float(0.02 * sin(2.0 * .pi * 10.0 * t))
            let sample = target + SIMD3<Float>(jitter, -jitter, jitter * 0.5)
            last = filter3D.filter(sample, at: t)
        }

        #expect(abs(last.x - target.x) < 0.015)
        #expect(abs(last.y - target.y) < 0.015)
        #expect(abs(last.z - target.z) < 0.015)

        // 非有限分量返回上一有效值且不污染状态
        let guarded = filter3D.filter(SIMD3<Float>(.nan, 0, 0), at: 2.1)
        #expect(guarded == last)

        // reset 后首帧原样返回
        filter3D.reset()
        let fresh = SIMD3<Float>(-0.3, 0.4, 0.7)
        #expect(filter3D.filter(fresh, at: 0.0) == fresh)
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }
}
