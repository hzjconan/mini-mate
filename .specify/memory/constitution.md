# MiniMate Constitution

本宪章约束 MiniMate 所有 spec、plan、tasks 与代码。技术细节与选型依据见 `docs/tech-selection.md`（v3.1）。

## Core Principles

### I. 陪伴而非镜像（NON-NEGOTIABLE）

- 形象 MUST NOT 把用户的表情系数直接映射到自己身上。用户的表情、手势、语气只作为**情绪状态机**的输入，由状态机决定形象用它**自己的**表情集、动作和时机回应。
- 唯一允许"跟随"用户的通道是视线（形象看向用户的脸）。
- 任何把感知结果绕过状态机直接驱动渲染的设计，都视为违反本条。

### II. 感知在本地，永不经过 LLM

- 摄像头帧、表情系数、手势、视线 MUST 在端侧处理，MUST NOT 送入任何语言模型。
- 只有用户主动触发的"看图"功能可以上传单帧图片（不在 MVP 范围）。
- 每轮对话都 MUST 有即时的非语言反馈（倾听/思考），不依赖网络。

### III. 度量先于假设

- 文档中标注"需确认"的能力，MUST 在依赖它的任务开始前通过探测或实测验证；验证结果记录到对应 spec 的 `research.md`。
- 关键体验以指标衡量：M_feedback、M_answer、M_reflex、M_track、M_bargein（定义见 `docs/tech-selection.md` 第 6 章）。验收报告 MUST 给出 p50/p90，而不是单次观察。
- 有条件启动的工作（如端侧小脑 M4）MUST 在其门槛指标被实测触发后才开始。

### IV. 可替换边界

- 感知（`PerceptionSource`）、对话（`ConversationEngine`）、渲染（`AvatarRenderer`）三处 MUST 以协议隔离，业务层只依赖协议。
- 云端 URL、Key、鉴权、厂商协议细节 MUST 收敛在 Session / Provider 实现内部，不得散落到业务代码。
- 不做超出当前需要的抽象：只为已经存在、或已列入 spec 的第二种实现建立协议。

### V. 纯逻辑可测（Test-First）

- 不依赖设备的逻辑（情绪状态机、标签解析、分句、收音闸门判定、上下文构建）MUST 放在 Swift Package 中，可在 macOS 上用 `swift test` 运行。
- 上述模块 MUST 先写测试、确认失败，再实现。
- 依赖设备的部分（ARKit、音频会话、RealityKit）以真机验收清单（`quickstart.md`）验证。

### VI. 简单优先

- 不引入重型第三方 SDK；能用系统框架或 `URLSession` 完成的，不加依赖。
- 新增第三方依赖 MUST 在 plan 的 Complexity Tracking 中说明理由，且版本发布满 7 天。
- 不自建后端、不做多厂商路由、不做后台常驻，直到有 spec 明确要求。

### VII. 隐私与密钥

- API Key 只存 iOS Keychain，MUST NOT 出现在仓库、日志或崩溃报告中。
- "一直听"MUST 经过本地人声闸门：没有检测到人声时不向云端发送任何音频。
- 收音状态 MUST 对用户始终可见，且有一步可达的静音方式。

## Additional Constraints

| 项 | 约束 |
|---|---|
| 平台 | iOS 26+，仅 iPhone；参考设备 iPhone 16 Pro Max |
| 语言与工具 | Swift 6（严格并发检查）、SwiftUI、Xcode 26、Swift Testing |
| 签名 | 开发者账号（付费个人会员，约 1 年有效）；App 不声明付费账号独有的 capability，免费账号路径仍可工作 |
| 内存 | App 常驻内存目标 < 1.5 GB（不含系统模型） |
| 对话架构 | 方案 B（实时语音模型只出文字 + 情感 TTS）为主，方案 C 为备选 |
| 分发 | 个人自用，不上架；上架前 MUST 先完成自建后端代理 |

## Development Workflow

1. **流程**：每个里程碑一个 feature 目录 `specs/NNN-name/`，依次产出 `spec.md` → `plan.md`（含 `research.md`、`data-model.md`、`contracts/`、`quickstart.md`）→ `tasks.md`，然后实现。
2. **Constitution Check**：每份 plan MUST 逐条对照本宪章；有违反项须在 Complexity Tracking 中说明，否则不得进入 tasks。
3. **澄清**：spec 中的 `[NEEDS CLARIFICATION]` 项 MUST 在 plan 之前解决，或在 plan 中明确记为风险并给出默认值。
4. **验收**：每个 user story 独立验收；里程碑完成的标准是该 spec 的全部 Success Criteria 达成，并把实测数据写入 `research.md`。
5. **决策回写**：实测推翻了 `docs/tech-selection.md` 中的结论时，MUST 同步修订该文档并在其修订记录中注明。
6. **提交**：每个任务或一组逻辑相关的任务一次提交；提交信息说明"为什么"。

## Governance

- 本宪章优先于其他所有文档与习惯做法。
- 修订本宪章需要：说明修订理由、受影响的 spec/plan、迁移方式，并更新版本号（原则增删为 MAJOR，原则内容调整为 MINOR，措辞修正为 PATCH）。
- 运行期开发指引见 `AGENTS.md`。

**Version**: 1.1.0 | **Ratified**: 2026-11-20 | **Last Amended**: 2026-11-20

**v1.1.0 修订说明**：签名约束由免费 Apple ID 改为付费开发者账号——2026-11-20 真机安装时免费账号设备注册名额已满，购入个人付费会员。受影响：001 的 spec/plan/quickstart/tasks/research 与 docs/tech-selection.md。迁移方式：无代码改动；签名有效期 7 天变为约一年，重签由每周改为到期（或用删除描述文件模拟）；"不使用付费能力"保留为兼容性约束。
