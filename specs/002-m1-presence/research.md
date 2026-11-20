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

### D3. 素材管线：VRoid Perfect Sync → Blender → USDZ

- **Decision**：
  1. 选一个带 Perfect Sync（52 个 ARKit blendShape）的 VRoid 模型，确认许可允许个人使用与修改；
  2. Blender 中用 VRM 导入插件导入；
  3. 检查形态键名称与 ARKit 名称一致，缺失或命名不同的在 Blender 中重命名；
  4. 制作或导入动作片段（点头、挥手、转圈、比心、害羞、后仰、四处看、注意到你），命名与 `ActionTag` 一致；
  5. 用 Blender USD 导出（勾选形态键与动画）得到 USDZ，必要时用 Reality Converter 检查。
- **Rationale**：起步成本最低的 52 系数模型来源。
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
| 所选模型与许可 | 待填 | |
| V10 形态键保留 | 待填 | |
| V10 动作片段 | 待填 | |
| 材质效果 | 待填 | |
| SC-002 M_track p50/p90 | 待填 | |
| SC-003 M_reflex 区间命中率 | 待填 | |
| SC-004 相关系数 | 待填 | |
| SC-005 手势准确率 / 误触发 | 待填 | |
| SC-006 帧率 / 内存 / 温度 | 待填 | |
| 调参后的 D5 阈值 | 待填 | |
