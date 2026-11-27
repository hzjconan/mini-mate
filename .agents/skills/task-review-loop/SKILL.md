---
name: task-review-loop
description: >-
  Run an iterative implementation-and-independent-review loop (up to 5 rounds)
  where an implementer invokes an isolated high-thinking read-only reviewer to
  catch defects and verify root-cause fixes before reporting acceptance to the
  user. Works seamlessly with task-handoff documents or standalone against a
  task spec and git diff. Use this skill whenever a task implementation or
  external-review rework is finished and before reporting acceptance, updating
  task trackers, or committing.
---

# Task Implementation & Independent Review Loop

每个任务实施完成（或按外部评审返工完成）、向用户汇报验收前，执行本闭环（最多 5 轮）。本文件聚焦实施方编排；审查员的完整只读协议、意见分级、双重审查视角、6 类攻击面与 Round 2+ 防漂移规则单源维护于 [references/reviewer-protocol.md](./references/reviewer-protocol.md)（按需参阅 [references/checklists.md](./references/checklists.md)）。

## 第 0 步：项目上下文发现（零配置可用，有约定优先继承）

执行闭环前，先只读核对目标仓库根目录的项目规范文件（`AGENTS.md` / `CLAUDE.md` / `GEMINI.md`），提取并继承：
- **项目红线**：禁读/禁改路径、只读基线保护、禁止审查员执行的写副作用命令；
- **验收门禁命令**：约定的测试、lint、类型检查、构建或只读校验命令（未约定时按技术栈探测）；
- **收口策略**：默认在用户明确确认验收前不 `git commit`、不 `git push`、不勾选任务追踪项、**不提前改写 `HANDOFF_LEDGER.md`**；
- **可选上下文外存**：`CODEBASE_MAP.md`（只认第 0 步识别到的项目规范文件声明路径与默认 `docs/CODEBASE_MAP.md`）与 `HANDOFF_LEDGER.md`（无则跳过）；
- **首选审查模型（纯可选）**：未指定时默认同系列 `High` 档位（不默认升 `XHigh`）。

## 闭环步骤（最多 5 轮）

### 第 1 步：完成实现、自检与留存整树快照 `T_CUR`

1. **按基线完成实现**：有定稿执行单则严格按其范围、不做清单、契约、测试矩阵与偏差止损规则完成代码、测试与附加文档；无执行单则按用户任务与项目规范实现。
2. **跑通完整验收门禁**：运行目标单测、全量测试、lint/类型检查/构建及只读基线校验。
3. **检查仓库干净度**：核查 `git status` / `git diff`，确认无意外改动、无遗留临时文件或空目录、历史只读产物未动，且未提前收口。
4. **留存送审前防篡改整树快照 `T_CUR`（覆盖所有未被 `.gitignore` 忽略的文件与真实暂存区）**：
   - 记录 `git -c core.quotePath=false status --porcelain -uall` 与 `git diff --cached | git hash-object --stdin`；
   - 在**目标仓库目录树之外**创建临时目录计算整树快照 `T_CUR`（严禁放仓内以防临时索引自身被打进快照）：
     ```bash
     TMPD="$(mktemp -d "${TMPDIR:-/tmp}/fish996-snap.XXXXXX")"
     trap 'rm -rf "$TMPD"' EXIT
     REAL_IDX="$(git rev-parse --git-path index)"
     [ -f "$REAL_IDX" ] && cp "$REAL_IDX" "$TMPD/idx"
     T_CUR="$(GIT_INDEX_FILE="$TMPD/idx" git add -A && GIT_INDEX_FILE="$TMPD/idx" git write-tree)"
     ```
     （Windows PowerShell 改用 `$env:GIT_INDEX_FILE` + `Join-Path ([IO.Path]::GetTempPath()) ...` + `try/finally` 清理；注：未忽略的大二进制/数据集会被 `git add -A` 写入松散 blob，宜规范 `.gitignore` 或按需回退只读指纹；若 `.git/objects` 只读导致 `git write-tree` 不可用，自动回退纯只读指纹：`status --porcelain -uall` + `git diff` hash + `git diff --cached` hash + 未跟踪文件逐个 `git hash-object`。）

### 第 2 步：派发独立只读复审（Round 1）

启动**隔离上下文的独立审查员**，严格按以下三级优先级执行（不得越级跳过首选）：
1. **首选 · 单节点高思考审查员（如 Antigravity 的 `swarm`）**：
   - **必须先 `swarm(action="models")` 再 `swarm(action="add", name="reviewer", workspace="inherit", model=...)`**（外部返工轮如 `reviewer-v2`），仅拉起 1 个节点；**严禁**以只读子代理更轻量跳过首选降级到 `invoke_subagent`；
   - **同系列防漂移选型**：`用户本次指定 > 项目规范指定 > 默认同系列 High`；无法确认当前系列时先不传 `model` 拉起并 `status` 核实，再切同系列 `*-high`；
   - 闭环结束后立刻回收（`kill`）该审查节点。
2. **降级 1 · 独立只读子代理（仅无精确模型单节点工具或首选不可用时）**：派发隔离只读子代理；若仅支持粗粒度档位枚举，严禁传 `pro` 等跨系列别名，优先 `inherit` 并在汇报注明降级原因。
3. **降级 2 · 无子代理能力兜底**：汇报中注明原因，由实施方直接阅读并严格按 [references/reviewer-protocol.md](./references/reviewer-protocol.md)（及 `checklists.md`）逐项自查后交用户或外部模型复审。

**发给审查员的 `brief` 必须明文包含以下 4 项**（审查员**无需再读取本 `SKILL.md`**）：
1. **`references/reviewer-protocol.md` 的实际文件路径**（及同目录 `references/checklists.md` 路径），要求严格按该协议执行；
2. **只读红线与项目红线**：禁止修改文件、禁止写盘或改 Git 状态，并列出从项目规范继承的全部红线；
3. **审查目标、快照与可选线索**：目标执行单路径（若有）或任务需求、本轮 `T_CUR` 值、已发现的 `CODEBASE_MAP.md` / `HANDOFF_LEDGER.md` 路径（若有）、本轮改动说明（外部返工附外部意见原文）；
4. **统一输出格式**：按 `reviewer-protocol.md` 第 6 节输出（无问题攻击面 1 行含具体命令或 `file:line` 的硬证据）。

### 第 3 步：核验零修改、严格修复或举证异议

收到复审报告后，**先重算 `T_CUR'`、`git -c core.quotePath=false status --porcelain -uall` 与 `--cached` hash，核验与送审前完全一致（确认所有未被 `.gitignore` 忽略的文件及真实暂存区字节级零修改）**，再逐条核实：
- **认同的阻断项**：根因修复并补确定性回归测试；严禁静默吞错、删测试、放宽断言；涉及改既定契约/扩范围须按偏差止损规则评估或上报；
- **认同的非阻断建议**：仅改动小、低回归风险时顺带修复；较大重构留待后续待办；
- **有异议条目**：整理具体 `file:line`、规范条款或实测输出举证，不得忽略；
- **同步与全量回归**：每次修复后同步清理文档旧表述并重跑全量门禁，严禁拿未过全量门禁的半成品唤醒下一轮复审。

若本轮**阻断项 = 0 且无待审核修复或未决异议**，回收审查节点并跳至第 5 步。

### 第 4 步：提交下一轮复审（Round 2 … 5）

- 记上轮快照为 `T_PREV`，按第 1 步重新计算本轮快照 `T_CUR` 及双保险指纹；
- **优先复用同一审查员会话**（`@reviewer` 续聊），在续审消息中明文提供：① 上轮阻断项逐条修复与 `file:line`；② `T_PREV` 与 `T_CUR` 及本轮申报改动文件清单；③ 最新全量门禁结果与异议证据；
- 若 CLI 不支持续聊则新开审查员，附上上轮问题清单、本轮变动说明与最新验证输出；回到第 3 步循环。

### 终止条件与外部评审返工

满足任一条件即停止并回收审查节点（先核验零修改）：① **一致通过**（阻断项 = 0 且无未决异议）；② **僵局早停**（同一阻断项连续 2 轮未收敛或触发偏差止损，整理卡点交用户裁决）；③ **达到 5 轮上限**。外部评审返工完成后同样执行本闭环（新拉 `reviewer-v2`）。

### 第 5 步：落盘记录、终检与向用户汇报

1. 若本次任务有执行单，将完整复审结果追加写入执行单末尾；
2. **汇报前 3 项一致性终检**：① `git diff --stat` / `git status` 与待汇报改动清单一致；② 未提前勾选任务追踪项、未 `git commit`/`git push`、未提前改写台账；③ 汇报的测试数、校验结果与验证方式与最终代码最后一次实测输出逐字一致；
3. **向用户精简汇报**：闭环结果（轮次、结束原因、实际审查通道/精确模型名/思考等级与降级原因）、每轮问题与处置、未决分歧/僵局卡点、验收实测证据、待审改动清单（标注尚未 commit）；
4. **附「验收收口待办」（当项目启用 `HANDOFF_LEDGER.md` 或涉及 `CODEBASE_MAP.md` 边界变动时）**：在汇报末尾输出可直接落盘的 3–5 行台账增量草稿（未清零非阻断待办、新发现陷阱、近期契约变更与已清零待删项）及地图更新要点，使其留在对话上下文中，待用户明确确认验收进入收口时一并更新落盘后再提交。
