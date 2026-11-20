# Feature Specification: M1 感知与形象（"它在看我，且在回应我"）

**Feature Branch**: `002-m1-presence`

**Created**: 2026-11-20

**Status**: Draft

**Input**: `docs/tech-selection.md` v3.1 第 4.1、4.2、4.11 节与第 7 章 M1："感知层 + 情绪状态机 v0 + 形象渲染"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 一个能被逐个表情驱动的形象 (Priority: P1)

我打开 App，屏幕上出现一个虚拟形象，它会自然地呼吸、眨眼。在调试面板里，我可以逐个拖动 52 个表情系数，看到形象对应部位的变化，也可以点播每一个动作片段（点头、挥手、转圈等）。

**Why this priority**：素材管线（VRM → USDZ → RealityKit 驱动）是 M1 的第一个技术风险（V10）。不通，后面所有表现都无从谈起。

**Independent Test**：只依赖渲染模块与素材，不需要摄像头。拖动任一系数滑杆，形象对应部位变化；点播动作片段，动作完整播放。

**Acceptance Scenarios**:

1. **Given** App 启动且无人脸，**When** 停留 30 秒，**Then** 形象持续呼吸、随机眨眼、偶尔四处看，没有静止或抖动。
2. **Given** 调试面板打开，**When** 把 `jawOpen` 拖到 1.0，**Then** 形象嘴巴张到最大；其余 51 个系数逐一测试均有可见变化。
3. **Given** 调试面板打开，**When** 点播动作片段列表中的任一项，**Then** 该动作完整播放并平滑回到待机姿态。

---

### User Story 2 - 它在看我 (Priority: P1)

我把手机立在支架上，看向屏幕时，形象会注意到我并把视线转向我；我左右移动，它的视线和头部跟着我；我离开画面，它会四处张望；我回来时，它会再次注意到我。

**Why this priority**：这是"它在看我"体验的唯一来源（tech-selection 第 1 章），成本低、收益最高。

**Independent Test**：仅需感知层 + 状态机 + 渲染，不需要网络。

**Acceptance Scenarios**:

1. **Given** 形象处于 Idle，**When** 我出现在前置摄像头前并看向屏幕，**Then** 形象在 0.5 秒内进入 Attending，视线转向我。
2. **Given** 形象处于 Attending，**When** 我左右移动头部，**Then** 形象视线与头部朝向平滑跟随，跟随延迟（M_track）p50 < 100 ms。
3. **Given** 形象处于 Attending，**When** 我离开画面超过 3 秒，**Then** 形象回到 Idle 并四处张望。
4. **Given** 我离开后重新出现，**When** 被检测到，**Then** 形象做出一次"注意到你"的反应（如轻微抬头、微笑），之后进入 Attending。
5. **Given** 我快速靠近屏幕，**When** 距离在 1 秒内缩短超过 15 cm，**Then** 形象做出轻微后仰或惊讶反应。

---

### User Story 3 - 它用自己的方式回应我的表情 (Priority: P1)

我对它笑，它过一会儿也会笑，但不是照抄我的脸——它有自己的笑法；我皱眉，它会露出关切的神情；我做惊讶的表情，它也会惊讶。它不会每次都同样反应，也不会一直抖动地模仿我。

**Why this priority**：宪章原则 I，产品的核心差异。M1 第一件事就是定下这个行为模式。

**Independent Test**：状态机为纯逻辑，可用录制或合成的表情序列在 macOS 测试；真机上按 quickstart 用真实表情验证。

**Acceptance Scenarios**:

1. **Given** 形象处于 Attending，**When** 我持续微笑 ≥ 0.4 秒，**Then** 形象在 300–800 ms 后用它自己的"开心"表情回应，持续约 1.5 秒后回到 Attending。
2. **Given** 形象刚回应过我的微笑，**When** 我在冷却时间（默认 8 秒）内再次微笑，**Then** 形象不重复同样的回应（可保持轻微愉悦表情）。
3. **Given** 我持续皱眉 ≥ 0.6 秒，**When** 状态机判定为"不开心"，**Then** 形象露出关切神情，而不是皱眉。
4. **Given** 任意时刻，**When** 对比形象与我的 52 维表情系数，**Then** 形象的系数不随我的系数逐帧变化（相关性检测见 SC-004）。

---

### User Story 4 - 它回应我的手势 (Priority: P2)

我对它挥手，它会挥手回应；我比心，它会害羞并回一个比心；我竖大拇指，它会开心地点头。

**Why this priority**：增加互动乐趣，但不是"在看我"的必要条件。

**Independent Test**：手势分类为纯逻辑，可用录制的关节点序列测试；真机按 quickstart 验证。

**Acceptance Scenarios**:

1. **Given** 形象处于 Attending，**When** 我在镜头前挥手 ≥ 2 个来回，**Then** 形象在 1 秒内挥手回应。
2. **Given** 形象处于 Attending，**When** 我双手比心并保持 0.5 秒，**Then** 形象做出害羞 + 比心的反应。
3. **Given** 我竖大拇指并保持 0.5 秒，**When** 被识别，**Then** 形象开心地点头。
4. **Given** 我只是正常抬手或摸脸，**When** 持续 1 分钟，**Then** 不触发任何手势反应（误触发 ≤ 1 次）。

---

### User Story 5 - 状态机覆盖对话阶段（为 M2 预备） (Priority: P3)

我可以在调试面板里模拟对话事件（用户开始/结束说话、助手开始/结束说话、助手情绪与动作标签、用户语气标签），看到形象在 Listening、Thinking、Speaking 之间正确切换。

**Why this priority**：M2 接入对话后直接复用；M1 先把状态与优先级规则做对。

**Independent Test**：纯逻辑测试 + 调试面板手动注入事件。

**Acceptance Scenarios**:

1. **Given** Attending，**When** 注入"用户开始说话"，**Then** 进入 Listening。
2. **Given** Listening，**When** 注入"用户结束说话"，**Then** 在 100 ms 内进入 Thinking（M_feedback）。
3. **Given** Thinking，**When** 注入 `<user:sad>`，**Then** 形象先切换为关切神情，仍保持 Thinking。
4. **Given** Thinking，**When** 注入"助手开始说话"+`<emo:happy>`，**Then** 进入 Speaking(happy)。
5. **Given** Speaking，**When** 同时到达用户微笑事件，**Then** 情绪标签优先，感知反应不打断说话表情。

---

### Edge Cases

- 光线很暗或逆光，ARKit 人脸追踪丢失又恢复（应平滑过渡，不跳变）。
- 画面中出现两个人脸（ARKit 默认只追踪一个；以当前追踪的为准）。
- 用户戴口罩或侧脸，部分表情系数不可信（降低该类反应的触发）。
- 手机温度升高、系统降频（手势检测降到 5 fps 或暂停，人脸追踪优先）。
- App 切到后台再回来（ARSession 中断并恢复，状态机回到 Idle）。
- 摄像头权限被拒绝（形象仍可 Idle，并提示开启权限）。

## Requirements *(mandatory)*

### Functional Requirements

**渲染**

- **FR-001**：App MUST 用 RealityKit 渲染一个带 52 个 ARKit 命名 blendShape 的 3D 形象，并能逐个设置权重。
- **FR-002**：形象 MUST 支持播放命名动作片段，片段集合与 `ActionTag` 枚举一一对应（见 contracts/avatar-renderer.md）。
- **FR-003**：形象 MUST 始终叠加呼吸与眨眼等待机微动作，不受其他状态影响。
- **FR-004**：App MUST 提供调试面板：52 个系数滑杆、动作片段点播、对话事件注入、当前状态与指标显示。

**感知**

- **FR-005**：感知层 MUST 使用 ARKit 人脸追踪（60 fps）输出表情系数、注视方向、人脸位置与距离；MUST NOT 显示摄像头画面。
- **FR-006**：手势检测 MUST 使用 Vision 手部关节点，跑在 `ARFrame.capturedImage` 上，频率限制为 10–15 fps；识别挥手、比心、点赞三种手势。
- **FR-007**：感知层 MUST 输出"是否在看屏幕"信号（供 M2 视线软闸门复用）。
- **FR-008**：感知层 MUST NOT 把任何图像或系数发送到网络（宪章 II）。

**情绪状态机**

- **FR-009**：状态机 MUST 实现 Idle、Attending、Listening、Thinking、Speaking(emotion)、Reacting 六个状态及 contracts/emotion-state-machine.md 中的转换规则。
- **FR-010**：状态机 MUST 是纯逻辑、可注入时钟与随机源，可在 macOS 上测试。
- **FR-011**：对用户表情的回应 MUST 使用形象自己的表情预设，并带 300–800 ms 的随机延迟；同类反应 MUST 有冷却时间。
- **FR-012**：表情信号 MUST 经过时间平滑与阈值滞回，避免抖动。
- **FR-013**：优先级 MUST 为：Speaking 中的情绪标签 > 动作标签 > 感知反应 > 待机微动作。
- **FR-014**：形象的 blendShape 权重 MUST NOT 由用户的系数直接赋值（宪章 I）；视线朝向除外。

**指标**

- **FR-015**：App MUST 记录 M_track、M_reflex、M_feedback（注入事件）的样本，并在调试面板显示 p50/p90，可导出。

### Key Entities

- **PerceptionFeatures**：每帧感知结果（表情系数、注视、位置、距离、是否在看、手势事件、时间戳）。
- **FaceSignals**：由表情系数推导出的平滑语义信号（微笑、皱眉、惊讶强度）。
- **GestureEvent**：识别出的手势（挥手、比心、点赞）及置信度。
- **AvatarState**：状态机当前状态与其上下文（进入时间、当前情绪、冷却表）。
- **AvatarPose**：每帧送给渲染器的形象姿态（自身表情权重、头部与视线朝向、动作片段指令）。
- **ExpressionPreset**：形象自己的表情预设（如"开心""关切""害羞"），由若干 blendShape 权重组成。
- **ActionClip**：命名动作片段。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**：52 个 blendShape 全部可见可驱动；全部动作片段可播放（V10 通过）。
- **SC-002**：M_track p50 < 100 ms、p90 < 150 ms。
- **SC-003**：微笑 → 形象回应的 M_reflex 落在 300–800 ms 区间的样本 ≥ 90%。
- **SC-004**：用户做 30 秒自由表情时，形象与用户同名 blendShape 的逐帧相关系数绝对值 < 0.3（证明不是镜像）。
- **SC-005**：手势识别：每种手势 10 次尝试，正确触发 ≥ 8 次；1 分钟日常动作误触发 ≤ 1 次。
- **SC-006**：连续运行 10 分钟，渲染保持 ≥ 55 fps，App 内存 < 1 GB，无热降频导致的人脸追踪中断。
- **SC-007**：主观验收：在 quickstart 场景下，我的感受是"它在看我，且在回应我"，而不是"它在模仿我"。

## Assumptions

- 形象风格为 3D 二次元（VRoid Perfect Sync 模型）。（2026-11-20 已确认）
- 具体形象素材（哪一个模型、是否自制）在 plan 阶段选定，需满足可个人使用的许可。
- 本 feature 不接入语音与网络；对话相关状态通过调试面板注入事件验证。
- 用户与手机距离约 30–80 cm，手机竖放在支架上。
