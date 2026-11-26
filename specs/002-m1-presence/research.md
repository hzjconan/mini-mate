# Research: M1 感知与形象

**Feature**: `002-m1-presence` | **Date**: 2026-11-20

## 决策

### D1. ARSession 独立运行，形象用 RealityView 渲染

- **Decision**：直接创建 `ARSession` 并运行 `ARFaceTrackingConfiguration`，通过 delegate 读取 `ARFaceAnchor` 与 `ARFrame`；形象在非 AR 的 `RealityView` 中用虚拟相机渲染，不显示摄像头画面。
- **Rationale**：产品界面是"形象面对用户"，不是 AR 叠加；独立 session 也便于将来替换为 `ARWorldTrackingConfiguration` + `userFaceTrackingEnabled`（V11）。
- **Alternatives considered**：`ARView` + 隐藏相机背景（耦合渲染与感知，不利于替换）。
- **需确认**：独立 `ARSession` 与 `RealityView` 同时运行时的帧率与发热（SC-006）。

### D2. 用 `BlendShapeWeightsComponent` 驱动表情

- **Decision**：加载 USDZ 后读取模型的 blendShape 名称列表，建立"ARKit 名称 → 索引"映射（`BlendShapeIndex`），每帧写入权重。
- **Rationale**：RealityKit 原生能力（iOS 18+），无需自写蒙皮。
- **需确认**：API 细节（`BlendShapeWeightsMapping`、对多网格的支持）以 Xcode 26 SDK 为准；若不可行，退路是 SceneKit `SCNMorpher`（已进入弃用流程，仅作临时方案）。

### D3. 素材管线：VRoid Perfect Sync → Blender → USDZ（由 auto-build 自动执行）

- **Decision**：以 `Assets/avatar/VRoid_V110_Female_v1.1.3.vrm`（带 Perfect Sync 的 VRoid 模型）为底座，构建全部由 `Assets/avatar/auto-build/` 下的 Blender 无头脚本完成（贴图重绘、比例、猫耳/呆毛、连帽衫、8 个动作、USDZ 导出与硬门禁校验）。构建方式与参数见该目录的 `PLAN.md`、`README.md` 与 `config/avatar.json`。
- **Rationale**：起步成本最低的 52 系数模型来源；脚本可重复运行，避免手工步骤丢失形态键。
- **约束**：`Face` 拓扑不可修改（52 个 ARKit 名称挂在该网格）；产物替换 `App/MiniMate/Resources/Avatar/minimate.usdz` 需单独批准。
- **Alternatives considered**：自建简化风格化模型（备选，约多 1–2 周）；Live2D（2D 路线备选）。
- **需确认（V10）**：导出后形态键、骨骼权重、MToon 材质的保留情况。MToon 卡通着色在 USDZ 中会退化为 PBR，可能需要在 RealityKit 中用 `ShaderGraphMaterial` 近似卡通效果。

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

| # | 问题 | 验证方式 | 时间点 |
|---|---|---|---|
| V10 | VRM → USDZ 后 52 个 blendShape 与动作能否在 RealityKit 中驱动 | 走完 D3 管线，用调试面板逐个验证 | 第一周 |
| — | 独立 ARSession + RealityView 的帧率与温度 | 连续运行 10 分钟（SC-006） | 第二周 |
| — | D5 阈值是否合适 | 真机录制自己的表情，调参 | 第二–三周 |

## 实测结果

| 项 | 结果 | 备注 |
|---|---|---|
| 所选模型与许可 | VRoid_V110_Female_v1.1.3.vrm（hinzka/52blendshapes-for-VRoid-face） | 个人与商用均可、可再分发、免署名；52 个 ARKit 名称全部落在 `Face` 网格。详见 `Assets/avatar/README.md` |
| V10 形态键保留 | 52/52（macOS 运行时探针 + 真机逐项置 1） | 124 个形态键含 52 个 ARKit 名称（零缺失）；写 `jawOpen=0.75` 读回一致。2026-11-25 真机逐项验证（`-freezeIdle -blendName`，每次只置 1 个系数、截图与冻结待机基线对比）：52/52 均有可见变化，无缺失项；`mouthDimple*`、`mouthFrown*`、`mouthPress*`、`cheekSquint*`、`eyeLook*` 较弱但可辨 |
| V10 动作片段 | 8/8（真机逐个点播，2026-11-25） | auto-build 一条时间线 + `actions.json`，8 个片段完整播放并回到待机（循环预览逐帧核对）；`spin` 采样残缺已修复；`shyCover` 最终姿势见 3862e50 |
| V10 骨骼驱动 | 真机显示正常（2026-11-24；2026-11-25 改为 `jointTransforms` 直驱） | 初期用 `FromToByAnimation` 驱动头部与动作 `SampledAnimation` 切换时出现跨类型混合闪烁（`FromToByAnimation` 未动画化平移/缩放，而动作含完整变换）；2026-11-25 确认 `Armature` 实为 `ModelEntity`（118 关节与 rest pose 一致），改用 `ModelEntity.jointTransforms` + 60 Hz 指数平滑直驱脖子（35%）与头部（65%），静态切入动作改用 `transitionDuration: 0`，真机确认姿态切换零闪烁 |
| 材质效果 | PBR 与 Blender MToon 有差异（真机已调优） | 原灯光 5000 会把浅色衣服/头发洗白；改为 2000 + 浅色背景后接近 `renders/phase1/review.html`。调色板的衣服渐变上下只差 ~9 级，PBR 光照下被压平；auto-build 已把 `hoodie_gradient.png` 的对比拉开（上提亮、下压暗），真机可见上浅下深。USDZ 的 PBR 无法完全复现 MToon 高光/描边 |
| SC-002 M_track p50/p90 | 真机 US2 验收通过（2026-11-25）；p50/p90 数值待补填 | 真机（iPhone 16 Pro Max）验证 Idle ↔ Attending、视线与头部平滑跟随、离开 >3 s 回 Idle 触发 `lookAround`、重现触发 `notice`、快速靠近（阈值实调为 1 s 内 >10 cm）触发 `leanBack`，且姿态切换无闪烁；`M_track` 精确 p50/p90 毫秒数待从调试面板抄录补齐 |
| SC-003 M_reflex 区间命中率 | 真机 US3 验收通过（2026-11-26）；精确命中率数值待补填 | 真机验证微笑 → `happy`、皱眉 → `concerned`、惊讶 → `surprised` 均按 300–800 ms 延迟响应且 8 s 冷却与柔和底色增强生效；发现并修复 ARKit `BlendShapeLocation.rawValue` 使用 `_L`/`_R` 后缀问题 |
| SC-004 相关系数 | 30 s 自动化回放 `maxAbsCorrelation < 0.3` 通过；真机实测通过（2026-11-26） | `NoMirroringTests` 1800 帧端到端回放（排除 8 个 `eyeLook*` 视线通道）验证未映射通道全程为 `0` 且 `maxAbsCorrelation < 0.3` |
| SC-005 手势准确率 / 误触发 | 待填 | |
| SC-006 帧率 / 内存 / 温度 | 待填 | |
| 调参后的 D5 阈值 | `smile: 0.50 / 0.30 (400 ms)`；`frown: 0.38 / 0.22 (500 ms)`；`surprise: 0.38 / 0.22 (300 ms)` | 2026-11-26 真机实测调优，已同步写入 `FaceSignalDeriver.Config`；同时调优 `expression-presets.json`：`concerned`（`browInnerUp: 0.85, mouthFrown: 0.75, eyeSquint: 0.30, eyeBlink: 0.20, browDown: 0.35`）、`surprised`（`jawOpen: 0.65, eyeWide: 0.90, browOuterUp: 0.66, browInnerUp: 0.50`）、`playful`（改用单眼 Wink `eyeBlinkLeft: 0.90` 替代 `tongueOut` 避免闭嘴穿模） |
