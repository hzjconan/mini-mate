import Foundation
import Observation
import RealityKit
import SwiftUI
#if os(iOS)
import UIKit
#endif
import MMCore
import MMAvatar
import MMEmotion
import MMPerception

/// 形象场景：持有渲染器、正面相机、感知源与情绪状态机，按帧把姿态合成后交给渲染器。
@MainActor
@Observable
final class AvatarScene {
    private static let maxRecordedFrames = 10_800

    /// 调试面板写入；非零项覆盖状态机对应权重。
    var debugWeights: [String: Float] = [:]
    /// 调试面板“表情预设”当前选中的情绪；持久化在 scene 中，往返页面不丢失。
    private(set) var selectedPresetEmotion: EmotionTag?
    /// 真机调参滑杆：皱眉（concerned）眯眼与轻闭眼、惊讶（surprised）睁大眼与挑眉，实时同步至状态机预设。
    private(set) var concernedEyeSquint: Float = ExpressionPreset.bundledDefaults[.concerned]?.weights["eyeSquintLeft"] ?? 0.25
    private(set) var concernedEyeBlink: Float = ExpressionPreset.bundledDefaults[.concerned]?.weights["eyeBlinkLeft"] ?? 0.0
    private(set) var surprisedEyeWide: Float = ExpressionPreset.bundledDefaults[.surprised]?.weights["eyeWideLeft"] ?? 0.80
    private(set) var surprisedBrowOuterUp: Float = ExpressionPreset.bundledDefaults[.surprised]?.weights["browOuterUpLeft"] ?? 0.70
    private(set) var playingAction: ActionTag?
    private(set) var loadError: String?
    private(set) var capabilities: AvatarCapabilities?
    /// 调试面板最近点播的动作；返回形象页后仍会循环，方便观察。
    private(set) var previewAction: ActionTag?
    /// 调试面板的循环开关；默认开。
    var loopsPreviewAction = true
    /// 调试预览速度，1 为正常速度。
    var previewSpeed: Float = 1.0

    // MARK: - 感知、状态机与指标可观察状态

    private(set) var currentStateKind: AvatarStateKind = .idle
    private(set) var currentBaseEmotion: EmotionTag = .neutral
    private(set) var currentHeldCue: AvatarCue?
    private(set) var debugAudioLevel: Float = 0
    private(set) var isSimulatingSpeechMouth: Bool = false
    /// 调试选项（2A）：主界面底部悬浮对话调试条，默认关闭。
    var showConversationOverlay: Bool = false
    private(set) var isFaceTracked: Bool = false
    private(set) var isLookingAtScreen: Bool = false
    private(set) var latestFacePosition: SIMD3<Float>?
    private(set) var latestFaceSignals: FaceSignals = FaceSignals()
    private(set) var latestHeadRotation: SIMD3<Float> = .zero
    private(set) var latestEyeTarget: SIMD2<Float> = .zero
    private(set) var perceptionErrorMessage: String?

    private(set) var isRecordingPerception: Bool = false
    private(set) var recordedFrameCount: Int = 0
    private(set) var lastRecordedJSONLines: String?
    private(set) var latencyRecorder = LatencyRecorder()

    private(set) var isRunningMirrorCheck: Bool = false
    private(set) var mirrorCheckElapsed: TimeInterval = 0
    let mirrorCheckTargetDuration: TimeInterval = 30.0
    private(set) var mirrorCheckSampleCount: Int = 0
    private(set) var lastMirrorReport: MirrorCorrelationReport?

    // SC-006 10 分钟稳定性压测只读观测
    private(set) var isRunningStabilityTest: Bool = false
    private(set) var stabilityElapsed: TimeInterval = 0
    let stabilityTargetDuration: TimeInterval = 600.0
    private(set) var stabilitySampleCount: Int = 0
    private(set) var currentFps: Double = 0
    private(set) var currentMemoryMB: Double = 0
    private(set) var lastStabilityReport: StabilityReport?

    // US4 手势与热状态只读观测（3A）
    private(set) var lastGestureEvent: GestureEvent?
    private(set) var gestureEventCounts: [GestureKind: Int] = [:]
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    private(set) var effectiveGestureRateHz: Double = ThermalGesturePolicy.effectiveRate(
        configuredHz: 12.0,
        thermalState: ProcessInfo.processInfo.thermalState
    )
    private(set) var detectedHandCount: Int = 0
    private(set) var lastGestureDiagnostics: HandGestureClassifier.DebugSnapshot = .empty
    /// 同类感知反应冷却时间（3...8 s，默认 5 s），在调试面板实时可调并同步至状态机。
    private(set) var reactionCooldownSeconds: Double = 5.0

    let root: Entity
    /// `RealityView` 的非 AR 虚拟相机：加入场景时采用这台 `PerspectiveCamera` 的变换。
    let camera = PerspectiveCamera()

    @ObservationIgnored private let renderer: RealityKitAvatarRenderer
    @ObservationIgnored private var clock: any MMCore.Clock
    @ObservationIgnored private var perceptionSource: (any PerceptionSource)?
    @ObservationIgnored private var stateMachine: any EmotionStateMachine
    @ObservationIgnored private var isConfiguredFromComposition = false

    @ObservationIgnored private var subscription: EventSubscription?
    @ObservationIgnored private var perceptionTask: Task<Void, Never>?
    @ObservationIgnored private var isStartingPerception = false
    @ObservationIgnored private var perceptionGeneration: UInt64 = 0
    @ObservationIgnored private var poseTask: Task<Void, Never>?
    @ObservationIgnored private var cooldownSyncTask: Task<Void, Never>?
    @ObservationIgnored private var latestPose = AvatarPose()
    @ObservationIgnored private var pendingStateMachineAction: ActionCommand?
    private enum ConversationQueueItem {
        case event(ConversationEvent)
        case reset
    }

    @ObservationIgnored private var trackLatencyTracker = TrackLatencyTracker()
    @ObservationIgnored private var reflexLatencyTracker = ReflexLatencyTracker()
    @ObservationIgnored private var feedbackLatencyTracker = FeedbackLatencyTracker()
    @ObservationIgnored private var pendingConversationItems: [ConversationQueueItem] = []
    @ObservationIgnored private var conversationEventTask: Task<Void, Never>?
    @ObservationIgnored private var conversationQueueGeneration: UInt64 = 0
    @ObservationIgnored private var mouthSimulationTask: Task<Void, Never>?
    @ObservationIgnored private var mirrorCheckStartedAt: TimeInterval?
    @ObservationIgnored private var mirrorCheckPairs: [(user: [String: Float], avatar: [String: Float])] = []
    @ObservationIgnored private var recordedFrames: [PerceptionFeatures] = []
    @ObservationIgnored private var isDebugPanelPresented = false
    @ObservationIgnored private var isSceneActive = true
    @ObservationIgnored private var stabilityRecorder = StabilitySessionRecorder()
    @ObservationIgnored private var lastObservedSessionInterruptions: Int = 0
    @ObservationIgnored private var lastObservedThermalSessionInterruptions: Int = 0

    private var canMeasureTrackLatency: Bool {
        currentStateKind == .attending && playingAction == nil && !isDebugPanelPresented
    }

    @ObservationIgnored private var pendingAction: ActionTag?
    @ObservationIgnored private var pendingStopAction = false
    /// 害羞遮嘴时眼睛的闭合/眯眼混合量，随动作平滑进入和退出。
    @ObservationIgnored private var shyEyeBlend: Float = 0
    #if DEBUG
    /// 真机调试：`-playAction nod` 循环播放单个动作，便于录屏核对。
    @ObservationIgnored private var debugActionTag: ActionTag?
    @ObservationIgnored private var debugActionTask: Task<Void, Never>?
    @ObservationIgnored private var debugDisableHeadPose = false
    @ObservationIgnored private var debugFullTimeline = false
    @ObservationIgnored private var debugPoseTag: ActionTag?
    @ObservationIgnored private var debugPoseFraction: Double = 0.5
    @ObservationIgnored private var debugPreviewTag: ActionTag?
    /// 真机逐个验证形态键时冻结呼吸/眨眼与自动感知驱动，避免截图差异混入待机动作。
    @ObservationIgnored private var debugFreezeIdle = false
    #endif

    init(
        clock: any MMCore.Clock = SystemClock(),
        perceptionSource: (any PerceptionSource)? = nil,
        stateMachine: (any EmotionStateMachine)? = nil
    ) {
        let renderer = RealityKitAvatarRenderer()
        self.renderer = renderer
        self.root = renderer.root
        self.clock = clock
        self.perceptionSource = perceptionSource
        self.stateMachine = stateMachine ?? RuleBasedEmotionStateMachine(clock: clock)
        syncReactionCooldownToStateMachine()

        var intensity: Float = 2000
        var fillIntensity: Float = 900
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-light"),
           index + 1 < arguments.count,
           let value = Float(arguments[index + 1]) {
            intensity = value
        }
        if let index = arguments.firstIndex(of: "-fill"),
           index + 1 < arguments.count,
           let value = Float(arguments[index + 1]) {
            fillIntensity = value
        }
        if let index = arguments.firstIndex(of: "-playAction"),
           index + 1 < arguments.count {
            debugActionTag = ActionTag(rawValue: arguments[index + 1])
        }
        debugDisableHeadPose = arguments.contains("-disableHeadPose")
        debugFullTimeline = arguments.contains("-fullTimeline")
        if let index = arguments.firstIndex(of: "-actionPose"),
           index + 2 < arguments.count {
            debugPoseTag = ActionTag(rawValue: arguments[index + 1])
            debugPoseFraction = Double(arguments[index + 2]) ?? 0.5
        }
        if let index = arguments.firstIndex(of: "-previewAction"),
           index + 1 < arguments.count {
            debugPreviewTag = ActionTag(rawValue: arguments[index + 1])
        }
        // 真机逐项验收 52 个形态键：一个进程只置一个系数为 1。
        debugFreezeIdle = arguments.contains("-freezeIdle")
        if let index = arguments.firstIndex(of: "-blendName"),
           index + 1 < arguments.count {
            debugWeights[arguments[index + 1]] = 1
        }
        renderer.debugDisableHeadPose = debugDisableHeadPose
        #endif

        let light = DirectionalLight()
        light.light.intensity = intensity
        light.transform.rotation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])
        // 不投实时阴影：短裤下摆会把整条腿罩进主光的阴影里，腿部只剩补光，
        // 真机肤色明显深于脸部。关掉投影后腿部与脸部接受同样的主光 + 补光。
        light.shadow = nil
        root.addChild(light)

        // 正面下方补光，抬亮腿部和下巴底面。
        let fill = DirectionalLight()
        fill.light.intensity = fillIntensity
        fill.transform.rotation = simd_quatf(angle: .pi / 6, axis: [1, 0, 0])
        fill.shadow = nil
        root.addChild(fill)

        camera.camera.fieldOfViewInDegrees = 35
        camera.camera.near = 0.05
        camera.camera.far = 100
    }

    func configure(from composition: AppComposition) {
        guard !isConfiguredFromComposition else { return }
        isConfiguredFromComposition = true
        self.clock = composition.clock
        if self.perceptionSource == nil {
            self.perceptionSource = composition.makePerceptionSource()
        }
        self.stateMachine = composition.makeEmotionStateMachine()
        syncReactionCooldownToStateMachine()
    }

    func load() async {
        do {
            capabilities = try await renderer.load(named: "minimate")
            frameCamera()
            #if DEBUG
            if let tag = debugPoseTag {
                renderer.debugPoseAction(tag, at: debugPoseFraction)
            } else if debugFullTimeline {
                renderer.debugPlayFullTimeline()
            } else {
                startDebugActionLoopIfNeeded()
            }
            if let tag = debugPreviewTag {
                preview(tag, loop: true)
            }
            #endif
        } catch {
            loadError = "形象加载失败：\(error)"
        }
    }

    // MARK: - 感知生命周期

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }

    func startPerception() async {
        #if DEBUG
        if debugFreezeIdle { return }
        #endif
        guard perceptionTask == nil, !isStartingPerception else { return }
        guard let source = perceptionSource else { return }

        isStartingPerception = true
        perceptionGeneration &+= 1
        let generation = perceptionGeneration
        defer {
            if perceptionGeneration == generation {
                isStartingPerception = false
            }
        }

        perceptionErrorMessage = nil
        let stream = source.features
        do {
            try await source.start()
        } catch let error as PerceptionError {
            guard perceptionGeneration == generation else { return }
            switch error {
            case .cameraPermissionDenied:
                perceptionErrorMessage = "未获得摄像头权限，请在系统设置中开启以启用视线跟随（形象仍可正常待机）。"
            case .faceTrackingUnsupported:
                perceptionErrorMessage = "当前设备不支持前置人脸追踪（形象仍可正常待机）。"
            case .sessionInterrupted:
                perceptionErrorMessage = "摄像头会话暂时中断，恢复后将自动继续。"
            }
            return
        } catch {
            guard perceptionGeneration == generation else { return }
            perceptionErrorMessage = "感知启动失败：\(error.localizedDescription)"
            return
        }

        // 启动挂起期间若已离页或被 stopPerception()，立刻关闭摄像头防泄漏
        guard !Task.isCancelled, perceptionGeneration == generation else {
            source.stop()
            return
        }

        if isSceneActive {
            setIdleTimerDisabled(true)
        }
        perceptionTask = Task { [weak self] in
            for await features in stream {
                guard let self, !Task.isCancelled, self.perceptionGeneration == generation else { break }
                self.handleIncomingFeatures(features)
                await self.stateMachine.handle(features)
                // 收到感知帧后立即同步求值最新姿态，消除额外 1~2 帧 actor hop 延迟并保持调试面板实时刷新
                guard !Task.isCancelled, self.perceptionGeneration == generation else { break }
                let evalTime = self.clock.now.timeIntervalSinceReferenceDate
                let pose = await self.stateMachine.pose(at: evalTime)
                let state = await self.stateMachine.state
                guard !Task.isCancelled, self.perceptionGeneration == generation else { break }
                self.latestPose = pose
                self.currentStateKind = state.kind
                self.currentBaseEmotion = state.baseEmotion
                self.currentHeldCue = state.heldCue
                self.latestHeadRotation = pose.headRotation
                self.latestEyeTarget = pose.eyeTarget
                if let cmd = pose.action {
                    self.pendingStateMachineAction = cmd
                }
                self.observePostPerception(features: features, state: state, pose: pose)
            }
        }
    }

    func stopPerception() {
        setIdleTimerDisabled(false)
        if isRunningStabilityTest {
            stopStabilityTest()
        }
        perceptionGeneration &+= 1
        isStartingPerception = false
        perceptionTask?.cancel()
        perceptionTask = nil
        perceptionSource?.stop()
        poseTask?.cancel()
        poseTask = nil
        mouthSimulationTask?.cancel()
        mouthSimulationTask = nil
        isSimulatingSpeechMouth = false
        debugAudioLevel = 0
        conversationQueueGeneration &+= 1
        conversationEventTask?.cancel()
        conversationEventTask = nil
        pendingConversationItems.removeAll()
        isFaceTracked = false
        isLookingAtScreen = false
        latestFacePosition = nil
        latestFaceSignals = FaceSignals()
        detectedHandCount = 0
        trackLatencyTracker.reset()
        reflexLatencyTracker.reset()
        feedbackLatencyTracker.reset()
        if isRunningMirrorCheck {
            stopMirrorCheck()
        }
    }

    func handleBackground() async {
        isSceneActive = false
        setIdleTimerDisabled(false)
        if isRunningStabilityTest {
            stopStabilityTest()
        }
        poseTask?.cancel()
        poseTask = nil
        mouthSimulationTask?.cancel()
        mouthSimulationTask = nil
        isSimulatingSpeechMouth = false
        debugAudioLevel = 0
        conversationQueueGeneration &+= 1
        conversationEventTask?.cancel()
        conversationEventTask = nil
        pendingConversationItems.removeAll()
        let now = clock.now.timeIntervalSinceReferenceDate
        if let ruleBased = stateMachine as? RuleBasedEmotionStateMachine {
            await ruleBased.resetToIdle(at: now)
        }
        currentStateKind = .idle
        currentBaseEmotion = .neutral
        currentHeldCue = nil
        isFaceTracked = false
        isLookingAtScreen = false
        latestFacePosition = nil
        latestFaceSignals = FaceSignals()
        detectedHandCount = 0
        latestHeadRotation = .zero
        latestEyeTarget = .zero
        latestPose = AvatarPose()
        pendingStateMachineAction = nil
        trackLatencyTracker.reset()
        reflexLatencyTracker.reset()
        feedbackLatencyTracker.reset()
        if isRunningMirrorCheck {
            stopMirrorCheck()
        }
    }

    func handleForeground() async {
        isSceneActive = true
        if perceptionTask != nil {
            setIdleTimerDisabled(true)
        } else {
            await startPerception()
        }
    }

    func setDebugPanelPresented(_ presented: Bool) {
        isDebugPanelPresented = presented
        if isRunningStabilityTest {
            let now = clock.now.timeIntervalSinceReferenceDate
            if presented {
                stabilityRecorder.pause(at: now)
            } else {
                stabilityRecorder.resume(at: now)
            }
        }
    }

    // MARK: - SC-006 稳定性压测（10 分钟）

    func startStabilityTest() {
        let now = clock.now.timeIntervalSinceReferenceDate
        stabilityRecorder = StabilitySessionRecorder(targetDuration: stabilityTargetDuration)
        stabilityRecorder.start(at: now, initialThermalLevel: StabilityThermalLevel(thermalState))
        #if os(iOS)
        if let arkitSource = perceptionSource as? ARKitPerceptionSource {
            lastObservedSessionInterruptions = arkitSource.sessionInterruptionCount
            lastObservedThermalSessionInterruptions = arkitSource.thermalSessionInterruptionCount
        } else {
            lastObservedSessionInterruptions = 0
            lastObservedThermalSessionInterruptions = 0
        }
        #else
        lastObservedSessionInterruptions = 0
        lastObservedThermalSessionInterruptions = 0
        #endif
        if isDebugPanelPresented {
            stabilityRecorder.pause(at: now)
        }
        lastStabilityReport = nil
        stabilityElapsed = 0
        stabilitySampleCount = 0
        currentFps = 0
        currentMemoryMB = 0
        isRunningStabilityTest = true
    }

    func stopStabilityTest() {
        guard isRunningStabilityTest else { return }
        syncARKitStabilityState(at: clock.now.timeIntervalSinceReferenceDate)
        let report = stabilityRecorder.finish()
        lastStabilityReport = report
        stabilityElapsed = report.duration
        stabilitySampleCount = report.sampleCount
        isRunningStabilityTest = false
    }

    /// 统一同步 ARKit 热状态、中断态与中断计数增量（避免中断期间无新帧时漏记或恢复降温后误判热态中断）。
    private func syncARKitStabilityState(at timestamp: TimeInterval) {
        #if os(iOS)
        if let arkitSource = perceptionSource as? ARKitPerceptionSource {
            let latestThermal = arkitSource.currentThermalState
            if thermalState != latestThermal {
                thermalState = latestThermal
            }
            let latestGestureHz = arkitSource.effectiveGestureRateHz
            if effectiveGestureRateHz != latestGestureHz {
                effectiveGestureRateHz = latestGestureHz
            }
            if arkitSource.isSessionInterrupted, isFaceTracked {
                isFaceTracked = false
            }
            let totalCount = arkitSource.sessionInterruptionCount
            let thermalCount = arkitSource.thermalSessionInterruptionCount
            if totalCount > lastObservedSessionInterruptions {
                let totalDelta = totalCount - lastObservedSessionInterruptions
                let thermalDelta = max(0, min(totalDelta, thermalCount - lastObservedThermalSessionInterruptions))
                let nonThermalDelta = totalDelta - thermalDelta
                if isRunningStabilityTest {
                    let currentThermal = StabilityThermalLevel(thermalState)
                    let thermalLevelForInterrupt = max(currentThermal, .serious)
                    for _ in 0..<thermalDelta {
                        stabilityRecorder.recordSessionInterruption(at: timestamp, thermalLevel: thermalLevelForInterrupt)
                    }
                    for _ in 0..<nonThermalDelta {
                        stabilityRecorder.recordSessionInterruption(at: timestamp, thermalLevel: .nominal)
                    }
                }
                lastObservedSessionInterruptions = totalCount
                lastObservedThermalSessionInterruptions = thermalCount
            } else if totalCount < lastObservedSessionInterruptions {
                lastObservedSessionInterruptions = totalCount
                lastObservedThermalSessionInterruptions = thermalCount
            }
        }
        #endif
    }

    func clearStabilityTest() {
        stabilityRecorder.reset()
        lastStabilityReport = nil
        stabilityElapsed = 0
        stabilitySampleCount = 0
        currentFps = 0
        currentMemoryMB = 0
        isRunningStabilityTest = false
    }

    func handleScreenDisappear() {
        if !isDebugPanelPresented {
            stopPerception()
        }
    }

    func resetGestureCounters() {
        lastGestureEvent = nil
        gestureEventCounts.removeAll()
    }

    func setReactionCooldown(_ seconds: Double) {
        guard seconds.isFinite else { return }
        reactionCooldownSeconds = min(max(seconds, 3.0), 8.0)
        syncReactionCooldownToStateMachine()
    }

    private func syncReactionCooldownToStateMachine() {
        cooldownSyncTask?.cancel()
        if let ruleBased = stateMachine as? RuleBasedEmotionStateMachine {
            cooldownSyncTask = Task { [weak self] in
                guard let self, !Task.isCancelled else { return }
                await ruleBased.updateCooldown(self.reactionCooldownSeconds)
            }
        }
    }

    private func handleIncomingFeatures(_ features: PerceptionFeatures) {
        isFaceTracked = features.isFaceTracked
        isLookingAtScreen = features.isLookingAtScreen
        latestFacePosition = features.facePosition
        latestFaceSignals = features.signals

        if let gesture = features.gesture {
            lastGestureEvent = gesture
            gestureEventCounts[gesture.kind, default: 0] += 1
        }
        #if os(iOS)
        if let arkitSource = perceptionSource as? ARKitPerceptionSource {
            detectedHandCount = arkitSource.lastDetectedHandCount
            lastGestureDiagnostics = arkitSource.lastGestureDiagnostics
            syncARKitStabilityState(at: features.timestamp)
        } else {
            let currentThermal = ProcessInfo.processInfo.thermalState
            thermalState = currentThermal
            effectiveGestureRateHz = ThermalGesturePolicy.effectiveRate(configuredHz: 12.0, thermalState: currentThermal)
            detectedHandCount = 0
        }
        #else
        let currentThermal = ProcessInfo.processInfo.thermalState
        thermalState = currentThermal
        effectiveGestureRateHz = ThermalGesturePolicy.effectiveRate(configuredHz: 12.0, thermalState: currentThermal)
        detectedHandCount = 0
        #endif

        if canMeasureTrackLatency {
            trackLatencyTracker.observeFacePosition(
                features.facePosition,
                currentHeadRotation: latestHeadRotation,
                at: features.timestamp
            )
        } else {
            trackLatencyTracker.reset()
        }

        if isRecordingPerception {
            recordedFrames.append(features)
            recordedFrameCount = recordedFrames.count
            if recordedFrames.count >= Self.maxRecordedFrames {
                stopPerceptionRecording()
            }
        }
    }

    // MARK: - 感知录制与指标导出

    func startPerceptionRecording() {
        recordedFrames.removeAll(keepingCapacity: true)
        recordedFrameCount = 0
        lastRecordedJSONLines = nil
        isRecordingPerception = true
    }

    func stopPerceptionRecording() {
        guard isRecordingPerception else { return }
        isRecordingPerception = false
        guard !recordedFrames.isEmpty else {
            lastRecordedJSONLines = nil
            return
        }
        if let data = try? ScriptedPerceptionSource.encodeJSONLines(recordedFrames),
           let text = String(data: data, encoding: .utf8) {
            lastRecordedJSONLines = text
        }
    }

    func clearPerceptionRecording() {
        isRecordingPerception = false
        recordedFrames.removeAll()
        recordedFrameCount = 0
        lastRecordedJSONLines = nil
    }

    func metricsCSV() -> String {
        latencyRecorder.csv()
    }

    func clearMetrics() {
        latencyRecorder = LatencyRecorder()
        trackLatencyTracker.reset()
        reflexLatencyTracker.reset()
        feedbackLatencyTracker.reset()
    }

    // MARK: - US5 对话事件注入、口型模拟与 M_feedback

    func injectConversationEvent(_ event: ConversationEvent) {
        switch event {
        case .userSpeechStarted, .assistantSpeechEnded, .assistantCueEnded:
            stopMouthSimulationWithoutInjecting()
            pendingConversationItems.removeAll { item in
                if case .event(.assistantAudioLevel) = item { return true }
                return false
            }
        default:
            break
        }
        enqueueConversationItem(.event(event))
    }

    private func enqueueConversationItem(_ item: ConversationQueueItem) {
        pendingConversationItems.append(item)
        guard conversationEventTask == nil else { return }
        let generation = conversationQueueGeneration
        conversationEventTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled,
                  self.conversationQueueGeneration == generation,
                  !self.pendingConversationItems.isEmpty
            {
                let nextItem = self.pendingConversationItems.removeFirst()
                switch nextItem {
                case .event(let event):
                    await self.processConversationEvent(event, generation: generation)
                case .reset:
                    await self.processConversationReset(generation: generation)
                }
            }
            if self.conversationQueueGeneration == generation {
                self.conversationEventTask = nil
            }
        }
    }

    private func processConversationEvent(_ event: ConversationEvent, generation: UInt64) async {
        switch event {
        case .userSpeechEnded:
            let injectedAt = clock.now.timeIntervalSinceReferenceDate
            feedbackLatencyTracker.observeUserSpeechEnded(
                previousState: currentStateKind,
                at: injectedAt
            )
        case .userSpeechStarted:
            feedbackLatencyTracker.reset()
        default:
            break
        }

        await stateMachine.handle(event)
        guard !Task.isCancelled, conversationQueueGeneration == generation else { return }

        let evalTime = clock.now.timeIntervalSinceReferenceDate
        let pose = await stateMachine.pose(at: evalTime)
        let state = await stateMachine.state
        guard !Task.isCancelled, conversationQueueGeneration == generation else { return }

        latestPose = pose
        currentStateKind = state.kind
        currentBaseEmotion = state.baseEmotion
        currentHeldCue = state.heldCue
        latestHeadRotation = pose.headRotation
        latestEyeTarget = pose.eyeTarget
        if let cmd = pose.action {
            pendingStateMachineAction = cmd
        }

        if isDebugPanelPresented,
           let sample = feedbackLatencyTracker.observeAppliedState(
               state.kind,
               at: clock.now.timeIntervalSinceReferenceDate
           )
        {
            latencyRecorder.record(sample, metric: "M_feedback")
        }
    }

    private func processConversationReset(generation: UInt64) async {
        let now = clock.now.timeIntervalSinceReferenceDate
        if let ruleBased = stateMachine as? RuleBasedEmotionStateMachine {
            await ruleBased.resetToIdle(at: now)
        }
        guard !Task.isCancelled, conversationQueueGeneration == generation else { return }
        let pose = await stateMachine.pose(at: now)
        let state = await stateMachine.state
        guard !Task.isCancelled, conversationQueueGeneration == generation else { return }
        latestPose = pose
        currentStateKind = state.kind
        currentBaseEmotion = state.baseEmotion
        currentHeldCue = state.heldCue
        latestHeadRotation = pose.headRotation
        latestEyeTarget = pose.eyeTarget
        pendingStateMachineAction = nil
    }

    func injectSpeakingStart(emotion: EmotionTag) {
        injectConversationEvent(.assistantSpeechStarted)
        injectConversationEvent(.assistantEmotion(emotion))
    }

    func setDebugAudioLevel(_ level: Float) {
        stopMouthSimulationWithoutInjecting()
        let clamped = level.isFinite ? min(max(level, 0), 1) : 0
        debugAudioLevel = clamped
        injectConversationEvent(.assistantAudioLevel(clamped))
    }

    func setSimulatingSpeechMouth(_ enabled: Bool) {
        if enabled {
            guard !isSimulatingSpeechMouth else { return }
            isSimulatingSpeechMouth = true
            let startedAt = clock.now.timeIntervalSinceReferenceDate
            mouthSimulationTask?.cancel()
            mouthSimulationTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.isSimulatingSpeechMouth else { break }
                    let t = self.clock.now.timeIntervalSinceReferenceDate - startedAt
                    // 复合正弦波形输出 0.05...0.85，模拟自然说话音节起伏
                    let wave = 0.5
                        + 0.30 * sin(t * 2.0 * .pi * 3.2)
                        + 0.18 * sin(t * 2.0 * .pi * 7.1 + 0.8)
                        + 0.12 * cos(t * 2.0 * .pi * 1.4)
                    let level = Float(min(max(wave, 0.05), 0.85))
                    self.debugAudioLevel = level
                    self.injectConversationEvent(.assistantAudioLevel(level))
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }
        } else {
            stopMouthSimulationWithoutInjecting()
            injectConversationEvent(.assistantAudioLevel(0))
        }
    }

    func resetConversationState() {
        stopMouthSimulationWithoutInjecting()
        conversationQueueGeneration &+= 1
        conversationEventTask?.cancel()
        conversationEventTask = nil
        pendingConversationItems.removeAll()
        feedbackLatencyTracker.reset()
        enqueueConversationItem(.reset)
    }

    private func stopMouthSimulationWithoutInjecting() {
        mouthSimulationTask?.cancel()
        mouthSimulationTask = nil
        isSimulatingSpeechMouth = false
        debugAudioLevel = 0
    }

    // MARK: - SC-004 镜像检测（30 s）与表情预设调参

    func startMirrorCheck() {
        mirrorCheckPairs.removeAll(keepingCapacity: true)
        mirrorCheckStartedAt = nil
        mirrorCheckElapsed = 0
        mirrorCheckSampleCount = 0
        lastMirrorReport = nil
        isRunningMirrorCheck = true
    }

    func stopMirrorCheck() {
        guard isRunningMirrorCheck else { return }
        isRunningMirrorCheck = false
        if mirrorCheckPairs.count >= 2 {
            lastMirrorReport = MirrorCorrelationEvaluator.evaluate(
                pairs: mirrorCheckPairs,
                duration: mirrorCheckElapsed
            )
        } else {
            lastMirrorReport = nil
        }
        mirrorCheckPairs.removeAll()
        mirrorCheckStartedAt = nil
    }

    func clearMirrorCheck() {
        isRunningMirrorCheck = false
        mirrorCheckPairs.removeAll()
        mirrorCheckStartedAt = nil
        mirrorCheckElapsed = 0
        mirrorCheckSampleCount = 0
        lastMirrorReport = nil
    }

    func applyPresetToDebugWeights(_ emotion: EmotionTag) {
        selectedPresetEmotion = emotion
        debugWeights.removeAll()
        guard let preset = effectivePreset(for: emotion) else { return }
        for (name, value) in preset.weights {
            debugWeights[name] = value
        }
    }

    func setConcernedEyeTuning(squint: Float, blink: Float) {
        concernedEyeSquint = min(max(squint, 0), 1)
        concernedEyeBlink = min(max(blink, 0), 0.6)
        syncTunedPreset(for: .concerned)
    }

    func setSurprisedEyeTuning(eyeWide: Float, browOuterUp: Float) {
        surprisedEyeWide = min(max(eyeWide, 0), 1)
        surprisedBrowOuterUp = min(max(browOuterUp, 0), 1)
        syncTunedPreset(for: .surprised)
    }

    func resetEyeTuning() {
        concernedEyeSquint = ExpressionPreset.bundledDefaults[.concerned]?.weights["eyeSquintLeft"] ?? 0.25
        concernedEyeBlink = ExpressionPreset.bundledDefaults[.concerned]?.weights["eyeBlinkLeft"] ?? 0.0
        surprisedEyeWide = ExpressionPreset.bundledDefaults[.surprised]?.weights["eyeWideLeft"] ?? 0.80
        surprisedBrowOuterUp = ExpressionPreset.bundledDefaults[.surprised]?.weights["browOuterUpLeft"] ?? 0.70
        syncTunedPreset(for: .concerned)
        syncTunedPreset(for: .surprised)
    }

    private func effectivePreset(for emotion: EmotionTag) -> ExpressionPreset? {
        guard let base = ExpressionPreset.bundledDefaults[emotion] else { return nil }
        var weights = base.weights
        switch emotion {
        case .concerned:
            weights["eyeSquintLeft"] = concernedEyeSquint
            weights["eyeSquintRight"] = concernedEyeSquint
            if concernedEyeBlink > 0.001 {
                weights["eyeBlinkLeft"] = concernedEyeBlink
                weights["eyeBlinkRight"] = concernedEyeBlink
            } else {
                weights.removeValue(forKey: "eyeBlinkLeft")
                weights.removeValue(forKey: "eyeBlinkRight")
            }
        case .surprised:
            weights["eyeWideLeft"] = surprisedEyeWide
            weights["eyeWideRight"] = surprisedEyeWide
            weights["browOuterUpLeft"] = surprisedBrowOuterUp
            weights["browOuterUpRight"] = surprisedBrowOuterUp
        default:
            break
        }
        return ExpressionPreset(
            emotion: base.emotion,
            weights: weights,
            blendIn: base.blendIn,
            blendOut: base.blendOut
        )
    }

    private func syncTunedPreset(for emotion: EmotionTag) {
        guard let preset = effectivePreset(for: emotion) else { return }
        if selectedPresetEmotion == emotion {
            debugWeights.removeAll()
            for (name, value) in preset.weights {
                debugWeights[name] = value
            }
        }
        if let ruleBased = stateMachine as? RuleBasedEmotionStateMachine {
            Task {
                await ruleBased.updatePreset(preset)
            }
        }
    }

    func exportDebugWeightsAsPresetJSON(emotion: EmotionTag) -> String? {
        var activeWeights: [String: Float] = [:]
        for (name, value) in debugWeights where value > 0.001 {
            activeWeights[name] = value
        }
        let defaultPreset = ExpressionPreset.bundledDefaults[emotion]
        let preset = ExpressionPreset(
            emotion: emotion,
            weights: activeWeights,
            blendIn: defaultPreset?.blendIn ?? .milliseconds(200),
            blendOut: defaultPreset?.blendOut ?? .milliseconds(300)
        )
        guard let data = try? ExpressionPreset.encodeSingleJSON(preset) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func observePostPerception(
        features: PerceptionFeatures,
        state: AvatarState,
        pose: AvatarPose
    ) {
        #if DEBUG
        let freezeIdle = debugFreezeIdle
        #else
        let freezeIdle = false
        #endif

        if !freezeIdle, !isDebugPanelPresented {
            reflexLatencyTracker.observePerception(
                activeExpression: features.isFaceTracked ? features.signals.activeExpression : nil,
                state: state,
                at: features.timestamp
            )
        } else {
            reflexLatencyTracker.reset()
        }

        if isRunningMirrorCheck, features.isFaceTracked {
            if mirrorCheckStartedAt == nil {
                mirrorCheckStartedAt = features.timestamp
            }
            mirrorCheckPairs.append((user: features.rawBlendShapes, avatar: pose.expressionWeights))
            mirrorCheckSampleCount = mirrorCheckPairs.count
            if let started = mirrorCheckStartedAt {
                mirrorCheckElapsed = max(0, features.timestamp - started)
                if mirrorCheckElapsed >= mirrorCheckTargetDuration {
                    stopMirrorCheck()
                }
            }
        }
    }

    #if DEBUG
    private func startDebugActionLoopIfNeeded() {
        guard let tag = debugActionTag, debugActionTask == nil else { return }
        debugActionTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.play(tag)
                try? await Task.sleep(for: .seconds(2.2))
            }
        }
    }
    #endif

    func play(_ action: ActionTag) {
        // 正常点播是一次性动作；结束调试预览循环，避免两者互相打断。
        previewAction = nil
        loopsPreviewAction = false
        renderer.actionLooping = false
        pendingStopAction = false
        pendingAction = action
    }

    /// 调试面板点播：可选循环，返回形象页后继续播放，方便逐个动作观察。
    func preview(_ action: ActionTag, loop: Bool) {
        previewAction = action
        loopsPreviewAction = loop
        renderer.actionLooping = loop
        pendingStopAction = false
        pendingAction = action
    }

    func setPreviewSpeed(_ speed: Float) {
        previewSpeed = speed
        renderer.playbackSpeed = speed
        renderer.setPlaybackSpeed(speed)
    }

    func stopPreview() {
        loopsPreviewAction = false
        previewAction = nil
        renderer.actionLooping = false
        pendingAction = nil
        pendingStopAction = true
    }

    func resetWeights() {
        selectedPresetEmotion = nil
        debugWeights.removeAll()
    }

    /// 订阅 RealityKit 的逐帧更新，持有订阅直到视图销毁。
    func subscribeToUpdates(in content: inout RealityViewCameraContent) {
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        // 加载完成前 `renderer` 还没有形态键映射，提前驱动会误报全部 blendShape 缺失。
        guard capabilities != nil else { return }

        let now = clock.now.timeIntervalSinceReferenceDate
        #if DEBUG
        let freezeIdle = debugFreezeIdle
        #else
        let freezeIdle = false
        #endif

        // 单飞行异步刷新状态机姿态，不在 60 Hz 回调里堆积并发 Task
        if !freezeIdle, poseTask == nil {
            poseTask = Task { [weak self] in
                guard let self else { return }
                let pose = await self.stateMachine.pose(at: now)
                let state = await self.stateMachine.state
                guard !Task.isCancelled else {
                    self.poseTask = nil
                    return
                }
                self.latestPose = pose
                self.currentStateKind = state.kind
                self.currentBaseEmotion = state.baseEmotion
                self.currentHeldCue = state.heldCue
                self.latestHeadRotation = pose.headRotation
                self.latestEyeTarget = pose.eyeTarget
                if let cmd = pose.action {
                    self.pendingStateMachineAction = cmd
                }
                self.poseTask = nil
            }
        }

        var weights: [String: Float] = freezeIdle ? [:] : latestPose.expressionWeights
        // 调试滑杆非零项覆盖状态机权重，保留 T019 52 滑杆逐项测试与 -blendName 能力
        for (name, value) in debugWeights where value > 0 {
            weights[name] = value
        }

        // shyCover：手遮嘴时眼睛微微闭上（眯眼 + 轻闭），动作结束后平滑恢复。
        let shyTarget: Float = (playingAction == .shyCover) ? 1 : 0
        shyEyeBlend += (shyTarget - shyEyeBlend) * 0.18
        if shyEyeBlend > 0.01 {
            let blink = 0.32 * shyEyeBlend
            let squint = 0.22 * shyEyeBlend
            weights["eyeBlinkLeft"] = max(weights["eyeBlinkLeft"] ?? 0, blink)
            weights["eyeBlinkRight"] = max(weights["eyeBlinkRight"] ?? 0, blink)
            weights["eyeSquintLeft"] = max(weights["eyeSquintLeft"] ?? 0, squint)
            weights["eyeSquintRight"] = max(weights["eyeSquintRight"] ?? 0, squint)
        }

        // 调试动作指令优先于状态机自动动作
        let action: ActionCommand?
        if pendingStopAction {
            action = .stop
            pendingStopAction = false
            pendingStateMachineAction = nil
        } else if let debugCmd = pendingAction {
            action = .play(debugCmd)
            pendingAction = nil
            pendingStateMachineAction = nil
        } else if previewAction != nil {
            action = nil
            pendingStateMachineAction = nil
        } else if !freezeIdle {
            action = pendingStateMachineAction
            pendingStateMachineAction = nil
        } else {
            action = nil
        }

        let headRotation = freezeIdle ? .zero : latestPose.headRotation
        let eyeTarget = freezeIdle ? .zero : latestPose.eyeTarget
        let pose = AvatarPose(
            expressionWeights: weights,
            headRotation: headRotation,
            eyeTarget: eyeTarget,
            action: action
        )
        renderer.apply(pose)
        playingAction = renderer.playingAction

        if isRunningStabilityTest, !isDebugPanelPresented {
            syncARKitStabilityState(at: now)
            if let sample = stabilityRecorder.recordFrame(
                at: now,
                thermalLevel: StabilityThermalLevel(thermalState),
                effectiveGestureRateHz: effectiveGestureRateHz,
                isFaceTracked: isFaceTracked,
                memoryMBProvider: { ProcessMemory.physicalFootprintMB() }
            ) {
                currentFps = sample.fps
                currentMemoryMB = sample.memoryMB
                stabilityElapsed = sample.elapsed
                stabilitySampleCount = stabilityRecorder.samples.count
                if stabilityRecorder.elapsed + 1e-9 >= stabilityTargetDuration {
                    stopStabilityTest()
                }
            }
        }

        if !freezeIdle, canMeasureTrackLatency {
            if let sample = trackLatencyTracker.observeAppliedHeadRotation(headRotation, at: now) {
                latencyRecorder.record(sample, metric: "M_track")
            }
        } else {
            trackLatencyTracker.reset()
        }

        if !freezeIdle, !isDebugPanelPresented {
            if let reflexSample = reflexLatencyTracker.observeAppliedState(currentStateKind, at: now) {
                latencyRecorder.record(reflexSample, metric: "M_reflex")
            }
            if let feedbackSample = feedbackLatencyTracker.observeAppliedState(currentStateKind, at: now) {
                latencyRecorder.record(feedbackSample, metric: "M_feedback")
            }
        } else {
            reflexLatencyTracker.reset()
        }
    }

    /// 按模型包围盒放一台正面相机，留 20% 边距。
    private func frameCamera() {
        let bounds = root.visualBounds(recursive: true, relativeTo: nil)
        guard bounds.extents.y > 0 else { return }

        let center = (bounds.min + bounds.max) / 2
        let fov = camera.camera.fieldOfViewInDegrees * .pi / 180
        let distance = (bounds.extents.y / 2) / tan(fov / 2) * 1.2
        let eye = SIMD3<Float>(center.x, center.y, bounds.max.z + distance)
        camera.look(at: center, from: eye, relativeTo: nil)
    }
}

struct AvatarScreen: View {
    @Environment(AppComposition.self) private var composition: AppComposition?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene = AvatarScene()
    @State private var isShowingDebugPanel = false

    var body: some View {
        RealityView { (content: inout RealityViewCameraContent) in
            content.camera = .virtual
            content.add(scene.root)
            scene.subscribeToUpdates(in: &content)
            await scene.load()
            // 虚拟相机在实体加入场景的那一刻锁定变换；必须在 frameCamera 之后再加相机。
            content.add(scene.camera)
        }
        // 浅色背景贴近 review 图的观感；深色模式保持深底，避免导航栏/状态栏对比度问题。
        .background(colorScheme == .dark
            ? Color(white: 0.10)
            : Color(red: 0.94, green: 0.95, blue: 0.97))
        .ignoresSafeArea()
        .task {
            if let composition {
                scene.configure(from: composition)
            }
            await scene.startPerception()
        }
        .onDisappear {
            scene.handleScreenDisappear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task {
                    await scene.handleBackground()
                }
            } else if newPhase == .active {
                Task {
                    await scene.handleForeground()
                }
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                if let message = scene.perceptionErrorMessage {
                    Text(message)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: .rect(cornerRadius: 10))
                }
                if scene.isRunningMirrorCheck {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(.orange)
                        Text(String(
                            format: "镜像检测 %.0fs / %.0fs（%d 帧）",
                            min(scene.mirrorCheckElapsed, scene.mirrorCheckTargetDuration),
                            scene.mirrorCheckTargetDuration,
                            scene.mirrorCheckSampleCount
                        ))
                        .monospacedDigit()
                        Button("结束") {
                            scene.stopMirrorCheck()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                }
                if scene.isRunningStabilityTest {
                    HStack(spacing: 8) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .foregroundStyle(.blue)
                        Text(stabilityCapsuleText)
                            .monospacedDigit()
                        Button("结束") {
                            scene.stopStabilityTest()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .overlay {
            if let loadError = scene.loadError {
                Text(loadError)
                    .font(.footnote)
                    .padding(12)
                    .background(.thinMaterial, in: .rect(cornerRadius: 8))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                scene.setDebugPanelPresented(true)
                isShowingDebugPanel = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }
            .padding()
        }
        .navigationDestination(isPresented: $isShowingDebugPanel) {
            AvatarDebugPanel(scene: scene)
        }
        .onChange(of: isShowingDebugPanel) { _, presented in
            scene.setDebugPanelPresented(presented)
        }
        .overlay(alignment: .bottomLeading) {
            if let action = scene.previewAction, scene.loopsPreviewAction {
                HStack(spacing: 8) {
                    Image(systemName: "repeat")
                    Text("循环：\(action.rawValue)")
                    Button("停止") {
                        scene.stopPreview()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding()
            }
        }
        .overlay(alignment: .bottom) {
            if scene.showConversationOverlay {
                ConversationDebugOverlay(scene: scene)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 72)
            }
        }
        .navigationTitle("小瓜")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stabilityCapsuleText: String {
        let clamped = min(scene.stabilityElapsed, scene.stabilityTargetDuration)
        let elapsedMin = Int(clamped) / 60
        let elapsedSec = Int(clamped) % 60
        let targetMin = Int(scene.stabilityTargetDuration) / 60
        let targetSec = Int(scene.stabilityTargetDuration) % 60
        let thermalName = StabilityThermalLevel(scene.thermalState).rawValue
        return String(
            format: "稳定性 %02d:%02d / %02d:%02d · %.1f fps · %.0f MB · %@",
            elapsedMin,
            elapsedSec,
            targetMin,
            targetSec,
            scene.currentFps,
            scene.currentMemoryMB,
            thermalName
        )
    }
}

private struct ConversationDebugOverlay: View {
    let scene: AvatarScene

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(shortStateLabel)
                    .font(.caption.monospaced().weight(.semibold))
                    .lineLimit(1)
                Text("底色:\(scene.currentBaseEmotion.rawValue)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if let held = scene.currentHeldCue {
                    Text("Cue:\(held.emotion.rawValue)\(held.hold ? "(H)" : "")")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    scene.showConversationOverlay = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button("开始说") {
                        scene.injectConversationEvent(.userSpeechStarted)
                    }
                    Button("说完(M_fb)") {
                        scene.injectConversationEvent(.userSpeechEnded)
                    }
                    Button("<user:sad>") {
                        scene.injectConversationEvent(.userEmotion(.sad))
                    }
                    Button("开讲(gentle)") {
                        scene.injectSpeakingStart(emotion: .gentle)
                    }
                    Button("开讲(happy)") {
                        scene.injectSpeakingStart(emotion: .happy)
                    }
                    Button("讲完") {
                        scene.injectConversationEvent(.assistantSpeechEnded)
                    }
                    Button(scene.isSimulatingSpeechMouth ? "停口型" : "口型模拟") {
                        scene.setSimulatingSpeechMouth(!scene.isSimulatingSpeechMouth)
                    }
                    .tint(scene.isSimulatingSpeechMouth ? .orange : .accentColor)
                    Button("Cue:问好(hold)") {
                        scene.injectConversationEvent(.assistantCue(
                            AvatarCue(emotion: .playful, action: .lookAround, hold: true)
                        ))
                    }
                    Button("Cue:茄子(hold)") {
                        scene.injectConversationEvent(.assistantCue(
                            AvatarCue(emotion: .happy, action: .heart, hold: true)
                        ))
                    }
                    Button("结束Cue") {
                        scene.injectConversationEvent(.assistantCueEnded)
                    }
                    Button("重置") {
                        scene.resetConversationState()
                    }
                    .tint(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: .rect(cornerRadius: 12))
    }

    private var shortStateLabel: String {
        switch scene.currentStateKind {
        case .idle: return "idle"
        case .attending: return "attending"
        case .listening: return "listening"
        case .thinking: return "thinking"
        case .speaking(let emotion): return "speaking(\(emotion.rawValue))"
        case .reacting(let r):
            if r.isCue {
                let act = r.action.map { "/\($0.rawValue)" } ?? ""
                return "cue(\(r.expression.rawValue)\(act)\(r.holdsUntilEnded ? ",H" : ""))"
            }
            if let action = r.action {
                return "reacting(\(r.expression.rawValue)/\(action.rawValue))"
            }
            return "reacting(\(r.expression.rawValue))"
        }
    }
}

#Preview {
    NavigationStack {
        AvatarScreen()
            .environment(AppComposition())
    }
}
