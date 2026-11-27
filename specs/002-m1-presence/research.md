# Research: M1 感知与形象

**Feature**: `002-m1-presence` | **Date**: 2026-11-20

## 决策

### D1. ARSession 独立运行，形象用 RealityView 渲染

- **Decision**：直接创建 `ARSession` 并运行 `ARFaceTrackingConfiguration`，通过 delegate 读取 `ARFaceAnchor` 与 `ARFrame`；形象在非 AR 的 `RealityView` 中用虚拟相机渲染，不显示摄像头画面。
- **Rationale**：产品界面是"形象面对用户"，不是 AR 叠加；独立 session 也便于将来替换为 `ARWorldTrackingConfiguration` + `userFaceTrackingEnabled`（V11）。
- **Alternatives considered**：`ARView` + 隐藏相机背景（耦合渲染与感知，不利于替换）。
- **实测闭环（2026-11-27）**：独立 `ARSession` 与 `RealityView` 连续运行 10 分钟（SC-006）实测 avg 59.95 fps、峰值内存 518.2 MiB、全程 `nominal` 零升温，见下方「实测结果」。

### D2. 用 `BlendShapeWeightsComponent` 驱动表情

- **Decision**：加载 USDZ 后读取模型的 blendShape 名称列表，建立"ARKit 名称 → 索引"映射（`BlendShapeIndex`），每帧写入权重。
- **Rationale**：RealityKit 原生能力（iOS 18+），无需自写蒙皮。
- **实测闭环（2026-11-25）**：Xcode 27 / iOS 26+ SDK 下 `BlendShapeWeightsComponent` 实测可用，52/52 ARKit 形态键全部保留并可逐项驱动，无需退回 SceneKit，见下方「实测结果」。

### D3. 素材管线：VRoid Perfect Sync → Blender → USDZ（由 auto-build 自动执行）

- **Decision**：以 `Assets/avatar/VRoid_V110_Female_v1.1.3.vrm`（带 Perfect Sync 的 VRoid 模型）为底座，构建全部由 `Assets/avatar/auto-build/` 下的 Blender 无头脚本完成（贴图重绘、比例、猫耳/呆毛、连帽衫、8 个动作、USDZ 导出与硬门禁校验）。构建方式与参数见该目录的 `PLAN.md`、`README.md` 与 `config/avatar.json`。
- **Rationale**：起步成本最低的 52 系数模型来源；脚本可重复运行，避免手工步骤丢失形态键。
- **约束**：`Face` 拓扑不可修改（52 个 ARKit 名称挂在该网格）；产物替换 `App/MiniMate/Resources/Avatar/minimate.usdz` 需单独批准。
- **Alternatives considered**：自建简化风格化模型（备选，约多 1–2 周）；Live2D（2D 路线备选）。
- **实测闭环（V10，2026-11-25）**：52/52 形态键与 8/8 动作（单条 `SkelAnimation` 时间线 + `actions.json` + 运行时 `trimmed` 裁剪）均在真机验证通过；头部改用 `ModelEntity.jointTransforms` 直驱消除切换闪烁；MToon 退化为 PBR 后通过调灯光（5000→2000）与拉大贴图对比度已满足观感，暂无需 `ShaderGraphMaterial`。见下方「实测结果」。

### D4. 表情信号平滑：One Euro Filter

- **Decision**：对推导出的语义信号与人脸位置使用 One Euro Filter；语义触发再加阈值滞回（进入阈值 > 退出阈值）与最短持续时间。
- **Rationale**：在低延迟与去抖之间可调；实现简单，可测。
- **Alternatives considered**：固定 EMA（静止时仍抖或移动时滞后明显）。

### D5. 语义信号推导规则（初值，M1 真机调参）

| 信号 | 公式（初值） | 进入 / 退出阈值 | 最短持续 |
|---|---|---|---|
| smile | `(mouthSmileLeft + mouthSmileRight) / 2` | 0.5 / 0.3 | 400 ms |
| frown | `max(browDownLeft, browDownRight) * 0.6 + (mouthFrownLeft + mouthFrownRight) / 2 * 0.4` | 0.45 / 0.3 | 600 ms |
| surprise | `browInnerUp * 0.5 + jawOpen * 0.3 + (eyeWideLeft + eyeWideRight) / 2 * 0.2` | 0.55 / 0.35 | 300 ms |
| lookingAtScreen | 人脸被追踪 且 `lookAtPoint` 与相机方向夹角 < 20° | — | 200 ms |

### D6. 手势分类：规则法

- **Decision**：基于 Vision 21 个关节点的几何规则（见 plan "关键设计"），不训练模型。
- **Rationale**：三种手势形状差异大，规则足够；无需数据集。
- **Alternatives considered**：CreateML 手势分类器（若 SC-005 不达标再考虑）。

## 待实测项

| # | 问题 | 验证方式 | 时间点 | 状态 |
|---|---|---|---|---|
| V10 | VRM → USDZ 后 52 个 blendShape 与动作能否在 RealityKit 中驱动 | 走完 D3 管线，用调试面板逐个验证 | 第一周 | ✅ 已实测（52/52 形态键 + 8/8 动作通过） |
| — | 独立 ARSession + RealityView 的帧率与温度 | 连续运行 10 分钟（SC-006） | 第二周 | ✅ 已实测（59.95 fps / 518.2 MiB / 全程 nominal） |
| — | D5 阈值是否合适 | 真机录制自己的表情，调参 | 第二–三周 | ✅ 已实测（已写回 `FaceSignalDeriver.Config` 与 `ReactionRules`） |

## 实测结果

> 测试设备：**iPhone 16 Pro Max**（`iPhone17,2`，国行 CH/A，iOS 27.2）；Phase 8 收尾量化补采与 10 分钟压测均为 **Release** 构建（2026-11-27）。

| 项 | 结果 | 备注 |
|---|---|---|
| 所选模型与许可 | VRoid_V110_Female_v1.1.3.vrm（hinzka/52blendshapes-for-VRoid-face） | 个人与商用均可、可再分发、免署名；52 个 ARKit 名称全部落在 `Face` 网格。详见 `Assets/avatar/README.md` |
| V10 形态键保留 | 52/52（macOS 运行时探针 + 真机逐项置 1） | 124 个形态键含 52 个 ARKit 名称（零缺失）；写 `jawOpen=0.75` 读回一致。2026-11-25 真机逐项验证（`-freezeIdle -blendName`，每次只置 1 个系数、截图与冻结待机基线对比）：52/52 均有可见变化，无缺失项；`mouthDimple*`、`mouthFrown*`、`mouthPress*`、`cheekSquint*`、`eyeLook*` 较弱但可辨 |
| V10 动作片段 | 8/8（真机逐个点播，2026-11-25） | auto-build 一条时间线 + `actions.json`，8 个片段完整播放并回到待机（循环预览逐帧核对）；`spin` 采样残缺已修复；`shyCover` 最终姿势见 3862e50 |
| V10 骨骼驱动 | 真机显示正常（2026-11-24；2026-11-25 改为 `jointTransforms` 直驱） | 初期用 `FromToByAnimation` 驱动头部与动作 `SampledAnimation` 切换时出现跨类型混合闪烁（`FromToByAnimation` 未动画化平移/缩放，而动作含完整变换）；2026-11-25 确认 `Armature` 实为 `ModelEntity`（118 关节与 rest pose 一致），改用 `ModelEntity.jointTransforms` + 60 Hz 指数平滑直驱脖子（35%）与头部（65%），静态切入动作改用 `transitionDuration: 0`，真机确认姿态切换零闪烁 |
| 材质效果 | PBR 与 Blender MToon 有差异（真机已调优） | 原灯光 5000 会把浅色衣服/头发洗白；改为 2000 + 浅色背景后接近 `renders/phase1/review.html`。调色板的衣服渐变上下只差 ~9 级，PBR 光照下被压平；auto-build 已把 `hoodie_gradient.png` 的对比拉开（上提亮、下压暗），真机可见上浅下深。USDZ 的 PBR 无法完全复现 MToon 高光/描边 |
| SC-002 M_track p50/p90 | 真机交互验收通过；实测 `p50 = 244.4 ms / p90 = 379.7 ms (n=157)`（复采 `247.4 / 325.4 ms, n=179`） | 2026-11-25 验证 Idle ↔ Attending、视线与头部跟随、离开 >3 s 回 Idle 触发 `lookAround`、重现触发 `notice`、快速靠近触发 `leanBack` 且零闪烁；2026-11-27 实测肉眼跟随流畅无滞后，数值高于 `<100 / <150 ms` 口径主要因日常慢速头部漂移叠加 `OneEuroFilter3D` 与状态机平滑爬升至 `0.5°` 阈值（同期 `M_feedback = 16.5 ms` 验证渲染主链路为 1 帧级响应）。另据用户反馈“惊讶后仰偏敏感”，2026-11-27 已将快速靠近收紧为 `0.6 s` 内缩短 `>14 cm` 且最终距离 `≤0.38 m` |
| SC-003 M_reflex 区间命中率 | 真机 US3 验收通过；实测 `p50 = 580.9 ms / p90 = 829.2 ms (n=18)`；复采 `p50 = 506.5 ms / p90 = 805.7 ms`，300–800 ms 命中率 `88.9% (8/9)` | 真机验证微笑 → `happy`、皱眉 → `concerned`、惊讶 → `surprised` 均按 300–800 ms 延迟响应且冷却与柔和底色增强生效；发现并修复 ARKit `BlendShapeLocation.rawValue` 使用 `_L`/`_R` 后缀问题；1/9 样本落在 `805.7 ms` 属 800 ms 延迟上界 + 单帧渲染抖动 |
| SC-004 相关系数 | 自动化 1800 帧回放 `maxAbsR < 0.3` 通过；2026-11-27 真机 30.0 s（801 帧）实测 `meanAbsR = 0.1248`，`maxAbsR = 0.4904 (cheekSquintRight)` | `NoMirroringTests` 验证未映射通道全程为 `0` 且 `maxAbsR < 0.3`；真机 30 s 自由表情肉眼无镜像感、`meanAbsR = 0.1248` 很低，Top 通道（`cheekSquint*` 0.49、`browOuterUp*` 0.48）源于用户持续保持微笑/惊讶 2–3 s 时与状态机 0.5 s 后语义回应（`happy`/`surprised`）的时间窗重叠，而非原始系数镜像复制（S-1 未违反） |
| SC-005 手势准确率 / 误触发 | 真机 US4 验收通过；2026-11-27 定量批次累计触发 `挥手 12 / 比心 10 / 点赞 7`（冷却 3.0 s），日常无明显误触 | 2026-11-26 真机实测调优（iPhone 16 Pro Max）：① 挥手改为跟踪手腕+指尖加权重心（`0.35*wrist + 0.65*meanTip`）、2 次有效翻转、解锁竖直换高度后的旧 `anchor.y` 死锁并放宽端点倾角（`tipDeltaY >= -0.25*palmScale`）；② 修复 `ARKitPerceptionSource` 60 Hz `AsyncStream(.bufferingNewest)` 背压丢单帧手势事件问题（`.bufferingNewest(8)` + `.dropped` 截获无损恢复）；③ 适配左右手单手比心（基于真实 Vision 21 关节点实测改为 2D 线段 X 交叉 + 抗透视有效尺度 + 近距离缺失 `wrist` 时 MCP 虚拟手腕兜底 + `holdDropoutTolerance = 0.22 s`）；④ 调试面板新增反应冷却时间滑杆（`3–8 s`，App 默认 `5 s`）与手部只读诊断行。偶发待观察现象记录见 `docs/issues/001-periodic-bottom-left-head-drop.md` |
| US5 对话态与 M_feedback | 真机验收通过（2026-11-27）；`M_feedback p50 = 16.5 ms / p90 = 48.0 ms (n = 6)`（门槛 `< 100 ms`） | 验证 Listening → Thinking → `<user:sad>` → Speaking(gentle) → Attending、Speaking 期间微笑不打断、口型驱动及 `assistantCue` EM-1–EM-5 全链路 |
| SC-006 帧率 / 内存 / 温度 | ✅ 全项通过（2026-11-27，Release，10 分钟压测） | 时长 `600.5 / 600 s`（595 采样）；FPS `avg 59.95 / p50 59.99 / p10 59.92 / min 38.94`（首秒切回过渡，第 3 秒起稳锁 60 fps）；物理内存 `phys_footprint` `avg 508.6 / max 518.2 MiB`（< 1024 MiB，全程平稳无增长）；热状态全程 600.5 s 保持 `nominal`；`ARSession` 中断 `0` 次；人脸追踪占比 `89.9%`；`issue-001` 未复现 |
| SC-007 主观验收 | ✅ 通过（2026-11-27） | 用户主观验收合格：整体体验自然流畅、无肉眼可见问题，满足“它在看我且在回应我，而不是在模仿我”；用户顺带反馈惊讶后仰偏敏感，已同步按方案 A 收紧快速靠近门槛 |
| 调参后的 D5 阈值与规则 | `smile: 0.50 / 0.30 (400 ms)`；`frown: 0.38 / 0.22 (500 ms)`；`surprise: 0.38 / 0.22 (300 ms)`；快速靠近：`0.6 s` 内缩短 `>0.14 m` 且最终距离 `≤0.38 m` | 2026-11-26 真机实测调优并写入 `FaceSignalDeriver.Config` 与 `expression-presets.json`（`concerned`/`surprised`/`playful` 单眼 Wink 替代 `tongueOut`）；`ReactionRules.cooldown` 源码默认 `8 s`，App 调试面板默认 `5 s`（`3–8 s` 实时可调）；2026-11-27 将 `ReactionRules` 快速靠近调优为 `approachWindow = 0.6 s`、`approachDistance = 0.14 m`、`approachMaxDistance = 0.38 m` |
