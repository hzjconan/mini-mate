import SwiftUI
import MMCore
import MMAvatar

/// 调试面板：52 个表情系数滑杆 + 动作点播。
struct AvatarDebugPanel: View {
    let scene: PlaceholderAvatarScene

    var body: some View {
        List {
            Section {
                Text("当前为占位形象，只有 jawOpen 会改变嘴部；其余系数等真实模型接入后生效。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("动作") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 8) {
                    ForEach(ActionTag.allCases, id: \.self) { tag in
                        Button(tag.rawValue) {
                            scene.play(tag)
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
