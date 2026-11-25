import Foundation
import Testing
import simd
import MMPerception

@Suite("LookingAtScreenDetector")
struct LookingAtScreenTests {

    @Test("gazeAngleRadians 精确计算同向/垂直/反向与典型 15°/25° 夹角")
    func gazeAngleComputationIsAccurate() throws {
        let cam = SIMD3<Float>(0, 0, 1)

        let zero = try #require(LookingAtScreenDetector.gazeAngleRadians(
            lookAtPointInFaceSpace: SIMD3<Float>(0, 0, 2),
            cameraPositionInFaceSpace: cam
        ))
        #expect(abs(zero - 0) < 1e-4)

        let rightAngle = try #require(LookingAtScreenDetector.gazeAngleRadians(
            lookAtPointInFaceSpace: SIMD3<Float>(1, 0, 0),
            cameraPositionInFaceSpace: cam
        ))
        #expect(abs(rightAngle - .pi / 2) < 1e-4)

        let opposite = try #require(LookingAtScreenDetector.gazeAngleRadians(
            lookAtPointInFaceSpace: SIMD3<Float>(0, 0, -1),
            cameraPositionInFaceSpace: cam
        ))
        #expect(abs(opposite - .pi) < 1e-4)

        let deg15: Float = 15 * .pi / 180
        let angle15 = try #require(LookingAtScreenDetector.gazeAngleRadians(
            lookAtPointInFaceSpace: SIMD3<Float>(sin(deg15), 0, cos(deg15)),
            cameraPositionInFaceSpace: cam
        ))
        #expect(abs(angle15 - deg15) < 1e-4)

        let deg25: Float = 25 * .pi / 180
        let angle25 = try #require(LookingAtScreenDetector.gazeAngleRadians(
            lookAtPointInFaceSpace: SIMD3<Float>(0, sin(deg25), cos(deg25)),
            cameraPositionInFaceSpace: cam
        ))
        #expect(abs(angle25 - deg25) < 1e-4)
    }

    @Test("零向量或非有限向量返回 nil")
    func invalidVectorsReturnNil() {
        #expect(LookingAtScreenDetector.gazeAngleRadians(
            lookAtPointInFaceSpace: .zero,
            cameraPositionInFaceSpace: SIMD3<Float>(0, 0, 1)
        ) == nil)

        #expect(LookingAtScreenDetector.gazeAngleRadians(
            lookAtPointInFaceSpace: SIMD3<Float>(0, 0, 1),
            cameraPositionInFaceSpace: SIMD3<Float>(1e-7, 0, 0)
        ) == nil)

        #expect(LookingAtScreenDetector.gazeAngleRadians(
            lookAtPointInFaceSpace: SIMD3<Float>(.nan, 0, 1),
            cameraPositionInFaceSpace: SIMD3<Float>(0, 0, 1)
        ) == nil)
    }

    @Test("19.9° 持续 199ms 为 false、200ms 翻为 true；20.0° 精确边界保持 false")
    func thresholdAndDurationBoundaries() {
        var detector = LookingAtScreenDetector(maxAngleDegrees: 20, minDuration: 0.2)
        let angle19_9: Float = 19.9 * .pi / 180
        let angle20_0: Float = 20.0 * .pi / 180

        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle19_9, at: 1.000) == false)
        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle19_9, at: 1.199) == false)
        #expect(detector.isLookingAtScreen == false)

        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle19_9, at: 1.200) == true)
        #expect(detector.isLookingAtScreen == true)

        // 恰好 20.0°（非严格小于）立即变为 false，且持续也不翻 true
        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle20_0, at: 1.250) == false)
        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle20_0, at: 1.600) == false)
        #expect(detector.isLookingAtScreen == false)
    }

    @Test("人脸丢失、夹角为 nil 或中断时立即清零，重新注视需再满 200ms")
    func faceLostOrNilAngleResetsImmediately() {
        var detector = LookingAtScreenDetector(maxAngleDegrees: 20, minDuration: 0.2)
        let angle10: Float = 10 * .pi / 180

        _ = detector.update(isFaceTracked: true, gazeAngleRadians: angle10, at: 0.0)
        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle10, at: 0.2) == true)

        // 人脸丢失立即复位
        #expect(detector.update(isFaceTracked: false, gazeAngleRadians: angle10, at: 0.25) == false)
        #expect(detector.isLookingAtScreen == false)

        // 重新注视需再满 200ms
        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle10, at: 0.30) == false)
        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle10, at: 0.49) == false)
        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle10, at: 0.50) == true)

        // nil 夹角立即复位
        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: nil, at: 0.55) == false)
        #expect(detector.isLookingAtScreen == false)

        // 时间戳倒退复位计时
        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle10, at: 1.00) == false)
        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle10, at: 0.90) == false)
        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle10, at: 1.05) == false)
        #expect(detector.update(isFaceTracked: true, gazeAngleRadians: angle10, at: 1.10) == true)
    }
}
