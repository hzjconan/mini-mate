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

# M2a 厂商验证（Key 只通过环境变量传入）
cd Packages/MiniMateKit && swift run mm-probe tone-suite --vendor qwen
```

App 构建与真机安装在 Xcode 中进行，步骤见 `specs/001-m0-foundation/quickstart.md`。

## 约定

- Swift 6 严格并发；测试用 Swift Testing
- 纯逻辑代码先写测试；依赖设备的部分按各 feature 的 `quickstart.md` 真机验收
- 不引入第三方依赖，除非 plan 的 Complexity Tracking 说明理由
- API Key 只存 Keychain（App）或环境变量（`mm-probe`）；不得写入仓库、日志、测试夹具
- 语音样本（`Assets/voice-samples/*.wav`）含个人声音，不提交
- 实测推翻 `docs/tech-selection.md` 中的结论时，同步修订该文档
