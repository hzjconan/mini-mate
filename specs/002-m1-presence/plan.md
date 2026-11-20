# Implementation Plan: M1 感知与形象

**Branch**: `002-m1-presence` | **Date**: 2026-11-20 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-m1-presence/spec.md`

## Summary

用 ARKit 人脸追踪 + Vision 手势构建感知层，输出平滑后的语义信号；用纯逻辑的情绪状态机把感知与（模拟的）对话事件转为形象自己的姿态；用 RealityKit 渲染一个带 52 个 blendShape 的 VRoid 模型。第一周先打通素材管线（V10），再做"在看我"（视线跟随），最后做表情与手势回应。

## Technical Context

**Language/Version**：Swift 6

**Primary Dependencies**：ARKit（`ARSession` + `ARFaceTrackingConfiguration`，不使用 `ARView`）、Vision（`VNDetectHumanHandPoseRequest`）、RealityKit（`RealityView`、`BlendShapeWeightsComponent`、动画资源）、SwiftUI；素材工具链：VRoid Studio、Blender（含 VRM 导入插件）、Reality Converter（可选）

**Storage**：素材以 USDZ 打包进 App bundle；指标样本仅内存 + 导出

**Testing**：Swift Testing（状态机、平滑器、信号推导、手势分类、指标统计）；真机按 quickstart 验收

**Target Platform**：iOS 26+

**Project Type**：mobile-app

**Performance Goals**：渲染 60 fps；人脸追踪 60 fps；手势 10–15 fps；M_track p50 < 100 ms

**Constraints**：不显示摄像头画面；感知数据不出设备；App 内存 < 1 GB

**Scale/Scope**：1 个形象、约 8 个表情预设、约 8 个动作片段、6 个状态

## Constitution Check

| 原则 | 结论 |
|---|---|
| I. 陪伴而非镜像 | ✅ 状态机只输出形象自己的预设；用户系数不直接进入 `AvatarPose`（视线除外）；SC-004 以相关系数验证 |
| II. 感知在本地 | ✅ 感知模块无网络依赖；不显示也不保存图像 |
| III. 度量先于假设 | ✅ V10 第一周验证；M_track / M_reflex 有记录与导出 |
| IV. 可替换边界 | ✅ `PerceptionSource`、`EmotionStateMachine`、`AvatarRenderer` 三个协议（contracts/） |
| V. 纯逻辑可测 | ✅ `MMEmotion` 与信号推导、手势分类不依赖设备，测试先行 |
| VI. 简单优先 | ✅ 无第三方运行时依赖；素材工具只在开发机使用 |
| VII. 隐私与密钥 | ✅ 不涉及网络 |

无违反项。

## Project Structure

### Documentation (this feature)

```text
specs/002-m1-presence/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── perception-source.md
│   ├── emotion-state-machine.md
│   └── avatar-renderer.md
└── tasks.md
```

### Source Code

```text
Packages/MiniMateKit/Sources/
├── MMCore/
│   ├── EmotionTag.swift            # 形象情绪枚举（M2 标签复用）
│   ├── ActionTag.swift             # 动作枚举
│   ├── UserEmotion.swift           # 用户语气枚举（M2 标签复用）
│   ├── ConversationEvent.swift     # 对话事件（M1 由调试面板注入）
│   └── Metrics/LatencyRecorder.swift
├── MMPerception/
│   ├── PerceptionFeatures.swift
│   ├── FaceSignalDeriver.swift     # 52 系数 → 微笑/皱眉/惊讶（纯逻辑）
│   ├── OneEuroFilter.swift         # 平滑（纯逻辑）
│   ├── HandGestureClassifier.swift # 关节点序列 → 手势（纯逻辑）
│   └── ARKitPerceptionSource.swift # iOS only：ARSession + Vision
├── MMEmotion/
│   ├── AvatarState.swift
│   ├── AvatarPose.swift
│   ├── ExpressionPreset.swift
│   ├── EmotionStateMachine.swift   # 协议
│   ├── RuleBasedEmotionStateMachine.swift
│   └── ReactionRules.swift         # 阈值、延迟、冷却等可调参数
└── MMAvatar/
    ├── AvatarRenderer.swift        # 协议
    ├── RealityKitAvatarRenderer.swift
    ├── BlendShapeIndex.swift       # ARKit 名称 → 模型 blendShape 索引映射
    └── IdleMotionLayer.swift       # 呼吸、眨眼

Packages/MiniMateKit/Tests/
├── MMPerceptionTests/
├── MMEmotionTests/
└── MMCoreTests/

App/MiniMate/
├── Screens/AvatarScreen.swift      # 主界面：RealityView
├── Screens/Debug/AvatarDebugPanel.swift
└── Resources/Avatar/minimate.usdz

Assets/avatar/                       # 素材源文件（.vrm、.blend），不进 App bundle
└── README.md                        # 素材来源、许可、导出步骤
```

**Structure Decision**：沿用 001 的单 Package 多 target。`MMPerception` 中依赖 ARKit 的文件用 `#if os(iOS)` 隔离，其余可在 macOS 测试。`MMEmotion` 完全不依赖 Apple 框架以外的 UI/设备 API。

### 关键设计

**数据流（每帧）**

```
ARSession delegate (60 Hz) ─▶ FaceSignalDeriver + OneEuroFilter ─▶ PerceptionFeatures
ARFrame 抽帧 (10–15 Hz) ─▶ Vision hand pose ─▶ HandGestureClassifier ─▶ GestureEvent
                                                     │
PerceptionFeatures / ConversationEvent ─▶ EmotionStateMachine.handle(...)
CADisplayLink / RealityKit update (60 Hz) ─▶ stateMachine.pose(at: now) ─▶ AvatarRenderer.apply
```

- 状态机采用"事件 + 按时间求值"的模式：`handle(_:)` 只更新状态，`pose(at:)` 根据当前状态与时间计算插值后的 `AvatarPose`。延迟反应通过"计划在 t 时刻触发"的待办队列实现，便于用假时钟测试。
- 线程：ARSession 回调在专用队列；状态机放在一个 `actor` 中；渲染在 MainActor。`AvatarPose` 为 `Sendable` 值类型。
- **视线跟随**：用 `ARFaceAnchor.transform` 得到用户脸在相机坐标系中的位置，映射为形象头部骨骼旋转（限幅 ±25°）+ 自身 `eyeLook*` 系数；带 OneEuro 平滑。这是唯一直接使用用户数据的通道，且使用的是位置而非表情系数。
- **表情预设混合**：`AvatarPose.expression` = 预设权重 × 强度，叠加待机层（眨眼会覆盖 `eyeBlink*`），叠加口型层（M2 使用 `jawOpen`、`mouthFunnel` 等）。
- **手势**：挥手 = 手腕 x 坐标在 1.5 s 内过零 ≥ 3 次且手掌张开；比心 = 双手拇指尖与食指尖分别相近且两手靠近；点赞 = 拇指伸直向上、其余四指弯曲。阈值集中在 `ReactionRules`。
- **热降频**：监听 `ProcessInfo.thermalState`，`.serious` 时手势降到 5 fps，`.critical` 时暂停手势。

## Complexity Tracking

| 项 | 为什么需要 | 更简单的替代为何不行 |
|---|---|---|
| 开发机素材工具链（Blender + VRM 插件） | RealityKit 不能直接加载 VRM | 从零建模成本更高；Live2D 需第三方 SDK 运行时（违反 VI 更严重） |
