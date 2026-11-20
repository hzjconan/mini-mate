# Implementation Plan: M3 记忆、离线与预置短句

**Branch**: `004-m3-memory-offline` | **Date**: 2026-11-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-m3-memory-offline/spec.md`

## Summary

用 SwiftData 在本地持久化会话、轮次、摘要与长期事实；会话结束后调用同厂商文本模型生成摘要并抽取事实；建立会话时由 `SessionContextBuilder` 在 token 预算内组装上下文。新增 `OfflineConversationEngine`（端侧转写 + 意图匹配 + 预置短句 + 系统 TTS）与在线 / 离线自动切换。预置短句用当前音色批量合成缓存，垫场短句按阈值触发。

## Technical Context

**Language/Version**：Swift 6

**Primary Dependencies**：SwiftData、Speech（`SpeechAnalyzer` / `SpeechTranscriber`，或 `SFSpeechRecognizer` 回退，依 001 V2 结论）、NaturalLanguage（`NLEmbedding`，依 001 结论）、Network（`NWPathMonitor`）、AVFoundation（`AVSpeechSynthesizer`）、003 的 `MMConversation` / `MMAudio`

**Storage**：SwiftData（App 沙盒内）；预合成音频存于 `Application Support/PresetPhrases/<vendor>-<voice>-<catalogVersion>/`

**Testing**：Swift Testing——上下文组装与预算、事实合并、摘要触发策略、意图匹配（关键词层）、垫场策略、在线 / 离线切换状态机；SwiftData 用内存容器测试

**Target Platform**：iOS 26+

**Project Type**：mobile-app

**Performance Goals**：预合成短句播放 < 50 ms；离线指令响应 < 1 s；摘要 < 60 s

**Constraints**：记忆只存本地；摘要请求只发送必要文本

**Scale/Scope**：单用户；预计数千轮 / 数百条事实以内

## Constitution Check

| 原则 | 结论 |
|---|---|
| I. 陪伴而非镜像 | 不涉及 |
| II. 感知在本地 | ✅ 离线模式完全本地 |
| III. 度量先于假设 | ✅ SC-001 以回忆测试量化；垫场以首字耗时阈值触发并统计 |
| IV. 可替换边界 | ✅ 离线引擎实现同一 `ConversationEngine`；文本模型经 `TextLLMProvider` 协议 |
| V. 纯逻辑可测 | ✅ 上下文组装、事实合并、意图匹配、垫场策略、切换逻辑均可在 macOS 测试 |
| VI. 简单优先 | ✅ 不引入向量数据库；事实条目少，全部按类别与时间排序后截断即可 |
| VII. 隐私与密钥 | ✅ 本地存储、可查看可删除可清空 |

无违反项。

## Project Structure

### Documentation (this feature)

```text
specs/004-m3-memory-offline/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── session-context.md
│   ├── memory-extraction.md
│   ├── offline-intents.md
│   └── preset-phrases.md
└── tasks.md
```

### Source Code

```text
Packages/MiniMateKit/Sources/
├── MMMemory/
│   ├── Models/                        # SwiftData @Model：ConversationSession、Turn、SessionSummary、MemoryFact
│   ├── MemoryStore.swift              # 读写、删除、清空
│   ├── TurnRecorder.swift             # 订阅 ConversationEvent，按轮落盘
│   ├── TokenEstimator.swift           # 中文按字估算 token（纯逻辑）
│   ├── SessionContextBuilder.swift    # 预算内组装（纯逻辑）
│   ├── MoodTrend.swift                # 最近 3 次会话语气统计（纯逻辑）
│   ├── FactMerger.swift               # 新旧事实合并（纯逻辑）
│   └── MemoryMaintenance.swift        # 会话结束后摘要 + 抽取，失败重试
├── MMConversation/
│   ├── Text/TextLLMProvider.swift     # 协议 + 选定厂商实现（非流式 JSON 输出）
│   ├── OfflineConversationEngine.swift
│   ├── EngineSwitcher.swift           # 在线 / 离线切换（纯逻辑状态机 + NWPathMonitor 适配）
│   ├── Offline/IntentMatcher.swift    # 关键词层 + NLEmbedding 层
│   ├── Offline/LocalTranscriber.swift # SpeechTranscriber / SFSpeechRecognizer 适配
│   ├── Filler/FillerPolicy.swift      # 垫场触发策略（纯逻辑）
│   ├── Presets/PresetCatalog.swift    # 读取 preset-phrases.json
│   ├── Presets/PresetSynthesizer.swift# 批量合成与失效检测
│   └── Presets/PresetPlayer.swift
└── Resources/
    ├── preset-phrases.json
    └── offline-intents.json

App/MiniMate/Screens/
├── Settings/MemoryView.swift          # 查看 / 删除 / 清空
└── Settings/PresetPhrasesView.swift   # 生成 / 状态 / 试听
```

**Structure Decision**：新增 `MMMemory` target；离线引擎、垫场、预置短句放在 `MMConversation`，因为它们与对话事件、TTS、播放紧密相关。

### 关键设计

**记忆生命周期**

```
ConversationEvent ─▶ TurnRecorder ─▶ Turn（每轮结束落盘）
会话结束 / App 进入后台 / 冷启动发现未摘要会话
        ─▶ MemoryMaintenance ─▶ TextLLMProvider（摘要 + 事实 JSON）─▶ FactMerger ─▶ MemoryStore
建立会话 ─▶ SessionContextBuilder(persona, facts, summaries, moodTrend, budget) ─▶ SessionContext
会话内 ≥ 20 轮 / 断线重连 ─▶ 中间摘要 ─▶ 重建会话（注入：原上下文 + 本会话中间摘要 + 最近 4 轮原文）
```

**在线 / 离线切换（`EngineSwitcher`）**

| 当前 | 事件 | 新状态 |
|---|---|---|
| online | `connectionStateChanged(.lost)` 或 `NWPath.status == .unsatisfied` | offline（播放离线提示） |
| offline | `NWPath.status == .satisfied` | probing（尝试建立实时会话） |
| probing | 建立成功 | online（播放"回来了"反应） |
| probing | 失败 | offline，30 s 后再试 |

切换时保持同一 `AudioIO`（不重启音频引擎），只替换上层引擎。

**意图匹配（离线）**

1. 关键词 / 正则层（`offline-intents.json` 中的 `patterns`）——命中即返回。
2. `NLEmbedding` 层（若 001 结论为可用）：与每个意图的示例句计算余弦距离，最近且距离 < 阈值（初值 0.35，需调）即命中。
3. 都不命中 → `fallback` 意图。

**垫场（`FillerPolicy`）**

- 输入：`userSpeechEnded` 时刻、首个 `assistantText` 时刻、本会话上次垫场的轮次号。
- `userSpeechEnded` 后 1.2 s 仍无文字且距上次垫场 ≥ 3 轮 → 播放 `filler` 类短句（随机，避免与上次相同）。
- 实质回答首句排在垫场短句之后播放。

## Complexity Tracking

无。
