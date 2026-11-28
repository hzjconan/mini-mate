# AGENTS.md

## 项目文档

- 项目原则（最高优先级）：`.specify/memory/constitution.md`
- 选型依据：`docs/tech-selection.md`
- 规格 / 计划 / 任务：`specs/`，索引见 `specs/README.md`
- 开发流程：spec → plan（含 research、data-model、contracts、quickstart）→ tasks → 实现；每份 plan 须通过 Constitution Check

## 工程结构（计划，见 `specs/001-m0-foundation/plan.md`）

- `App/MiniMate.xcodeproj`：iOS App，组合根
- `Packages/MiniMateKit`：本地 Swift Package，业务模块（`MMCore`、`MMDiagnostics`、`MMSecurity`、`MMPerception`、`MMEmotion`、`MMAvatar`、`MMAudio`、`MMConversation`、`MMMemory`）与 `mm-probe` 命令行工具

## 常用命令

```bash
# 纯逻辑单元测试（macOS）
cd Packages/MiniMateKit && swift test

# App 模拟器编译验证（无签名，命令行可用）
xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# 包内模块单独按 iOS 编译（验证 #if os(iOS) 分支）
cd Packages/MiniMateKit && xcodebuild -scheme MMDiagnostics \
  -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

# M2a 驱动验证（Key 只通过环境变量传入，--driver 为注册表中的驱动 ID）
cd Packages/MiniMateKit && swift run mm-probe tone-suite --driver <driver-id>
```

App 构建与真机安装在 Xcode 中进行（工程为 objectVersion 77 文件系统同步组，`App/MiniMate/` 下新增文件自动纳入 target），步骤见 `specs/001-m0-foundation/quickstart.md`。签名需在 Xcode 的 Signing & Capabilities 中选择开发者团队（当前为付费个人会员）。

## 约定

- Swift 6 严格并发；测试用 Swift Testing
- 纯逻辑代码先写测试；依赖设备的部分按各 feature 的 `quickstart.md` 真机验收
- 不引入第三方依赖，除非 plan 的 Complexity Tracking 说明理由
- API Key 只存 Keychain（App）或环境变量（`mm-probe`）；不得写入仓库、日志、测试夹具
- **开发 / Debug 隐私红线**：在开发或 debug 期间，模型与工具严禁擅自读取用户配置的其他模型厂商的任何信息（连厂商名称都不行）；若确实需要读取，必须每次先向用户说明原因并获得用户明确同意
- 语音样本（`Assets/voice-samples/*.wav`）含个人声音，不提交
- 实测推翻 `docs/tech-selection.md` 中的结论时，同步修订该文档

<!-- fish-996:task-handoff-rules:begin -->
## 开发工作流约定（Task Handoff & Review Loop）

- **新任务先出执行单**：收到“推进下一步”、规划任务、起草或按审稿意见修改执行单时，必须使用 `task-handoff` skill，在 `docs/handoffs/` 下起草并维护执行单；等用户审阅拍板并完成定稿后，再开始写代码。
- **验收前走独立复审闭环**：每个任务实施完成（或按外部评审返工完成）、向用户汇报验收前，必须使用 `task-review-loop` skill 执行「实现 → 独立只读复审 → 核实修复/举证异议 → 再复审」闭环（最多 5 轮）。
- **收口策略**：在用户明确确认验收前，不得勾选任务清单，不得 `git commit`，不得 `git push`；待用户明确确认验收进入收口时，若项目启用了 `HANDOFF_LEDGER.md`（或需同步 `CODEBASE_MAP.md`），须先一并落盘更新台账与地图后再提交。
<!-- fish-996:task-handoff-rules:end -->

- **高思考模型偏好**： `designer` 优先使用同系列 `XHigh` 档位（如 `gemini-4-neon-xhigh`）。
