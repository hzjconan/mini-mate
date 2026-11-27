import SwiftUI
import MMCore
import MMAvatar
import MMEmotion
import MMPerception

/// 调试面板：状态与感知、对话事件注入（US5）、手势与热状态、镜像检测（SC-004）、录制导出、指标（M_track / M_reflex / M_feedback）、表情预设、动作点播与 52 个表情系数滑杆。
struct AvatarDebugPanel: View {
    let scene: AvatarScene

    @State private var selectedAssistantEmotion: EmotionTag = .gentle
    @State private var selectedCueEmotion: EmotionTag = .playful
    @State private var selectedCueAction: ActionTag? = .lookAround
    @State private var cueHold: Bool = true

    var body: some View {
        List {
            Section("状态与感知") {
                LabeledContent("状态", value: stateLabel(scene.currentStateKind))
                LabeledContent("底色情绪", value: scene.currentBaseEmotion.rawValue)
                LabeledContent("保持提示", value: formatHeldCue(scene.currentHeldCue))
                LabeledContent("人脸追踪", value: scene.isFaceTracked ? "已追踪" : "未追踪")
                LabeledContent("注视屏幕", value: scene.isLookingAtScreen ? "是" : "否")
                LabeledContent(
                    "语义信号 (笑/皱/惊)",
                    value: String(
                        format: "%.2f / %.2f / %.2f",
                        scene.latestFaceSignals.smile,
                        scene.latestFaceSignals.frown,
                        scene.latestFaceSignals.surprise
                    )
                )
                LabeledContent(
                    "激活表情",
                    value: scene.latestFaceSignals.activeExpression?.rawValue ?? "none"
                )
                LabeledContent("人脸位置 (m)", value: formatPosition(scene.latestFacePosition))
                LabeledContent("头部欧拉角 (°)", value: formatHeadDegrees(scene.latestHeadRotation))
                LabeledContent("视线目标", value: String(format: "(%.2f, %.2f)", scene.latestEyeTarget.x, scene.latestEyeTarget.y))
                if let error = scene.perceptionErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("对话事件注入（US5）") {
                Toggle(
                    "主界面悬浮对话调试条",
                    isOn: Binding(
                        get: { scene.showConversationOverlay },
                        set: { scene.showConversationOverlay = $0 }
                    )
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                    Button("用户开始说话") {
                        scene.injectConversationEvent(.userSpeechStarted)
                    }
                    Button("用户结束说话（记 M_feedback）") {
                        scene.injectConversationEvent(.userSpeechEnded)
                    }
                    Button("助手开始说话") {
                        scene.injectConversationEvent(.assistantSpeechStarted)
                    }
                    Button("助手结束说话") {
                        scene.injectConversationEvent(.assistantSpeechEnded)
                    }
                    Button("重置回 Idle", role: .destructive) {
                        scene.resetConversationState()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("用户语气 <user:…>（Thinking 态生效）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 6) {
                        ForEach(UserEmotion.allCases, id: \.self) { userEmotion in
                            Button(userEmotionLabel(userEmotion)) {
                                scene.injectConversationEvent(.userEmotion(userEmotion))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Picker("助手情绪 <emo:…>", selection: $selectedAssistantEmotion) {
                        ForEach(EmotionTag.allCases, id: \.self) { emotion in
                            Text("\(emotionLabel(emotion)) (\(emotion.rawValue))").tag(emotion)
                        }
                    }
                    HStack(spacing: 8) {
                        Button("注入 <emo>") {
                            scene.injectConversationEvent(.assistantEmotion(selectedAssistantEmotion))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("开始说话 + 该情绪") {
                            scene.injectSpeakingStart(emotion: selectedAssistantEmotion)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("助手动作 <act:…>（高优先级，不改状态）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 6) {
                        ForEach(ActionTag.allCases, id: \.self) { action in
                            Button(actionLabel(action)) {
                                scene.injectConversationEvent(.assistantAction(action))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("口型电平 (assistantAudioLevel)")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.2f", scene.debugAudioLevel))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(scene.debugAudioLevel) },
                            set: { scene.setDebugAudioLevel(Float($0)) }
                        ),
                        in: 0...1
                    )
                    Toggle(
                        "模拟说话口型（30 Hz）",
                        isOn: Binding(
                            get: { scene.isSimulatingSpeechMouth },
                            set: { scene.setSimulatingSpeechMouth($0) }
                        )
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("形象提示（assistantCue / 005 EM-1–EM-5）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("提示表情", selection: $selectedCueEmotion) {
                        ForEach(EmotionTag.allCases, id: \.self) { emotion in
                            Text("\(emotionLabel(emotion)) (\(emotion.rawValue))").tag(emotion)
                        }
                    }
                    Picker("提示动作", selection: $selectedCueAction) {
                        Text("无动作").tag(Optional<ActionTag>.none)
                        ForEach(ActionTag.allCases, id: \.self) { action in
                            Text("\(actionLabel(action)) (\(action.rawValue))").tag(Optional(action))
                        }
                    }
                    Toggle("持续保持（hold）", isOn: $cueHold)

                    HStack(spacing: 8) {
                        Button("发送 assistantCue") {
                            scene.injectConversationEvent(.assistantCue(
                                AvatarCue(
                                    emotion: selectedCueEmotion,
                                    action: selectedCueAction,
                                    hold: cueHold
                                )
                            ))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("发送 assistantCueEnded") {
                            scene.injectConversationEvent(.assistantCueEnded)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text("005 预设快捷触发")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 6) {
                        Button("问好 playful/lookAround/hold") {
                            scene.injectConversationEvent(.assistantCue(
                                AvatarCue(emotion: .playful, action: .lookAround, hold: true)
                            ))
                        }
                        Button("茄子 happy/heart/hold") {
                            scene.injectConversationEvent(.assistantCue(
                                AvatarCue(emotion: .happy, action: .heart, hold: true)
                            ))
                        }
                        Button("庆祝 happy/spin/单次") {
                            scene.injectConversationEvent(.assistantCue(
                                AvatarCue(emotion: .happy, action: .spin, hold: false)
                            ))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("指令忽略验证（发送 .assistantCommand(.photo)）") {
                    scene.injectConversationEvent(.assistantCommand(.photo))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Section("手势与热状态（US4 / SC-005）") {
                LabeledContent("检测到手数", value: "\(scene.detectedHandCount)")
                LabeledContent("最近手势", value: formatGestureEvent(scene.lastGestureEvent))
                LabeledContent(
                    "累计触发 (挥手/比心/点赞)",
                    value: "\(scene.gestureEventCounts[.wave, default: 0]) / \(scene.gestureEventCounts[.heart, default: 0]) / \(scene.gestureEventCounts[.thumbsUp, default: 0])"
                )
                LabeledContent("热状态 / 采样率", value: formatThermalRate(state: scene.thermalState, rateHz: scene.effectiveGestureRateHz))
                LabeledContent("最近手部诊断", value: formatGestureDiagnostics(scene.lastGestureDiagnostics))
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("反应冷却时间")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.1f s", scene.reactionCooldownSeconds))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { scene.reactionCooldownSeconds },
                            set: { scene.setReactionCooldown($0) }
                        ),
                        in: 3.0...8.0,
                        step: 0.5
                    )
                }
                Button("清零手势计数", role: .destructive) {
                    scene.resetGestureCounters()
                }
                .disabled(scene.lastGestureEvent == nil && scene.gestureEventCounts.isEmpty)
            }

            Section("镜像检测（SC-004，30 s）") {
                HStack {
                    Button(scene.isRunningMirrorCheck ? "停止检测" : "开始 30 s 检测") {
                        if scene.isRunningMirrorCheck {
                            scene.stopMirrorCheck()
                        } else {
                            scene.startMirrorCheck()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(scene.isRunningMirrorCheck ? .red : .accentColor)

                    Spacer()

                    Text(String(
                        format: "%.1fs / %.0fs · %d 帧",
                        scene.mirrorCheckElapsed,
                        scene.mirrorCheckTargetDuration,
                        scene.mirrorCheckSampleCount
                    ))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                }

                if scene.isRunningMirrorCheck {
                    Text("返回主界面，对着小瓜做 30 秒自由表情，完成后自动生成报告。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let report = scene.lastMirrorReport {
                    HStack {
                        Text("判定")
                        Spacer()
                        Text(report.passed ? "通过 (|r| < 0.3)" : "未通过")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                (report.passed ? Color.green : Color.red).opacity(0.18),
                                in: Capsule()
                            )
                            .foregroundStyle(report.passed ? .green : .red)
                    }
                    LabeledContent(
                        "最大 |r|",
                        value: String(
                            format: "%.4f (%@)",
                            report.maxAbsCorrelation,
                            report.maxChannelName ?? "—"
                        )
                    )
                    LabeledContent("平均 |r|", value: String(format: "%.4f", report.meanAbsCorrelation))
                    ForEach(Array(report.topChannels.prefix(3)), id: \.name) { item in
                        LabeledContent(
                            "Top · \(item.name)",
                            value: String(format: "r=%.3f (|r|=%.3f)", item.correlation, item.absCorrelation)
                        )
                    }
                    ShareLink(item: report.summaryText()) {
                        Label("导出镜像检测报告", systemImage: "square.and.arrow.up")
                    }
                    Button("清空检测结果", role: .destructive) {
                        scene.clearMirrorCheck()
                    }
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

            Section("指标（M_track / M_reflex / M_feedback）") {
                let trackCount = scene.latencyRecorder.count(for: "M_track")
                let reflexCount = scene.latencyRecorder.count(for: "M_reflex")
                let feedbackCount = scene.latencyRecorder.count(for: "M_feedback")

                LabeledContent("M_track 样本数", value: "\(trackCount)")
                LabeledContent("M_track p50", value: formatMilliseconds(scene.latencyRecorder.p50(for: "M_track")))
                LabeledContent("M_track p90", value: formatMilliseconds(scene.latencyRecorder.p90(for: "M_track")))

                LabeledContent("M_reflex 样本数", value: "\(reflexCount)")
                LabeledContent("M_reflex p50", value: formatMilliseconds(scene.latencyRecorder.p50(for: "M_reflex")))
                LabeledContent("M_reflex p90", value: formatMilliseconds(scene.latencyRecorder.p90(for: "M_reflex")))
                LabeledContent("M_reflex 300–800 ms 命中率", value: formatReflexHitRate())

                LabeledContent("M_feedback 样本数", value: "\(feedbackCount)")
                LabeledContent("M_feedback p50", value: formatMilliseconds(scene.latencyRecorder.p50(for: "M_feedback")))
                LabeledContent("M_feedback p90", value: formatMilliseconds(scene.latencyRecorder.p90(for: "M_feedback")))

                if trackCount > 0 || reflexCount > 0 || feedbackCount > 0 {
                    ShareLink(item: scene.metricsCSV()) {
                        Label("导出指标 CSV", systemImage: "square.and.arrow.up")
                    }
                    Button("清空指标", role: .destructive) {
                        scene.clearMetrics()
                    }
                }
            }

            Section("表情预设（预览与导出）") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 8) {
                    ForEach(EmotionTag.allCases, id: \.self) { emotion in
                        Button(emotionLabel(emotion)) {
                            scene.applyPresetToDebugWeights(emotion)
                        }
                        .buttonStyle(.bordered)
                        .tint(scene.selectedPresetEmotion == emotion ? .accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)

                Button("还原（回到不做表情状态）") {
                    scene.resetWeights()
                }
                .disabled(scene.selectedPresetEmotion == nil && scene.debugWeights.values.allSatisfy { $0 <= 0.001 })

                if let selected = scene.selectedPresetEmotion,
                   let presetJSON = scene.exportDebugWeightsAsPresetJSON(emotion: selected) {
                    ShareLink(item: presetJSON) {
                        Label("导出「\(emotionLabel(selected))」预设 JSON", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section("表情幅值微调（实时生效）") {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("皱眉 · 眯眼 (eyeSquint)")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.2f", scene.concernedEyeSquint))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(scene.concernedEyeSquint) },
                            set: { scene.setConcernedEyeTuning(squint: Float($0), blink: scene.concernedEyeBlink) }
                        ),
                        in: 0...1
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("皱眉 · 轻闭眼 (eyeBlink)")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.2f", scene.concernedEyeBlink))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(scene.concernedEyeBlink) },
                            set: { scene.setConcernedEyeTuning(squint: scene.concernedEyeSquint, blink: Float($0)) }
                        ),
                        in: 0...0.6
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("惊讶 · 睁大眼 (eyeWide)")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.2f", scene.surprisedEyeWide))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(scene.surprisedEyeWide) },
                            set: { scene.setSurprisedEyeTuning(eyeWide: Float($0), browOuterUp: scene.surprisedBrowOuterUp) }
                        ),
                        in: 0...1
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("惊讶 · 挑眉 (browOuterUp)")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.2f", scene.surprisedBrowOuterUp))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(scene.surprisedBrowOuterUp) },
                            set: { scene.setSurprisedEyeTuning(eyeWide: scene.surprisedEyeWide, browOuterUp: Float($0)) }
                        ),
                        in: 0...1
                    )
                }

                Button("重置微调为当前默认值", role: .destructive) {
                    scene.resetEyeTuning()
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
                        Button(actionLabel(tag)) {
                            scene.preview(tag, loop: scene.loopsPreviewAction)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)

                if let playing = scene.playingAction {
                    Text("播放中：\(actionLabel(playing))")
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

    private func formatReflexHitRate() -> String {
        let samples = scene.latencyRecorder.samples(for: "M_reflex")
        let range: ClosedRange<TimeInterval> = 0.300...0.800
        guard let rate = scene.latencyRecorder.hitRate(in: range, for: "M_reflex"), !samples.isEmpty else {
            return "—"
        }
        let hits = samples.filter { range.contains($0) }.count
        return String(format: "%.1f%% (%d/%d)", rate * 100, hits, samples.count)
    }

    private func emotionLabel(_ emotion: EmotionTag) -> String {
        switch emotion {
        case .happy: "开心"
        case .gentle: "温柔"
        case .sad: "难过"
        case .surprised: "惊讶"
        case .shy: "害羞"
        case .playful: "俏皮"
        case .concerned: "关切"
        case .neutral: "平静"
        }
    }

    private func actionLabel(_ action: ActionTag) -> String {
        switch action {
        case .nod: "点头"
        case .wave: "挥手"
        case .spin: "转圈"
        case .heart: "比心"
        case .shyCover: "害羞遮嘴"
        case .leanBack: "后仰"
        case .lookAround: "张望"
        case .notice: "注意到你"
        }
    }

    private func userEmotionLabel(_ emotion: UserEmotion) -> String {
        switch emotion {
        case .happy: "开心 (happy)"
        case .calm: "平静 (calm)"
        case .sad: "难过 (sad)"
        case .tired: "疲惫 (tired)"
        case .anxious: "焦虑 (anxious)"
        case .angry: "生气 (angry)"
        }
    }

    private func formatHeldCue(_ cue: AvatarCue?) -> String {
        guard let cue else { return "none" }
        let actionPart = cue.action.map { "/\($0.rawValue)" } ?? ""
        return cue.hold ? "\(cue.emotion.rawValue)\(actionPart), hold" : "\(cue.emotion.rawValue)\(actionPart)"
    }

    private func stateLabel(_ kind: AvatarStateKind) -> String {
        switch kind {
        case .idle: return "idle"
        case .attending: return "attending"
        case .listening: return "listening"
        case .thinking: return "thinking"
        case .speaking(let emotion): return "speaking(\(emotion.rawValue))"
        case .reacting(let reaction):
            let actionPart = reaction.action.map { "/\($0.rawValue)" } ?? ""
            if reaction.isCue {
                if reaction.holdsUntilEnded {
                    return "reacting(cue:\(reaction.expression.rawValue)\(actionPart), hold)"
                } else {
                    return "reacting(cue:\(reaction.expression.rawValue)\(actionPart))"
                }
            }
            return "reacting(\(reaction.expression.rawValue)\(actionPart))"
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

    private func formatGestureEvent(_ event: GestureEvent?) -> String {
        guard let event else { return "none" }
        return String(format: "%@ (%.2f)", event.kind.rawValue, event.confidence)
    }

    private func formatThermalRate(state: ProcessInfo.ThermalState, rateHz: Double) -> String {
        let stateName: String = switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
        if rateHz <= 0 {
            return "\(stateName) · 0 Hz (已暂停)"
        }
        return String(format: "%@ · %.0f Hz", stateName, rateHz)
    }

    private func formatGestureDiagnostics(_ d: HandGestureClassifier.DebugSnapshot) -> String {
        guard d.validHandCount > 0 else { return "暂无有效手部帧" }
        let latchText = d.latchedGesture?.rawValue ?? "none"
        return String(
            format: "有效%d手/掌%d · 伸%d指 · ΔX%+.2f ΔY%+.2f · s=%.2f · rev=%d · latch=%@",
            d.validHandCount,
            d.openPalmCount,
            d.maxExtendedFingers,
            d.tipDeltaX,
            d.tipDeltaY,
            d.palmScale,
            d.waveReversalCount,
            latchText
        )
    }
}
