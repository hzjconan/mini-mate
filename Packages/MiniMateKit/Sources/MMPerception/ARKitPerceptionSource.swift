#if os(iOS)
import ARKit
import AVFoundation
import Foundation
import os
import simd
import MMCore

private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

/// 基于 ARKit 人脸追踪的本地感知源（独立 ARSession，不暴露也不保存摄像头画面）。
public final class ARKitPerceptionSource: PerceptionSource, @unchecked Sendable {
    private struct MutableState: Sendable {
        var continuations: [UUID: AsyncStream<PerceptionFeatures>.Continuation] = [:]
        var session: UncheckedBox<ARSession>?
        var delegateProxy: SessionDelegateProxy?
        var positionFilter: OneEuroFilter3D
        var lookingDetector: LookingAtScreenDetector
        var lastTimestamp: TimeInterval?
        var isInterrupted: Bool = false
        var isRunning: Bool = false
        var gestureRateHz: Double = 12.0
    }

    private let clock: any MMCore.Clock
    private let sessionQueue = DispatchQueue(label: "ai.minimate.perception.arkit", qos: .userInteractive)
    private let state: OSAllocatedUnfairLock<MutableState>

    public init(
        clock: any MMCore.Clock = SystemClock(),
        positionFilter: OneEuroFilter3D = OneEuroFilter3D(minCutoff: 3.5, beta: 2.5, dCutoff: 1.0),
        lookingDetector: LookingAtScreenDetector = LookingAtScreenDetector()
    ) {
        self.clock = clock
        self.state = OSAllocatedUnfairLock(initialState: MutableState(
            positionFilter: positionFilter,
            lookingDetector: lookingDetector
        ))
    }

    public var features: AsyncStream<PerceptionFeatures> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(2)) { continuation in
            state.withLock { $0.continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    /// 供后续 US4 读取当前已夹紧的手势帧率上限（0...15 Hz，默认 12）。
    public var gestureRateHz: Double {
        state.withLock { $0.gestureRateHz }
    }

    public func setGestureRate(_ hz: Double) {
        let clamped = hz.isFinite ? min(max(hz, 0), 15) : 0
        state.withLock { $0.gestureRateHz = clamped }
    }

    public func start() async throws {
        guard ARFaceTrackingConfiguration.isSupported else {
            throw PerceptionError.faceTrackingUnsupported
        }

        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authStatus {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                throw PerceptionError.cameraPermissionDenied
            }
        case .denied, .restricted:
            throw PerceptionError.cameraPermissionDenied
        @unknown default:
            throw PerceptionError.cameraPermissionDenied
        }

        guard !Task.isCancelled else { return }

        let session = ARSession()
        let boxedSession = UncheckedBox(value: session)
        let proxy = SessionDelegateProxy(owner: self)
        session.delegate = proxy
        session.delegateQueue = sessionQueue

        let oldSession = state.withLock { s -> UncheckedBox<ARSession>? in
            let prev = s.session
            s.session = boxedSession
            s.delegateProxy = proxy
            s.positionFilter.reset()
            s.lookingDetector.reset()
            s.lastTimestamp = nil
            s.isInterrupted = false
            s.isRunning = true
            return prev
        }
        oldSession?.value.delegate = nil
        oldSession?.value.pause()

        let configuration = Self.makeConfiguration()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    public func stop() {
        let (session, continuations) = state.withLock { s -> (UncheckedBox<ARSession>?, [AsyncStream<PerceptionFeatures>.Continuation]) in
            let currentSession = s.session
            s.session = nil
            s.delegateProxy = nil
            s.positionFilter.reset()
            s.lookingDetector.reset()
            s.lastTimestamp = nil
            s.isInterrupted = false
            s.isRunning = false
            let active = Array(s.continuations.values)
            s.continuations.removeAll()
            return (currentSession, active)
        }
        session?.value.delegate = nil
        session?.value.pause()
        for continuation in continuations {
            continuation.finish()
        }
    }

    fileprivate func handleFrame(_ frame: ARFrame, from session: ARSession) {
        let boxedSession = UncheckedBox(value: session)
        let uptime = ProcessInfo.processInfo.systemUptime
        let age = min(max(uptime - frame.timestamp, 0), 0.5)
        let nowRef = clock.now.timeIntervalSinceReferenceDate
        let computedTimestamp = nowRef - age

        // 锁外提取纯值类型，避免锁临界区过长并满足 Swift 6 Sendable 约束
        let extractedFace: (rawPos: SIMD3<Float>, gazeAngle: Float?, blendShapes: [String: Float])?
        if let faceAnchor = frame.anchors
            .compactMap({ $0 as? ARFaceAnchor })
            .first(where: { $0.isTracked })
        {
            // 竖屏相机视角坐标 → 规范面向屏幕坐标（+X 屏幕右，+Y 上，+Z 离屏正米数）
            // 实机验证：portrait viewMatrix 的 +X 已朝向屏幕右侧；补温和 +0.03 m 偏置避免仰头过猛
            let viewMatrix = frame.camera.viewMatrix(for: .portrait)
            let faceWorldPos = SIMD4<Float>(
                faceAnchor.transform.columns.3.x,
                faceAnchor.transform.columns.3.y,
                faceAnchor.transform.columns.3.z,
                1.0
            )
            let faceViewPos = viewMatrix * faceWorldPos
            let rawPos = SIMD3<Float>(faceViewPos.x, faceViewPos.y + 0.03, -faceViewPos.z)

            // 在 ARFaceAnchor 局部空间计算视线与相机方向夹角
            let camInFace4 = (simd_inverse(faceAnchor.transform) * frame.camera.transform).columns.3
            let cameraPosInFace = SIMD3<Float>(camInFace4.x, camInFace4.y, camInFace4.z)
            let gazeAngle = LookingAtScreenDetector.gazeAngleRadians(
                lookAtPointInFaceSpace: faceAnchor.lookAtPoint,
                cameraPositionInFaceSpace: cameraPosInFace
            )

            var blendShapes: [String: Float] = [:]
            blendShapes.reserveCapacity(faceAnchor.blendShapes.count)
            for (location, number) in faceAnchor.blendShapes {
                blendShapes[location.rawValue] = number.floatValue
            }

            extractedFace = (rawPos, gazeAngle, blendShapes)
        } else {
            extractedFace = nil
        }

        let (feature, continuations): (PerceptionFeatures?, [AsyncStream<PerceptionFeatures>.Continuation]) = state.withLock { s in
            guard s.isRunning, !s.isInterrupted, s.session?.value === boxedSession.value else {
                return (nil, [])
            }

            let timestamp: TimeInterval
            if let last = s.lastTimestamp {
                timestamp = max(computedTimestamp, last + 1e-5)
            } else {
                timestamp = computedTimestamp
            }
            s.lastTimestamp = timestamp

            let active = Array(s.continuations.values)
            guard let face = extractedFace else {
                s.positionFilter.reset()
                _ = s.lookingDetector.update(isFaceTracked: false, gazeAngleRadians: nil, at: timestamp)
                let lost = PerceptionFeatures(
                    timestamp: timestamp,
                    isFaceTracked: false,
                    rawBlendShapes: [:],
                    signals: FaceSignals(),
                    facePosition: nil,
                    isLookingAtScreen: false,
                    gesture: nil
                )
                return (lost, active)
            }

            let smoothedPos = s.positionFilter.filter(face.rawPos, at: timestamp)
            let isLooking = s.lookingDetector.update(
                isFaceTracked: true,
                gazeAngleRadians: face.gazeAngle,
                at: timestamp
            )

            let tracked = PerceptionFeatures(
                timestamp: timestamp,
                isFaceTracked: true,
                rawBlendShapes: face.blendShapes,
                signals: FaceSignals(),
                facePosition: smoothedPos,
                isLookingAtScreen: isLooking,
                gesture: nil
            )
            return (tracked, active)
        }

        if let feature {
            for continuation in continuations {
                continuation.yield(feature)
            }
        }
    }

    fileprivate func handleSessionWasInterrupted(_ session: ARSession) {
        let boxed = UncheckedBox(value: session)
        state.withLock { s in
            guard s.isRunning, s.session?.value === boxed.value else { return }
            s.isInterrupted = true
            s.positionFilter.reset()
            s.lookingDetector.reset()
        }
    }

    fileprivate func handleSessionInterruptionEnded(_ session: ARSession) {
        let boxed = UncheckedBox(value: session)
        let shouldResume = state.withLock { s -> Bool in
            guard s.isRunning, s.session?.value === boxed.value else { return false }
            s.isInterrupted = false
            s.positionFilter.reset()
            s.lookingDetector.reset()
            return true
        }
        if shouldResume {
            session.run(Self.makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        }
    }

    private static func makeConfiguration() -> ARFaceTrackingConfiguration {
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        config.maximumNumberOfTrackedFaces = 1
        return config
    }
}

private final class SessionDelegateProxy: NSObject, ARSessionDelegate, @unchecked Sendable {
    private weak var owner: ARKitPerceptionSource?

    init(owner: ARKitPerceptionSource) {
        self.owner = owner
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        owner?.handleFrame(frame, from: session)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        owner?.handleSessionWasInterrupted(session)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        owner?.handleSessionInterruptionEnded(session)
    }
}
#endif
