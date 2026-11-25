import SwiftUI
import MMCore
import MMAvatar

/// 调试面板：52 个表情系数滑杆 + 动作点播。
struct AvatarDebugPanel: View {
    let scene: AvatarScene

    var body: some View {
        List {
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
}
