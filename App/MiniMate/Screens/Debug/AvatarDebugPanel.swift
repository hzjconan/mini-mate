import SwiftUI
import MMCore
import MMAvatar
import MMEmotion

/// 调试面板：状态与感知、录制导出、指标（M_track）、动作点播与 52 个表情系数滑杆。
struct AvatarDebugPanel: View {
    let scene: AvatarScene

    var body: some View {
        List {
            Section("状态与感知") {
                LabeledContent("状态", value: stateLabel(scene.currentStateKind))
                LabeledContent("人脸追踪", value: scene.isFaceTracked ? "已追踪" : "未追踪")
                LabeledContent("注视屏幕", value: scene.isLookingAtScreen ? "是" : "否")
                LabeledContent("人脸位置 (m)", value: formatPosition(scene.latestFacePosition))
                LabeledContent("头部欧拉角 (°)", value: formatHeadDegrees(scene.latestHeadRotation))
                LabeledContent("视线目标", value: String(format: "(%.2f, %.2f)", scene.latestEyeTarget.x, scene.latestEyeTarget.y))
                if let error = scene.perceptionErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("录制感知") {
                HStack {
                    Button(scene.isRecordingPerception ? "停止录制" : "开始录制") {
                        if scene.isRecordingPerception {
                            scene.stopPerceptionRecording()
                        } else {
                            scene.startPerceptionRecording()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(scene.isRecordingPerception ? .red : .accentColor)

                    Spacer()

                    Text("已录 \(scene.recordedFrameCount) 帧")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if !scene.isRecordingPerception, let jsonLines = scene.lastRecordedJSONLines {
                    ShareLink(item: jsonLines) {
                        Label("导出 JSON Lines", systemImage: "square.and.arrow.up")
                    }
                }

                if scene.recordedFrameCount > 0 || scene.lastRecordedJSONLines != nil {
                    Button("清空录制", role: .destructive) {
                        scene.clearPerceptionRecording()
                    }
                }
            }

            Section("指标（M_track）") {
                let count = scene.latencyRecorder.count(for: "M_track")
                LabeledContent("样本数", value: "\(count)")
                LabeledContent("p50", value: formatMilliseconds(scene.latencyRecorder.p50(for: "M_track")))
                LabeledContent("p90", value: formatMilliseconds(scene.latencyRecorder.p90(for: "M_track")))

                if count > 0 {
                    ShareLink(item: scene.metricsCSV()) {
                        Label("导出指标 CSV", systemImage: "square.and.arrow.up")
                    }
                    Button("清空指标", role: .destructive) {
                        scene.clearMetrics()
                    }
                }
            }

            Section("动作") {
                Toggle(
                    "循环播放（回形象页持续观察）",
                    isOn: Binding(
                        get: { scene.loopsPreviewAction },
                        set: { value in
                            scene.loopsPreviewAction = value
                            if !value {
                                scene.stopPreview()
                            }
                        }
                    )
                )

                Picker(
                    "播放速度",
                    selection: Binding(
                        get: { Double(scene.previewSpeed) },
                        set: { scene.setPreviewSpeed(Float($0)) }
                    )
                ) {
                    Text("1×").tag(1.0)
                    Text("0.5×").tag(0.5)
                    Text("0.25×").tag(0.25)
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 8) {
                    ForEach(ActionTag.allCases, id: \.self) { tag in
                        Button(tag.rawValue) {
                            scene.preview(tag, loop: scene.loopsPreviewAction)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)

                if let playing = scene.playingAction {
                    Text("播放中：\(playing.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("停止动作", role: .destructive) {
                    scene.stopPreview()
                }
            }

            Section("表情系数（\(BlendShapeIndex.arkitNames.count)）") {
                ForEach(BlendShapeIndex.arkitNames, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(name)
                                .font(.caption.monospaced())
                            Spacer()
                            Text(String(format: "%.2f", scene.debugWeights[name] ?? 0))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: binding(for: name), in: 0...1)
                    }
                }
            }

            Section {
                Button("全部归零", role: .destructive) {
                    scene.resetWeights()
                }
            }
        }
        .navigationTitle("调试面板")
    }

    private func binding(for name: String) -> Binding<Double> {
        Binding(
            get: { Double(scene.debugWeights[name] ?? 0) },
            set: { scene.debugWeights[name] = Float($0) }
        )
    }

    private func stateLabel(_ kind: AvatarStateKind) -> String {
        switch kind {
        case .idle: "idle"
        case .attending: "attending"
        case .listening: "listening"
        case .thinking: "thinking"
        case .speaking(let emotion): "speaking(\(emotion.rawValue))"
        case .reacting(let reaction):
            if let action = reaction.action {
                "reacting(\(reaction.expression.rawValue)/\(action.rawValue))"
            } else {
                "reacting(\(reaction.expression.rawValue))"
            }
        }
    }

    private func formatPosition(_ pos: SIMD3<Float>?) -> String {
        guard let pos else { return "—" }
        return String(format: "(%.2f, %.2f, %.2f)", pos.x, pos.y, pos.z)
    }

    private func formatHeadDegrees(_ rad: SIMD3<Float>) -> String {
        let factor: Float = 180 / .pi
        return String(format: "P %.1f / Y %.1f / R %.1f", rad.x * factor, rad.y * factor, rad.z * factor)
    }

    private func formatMilliseconds(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "—" }
        return String(format: "%.1f ms", seconds * 1000)
    }
}
