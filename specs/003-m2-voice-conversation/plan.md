# Implementation Plan: M2 语音对话

**Branch**: `003-m2-voice-conversation` | **Date**: 2026-11-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-m2-voice-conversation/spec.md`

## Summary

分两段实施。**M2a**（第一周）：在 Mac 上用命令行工具 `mm-probe` 验证候选厂商的"实时语音只出文字"、语气理解与情感 TTS，选定厂商与方案。**M2b**：在 App 中实现 `RealtimeTextConversationEngine`——两道收音闸门 → 实时会话（只出文字）→ 标签解析 → 分句 → 情感 TTS → 同一 `AVAudioEngine` 播放（回声消除）→ 打断；输出事件驱动 M1 的情绪状态机。

## Technical Context

**Language/Version**：Swift 6

**Primary Dependencies**：AVFoundation（`AVAudioSession`、`AVAudioEngine`、`AVAudioPlayerNode`、`AVAudioConverter`）、Speech（`SpeechAnalyzer` / `SpeechDetector`，若 001 探测可用）、Foundation（`URLSessionWebSocketTask`、`URLSession` 流式）、ArgumentParser **不引入**（`mm-probe` 用 `CommandLine.arguments` 手工解析）

**Storage**：音频样本与验证结果在 `Assets/voice-samples/`、`specs/003-m2-voice-conversation/research.md`；App 内无持久化（004 负责）

**Testing**：Swift Testing——标签解析、分句、闸门判定、打断判定、事件顺序、厂商协议编解码（用录制的 WebSocket 消息回放）；真机按 quickstart

**Target Platform**：iOS 26+（App）；macOS 26（`mm-probe` 与测试）

**Project Type**：mobile-app + macOS CLI 工具

**Performance Goals**：M_feedback < 100 ms；M_bargein < 300 ms；M_answer 记录基准

**Constraints**：无人声不上传；Key 只在 Keychain（App）或环境变量（`mm-probe`，不写入文件）

**Scale/Scope**：2–3 家厂商适配器（M2a 后只保留选中的一家）；1 个对话引擎实现（方案 C 条件实施）

## Constitution Check

| 原则 | 结论 |
|---|---|
| I. 陪伴而非镜像 | ✅ 对话只输出事件给状态机，不直接驱动渲染 |
| II. 感知在本地 | ✅ 视线软闸门只使用本地感知结果；不上传图像 |
| III. 度量先于假设 | ✅ M2a 先验证 V4–V7 再建全链路；每轮记录分段耗时 |
| IV. 可替换边界 | ✅ `ConversationEngine` 之下再分 `RealtimeTextSession` / `TTSProvider` / `VoiceActivityGate`；厂商细节只在适配器中 |
| V. 纯逻辑可测 | ✅ 解析、分句、闸门、打断、协议编解码均在 macOS 可测 |
| VI. 简单优先 | ⚠️ M2a 期间同时存在 2–3 家适配器——为了对比所必需；选定后删除未选中的适配器 |
| VII. 隐私与密钥 | ✅ 人声闸门、静音开关、Key 不落盘、日志脱敏 |

## Project Structure

### Documentation (this feature)

```text
specs/003-m2-voice-conversation/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── conversation-engine.md
│   ├── tag-protocol.md
│   ├── realtime-session.md
│   ├── tts-provider.md
│   └── audio-gating.md
└── tasks.md
```

### Source Code

```text
Packages/MiniMateKit/
├── Sources/
│   ├── MMAudio/
│   │   ├── AudioSessionController.swift   # iOS：会话配置、中断与路由（#if os(iOS)）
│   │   ├── AudioIO.swift                  # AVAudioEngine：采集（语音处理）+ 播放节点 + 电平
│   │   ├── PCMConverter.swift             # 重采样到厂商格式
│   │   ├── PreRollBuffer.swift            # 环形预缓冲（纯逻辑）
│   │   ├── VoiceActivityGate.swift        # 协议 + EnergyVoiceGate（纯逻辑）
│   │   ├── SpeechDetectorGate.swift       # iOS 26 SpeechDetector 实现（若可用）
│   │   ├── GazeGatePolicy.swift           # 视线软闸门策略（纯逻辑）
│   │   └── BargeInDetector.swift          # 打断判定（纯逻辑）
│   ├── MMConversation/
│   │   ├── ConversationEngine.swift       # 协议
│   │   ├── RealtimeTextConversationEngine.swift
│   │   ├── TagParser.swift                # 流式标签解析（纯逻辑）
│   │   ├── SentenceSplitter.swift         # 流式分句（纯逻辑）
│   │   ├── TurnCoordinator.swift          # 一轮对话的状态与取消（纯逻辑）
│   │   ├── TurnMetrics.swift
│   │   ├── Persona.swift + Resources/persona.md
│   │   ├── Realtime/
│   │   │   ├── RealtimeTextSession.swift  # 协议
│   │   │   ├── QwenOmniRealtimeSession.swift
│   │   │   ├── DoubaoRealtimeSession.swift
│   │   │   └── OpenAIRealtimeSession.swift  # 可选，海外网络
│   │   └── TTS/
│   │       ├── TTSProvider.swift          # 协议
│   │       ├── EmotionMapping.swift       # EmotionTag → 厂商情感参数
│   │       ├── CosyVoiceTTSProvider.swift
│   │       └── DoubaoTTSProvider.swift
│   └── MMProbeCLI/                         # executable: mm-probe（macOS）
│       └── main.swift
└── Tests/
    ├── MMAudioTests/
    └── MMConversationTests/
        └── Fixtures/                      # 录制的 WebSocket 消息（JSON Lines）

App/MiniMate/
├── Screens/AvatarScreen.swift             # 接入对话引擎、静音按钮
└── Screens/Debug/ConversationDebugPanel.swift  # 闸门状态、每轮分段耗时、p50/p90

Assets/voice-samples/                       # 自录样本（.wav），见 quickstart
```

**Structure Decision**：`MMAudio`（设备音频与闸门）与 `MMConversation`（会话、协议、TTS）分开，后者不依赖 iOS-only API，以便 `mm-probe` 在 macOS 上复用同一套适配器。`MMAudio` 中依赖 `AVAudioSession` 的文件用 `#if os(iOS)` 隔离。

### 关键设计

**一轮对话的时序**

```
mic ─▶ AudioIO(voice processing) ─▶ PreRoll ─▶ VoiceGate ──open──▶ session.send(audio)
                                                   │                       │
                                         userSpeechStarted          server VAD: speech_end
                                                                           │ userSpeechEnded (M_feedback 起点为本地闸门检测到的停止发声时刻)
                                                                           ▼
            session.output: textDelta ─▶ TagParser ─▶ (userEmotion | emotion | action | text)
                                                            │ text
                                                            ▼
                                         SentenceSplitter ─▶ Sentence(emotion, actions@offset)
                                                            │
                                         TTS 队列（按句串行请求，最多并发预取 1 句）
                                                            │ audio chunks
                                                            ▼
                                         AudioIO.player ─▶ 扬声器；电平 ─▶ assistantAudioLevel
```

- **TurnCoordinator**：每轮一个 `turnID`；打断或新一轮开始时取消旧 turn 的所有任务（文字流、TTS 请求、播放队列），迟到的事件按 `turnID` 丢弃。
- **端点**：以服务端 VAD 为准触发回答；本地闸门检测到的"停止发声"时刻作为指标起点。
- **首句提速**：分句器首句长度下限 6 字、遇到逗号也可切分；后续句按句号类标点切分，上限 40 字。
- **打断**：播放期间 `BargeInDetector` 使用提高后的阈值（默认 +6 dB），连续 250 ms 判定；服务端的"用户开始说话"事件同样触发打断，取先到者。
- **视线软闸门**：`GazeGatePolicy` 输入 `isLookingAtScreen` / `isFaceTracked` 与时间，输出 `normal` / `raised` / `paused`；`paused` 时关闭实时会话（省流量），恢复时重建会话。
- **断线**：WebSocket 关闭或错误 → 指数退避重连（0.5 / 1 / 2 s），3 次失败后发出 `connectionLost` 事件。

**`mm-probe` 子命令**

| 命令 | 作用 |
|---|---|
| `mm-probe realtime --vendor qwen --input Assets/voice-samples/fine-sad.wav` | 只出文字模式发送音频，打印文字、标签、`speech_end → 首个文字` 耗时 |
| `mm-probe tone-suite --vendor qwen` | 跑全部语气样本组，输出 Markdown 表格 |
| `mm-probe tts --vendor cosyvoice --text "…" --all-emotions --out /tmp/tts` | 每种情绪合成一次，保存 wav，打印首包耗时 |
| `mm-probe record-fixture --vendor qwen --input … --out Tests/…/Fixtures/qwen-basic.jsonl` | 录制 WebSocket 消息作为测试夹具（去除鉴权头） |

Key 通过环境变量传入（如 `MM_QWEN_KEY`），工具不写任何文件到 Key 所在目录。

## Complexity Tracking

| 项 | 为什么需要 | 更简单的替代为何不行 |
|---|---|---|
| M2a 期间多家厂商适配器 | V4–V7 需要横向对比才能选型 | 只试一家无法判断"不满足"是厂商问题还是方案问题 |
| macOS CLI 工具 `mm-probe` | 在接入 App 前低成本验证，并录制测试夹具 | 直接在 App 里验证：迭代慢、难以批量跑语气样本 |
