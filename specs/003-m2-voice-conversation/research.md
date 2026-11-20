# Research: M2 语音对话

**Feature**: `003-m2-voice-conversation` | **Date**: 2026-11-20

## 决策

### D1. 对话架构：方案 B，C 备选

- **Decision**：实时语音模型输入音频、只输出文字（含标签）+ 同厂商情感 TTS。
- **Rationale**：同时满足"听得出语气""同一音色 + 情绪变化""标签驱动表情""免唤醒"（tech-selection 4.3）。
- **Alternatives considered**：方案 C（直接出语音：最自然但音色与情绪标签不可控）；方案 A（级联 + ASR 情绪识别：语气理解粗）。

### D2. 端点检测以服务端为准，本地闸门只管"是否上传"

- **Decision**：本地人声闸门决定何时开始/停止推送音频；一句话是否说完由服务端 VAD 判定。
- **Rationale**：服务端 VAD 与模型配套，对停顿的判断更好；本地只需解决隐私与计费。
- **风险**：本地闸门过早关闭会截断尾音 → 闸门关闭有 800 ms 拖尾。

### D3. 标签写在文字流里，而不是用 function call / JSON

- **Decision**：`<user:…>` `<emo:…>` `<act:…>` 行内标签（contracts/tag-protocol.md）。
- **Rationale**：流式下可边收边解析；对所有厂商通用；不依赖 tool calling 的实时支持。
- **Alternatives considered**：tool calling（各家实时接口支持度不一，且会打断文字流）；JSON（无法流式播放）。

### D4. TTS 按句串行，预取 1 句

- **Decision**：句子队列串行合成，当前句播放时预取下一句。
- **Rationale**：保证顺序与情感参数逐句切换；预取掩盖合成延迟；打断时最多浪费 1 句。

### D5. 回声消除：系统语音处理 + 同一引擎播放

- **Decision**：`inputNode.setVoiceProcessingEnabled(true)`，TTS 经 `AVAudioPlayerNode` 在同一 `AVAudioEngine` 播放。
- **Rationale**：系统级 AEC 需要参考信号；同一引擎最稳妥。
- **需确认（V8）**：外放音量较大时的残留回声水平；必要时降低默认音量或在播放期间提高闸门阈值。

## 候选厂商（M2a 验证）

| 厂商 | 实时语音（只出文字） | 情感 TTS（同音色） | 备注 |
|---|---|---|---|
| 阿里百炼 | Qwen-Omni realtime（据了解支持只输出文字，需确认） | CosyVoice（支持情感 / 指令控制，需确认参数） | 首选候选 |
| 火山引擎 | 豆包实时语音（是否支持只出文字需确认） | 豆包"多情感"音色（需确认） | 候选 |
| OpenAI | Realtime（支持只输出文字） | `gpt-4o-mini-tts`（指令控制语气） | 海外网络，备选 |

具体接口地址、消息格式、音频格式以各家最新文档为准，写入 `contracts/realtime-session.md` 的厂商附录。

## 待实测项

| # | 问题 | 验证方式 | 通过标准 |
|---|---|---|---|
| V4 | 实时接口能否只输出文字 | `mm-probe realtime` | 能稳定得到文字流，且无音频输出计费 |
| V5 | 只出文字时是否理解语气 | `mm-probe tone-suite`，3 组 × 3 语气 | ≥ 2 组的 `<user>` 与回答可辨识不同 |
| V6 | 同厂商 TTS 是否有同一音色多情感、首包耗时、是否有时间戳 | `mm-probe tts --all-emotions` | 至少 4 种情绪可辨；首包 < 500 ms |
| V7 | 实时接口是否提供用户输入转写 | 查文档 + 试接 | 有（004 记忆需要）；无则 004 用端侧转写 |
| V8 | 外放下 AEC 效果 | quickstart 第三节 | SC-003 |
| V9 | 视线软闸门过滤电视声 | quickstart 第五节 | SC-007 |
| V3 | `SpeechDetector` 作为人声闸门的误开率 | 安静 / 噪音 / 电视背景各 1 分钟 | 误开率低于能量阈值方案 |

## 语音样本（自录，放在 `Assets/voice-samples/`）

| 文件 | 内容 | 语气 |
|---|---|---|
| `fine-happy.wav` / `fine-flat.wav` / `fine-sad.wav` | "我今天还行吧" | 开心 / 平淡 / 低落 |
| `ok-happy.wav` / `ok-flat.wav` / `ok-sad.wav` | "我没事" | 同上 |
| `done-happy.wav` / `done-tired.wav` / `done-angry.wav` | "终于弄完了" | 开心 / 疲惫 / 生气 |

16 kHz 或 24 kHz、16-bit、单声道。样本含个人声音，`.gitignore` 排除，不提交。

## 实测结果

### M2a 厂商对比

| 厂商 | V4 只出文字 | V5 语气组通过数 | 首个文字耗时 p50 | V6 情绪可辨数 | TTS 首包 p50 | V7 用户转写 | 结论 |
|---|---|---|---|---|---|---|---|
| 阿里百炼 | 待填 | | | | | | |
| 火山引擎 | 待填 | | | | | | |
| OpenAI（可选） | 待填 | | | | | | |

**选型结论**：待填（厂商 + 方案 B/C + 理由）

### M2b 真机指标

| 指标 | 常态 p50 / p90 | 高峰 p50 / p90 | 样本数 |
|---|---|---|---|
| M_feedback | 待填 | | |
| M_answer | 待填 | | |
| 其中：端点判定 | 待填 | | |
| 其中：首个文字 | 待填 | | |
| 其中：首句完成 | 待填 | | |
| 其中：TTS 首包 | 待填 | | |
| M_bargein | 待填 | | |

| 验收项 | 结果 |
|---|---|
| SC-003 自问自答 / 误打断 | 待填 |
| SC-007 电视背景误触发 | 待填 |
| SC-008 静默上传字节数 | 待填 |
| M_answer p50 是否 > 1.5 s（M4 判断依据） | 待填 |
