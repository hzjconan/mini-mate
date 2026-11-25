import Foundation
import Observation
import RealityKit
import SwiftUI
import MMCore
import MMAvatar
import MMEmotion

/// 形象场景：持有渲染器与正面相机，按帧把待机层与调试面板的系数合成 `AvatarPose` 后交给渲染器。
@MainActor
@Observable
final class AvatarScene {
    /// 调试面板写入；每帧会补齐 52 个名称，未设置的按 0 处理。
    var debugWeights: [String: Float] = [:]
    private(set) var playingAction: ActionTag?
    private(set) var loadError: String?
    private(set) var capabilities: AvatarCapabilities?
    /// 调试面板最近点播的动作；返回形象页后仍会循环，方便观察。
    private(set) var previewAction: ActionTag?
    /// 调试面板的循环开关；默认开。
    var loopsPreviewAction = true
    /// 调试预览速度，1 为正常速度。
    var previewSpeed: Float = 1.0

    let root: Entity
    /// `RealityView` 的非 AR 虚拟相机：加入场景时采用这台 `PerspectiveCamera` 的变换。
    let camera = PerspectiveCamera()

    @ObservationIgnored private let renderer: RealityKitAvatarRenderer
    @ObservationIgnored private var idle = IdleMotionLayer()
    @ObservationIgnored private var subscription: EventSubscription?
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
    #endif

    init() {
        let renderer = RealityKitAvatarRenderer()
        self.renderer = renderer
        self.root = renderer.root

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
        let motion = idle.updateNow()

        var weights: [String: Float] = [:]
        for name in BlendShapeIndex.arkitNames {
            weights[name] = debugWeights[name] ?? 0
        }
        // 待机眨眼叠加在表情之上，不会把滑杆调出的闭眼抹掉。
        weights["eyeBlinkLeft"] = max(weights["eyeBlinkLeft"] ?? 0, motion.eyeBlink)
        weights["eyeBlinkRight"] = max(weights["eyeBlinkRight"] ?? 0, motion.eyeBlink)

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

        let action: ActionCommand?
        if pendingStopAction {
            action = .stop
            pendingStopAction = false
        } else {
            action = pendingAction.map { .play($0) }
            pendingAction = nil
        }

        let pose = AvatarPose(
            expressionWeights: weights,
            headRotation: motion.headRotation,
            action: action
        )
        renderer.apply(pose)
        playingAction = renderer.playingAction
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
    @State private var scene = AvatarScene()
    @Environment(\.colorScheme) private var colorScheme

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
        .overlay {
            if let loadError = scene.loadError {
                Text(loadError)
                    .font(.footnote)
                    .padding(12)
                    .background(.thinMaterial, in: .rect(cornerRadius: 8))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            NavigationLink {
                AvatarDebugPanel(scene: scene)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }
            .padding()
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
        .navigationTitle("小瓜")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AvatarScreen()
    }
}
