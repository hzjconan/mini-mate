# Feature Specification: M2 语音对话

**Feature Branch**: `003-m2-voice-conversation`

**Created**: 2026-11-20

**Status**: Draft

**Input**: `docs/tech-selection.md` v3.1 第 4.3–4.7 节与第 7 章 M2a/M2b。已确定的需求：免唤醒一直听；听得出语气；同一预置音色并随情绪变化语气；支架外放、短聊。架构为方案 B（实时语音模型只出文字 + 情感 TTS），方案 C 备选。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 确认方案 B 可行并选定厂商 (Priority: P1)

在接入 App 之前，我在 Mac 上用一个命令行工具，把同一句话用三种语气录的音频发给候选厂商的实时语音接口（只输出文字），再把回答用同厂商的情感 TTS 合成出来。我能看到：模型是否听出了语气、回答是否不同、TTS 能否用同一音色说出不同情绪、各环节耗时多少。据此选定厂商，或决定切到方案 C。

**Why this priority**：方案 B 的三个前提（V4–V6）全部是"需确认"。不先验证，后面的工程可能白做。

**Independent Test**：只需 Mac、API Key 和录好的音频样本；不需要 App 与真机。

**Acceptance Scenarios**:

1. **Given** 已配置某厂商 Key 与音频样本，**When** 运行验证工具，**Then** 输出每个样本的回答文字（含标签）、`<user:…>` 值、首个文字输出耗时。
2. **Given** 同一句"我今天还行吧"的开心 / 平淡 / 低落三个录音，**When** 发送，**Then** 三次的 `<user:…>` 不同，且回答内容有可辨识的差异。
3. **Given** 一句回答文字，**When** 用 TTS 按 6 种 `<emo>` 各合成一次，**Then** 得到 6 个同一音色、语气可区分的音频文件，并记录首包耗时。
4. **Given** 至少两家厂商的结果，**When** 汇总，**Then** 在 research.md 中给出选择结论（厂商 + 方案 B/C）及理由。

---

### User Story 2 - 不用唤醒，直接和它说话，它用同一个声音回答 (Priority: P1)

手机立在支架上外放。我看着它直接开口说话，不需要按按钮或说唤醒词；说完后它马上露出思考的神情，然后用它固定的声音回答我。我们可以这样连续聊多轮。

**Why this priority**：这是语音对话的主干闭环。

**Independent Test**：真机 + 网络；按 quickstart 连续对话 10 轮。

**Acceptance Scenarios**:

1. **Given** 形象处于 Attending，**When** 我开口说话，**Then** 形象进入 Listening；我说完后 100 ms 内进入 Thinking（M_feedback）。
2. **Given** 我说完一句话，**When** 回答到达，**Then** 形象用同一音色开口，M_answer 被记录。
3. **Given** 外放播放回答，**When** 回答播放过程中我不说话，**Then** 它自己的声音不会被当成我的输入（不出现自问自答）。
4. **Given** 连续 10 轮对话，**When** 每轮话题相关，**Then** 它能记住本次会话前面说过的内容。
5. **Given** 安静环境中我 30 秒不说话，**When** 观察网络流量，**Then** 没有音频被上传（人声闸门关闭）。

---

### User Story 3 - 它听得出我的语气 (Priority: P1)

我用低落的语气说"我没事"，它不会当真，而是关切地问我怎么了；我开心地说同样的话，它会跟着开心。形象在它开口之前，就先露出对应的神情。

**Why this priority**：用户明确要求；也是选择方案 B 的主要原因。

**Independent Test**：真机按 quickstart 用三种语气说同一句话。

**Acceptance Scenarios**:

1. **Given** 我用低落的语气说"我没事"，**When** 模型回答，**Then** `<user:…>` 为 `sad` / `tired` 等低落类，回答内容带有关切；形象在 Thinking 阶段已切换为关切神情。
2. **Given** 我用开心的语气说同一句话，**When** 模型回答，**Then** `<user:happy>`，回答语气轻快，形象表情开心。
3. **Given** 我脸上平静但语气低落，**When** 状态机合成表情，**Then** 以语气为准（tech-selection 4.2 原则 2）。

---

### User Story 4 - 我可以随时打断它 (Priority: P1)

它说话的时候，我直接开口插话，它会立刻停下来听我说，不会把剩下的话说完。

**Why this priority**：免唤醒对话的基本礼仪；不能打断会让对话很僵硬。

**Independent Test**：真机按 quickstart 在回答播放中插话 10 次。

**Acceptance Scenarios**:

1. **Given** 它正在说一段较长的回答，**When** 我插话，**Then** 它在 300 ms 内停止发声（M_bargein），进入 Listening。
2. **Given** 它已被打断，**When** 我说完新的话，**Then** 它回答新的话，不再继续之前被打断的内容。
3. **Given** 它在说话、我没有插话，**When** 播放过程中只有它自己的声音和轻微环境声，**Then** 不会误判为打断（10 轮中误打断 0 次）。

---

### User Story 5 - 不看屏幕、电视声、静音 (Priority: P2)

我转过头去和别人说话、或者开着电视时，它不会把这些声音当成对它说的话；我也能一步把它静音，静音时它有明确的姿态让我知道它没在听。

**Why this priority**：一直听的必要保护；同时满足宪章 VII。

**Independent Test**：真机按 quickstart 在电视背景声下测试 5 分钟。

**Acceptance Scenarios**:

1. **Given** 电视在播放节目、我不看屏幕，**When** 持续 5 分钟，**Then** 没有触发任何一轮对话。
2. **Given** 我离开画面超过 30 秒，**When** 观察，**Then** 收音暂停、实时会话断开；我回来看向屏幕后自动恢复。
3. **Given** 我点击静音按钮（或做静音手势），**When** 静音期间说话，**Then** 不会触发对话，形象保持"捂耳朵"等明确姿态；再次点击恢复。

---

### User Story 6 - 它说话时，嘴、表情和动作跟着变 (Priority: P2)

它说话时嘴巴随声音开合；每句话的表情与语气一致——说开心的话时笑、说安慰的话时温柔；回答里提到点头、挥手时它会做出动作。我说"笑一个""转个圈"，它会照做。

**Why this priority**：把 M1 的形象和对话连起来；但闭环本身不依赖它。

**Independent Test**：真机按 quickstart 观察 10 轮对话。

**Acceptance Scenarios**:

1. **Given** 它在说话，**When** 观察嘴部，**Then** 开合与声音同步，静音段闭嘴。
2. **Given** 回答中某句带 `<emo:gentle>`，**When** 该句开始播放，**Then** 形象表情与 TTS 语气同时切到温柔。
3. **Given** 我说"转个圈"，**When** 模型输出 `<act:spin>`，**Then** 形象在对应位置转圈。

---

### User Story 7 - 方案 C 备选实现 (Priority: P3，条件触发)

仅当 US1 结论为"方案 B 不可行"时实施：实时语音模型直接输出语音，形象情绪从回答转写文字中由本地推断。

**Why this priority**：备选，不默认实施。

**Independent Test**：同 US2–US4 的验收场景（US6 的情绪标签部分改为本地推断）。

**Acceptance Scenarios**:

1. **Given** 方案 C 已启用，**When** 运行 US2–US4 的 quickstart，**Then** 全部通过。

---

### Edge Cases

- 网络中断或 WebSocket 断开：形象做出"没听清"的姿态，自动重连；重连失败 3 次后提示"网络不太好"并进入离线兜底（离线能力在 004 实现，本 feature 只需提示）。
- 模型输出缺失标签、未知标签、标签被截断在两个数据包之间。
- 一句话特别长、没有标点：分句器按长度上限强制切分。
- 用户说话中途停顿较长，被服务端提前判定为说完。
- TTS 合成失败：跳过该句并继续下一句，形象保持说话表情的自然收尾。
- 蓝牙耳机连接 / 断开导致音频路由变化。
- 来电、闹钟等系统音频中断。
- 用户插话时 TTS 正在合成尚未播放的句子：全部丢弃。

## Requirements *(mandatory)*

### Functional Requirements

**厂商验证（M2a）**

- **FR-001**：仓库 MUST 提供 macOS 命令行验证工具，能把音频文件以流式方式发送到候选厂商的实时接口（只输出文字），输出文字、标签与分段耗时。
- **FR-002**：验证工具 MUST 能调用候选厂商的 TTS，按每种 `EmotionTag` 合成同一句话并保存音频与首包耗时。
- **FR-003**：至少评估两家国内厂商；结论 MUST 写入 research.md（厂商、方案 B/C、理由、实测数据）。

**收音**

- **FR-004**：App MUST 免唤醒持续收音；只有本地人声闸门打开时才向云端发送音频（宪章 VII）。
- **FR-005**：人声闸门打开时 MUST 附带闸门打开前 300–500 ms 的预缓冲音频。
- **FR-006**：视线软闸门 MUST 按 tech-selection 4.4：在看 → 正常阈值；不看超过数秒 → 提高阈值；无人脸超过 30 s → 暂停收音并断开会话；人脸重新出现并看向屏幕 → 自动恢复。
- **FR-007**：App MUST 提供一步可达的静音开关；静音状态下 MUST NOT 上传音频，形象 MUST 显示明确的静音姿态。

**对话**

- **FR-008**：对话引擎 MUST 实现 `ConversationEngine` 协议（contracts/conversation-engine.md），业务层不感知厂商。
- **FR-009**：每次建立会话时 MUST 注入人格设定（persona）与标签协议说明；本 feature 的上下文仅限当前会话（跨会话记忆在 004）。
- **FR-010**：模型输出 MUST 按标签协议解析（contracts/tag-protocol.md），标签 MUST NOT 被送入 TTS。
- **FR-011**：回答 MUST 按句流式送入 TTS；每句使用该句的 `<emo>` 对应的 TTS 情感参数，全程同一音色。
- **FR-012**：`<user:…>` MUST 在 Thinking 阶段转发给情绪状态机。

**音频**

- **FR-013**：音频会话 MUST 使用 `.playAndRecord` + `.voiceChat` + `.defaultToSpeaker`，并开启系统语音处理（回声消除）；TTS 播放 MUST 走同一个 `AVAudioEngine`。
- **FR-014**：播放期间 MUST 持续检测插话；连续检测到人声 ≥ 200–300 ms（播放期间使用提高后的阈值）即判定为打断：立即停播、丢弃待播音频与未完成的文字流、通知服务端取消当前回答。
- **FR-015**：音频中断（来电等）与路由变化 MUST 被处理：中断时暂停会话，结束后恢复。

**形象联动**

- **FR-016**：TTS 播放的音频电平 MUST 以 ≥ 30 Hz 发出 `assistantAudioLevel` 事件驱动口型。
- **FR-017**：`<emo>` 在其后句子开始播放时生效；`<act>` 在其所在文字位置对应的音频播放时触发。

**指标与日志**

- **FR-018**：每轮 MUST 记录 M_feedback、M_answer、M_bargein（若有）及分段耗时（端点、首个文字、首句完成、TTS 首包），可在调试面板查看 p50/p90 并导出。
- **FR-019**：日志 MUST NOT 包含 API Key；用户语音转写只保存在本机。

### Key Entities

- **Persona**：形象的人格设定（名字、性格、说话风格、对用户的称呼、禁忌），作为会话 system prompt 的一部分。
- **AudioChunk**：一段 PCM 音频及时间戳。
- **GateState**：收音闸门当前状态（关闭 / 正常 / 高阈值 / 暂停 / 静音）。
- **RealtimeOutput**：实时会话的输出事件（文字增量、用户转写、端点、回答结束、错误）。
- **TaggedSegment**：解析后的输出单元（文字片段 / 情绪 / 动作 / 用户语气）。
- **Sentence**：送入 TTS 的一句话，带情绪与句内动作位置。
- **TurnMetrics**：一轮对话的各段耗时。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**：research.md 给出厂商与方案结论，包含至少两家国内厂商的 V4–V7 实测数据。
- **SC-002**：语气测试：3 组"同一句话 × 3 种语气"中，至少 2 组的 `<user:…>` 与回答内容可辨识地不同。
- **SC-003**：支架外放连续 10 轮对话，自问自答 0 次、误打断 0 次。
- **SC-004**：M_feedback p50 < 100 ms。
- **SC-005**：M_answer 基准已记录（p50 / p90，常态与高峰各 20 轮以上）。本 feature 不以具体数值为验收门槛；p50 > 1.5 s 时在 research.md 记录，作为 M4 判断依据。
- **SC-006**：插话 10 次，M_bargein p50 < 300 ms，10 次全部成功停止。
- **SC-007**：电视背景声下不看屏幕 5 分钟，误触发对话 0 次。
- **SC-008**：安静环境 1 分钟不说话，上传音频字节数为 0。
- **SC-009**：10 轮对话中，表情与 TTS 语气不一致的句子 ≤ 1 句（主观判断）。

## Assumptions

- 人格设定：名字"小瓜"，呆萌、俏皮、话不多，称呼用户为"你"，每次回答 1–3 句。（2026-11-20 已确认）
- 它不主动开口：只在用户说话后回答；用户回来时只有表情与动作反应，不说话。（2026-11-20 已确认）
- 只支持普通话中文对话。
- 网络为家庭 Wi-Fi 或 5G；本 feature 只做断网提示，不做离线对话（004）。
- 厂商 API 费用由用户自行承担，个人用量下不构成约束。
