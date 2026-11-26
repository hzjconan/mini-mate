# Issue 001：静止注视时偶发约每 14–15 秒向左下方低头约 3 秒后回平视

- **状态**：观察中（暂未复现）
- **严重程度**：低（仅偶发观察到一次会话，随后同一构建无法复现；不影响核心手势与注视功能）
- **首次发现**：2026-11-26（iPhone 16 Pro Max，iOS 26+，US4 真机联调末轮）
- **关联任务**：`002-m1-presence` Phase 6 / US4（T039–T043）· [执行单](../handoffs/002-m1-us4-hand-gesture-handoff.md) · [`research.md`](../../specs/002-m1-presence/research.md)
- **相关源码锚点**：
  - `Packages/MiniMateKit/Sources/MMPerception/ARKitPerceptionSource.swift`（12 Hz `VNDetectHumanHandPoseRequest` 后台抽帧 + `ARFaceAnchor` 人脸追踪）
  - `Packages/MiniMateKit/Sources/MMPerception/LookingAtScreenDetector.swift`（20° 注视夹角与 200 ms 判定）
  - `Packages/MiniMateKit/Sources/MMEmotion/RuleBasedEmotionStateMachine.swift`（`idle` 8–14 s `lookAround` 调度、`lostFade`、`attending` 头部与眼球朝向合成）
  - `Packages/MiniMateKit/Sources/MMAvatar/RealityKitAvatarRenderer.swift`（`applyHeadRotation` 与动作切换）

---

## 1. 现象描述与现场线索

- **用户观察**：在主界面（`AvatarScreen`）盯着小瓜一动不动时，人物每隔约 **14–15 秒**，头会自动往**她的左下方**（画面右下方）低下去，大约 **3 秒后**回到平视状态；此前版本似乎未观察到该现象。
- **现场截图 1（低头瞬间，16:15）**：
  - 小瓜双手自然下垂于身体两侧，无微笑/皱眉/害羞等表情变化（自然中性微张嘴）；
  - 头部明显向她的左下方（画面右下方）偏转并低头；
  - **关键细节**：双眼的虹膜（`eyeLookOutLeft` / `eyeLookInRight` + `eyeLookDown*`）同步大幅转向她的左下方（与 `lookAround` 纯骨骼静态渲染图 `lookAround_1.png` 不同，后者眼球居中且几乎不低头）。
- **现场截图 2（低头后切入调试面板，16:28）**：
  - `状态`：`attending`
  - `人脸追踪`：`已追踪`；`注视屏幕`：`是`
  - `语义信号 (笑/皱/惊)`：`0.02 / 0.05 / 0.05`；`激活表情`：`none`
  - `人脸位置 (m)`：`(0.01, -0.03, 0.41)`；`头部欧拉角 (°)`：`P 2.1 / Y 4.7 / R 0.0`；`视线目标`：`(0.15, -0.44)`
  - `检测到手数`：`0`；`最近手势`：`none`；`累计触发 (挥手/比心/点赞)`：`0 / 0 / 0`；`热状态 / 采样率`：`fair · 12 Hz`
- **后续复现尝试**：同一真机安装包在稍后尝试复现时，该现象突然无法复现。

---

## 2. 排查过程与已排除项

按排查顺序逐项核查了以下模块与代码路径：

1. **排查手势误触发（已排除）**：
   - 调试面板显示 `累计触发 (挥手/比心/点赞): 0 / 0 / 0`、`最近手势: none`；且 3 种手势对应动作（`wave`、`heart`、`nod`）均不符合“双手下垂 + 左下方转头低头”，100% 排除。
2. **排查表情语义反应误触发（已排除）**：
   - 调试面板 `语义信号` 全低于 `0.05`、`激活表情: none`；`expression-presets.json` 中除 `.shy`（伴随 `heart` 动作）外均不改头部俯仰/偏航，100% 排除。
3. **排查全项目定时器与动作关键帧（`grep` + 逐行阅读）**：
   - 核查 `IdleMotionLayer.swift`（呼吸周期 4 s、眨眼 2–6 s）、`OneEuroFilter.swift`（无周期逻辑）、`AvatarScreen.swift`（无 14–15 s 定时任务）、`RealityKitAvatarRenderer.swift`（无定时任务）；
   - 核查 `Assets/avatar/auto-build/scripts/avatar_common.py` 中全部 8 个动作关键帧，确认全项目唯一接近 14–15 s 的定时逻辑为 `RuleBasedEmotionStateMachine.swift` 中 `.idle` 状态下的 `nextLookAroundAt = evalTime + lerp(8.0, 14.0, unitRandom())`（单次动作时长 1.45 s，第一拍为向角色左侧转头 + 微低头，随后转向右侧回正）；
   - 核查 `RuleBasedEmotionStateMachine.swift` 姿态合成代码：确认全代码能同时输出大幅左下方头部偏转与左下方眼球注视的通道仅有 `.attending`/`.reacting` 下的 `latestFacePosition` 驱动（`pos.x > 0, pos.y < 0`）。
4. **排查本轮 US4 代码 `git diff main`**：
   - 确认 `ARKitPerceptionSource` 的人脸坐标提取（`viewMatrix * faceWorldPos`）、`OneEuroFilter3D`、`LookingAtScreenDetector`、`FaceSignalDeriver` 均未改动；
   - 本轮唯一在静止注视期间持续后台运行的新增逻辑为 `ARKitPerceptionSource` 内的 12 Hz `VNDetectHumanHandPoseRequest`（独立串行 `gestureQueue` + 单飞行丢帧，仅持有 1 帧 `CVPixelBuffer`）。

---

## 3. 当前核心假设

因当时未能抓到连续逐帧数据，以下两个假设尚待复现时验证：

- **假设 A（`idle` 态 `lookAround` + 切面板瞬间恢复 `attending`）**：
  - 在大屏手机（iPhone 16 Pro Max）上直视屏幕中下部的小瓜时，视线相对顶部 TrueDepth 摄像头的夹角接近或略超 `20°`（`LookingAtScreenDetector` 阈值）；若状态停留在 `.idle`（或短暂丢追踪满 3 s 回 `.idle`），则会每 `8–14 s` 播一次 `lookAround`；而点击右下角调试按钮时视线/手机倾角变化使其在 `200 ms` 内迅速切回 `attending`，导致打开面板时看到的是 `attending`。
  - *待解释点*：纯 `lookAround` 动作不会把眼球大幅推向左下方，且动作时长为 `1.45 s` 而非 `3 s`。
- **假设 B（12 Hz Vision 并发下 ARKit 人脸坐标/追踪偶发瞬态漂移）**：
  - 在特定系统负载/温度（截图 2 为 `fair · 12 Hz`）下，TrueDepth `ARFaceTrackingConfiguration` 与 12 Hz `VNDetectHumanHandPoseRequest` 共享硬件管线时，偶发造成 `ARFaceAnchor.transform` 短暂偏移至 `(+x, -y)` 或追踪帧异常，持续数秒后恢复。

---

## 4. 复现与取证指南（零改代码，直接用内置工具）

若后续真机再次观察到此现象，按以下步骤 **20 秒内即可 100% 锁定根因**：

1. 点击主界面右下角打开 **调试面板**；
2. 在 **「录制感知」** 分区点击 **「开始录制」**，然后返回小瓜主界面；
3. 一动不动盯着小瓜约 **20 秒**，确保完整覆盖至少一次 **“头往左下方低下去 → 约 3 秒后回平视”**；
4. 立刻进入调试面板点击 **「停止录制」→「导出 JSON Lines」**（AirDrop 至 Mac 或保存至仓库外分析）。

### 拿到 JSON Lines 后的 3 秒判别法
逐帧检查低头那 3 秒时间窗口内的以下 3 个字段：
- **`isFaceTracked` 是否出现 `false`**：若连续 `false` ≥ 3 s，说明 ARKit 人脸追踪中断（偏向假设 B / 环境光照）；
- **`isLookingAtScreen` 是否长时间为 `false`**：若 `isFaceTracked == true` 但 `isLookingAtScreen == false`，说明状态卡在 `idle` 触发 `lookAround`（证实假设 A，需评估放宽 `LookingAtScreenDetector` 默认夹角或针对屏幕中心做俯仰偏置）；
- **`facePosition` 是否突然跳变为 `(+x, -y)`**：若 `isFaceTracked == true` 且 `facePosition` 自己飘移，则是 ARKit 锚点瞬态漂移（证实假设 B，可结合关闭 `setGestureRate(0)` 做 A/B 对照验证是否与 Vision 并发有关）。

---

## 5. 后续处置记录

- **2026-11-26**：首次记录并建档；当前无法复现，US4 按期收口，后续若在 Phase 8（SC-006 10 分钟稳定性压测）或日常使用中复现，按第 4 节取证并在此更新结论。
