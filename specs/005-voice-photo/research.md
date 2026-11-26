# Research: 语音拍照

**Feature**: `005-voice-photo` | **Date**: 2026-11-26（2026-11-26 按两轮外部评审修订）

## 背景约束

- 前置 TrueDepth 摄像头由 `ARKitPerceptionSource` 的 `ARFaceTrackingConfiguration` 独占；同一摄像头不能同时被 ARKit 与 `AVCaptureSession` 使用。
- 形象由 App 层 `AvatarScreen.swift` 中的 `RealityView`（非 AR，虚拟 `PerspectiveCamera` 与构图参数也在 App 层）渲染，当前没有截图接口。RealityKit 中一个 `Entity` 同一时间只能属于一个场景。
- 摄像头权限文案目前写的是"画面不会保存或上传"（`INFOPLIST_KEY_NSCameraUsageDescription`，工程为 `GENERATE_INFOPLIST_FILE = YES`），须修改（FR-020）。
- 002 `contracts/perception-source.md` P-6 规定"不保存图像"，须在开工前修改（plan.md"对既有契约的修改"）。
- 002 `contracts/emotion-state-machine.md`：`assistantEmotion` 只在 Speaking 状态生效；`assistantAction` 在任意状态可播。`RuleBasedEmotionStateMachine.handle(_ event:)` 目前为空实现（002 US5 未完成）。
- 003 `AudioIO` 只有 `flush()`，打断时清空全部播放队列（B-4）；004 `PresetPlayer` 没有"不可打断"与 `stop()`，且播放时会发出 `assistantEmotion`（PP-3）。

## 决策

### D1. 取帧方式：不中断 ARKit，优先高分辨率抓帧

| 方案 | 做法 | 分辨率 | 追踪中断 | 结论 |
|---|---|---|---|---|
| A | `ARSession.captureHighResolutionFrame(completion:)`（iOS 16+） | 取决于 `recommendedVideoFormatForHighResolutionFrameCapturing` | 预期无 | **首选**，但人脸追踪配置是否支持**需确认**（R1） |
| B | 快门时刻复制下一帧 `ARFrame.capturedImage` | 当前 `videoFormat.imageResolution` | 无 | **兜底**；可在 `supportedVideoFormats` 中选更高分辨率格式（R2） |
| C | 暂停 ARSession → `AVCaptureSession` + `AVCapturePhotoOutput` → 恢复 | 最高 | 预计 > 1 s | **不采用**：违反 FR-010；A、B 的画质都不可接受时才重新评估，且须先修改 spec |

- **Decision**：运行时探测：`recommendedVideoFormatForHighResolutionFrameCapturing != nil` 且 R1 实测追踪中断 ≤ 500 ms → A；否则 B。都在同一 `ARSession` 内完成。
- **快门对齐**：A 以返回帧的 `timestamp` 计算 M_shutter；B 对快门之后到达的第一帧 `capturedImage` 深拷贝一次后立即释放该帧（与现有手势检测的做法一致）。
- **方向**：照片的竖屏、不镜像转换在取帧实现内部完成（D7），输出给拍照流程的已经是最终方向。

### D2. 取景小窗：复用 ARFrame，按需降采样

- **Decision**：只在取景小窗显示时，从 `capturedImage` 以 15 fps（热状态 `serious` 起 10 fps）降采样到约 360 px 宽，经共享 Metal `CIContext` 转为 `CGImage`；小窗关闭立即停止。
- **Rationale**：不需要第二个摄像头会话；`RealityView` 为非 AR 视图，无法直接显示相机背景。
- **Alternatives considered**：`ARView` / `ARSCNView` 相机背景（需要再挂一个 AR 视图绑定同一 session）；`AVCaptureVideoPreviewLayer`（与 ARKit 冲突）。
- **风险**：转换开销 → R3。

### D3. 形象快照：离屏影子实体，静态贴纸兜底

| 方案 | 做法 | 透明背景 | 当前姿态 | 结论 |
|---|---|---|---|---|
| A | RealityKit 离屏渲染（`RealityRenderer`）一个**影子克隆实体**：启动时克隆形象实体放入离屏场景；快门瞬间把在屏实体的骨骼 `jointTransforms`、`BlendShapeWeightsComponent` 与 `HeartEffect` 状态同步到影子实体后渲染一帧 | 预期可以 | ✅ | **首选**；API 可用性、透明通道、同步完整性与耗时**需确认**（R4） |
| B | `UIView.drawHierarchy` 截 `RealityView` 所在视图 | ❌ | ✅ | 不采用：Metal 内容可能截不到，且没有透明通道 |
| C | 随包静态小瓜贴纸 PNG（比心姿势，透明背景） | ✅ | ❌ | **兜底**：A 不可用时使用，US4-3 降级为固定姿态 |

- 不把在屏实体直接加入离屏渲染器（会把形象从 `RealityView` 中移走，违反 AS-2）。
- 虚拟相机与构图参数（视场角、相机位置、取景框）从 `AvatarScreen.swift` 抽到 `MMAvatar` 的 `AvatarFraming`，在屏与离屏共用，保证快照与屏幕上看到的构图一致。
- 快照超时 500 ms 即放弃合影版。

### D4. 指令用独立的 `<cmd:…>` 标签

- **Decision**：新增 `<cmd:photo>`、`<cmd:photoReady>`、`<cmd:photoCancel>`，不复用 `<act:…>`。解析器对每个合法指令都立即发出事件，不在解析层去重或取舍；"同一轮多个指令以最后一个为准"由拍照流程控制器处理（后到的覆盖先到的）。
- **Rationale**：`ActionTag` rawValue 必须与 USDZ 动画名称一致，且 `<act>` 是位置标记；拍照指令要等整段回答播完才执行，语义不同。流式解析器无法预知后面是否还有指令，"只保留最后一个"放在解析层会与"解析到即发出"矛盾。沿用 003 D3"标签写在文字流里"，不引入 function call。
- **Alternatives considered**：function call（各厂商协议不一，宪章 VI）；本地关键词匹配（已选择走云端、说法不限）。

### D5. 拍照短句：优先预合成，同音色；文本由本 feature 自带

- **Decision**：`photo.*` 短句（问句、四拍、提示）的**文本清单**作为本 feature 的资源（`photo-phrases.json`，放在 App target），不依赖 004 的文件是否存在。
  - 004 US3 已完成 → 清单并入 004 预置短句缓存，经 `PresetPlayer` 播放（< 50 ms；需要 004 契约增补：可打断参数、`stop()`、不发出 `assistantEmotion` 的播放选项）。
  - 004 US3 未完成 → App 中的 `CountdownVoiceCache` 在启动且在线时用 003 `TTSProvider` 合成清单，只保存在内存中；收到指令时未就绪则现场合成（耗时单独记录）。
  - 合成失败 → 无声降级：问句改为取景小窗上的文字提示"准备好了吗？说「好了」就开始"，倒数只有动作、表情与数字；`SilentCountdownVoice` 按每条短句的标称时长等待后再返回"播完"，节拍与正常时一致。
- **Rationale**：FR-008 要求同音色；预合成保证节拍准确；文本自带避免对 004 的硬依赖。

### D6. 确认环节："准备好了吗"由 App 问，模型只理解回答

- **Decision**：问句由 App 用 `photo.askReady`（多条轮换）播放；用户回答经 003 进入模型，模型输出 `<cmd:photoReady>` / `<cmd:photoCancel>` 或不输出。再问计时从小瓜每次说完话开始，5 s，最多 5 次（2026-11-26 用户确认）。
- **Rationale**：预置短句零延迟；persona 设定模型不主动开口，"没回答时再问"只能由 App 触发。模型听不到 App 播放的问句，instructions 明确说明"App 会代你问"（R6 验证）。确认环节中 `photo` 与 `photoReady` 等价，提高容错。
- **竞态处理**（评审修订）：
  - 控制器全程跟踪"用户是否正在说话"（`userSpeechStarted` 到 `userSpeechEnded`）与"小瓜是否正在回应"（`assistantSpeechStarted` 到 `assistantSpeechEnded`）；两者任一为真时不启动再问计时。
  - 用户开口时清空本轮已收到但尚未生效的结论（避免 003 E-2"先发新一轮 `userSpeechStarted`、再发旧一轮 `assistantSpeechEnded`"时误用旧结论）。
  - 进入确认环节时若用户没在说话，默认设置等待回应上限（8 s），防止等不到回应时计时器永远为空。
  - 只有播放**完整播完**才算"小瓜说完话"；被停掉的播放不触发再问计时。
- **Alternatives considered**：由模型问（每次再问都要走云端，并且要给模型加主动发言的接口）；本地关键词识别（已选择走云端）。

### D7. 照片方向与镜像

- **Decision**：真实版与合影版均为竖屏、不镜像；取景小窗镜像。转换在 `MMPerception` 的取帧实现内完成（D1）。前置 `capturedImage` 为横向传感器方向，以真机核对为准（R5；Vision 手势检测当前用 `.leftMirrored` 作为镜像竖屏方向，不镜像竖屏的候选为 `.right`）。`PhotoCompositor` 只负责合成与编码。

### D8. 合影版角落选择（纯逻辑）

- **Decision**：人脸框由 Vision `VNDetectFaceRectanglesRequest` 在拍到的照片上检测（覆盖多人），每个外扩 10%。在照片的像素尺寸下计算（归一化坐标必须结合照片宽高比，否则竖屏照片上形象框的高度会被算错）：形象宽 = 照片宽 × 0.30，高 = 形象宽 ÷ 形象宽高比，边距 = 照片宽 × 0.04。按右下 → 左下 → 右上 → 左上取第一个与所有人脸都不重叠的角落；四角都重叠时选重叠面积之和最小的角，并把宽度缩到 20%。
- **Rationale**：纯逻辑，可在 macOS 测试（宪章 V）。

### D9. 写入相册

- **Decision**：`PHPhotoLibrary.requestAuthorization(for: .addOnly)`；一次 `performChanges` 内用两个 `PHAssetCreationRequest` 写入真实版与合影版，每张带明确的格式（HEIC，失败回退 JPEG，`uniformTypeIdentifier` 随数据一起传入），`creationDate` 相同。不建相簿。
- **配置**：工程为 `GENERATE_INFOPLIST_FILE = YES`，在 Debug 与 Release 两套构建设置中新增 `INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription`、修改 `INFOPLIST_KEY_NSCameraUsageDescription`。
- **授权弹窗**：系统授权弹窗只会让 App 进入 `.inactive`，不算"中断"；只有进入后台或音频会话中断才取消拍照。

### D10. 快门音效

- **Decision**：随包自制短音效（程序生成），经 003 `AudioIO` 以拍照专用 turn 播放（同一引擎，享受回声消除）。不使用 `AudioServicesPlaySystemSound`：`.voiceChat` 模式下可能被压低，且不经过同一引擎。

### D11. 倒数中的喊停判定：人声闸门打开期间 + 画面内口型动作

- **Decision**（2026-11-26 用户确认，评审修订）："3""2""1"阶段，满足下列条件即停止倒数，回到确认环节：
  - 人声闸门处于打开状态（`userSpeechStarted` 之后、`userSpeechEnded` 之前），且在此期间任一时刻检测到画面中有人在做说话口型；或
  - 闸门打开时刻之前 0.3 s 内已检测到说话口型（口型先于声音）。
  闸门打开期间一直没有口型 → 视为环境声，倒数继续。持续环境声（电视一直开着、闸门不关）期间，画面内的人一开口就能停止，不会被前面的环境声遮蔽。闸门状态跨"3→2→1"保留。
  无论口型如何，收到 `<cmd:photoCancel>` 都取消。
- **口型判定（纯逻辑，两路独立参数）**：
  | 通道 | 来源 | 频率 | 窗口 | 最少样本 | 判定 |
  |---|---|---|---|---|---|
  | ARKit | 被追踪那张脸的 `jawOpen`（减去 `mouthClose`） | 60 Hz | 0.4 s | 12 | 标准差 ≥ 0.04 且峰谷差 ≥ 0.12 |
  | Vision | 每张脸的内唇开合比（上下内唇距离 ÷ 嘴角宽度） | 12 Hz（`serious` 8 Hz） | 0.5 s | 3 | 标准差 ≥ 0.03 且峰谷差 ≥ 0.10 |
  两路结果取"任一为真"，不做 ARKit 与 Vision 人脸之间的匹配。阈值均为初值，由 R9 实测确定；R9 也评估两路能否合并为一路。热状态 `critical` 时 Vision 通道关闭，只用 ARKit 通道。
- **为什么倒数各拍不可被 003 打断**：003 的插话判定（B-2，连续 250 ms 人声）会先于口型判定把倒数停播，所以倒数各拍以"不可打断"方式播放，是否停止只由拍照流程决定，由拍照流程按 turn 主动取消播放。
- **宪章 I**：口型数据只是拍照流程的输入，不进入情绪状态机、不驱动形象。
- **已知局限**：笑也会被判为说话；嘴被遮挡时检测不到。
- **Alternatives considered**：声纹识别（宪章 VI）；只靠 `<cmd:photoCancel>`（云端约 1 s，来不及）。

### D12. 多人：Vision 检测全部人脸，ARKit 配置不变

- **Decision**：
  - `maximumNumberOfTrackedFaces` 保持 1，不改变 002 已验收的视线与表情行为。
  - 确认环节与倒数期间，以约 12 Hz 对 `capturedImage` 运行 `VNDetectFaceLandmarksRequest`（单飞行），得到全部人脸框与内唇关键点；期间手势检测频率临时设为 0，让出 Vision 算力（避免重现 issue 001 的负载问题），结束后恢复原值。
  - 等人脸阶段（`waitingForFace`）不跑口型检测。"人在画面中"默认只用 ARKit 的 `isFaceTracked`；若 R11 实测 1–1.5 m 多人时 ARKit 不稳定，则在 `isFaceTracked == false` 时改用 Vision 人脸检测兜底（同时手势检测频率设为 0，总算力持平）。
  - 拍到的照片上再运行一次 `VNDetectFaceRectanglesRequest`，用于合影避让。
  - 跨帧人脸关联（trackID，按人脸框 IoU 最近邻匹配）与内唇开合比计算都抽为纯函数，可在 macOS 测试。
- **Alternatives considered**：`maximumNumberOfTrackedFaces = 3`（上限 3 人，且需重新验证 002）。

### D13. 形象提示：新增专用的非对话轮次事件 `assistantCue`

- **Decision**（评审修订）：拍照流程的形象表现不再借用 `assistantEmotion`（它只在 Speaking 状态生效，而问句与倒数时状态机不在 Speaking）。在 `MMCore` 新增：
  - `ConversationEvent.assistantCue(AvatarCue)`：`AvatarCue` 含表情、可选动作、是否保持（`hold`）；
  - `ConversationEvent.assistantCueEnded`：结束当前保持中的提示。
  情绪状态机（002 US5 实现时一并加入）的规则：收到提示 → 以高优先级进入 `.reacting`，**不可被感知反应（表情或手势）打断**，可打断待机与旧的感知反应；新提示替换旧提示；`hold == true` 时保持到下一个提示或 `assistantCueEnded`；期间若进入 Speaking（模型回应），说完后回到保持中的提示。
- **Rationale**：不新增 `AvatarStateKind`，不把"拍照"这种业务概念放进通用的 `MMEmotion`；不改变 003 已有的 `assistantEmotion` 语义。现有"带动作的反应不被纯表情反应打断"的保护只在反应带动作时生效，且反应到期就回到 Attending，因此需要显式的"不可打断 + 保持"语义。
- **影响**：005 Phase 4 前置依赖 002 US5；002 的契约与任务需同步（plan.md"对既有契约的修改"）。

### D14. 拍照期间暂缓并丢弃对话回应的播放

- **问题**：倒数中电视声等环境声虽然不会停止倒数，但仍会上传给模型（以便识别"不拍了"）；模型若对它正常回应，其 TTS 会在"2、1、茄子"之间播出来，并让状态机进入 Speaking。
- **Decision**：003 `ConversationEngine` 新增"暂缓回应"能力：
  - 进入倒数时 `holdReplies()`：之后到达的回应照常解析（指令照常立即发出），但不播放、不发出 `assistantSpeech*` 事件。
  - 倒数因"人声 + 口型"停止 → `releaseReplies(discardingTurnsStartedBefore: 该次语音开始时刻)`：丢弃此前的环境声回应，保留触发停止的那一轮回应（如"好，不急～"）。
  - 倒数因 `<cmd:photoCancel>` 结束 → 同上，以该轮语音开始时刻为界，保留取消确认。
  - 快门完成（或拍照失败）→ `releaseReplies(discardingTurnsStartedBefore: .infinity)`：丢弃倒数与"茄子"阶段的全部回应。
- **对需求的影响**："茄子"阶段跟喊得到的回应不再播放（原 FR-012 为"快门后播放"），倒数中环境声的回应一律丢弃。见 spec FR-012。
- **Alternatives considered**：只在 `AudioIO` 层排队（无法阻止 `assistantSpeechStarted` 让状态机进入 Speaking，也无法区分该丢弃哪一轮）。

### D15. AudioIO：区分"对话打断清队"与"按 turn 强制取消"

- **Decision**：003 `AudioIO.enqueue` 增加 `interruptible` 参数；`flush()`（对话打断 B-4 使用）只清除可打断的缓冲；新增 `cancel(turnID:)`，无论是否可打断都立即停止并移除该 turn 的缓冲。拍照流程的每条短句与快门音效使用各自的 turnID，停止时调用 `cancel(turnID:)`。

### D16. 等待回应超时

- **Decision**：收到 `<cmd:photo>` 后若 8 s 内未收到该轮回应结束（断网等），取消流程并播放 `photo.giveUp`，避免流程卡在"等回应播完"而忽略后续指令。

## 待实测项

| # | 问题 | 验证方式 | 失败时的退路 |
|---|---|---|---|
| R1 | `ARFaceTrackingConfiguration` 是否支持 `captureHighResolutionFrame`；分辨率、耗时、期间 `ARFaceAnchor` 是否丢失 | 调试面板"测试拍照"× 20 次 | D1 方案 B |
| R2 | `supportedVideoFormats` 列表；更高分辨率格式下感知帧率与热状态 | 诊断页打印；高分辨率格式运行 5 分钟 | 保持默认格式 |
| R3 | 取景小窗 15 fps 对感知帧率、形象帧率与 CPU 的影响 | 小窗开 / 关各 30 s | 降到 10 fps / 缩小 |
| R4 | 离屏影子实体：`RealityRenderer` 可用性、透明通道、骨骼 / 形态键 / HeartEffect 同步完整性、单次耗时；在屏帧率不受影响 | 调试面板"测试形象快照"× 10 次（播 `heart` 时） | D3 方案 C |
| R5 | 前置画面竖屏不镜像的正确方向 | 拍带文字的纸 | — |
| R6 | 模型对"拍照请求 vs 只是提到拍照"、确认环节"好了 / 还没 / 不拍了"的区分 | SC-002 / SC-003 / SC-011 | 收紧 instructions；仍不足时给 `ConversationEngine` 增加上下文附加接口（需改 003 契约） |
| R7 | 倒数中"人声 + 口型"到倒数停止的耗时 | 调试面板指标，≥ 10 次 | 调整口型窗口与阈值 |
| R8 | 倒数每拍动作 / 表情搭配；"茄子"时比心姿态能否被快照捕捉 | 真机观察 + 合影版检查 | 调整 `CountdownScript` |
| R9 | 口型判定准确率与两路阈值：说话 / 安静 / 笑 / 只张嘴 | **US1**：单人 0.5 m 与 1–1.5 m 可行性冒烟（每类各 5 次）；有条件时 2 人各 5 次。**US3 / US6**：1–3 人每类 20 次精调，目标"画面内说话"召回 ≥ 90%、"安静 + 环境声"误判 ≤ 10% | 放宽窗口；仍不足时多人场景退回"只认 `<cmd:photoCancel>`"（需改 spec） |
| R10 | 12 Hz `VNDetectFaceLandmarksRequest` + 取景预览同时运行时的感知帧率、形象帧率与热状态（单人） | US1：确认 + 倒数场景连续 30 次 | 降到 8 Hz；只用 ARKit 通道 |
| R11 | 1–1.5 m 距离、偏角时 ARKit `isFaceTracked` 的稳定性（决定 D12 是否需要 Vision 兜底判断"人在画面中"） | US1：单人拉远与侧身各 1 分钟，记录丢失次数；有条件时 2 人 | 启用 Vision 兜底 |

## 实测结果

| 项 | 结果 | 备注 |
|---|---|---|
| R1 高分辨率抓帧是否支持 / 分辨率 / 耗时 / 追踪中断 | 待填 | |
| R2 支持的视频格式 | 待填 | |
| R3 小窗对帧率与 CPU 的影响 | 待填 | |
| R4 离屏影子实体快照 | 待填 | |
| R5 方向 | 待填 | |
| R9 冒烟（US1） / 精调阈值（US3 / US6） | 待填 | |
| R10 Vision 关键点负载 | 待填 | |
| R11 远距 ARKit 追踪稳定性 | 待填 | |
| D1 / D3 / D12 兜底最终方案 | 待填 | |
| SC-002 触发正确数 / 10 | 待填 | |
| SC-003 误触发数 / 20 | 待填 | |
| SC-004 \|M_shutter\| p50 / p90 | 待填 | |
| SC-005 追踪中断最大值 | 待填 | |
| SC-006 取消正确数 / 10；"等一下"回到确认 / 5；"茄子"跟喊照常拍照 / 10 | 待填 | |
| SC-007 合影重叠次数 | 待填 | |
| SC-010 M_photoStart p50 | 待填 | |
| SC-011 "准备好了"开始倒数 / 10；"还没好"误开始 / 10 | 待填 | |
| SC-012 再问间隔与放弃时机 | 待填 | |
| SC-013 画面内喊停停止 / 10；环境声误停 / 10 | 待填 | |
| SC-014 多人合影重叠次数；"你在哪呀"误提示次数 | 待填 | |
