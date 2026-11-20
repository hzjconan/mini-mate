# MiniMate Specs

按 GitHub Spec Kit 流程组织：`spec.md`（要什么）→ `plan.md` + `research.md` / `data-model.md` / `contracts/` / `quickstart.md`（怎么做）→ `tasks.md`（做哪些）。项目原则见 [`.specify/memory/constitution.md`](../.specify/memory/constitution.md)，选型依据见 [`docs/tech-selection.md`](../docs/tech-selection.md)。

## 里程碑

| Feature | 里程碑 | 目标 | 状态 | 依赖 |
|---|---|---|---|---|
| [001-m0-foundation](./001-m0-foundation/spec.md) | M0 | 工程基座、免费签名与重签、能力探测（V1–V3）、Keychain | Draft | — |
| [002-m1-presence](./002-m1-presence/spec.md) | M1 | 感知层 + 情绪状态机 + RealityKit 形象："它在看我，且在回应我" | Draft | 001 |
| [003-m2-voice-conversation](./003-m2-voice-conversation/spec.md) | M2 | M2a 厂商验证（方案 B / C）+ M2b 免唤醒语音对话、语气理解、情感 TTS、回声消除与打断 | Draft | 001；US6 依赖 002 |
| [004-m3-memory-offline](./004-m3-memory-offline/spec.md) | M3 | 跨会话记忆、离线模式、预合成短句与垫场、记忆管理 | Draft | 003 |
| — | M4 | 端侧小脑（条件启动：M_answer p50 > 1.5 s 或离线成为痛点） | 未立项 | 003、004 的实测数据 |

002 与 003 可并行（003 的 US1–US5 不依赖形象）。

## 已确认的产品决策（2026-11-20）

| 位置 | 问题 | 结论 |
|---|---|---|
| 002 spec Assumptions | 形象风格 | 3D 二次元（VRoid Perfect Sync） |
| 003 spec Assumptions | 形象的名字、性格、说话风格、对你的称呼 | "小瓜"，呆萌俏皮，话不多，称呼"你"，每次 1–3 句 |
| 003 spec Assumptions | 它是否主动开口 | 不主动开口，只有表情与动作反应 |
| 004 spec Edge Cases | 是否支持用语音让它"忘掉"某事 | 不支持；删除记忆只能在设置 > 记忆中手动操作 |

目前没有待澄清的问题。

## 跨 feature 的共享契约

| 契约 | 定义位置 | 使用方 |
|---|---|---|
| `EmotionTag` / `ActionTag` / `UserEmotion` / `ConversationEvent` | 002 `data-model.md` | 002、003、004 |
| `EmotionStateMachine` | 002 `contracts/emotion-state-machine.md` | 002、003 |
| 标签协议 `<user>` `<emo>` `<act>` | 003 `contracts/tag-protocol.md` | 003、004 |
| `ConversationEngine` / `SessionContext` | 003 `contracts/conversation-engine.md` | 003、004 |
| `TTSProvider` / 情感映射 | 003 `contracts/tts-provider.md` | 003、004（预合成短句） |
| `AudioIO` / 收音闸门 / 打断 | 003 `contracts/audio-gating.md` | 003、004（离线引擎） |
