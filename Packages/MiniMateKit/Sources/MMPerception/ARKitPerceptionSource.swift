#if os(iOS)
import ARKit
import AVFoundation
import Foundation
import ImageIO
import os
import simd
import Vision
import MMCore

private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

/// 基于 ARKit 人脸追踪与 Vision 手部检测的本地感知源（独立 ARSession，不暴露也不保存摄像头画面）。
public final class ARKitPerceptionSource: PerceptionSource, @unchecked Sendable {
    private struct SubscriberEntry: Sendable {
        let continuation: AsyncStream<PerceptionFeatures>.Continuation
        var recoveredGesture: GestureEvent?
    }

    private struct MutableState: Sendable {
        var continuations: [UUID: SubscriberEntry] = [:]
        var session: UncheckedBox<ARSession>?
        var delegateProxy: SessionDelegateProxy?
        var positionFilter: OneEuroFilter3D
        var lookingDetector: LookingAtScreenDetector
        var signalDeriver: FaceSignalDeriver
        var gestureClassifier: HandGestureClassifier
        var lastTimestamp: TimeInterval?
        var isInterrupted: Bool = false
        var isRunning: Bool = false
        var gestureRateHz: Double = 12.0
        var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
        var thermalObserver: UncheckedBox<NSObjectProtocol>?
        var runGeneration: UInt64 = 0
        var gestureResetGeneration: UInt64 = 0
        var isVisionInFlight: Bool = false
        var lastVisionDispatchedAt: TimeInterval?
        var pendingGesture: GestureEvent?
        var lastDetectedHandCount: Int = 0
    }

    private let clock: any MMCore.Clock
    private let handPoseOrientation: CGImagePropertyOrientation
    private let sessionQueue = DispatchQueue(label: "ai.minimate.perception.arkit", qos: .userInteractive)
    private let gestureQueue = DispatchQueue(label: "ai.minimate.perception.gesture", qos: .userInitiated)
    private let state: OSAllocatedUnfairLock<MutableState>

    public init(
        clock: any MMCore.Clock = SystemClock(),
        positionFilter: OneEuroFilter3D = OneEuroFilter3D(minCutoff: 3.5, beta: 2.5, dCutoff: 1.0),
        lookingDetector: LookingAtScreenDetector = LookingAtScreenDetector(),
        signalDeriver: FaceSignalDeriver = FaceSignalDeriver(),
        gestureClassifier: HandGestureClassifier = HandGestureClassifier(),
        handPoseOrientation: CGImagePropertyOrientation = .leftMirrored
    ) {
        self.clock = clock
        self.handPoseOrientation = handPoseOrientation
        self.state = OSAllocatedUnfairLock(initialState: MutableState(
            positionFilter: positionFilter,
            lookingDetector: lookingDetector,
            signalDeriver: signalDeriver,
            gestureClassifier: gestureClassifier
        ))
    }

    deinit {
        let observer = state.withLock { s -> UncheckedBox<NSObjectProtocol>? in
            let obs = s.thermalObserver
            s.thermalObserver = nil
            return obs
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer.value)
        }
    }

    public var features: AsyncStream<PerceptionFeatures> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            state.withLock { $0.continuations[id] = SubscriberEntry(continuation: continuation, recoveredGesture: nil) }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    /// 当前已夹紧的外部配置手势帧率上限（0...15 Hz，默认 12）。
    public var gestureRateHz: Double {
        state.withLock { $0.gestureRateHz }
    }

    /// 当前结合热状态后实际生效的手势检测频率（0...15 Hz）。
    public var effectiveGestureRateHz: Double {
        state.withLock {
            ThermalGesturePolicy.effectiveRate(configuredHz: $0.gestureRateHz, thermalState: $0.thermalState)
        }
    }

    /// 最近一次 Vision 手部检测识别到的手数量（0...2）。
    public var lastDetectedHandCount: Int {
        state.withLock { $0.lastDetectedHandCount }
    }

    /// 当前缓存的系统热状态。
    public var currentThermalState: ProcessInfo.ThermalState {
        state.withLock { $0.thermalState }
    }

    /// 最近一次有手帧的纯数值诊断快照（供真机调试面板排查阈值，无图像数据）。
    public var lastGestureDiagnostics: HandGestureClassifier.DebugSnapshot {
        state.withLock { $0.gestureClassifier.lastDiagnostics }
    }

    public func setGestureRate(_ hz: Double) {
        let clamped = hz.isFinite ? min(max(hz, 0), 15) : 0
        state.withLock { s in
            s.gestureRateHz = clamped
            if ThermalGesturePolicy.effectiveRate(configuredHz: s.gestureRateHz, thermalState: s.thermalState) == 0 {
                s.gestureResetGeneration &+= 1
                s.gestureClassifier.reset()
                s.lastDetectedHandCount = 0
                s.pendingGesture = nil
                for id in s.continuations.keys {
                    s.continuations[id]?.recoveredGesture = nil
                }
            }
        }
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

        let newObserverToken = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            let newState = ProcessInfo.processInfo.thermalState
            self.state.withLock { s in
                s.thermalState = newState
                if ThermalGesturePolicy.effectiveRate(configuredHz: s.gestureRateHz, thermalState: newState) == 0 {
                    s.gestureResetGeneration &+= 1
                    s.gestureClassifier.reset()
                    s.lastDetectedHandCount = 0
                    s.pendingGesture = nil
                    for id in s.continuations.keys {
                        s.continuations[id]?.recoveredGesture = nil
                    }
                }
            }
        }
        let boxedObserver = UncheckedBox(value: newObserverToken)
        let currentThermal = ProcessInfo.processInfo.thermalState

        let (oldSession, oldObserver) = state.withLock { s -> (UncheckedBox<ARSession>?, UncheckedBox<NSObjectProtocol>?) in
            let prevSession = s.session
            let prevObserver = s.thermalObserver
            s.session = boxedSession
            s.delegateProxy = proxy
            s.thermalObserver = boxedObserver
            s.thermalState = currentThermal
            s.runGeneration &+= 1
            s.gestureResetGeneration &+= 1
            s.positionFilter.reset()
            s.lookingDetector.reset()
            s.signalDeriver.reset()
            s.gestureClassifier.reset()
            s.lastTimestamp = nil
            s.isInterrupted = false
            s.isRunning = true
            s.isVisionInFlight = false
            s.lastVisionDispatchedAt = nil
            s.pendingGesture = nil
            s.lastDetectedHandCount = 0
            for id in s.continuations.keys {
                s.continuations[id]?.recoveredGesture = nil
            }
            return (prevSession, prevObserver)
        }
        if let oldObserver {
            NotificationCenter.default.removeObserver(oldObserver.value)
        }
        oldSession?.value.delegate = nil
        oldSession?.value.pause()

        let configuration = Self.makeConfiguration()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    public func stop() {
        let (session, observer, continuations) = state.withLock { s -> (UncheckedBox<ARSession>?, UncheckedBox<NSObjectProtocol>?, [AsyncStream<PerceptionFeatures>.Continuation]) in
            let currentSession = s.session
            let currentObserver = s.thermalObserver
            s.session = nil
            s.delegateProxy = nil
            s.thermalObserver = nil
            s.runGeneration &+= 1
            s.gestureResetGeneration &+= 1
            s.positionFilter.reset()
            s.lookingDetector.reset()
            s.signalDeriver.reset()
            s.gestureClassifier.reset()
            s.lastTimestamp = nil
            s.isInterrupted = false
            s.isRunning = false
            s.isVisionInFlight = false
            s.lastVisionDispatchedAt = nil
            s.pendingGesture = nil
            s.lastDetectedHandCount = 0
            let active = s.continuations.values.map(\.continuation)
            s.continuations.removeAll()
            return (currentSession, currentObserver, active)
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer.value)
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
                blendShapes[Self.canonicalName(for: location)] = number.floatValue
            }

            extractedFace = (rawPos, gazeAngle, blendShapes)
        } else {
            extractedFace = nil
        }

        let (feature, subscribers, frameGenerations, visionDispatch): (
            PerceptionFeatures?,
            [(id: UUID, continuation: AsyncStream<PerceptionFeatures>.Continuation, recoveredGesture: GestureEvent?)],
            (run: UInt64, gestureReset: UInt64)?,
            (timestamp: TimeInterval, generation: UInt64, gestureResetGeneration: UInt64)?
        ) = state.withLock { s in
            guard s.isRunning, !s.isInterrupted, s.session?.value === boxedSession.value else {
                return (nil, [], nil, nil)
            }

            let timestamp: TimeInterval
            if let last = s.lastTimestamp {
                timestamp = max(computedTimestamp, last + 1e-5)
            } else {
                timestamp = computedTimestamp
            }
            s.lastTimestamp = timestamp
            let currentGens = (run: s.runGeneration, gestureReset: s.gestureResetGeneration)

            // 1. 统一消费待发射手势（无论人脸是否追踪，避免比心遮脸漏触发）
            let gestureToEmit = s.pendingGesture
            s.pendingGesture = nil

            // 2. 判定是否按有效频率调度单飞行 Vision 手部检测
            let effectiveRate = ThermalGesturePolicy.effectiveRate(
                configuredHz: s.gestureRateHz,
                thermalState: s.thermalState
            )
            var dispatchInfo: (TimeInterval, UInt64, UInt64)? = nil
            if effectiveRate > 0, !s.isVisionInFlight {
                let minInterval = 1.0 / effectiveRate
                if s.lastVisionDispatchedAt == nil || timestamp - s.lastVisionDispatchedAt! + 1e-9 >= minInterval {
                    s.isVisionInFlight = true
                    s.lastVisionDispatchedAt = timestamp
                    dispatchInfo = (timestamp, s.runGeneration, s.gestureResetGeneration)
                }
            }

            var active: [(UUID, AsyncStream<PerceptionFeatures>.Continuation, GestureEvent?)] = []
            active.reserveCapacity(s.continuations.count)
            for (id, entry) in s.continuations {
                let recovered = entry.recoveredGesture
                if recovered != nil {
                    s.continuations[id]?.recoveredGesture = nil
                }
                active.append((id, entry.continuation, recovered))
            }

            guard let face = extractedFace else {
                s.positionFilter.reset()
                s.signalDeriver.reset()
                _ = s.lookingDetector.update(isFaceTracked: false, gazeAngleRadians: nil, at: timestamp)
                let lost = PerceptionFeatures(
                    timestamp: timestamp,
                    isFaceTracked: false,
                    rawBlendShapes: [:],
                    signals: FaceSignals(),
                    facePosition: nil,
                    isLookingAtScreen: false,
                    gesture: gestureToEmit
                )
                return (lost, active, currentGens, dispatchInfo)
            }

            let smoothedPos = s.positionFilter.filter(face.rawPos, at: timestamp)
            let isLooking = s.lookingDetector.update(
                isFaceTracked: true,
                gazeAngleRadians: face.gazeAngle,
                at: timestamp
            )
            let signals = s.signalDeriver.update(blendShapes: face.blendShapes, at: timestamp)

            let tracked = PerceptionFeatures(
                timestamp: timestamp,
                isFaceTracked: true,
                rawBlendShapes: face.blendShapes,
                signals: signals,
                facePosition: smoothedPos,
                isLookingAtScreen: isLooking,
                gesture: gestureToEmit
            )
            return (tracked, active, currentGens, dispatchInfo)
        }

        // 仅提取 CVPixelBuffer 投递至独立串行 gestureQueue，避免跨队列持有 ARFrame 耗尽帧缓冲池
        if let dispatch = visionDispatch {
            let boxedPixelBuffer = UncheckedBox(value: frame.capturedImage)
            let orientation = handPoseOrientation
            gestureQueue.async { [weak self] in
                guard let self else { return }
                defer {
                    self.state.withLock { s in
                        if s.runGeneration == dispatch.generation {
                            s.isVisionInFlight = false
                        }
                    }
                }

                let request = VNDetectHumanHandPoseRequest()
                request.maximumHandCount = 2
                let handler = VNImageRequestHandler(
                    cvPixelBuffer: boxedPixelBuffer.value,
                    orientation: orientation,
                    options: [:]
                )
                do {
                    try handler.perform([request])
                } catch {
                    return
                }

                let observations = request.results ?? []
                let handFrames = Self.extractHandFrames(from: observations)

                self.state.withLock { s in
                    guard s.isRunning,
                          !s.isInterrupted,
                          s.runGeneration == dispatch.generation,
                          s.gestureResetGeneration == dispatch.gestureResetGeneration,
                          ThermalGesturePolicy.effectiveRate(configuredHz: s.gestureRateHz, thermalState: s.thermalState) > 0
                    else {
                        return
                    }
                    s.lastDetectedHandCount = handFrames.count
                    if let event = s.gestureClassifier.update(hands: handFrames, at: dispatch.timestamp) {
                        s.pendingGesture = event
                    }
                }
            }
        }

        if let feature, let gens = frameGenerations {
            var droppedGestures: [(UUID, GestureEvent)] = []
            for sub in subscribers {
                let frameToYield: PerceptionFeatures
                if feature.gesture == nil,
                   let recovered = sub.recoveredGesture,
                   feature.timestamp - recovered.timestamp <= 1.0 {
                    frameToYield = PerceptionFeatures(
                        timestamp: feature.timestamp,
                        isFaceTracked: feature.isFaceTracked,
                        rawBlendShapes: feature.rawBlendShapes,
                        signals: feature.signals,
                        facePosition: feature.facePosition,
                        isLookingAtScreen: feature.isLookingAtScreen,
                        gesture: recovered
                    )
                } else {
                    frameToYield = feature
                }
                if case .dropped(let dropped) = sub.continuation.yield(frameToYield),
                   let lostGesture = dropped.gesture {
                    droppedGestures.append((sub.id, lostGesture))
                }
            }
            if !droppedGestures.isEmpty {
                let recoveredList = droppedGestures
                state.withLock { s in
                    guard s.isRunning,
                          !s.isInterrupted,
                          s.runGeneration == gens.run,
                          s.gestureResetGeneration == gens.gestureReset,
                          ThermalGesturePolicy.effectiveRate(configuredHz: s.gestureRateHz, thermalState: s.thermalState) > 0
                    else {
                        return
                    }
                    for (id, gesture) in recoveredList {
                        if s.continuations[id] != nil {
                            s.continuations[id]?.recoveredGesture = gesture
                        }
                    }
                }
            }
        }
    }

    fileprivate func handleSessionWasInterrupted(_ session: ARSession) {
        let boxed = UncheckedBox(value: session)
        state.withLock { s in
            guard s.isRunning, s.session?.value === boxed.value else { return }
            s.isInterrupted = true
            s.runGeneration &+= 1
            s.gestureResetGeneration &+= 1
            s.positionFilter.reset()
            s.lookingDetector.reset()
            s.signalDeriver.reset()
            s.gestureClassifier.reset()
            s.isVisionInFlight = false
            s.lastVisionDispatchedAt = nil
            s.pendingGesture = nil
            s.lastDetectedHandCount = 0
            for id in s.continuations.keys {
                s.continuations[id]?.recoveredGesture = nil
            }
        }
    }

    fileprivate func handleSessionInterruptionEnded(_ session: ARSession) {
        let boxed = UncheckedBox(value: session)
        let shouldResume = state.withLock { s -> Bool in
            guard s.isRunning, s.session?.value === boxed.value else { return false }
            s.isInterrupted = false
            s.runGeneration &+= 1
            s.gestureResetGeneration &+= 1
            s.positionFilter.reset()
            s.lookingDetector.reset()
            s.signalDeriver.reset()
            s.gestureClassifier.reset()
            s.isVisionInFlight = false
            s.lastVisionDispatchedAt = nil
            s.pendingGesture = nil
            s.lastDetectedHandCount = 0
            for id in s.continuations.keys {
                s.continuations[id]?.recoveredGesture = nil
            }
            return true
        }
        if shouldResume {
            session.run(Self.makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
        }
    }

    private static let visionJointMapping: [(VNHumanHandPoseObservation.JointName, HandJointName)] = [
        (.wrist, .wrist),
        (.thumbCMC, .thumbCMC),
        (.thumbMP, .thumbMP),
        (.thumbIP, .thumbIP),
        (.thumbTip, .thumbTip),
        (.indexMCP, .indexMCP),
        (.indexPIP, .indexPIP),
        (.indexDIP, .indexDIP),
        (.indexTip, .indexTip),
        (.middleMCP, .middleMCP),
        (.middlePIP, .middlePIP),
        (.middleDIP, .middleDIP),
        (.middleTip, .middleTip),
        (.ringMCP, .ringMCP),
        (.ringPIP, .ringPIP),
        (.ringDIP, .ringDIP),
        (.ringTip, .ringTip),
        (.littleMCP, .littleMCP),
        (.littlePIP, .littlePIP),
        (.littleDIP, .littleDIP),
        (.littleTip, .littleTip),
    ]

    private static func extractHandFrames(from observations: [VNHumanHandPoseObservation]) -> [HandPoseFrame] {
        var frames: [HandPoseFrame] = []
        frames.reserveCapacity(observations.count)
        for obs in observations {
            guard let recognized = try? obs.recognizedPoints(.all) else { continue }
            var joints: [HandJointName: HandJointPoint] = [:]
            joints.reserveCapacity(visionJointMapping.count)
            for (visionJoint, handJoint) in visionJointMapping {
                guard let pt = recognized[visionJoint] else { continue }
                joints[handJoint] = HandJointPoint(
                    x: Float(pt.location.x),
                    y: Float(pt.location.y),
                    confidence: Float(pt.confidence)
                )
            }
            frames.append(HandPoseFrame(joints: joints))
        }
        return frames
    }

    private static func makeConfiguration() -> ARFaceTrackingConfiguration {
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        config.maximumNumberOfTrackedFaces = 1
        return config
    }

    /// Apple ARKit 的 `BlendShapeLocation.rawValue` 对左右对称键使用 `_L`/`_R` 后缀（如 `mouthSmile_L`），
    /// 统一规范化为标准 ARKit camelCase 名称（如 `mouthSmileLeft`），与 `FaceSignalDeriver` 及 `BlendShapeIndex` 逐字对齐。
    private static let canonicalNamesByLocation: [ARFaceAnchor.BlendShapeLocation: String] = [
        .browDownLeft: "browDownLeft",
        .browDownRight: "browDownRight",
        .browInnerUp: "browInnerUp",
        .browOuterUpLeft: "browOuterUpLeft",
        .browOuterUpRight: "browOuterUpRight",
        .cheekPuff: "cheekPuff",
        .cheekSquintLeft: "cheekSquintLeft",
        .cheekSquintRight: "cheekSquintRight",
        .eyeBlinkLeft: "eyeBlinkLeft",
        .eyeBlinkRight: "eyeBlinkRight",
        .eyeLookDownLeft: "eyeLookDownLeft",
        .eyeLookDownRight: "eyeLookDownRight",
        .eyeLookInLeft: "eyeLookInLeft",
        .eyeLookInRight: "eyeLookInRight",
        .eyeLookOutLeft: "eyeLookOutLeft",
        .eyeLookOutRight: "eyeLookOutRight",
        .eyeLookUpLeft: "eyeLookUpLeft",
        .eyeLookUpRight: "eyeLookUpRight",
        .eyeSquintLeft: "eyeSquintLeft",
        .eyeSquintRight: "eyeSquintRight",
        .eyeWideLeft: "eyeWideLeft",
        .eyeWideRight: "eyeWideRight",
        .jawForward: "jawForward",
        .jawLeft: "jawLeft",
        .jawOpen: "jawOpen",
        .jawRight: "jawRight",
        .mouthClose: "mouthClose",
        .mouthDimpleLeft: "mouthDimpleLeft",
        .mouthDimpleRight: "mouthDimpleRight",
        .mouthFrownLeft: "mouthFrownLeft",
        .mouthFrownRight: "mouthFrownRight",
        .mouthFunnel: "mouthFunnel",
        .mouthLeft: "mouthLeft",
        .mouthLowerDownLeft: "mouthLowerDownLeft",
        .mouthLowerDownRight: "mouthLowerDownRight",
        .mouthPressLeft: "mouthPressLeft",
        .mouthPressRight: "mouthPressRight",
        .mouthPucker: "mouthPucker",
        .mouthRight: "mouthRight",
        .mouthRollLower: "mouthRollLower",
        .mouthRollUpper: "mouthRollUpper",
        .mouthShrugLower: "mouthShrugLower",
        .mouthShrugUpper: "mouthShrugUpper",
        .mouthSmileLeft: "mouthSmileLeft",
        .mouthSmileRight: "mouthSmileRight",
        .mouthStretchLeft: "mouthStretchLeft",
        .mouthStretchRight: "mouthStretchRight",
        .mouthUpperUpLeft: "mouthUpperUpLeft",
        .mouthUpperUpRight: "mouthUpperUpRight",
        .noseSneerLeft: "noseSneerLeft",
        .noseSneerRight: "noseSneerRight",
        .tongueOut: "tongueOut",
    ]

    private static func canonicalName(for location: ARFaceAnchor.BlendShapeLocation) -> String {
        if let mapped = canonicalNamesByLocation[location] {
            return mapped
        }
        let raw = location.rawValue
        if raw.hasSuffix("_L") {
            return String(raw.dropLast(2)) + "Left"
        }
        if raw.hasSuffix("_R") {
            return String(raw.dropLast(2)) + "Right"
        }
        return raw
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
