# 问题：phase1 USDZ 的 8 个动作只有 `nod` 能被 RealityKit 读到

> 状态：已修复（2026-11-23）。采用方案 1：8 个动作烘焙进一条绑定的 `actions` 时间线，随包输出 `minimate.actions.json`，运行时用 `trimmed` 裁成 8 个片段。下方保留原始问题描述。

- 日期：2026-11-23
- 素材：`Assets/avatar/auto-build/out/minimate_phase1.usdz`
- 相关脚本：`Assets/avatar/auto-build/scripts/avatar_common.py`（`export_actions_to_usd` / `merge_animations`）
- 运行时：RealityKit（macOS 26 / iOS 26）

## 复现

```bash
usdcat Assets/avatar/auto-build/out/minimate_phase1.usdz \
  | grep -n "SkelAnimation\|animationSource"
```

实际输出（节选）：

```
53: rel skel:animationSource = </root/Armature/Armature/nod>
55: def SkelAnimation "nod"
130: def SkelAnimation "wave"
229: def SkelAnimation "spin"
294: def SkelAnimation "heart"
393: def SkelAnimation "shyCover"
492: def SkelAnimation "leanBack"
567: def SkelAnimation "lookAround"
654: def SkelAnimation "notice"
```

8 个 `SkelAnimation` prim 确实都在，但 Skeleton 的 `skel:animationSource` 只指向 `nod`，其余 7 个是未被任何关系引用的孤儿 prim。

## RealityKit 侧的实际结果

用 RealityKit 直接加载该 USDZ，遍历 `AnimationLibraryComponent` 与 `availableAnimations`：

- Armature 的 animation library keys：`["skeletal animation 1", "default subtree animation", "/root/Armature/Armature/nod", "default scene animation"]`
- availableAnimations：只有 `/root/Armature/Armature/nod[0]`（重复两次）和两个 default 动画
- `wave / spin / heart / shyCover / leanBack / lookAround / notice` 完全不存在

所以运行时只有 `nod` 能播，其余 7 个动作对 App 不可见。

## 根因

`avatar_common.py` 的 `merge_animations()`：8 个动作分别导成临时 USDC，合并时逐个 `CopySpec` 到同一个 Skeleton 下，但最后只执行了

```python
animation_relationship.SetTargets([first_destination])   # 只有 nod
```

USD 的 `skel:animationSource` 是单目标绑定；RealityKit 的 USDZ 导入只把**绑定到骨架**的 `SkelAnimation` 转成 `AnimationResource`，不会把未引用的 `SkelAnimation` 暴露为可用动画。因此合并本身成功，绑定这一步丢了 7 个。

## 修复的验收标准

1. 导出的 USDZ 在 RealityKit 里 `load` 后，能拿到 8 个可区分、可独立播放的动画，分别对应 `nod / wave / spin / heart / shyCover / leanBack / lookAround / notice`。
2. 每个动作都能完整播完并回到静置姿态，互不串味（播放 A 不会带出 B 的骨骼通道）。
3. 不破坏现有素材约定：52 个 ARKit 形态键零缺失、贴图完整、`upAxis=Y`、`metersPerUnit=1`。
4. 不能靠“8 套完整模型 USDZ”实现（包体和内存不可接受）。

## 可行的修复方向（供评估）

- **方案 1（推荐，管线可自动化）**：把 8 个动作按顺序烘焙进**一条** `SkelAnimation` 时间线，只绑定这一条；同时随包输出一份 `actions.json`（`tag → start / duration`）。运行时用 `AnimationDefinition.trimmed(start:end:)` 裁出 8 个动作。时间线起点/终点必须与 Blender 中一致，且动作之间留 1–2 帧静置，避免裁剪边缘串味。
- **方案 2**：每个动作单独导一个**只含骨架 + 动画、不含网格贴图**的 USDZ，运行时加载后把动画资源播到主模型骨架上。需要先做一个小实验确认 RealityKit 能跨文件绑定同一骨架（Apple 论坛有“实体一致即可”的说法，但未验证）。
- **方案 3**：用 Reality Composer Pro 的 Animation Library 引用多个 USD 动画文件——能工作，但是手工步骤，会破坏全自动构建。

不建议：复制多个 Skeleton（网格只能绑一个骨架）、多个整套模型 USDZ（内存/包体失控）。

## 另外两个已确认的运行时事实（供参考，不需要施工方处理）

- 52 个 ARKit 形态键全部存在；写入 `jawOpen=0.75` 能正确读回。
- USDZ 里的关节不是 Entity（只有 `J_Bip_C_*_collider_*` 实体），头部朝向目前由 App 侧用 additive 关节动画驱动，不依赖动作片段。

## 修复结果（2026-11-23）

- 新 USDZ 只绑定一条 `SkelAnimation "actions"`（10.5 s），`SkelAnimation` 的 `skel:animationSource` 指向它。
- 同目录新增 `minimate_phase1.actions.json`：`fps=30`、`totalFrames=316`、8 个 `tag → startFrame/endFrame`。
- App 侧运行时探针按 `(frame - 1) / fps` 裁剪，8/8 全部成功，片段时长：nod 1.0、wave 1.4、spin 1.6、heart 1.4、shyCover 1.4、leanBack 1.0、lookAround 1.2、notice 0.8 秒。
- 接入文件：`App/MiniMate/Resources/Avatar/minimate.usdz` 与 `minimate.actions.json`；构建产物里两个文件都在 bundle 根目录。

**管线**（`Assets/avatar/auto-build/scripts/avatar_common.py`）：

- `merge_animations` 被 `build_animation_timeline` 取代：8 个动作按 `ACTION_NAMES` 顺序拼进一条 `SkelAnimation`（名为 `actions`），片段之间留 2 帧静置，间隔帧保持上一采样；逐关节做四元数符号连续化，避免导出按 `w≥0` 归一化造成的半球翻转。
- 合并后的时间线删除 `blendShapes` / `blendShapeWeights`（本素材没有形态键动画），避免 RealityKit 额外导入一条无用的 `SampledAnimation<BlendShapeWeights>`。
- 导出时同步写出 `out/minimate_phase1.actions.json`：`tag → startFrame/endFrame`、`fps`、`totalFrames`。
- 顺带修复 `spin`：原先首尾两个四元数关键帧（0 与 2π）被 Blender/USD 导出压成 3 个跳变采样；改为 0/90/180/270/360° 五个关键帧后导出 49 帧连续旋转。
- 管线在生产时会断言：采样逐帧连续、每个动作首末姿态一致、末帧回到静置、单动作最大偏差 ≥ 5°。

**运行时**（`Packages/MiniMateKit/Sources/MMAvatar/`）：

- 新增 `ActionClipManifest`：解析 `<asset>.actions.json`，换算 `start = (startFrame-1)/fps`、`duration = (endFrame-startFrame)/fps`。
- `RealityKitAvatarRenderer` 优先读取 USDZ 同级的 `<stem>.actions.json`，取 `SampledAnimation<JointTransforms>` 后用 `definition.trimmed(start:end:)` + `AnimationResource.generate` 生成 8 个片段；找不到清单时回退到旧的按动画名匹配。

**验证结果**：

- 新 USDZ：1 条 `SkelAnimation "actions"`，316 帧（10.5 s），`skel:animationSource` 正确指向它。
- macOS RealityKit 探针：8 个片段的 controller 时长与清单一致（nod 1.0 s、wave 1.4 s、spin 1.6 s、heart/shyCover 1.4 s、leanBack 1.0 s、lookAround 1.2 s、notice 0.8 s）。
- 离屏渲染对比：8 个片段的动作中段与首帧图像均有差异（spin 变化 13.3%，其余 0.7%–6.9%）。
- 时间线逐帧四元数符号翻转数为 0。
- `App/MiniMate/Resources/Avatar/` 的素材未随本次修改替换；接入时需同时放入 `minimate.usdz` 与 `minimate.actions.json`（Xcode 同步组会把两者平铺到 bundle 根目录）。

## 真机接入补充问题（2026-11-24）

把新素材接进 App 后，真机画面只剩猫耳出现在屏幕底部，控制台还打出 52 条 `素材缺少 blendShape` 警告。排查结论：

1. **头部 additive 关节动画会带偏整个模型**：原实现给 `FromToByAnimation<JointTransforms>` 只传了一个 `jointNames` 和单元素 transform 数组。RealityKit 会把该增量套到根关节上，整条骨架向下位移约 1.5 m（相机与素材都正常）。修复方式：动画携带**整条骨架的关节名 + 每个关节的 `restPoseTransform`**，只对头部关节叠加旋转，并关闭 translate/scale 动画。
2. **`reset()` 误删外部实体**：`RealityKitAvatarRenderer.reset()` 原先清空 `root` 的所有子节点，连 `AvatarScene` 挂上去的灯光和相机一起删掉（全黑）。现在只移除渲染器自己加载的模型。
3. **启动警告**：`tick()` 在 `load()` 完成前驱动渲染器，`weightTargets` 还是空的，于是 52 个名称各警告一次。现在加载完成前不驱动。
4. 非 AR 的取景使用 `RealityView` 的 `.virtual` 相机 + 显式 `PerspectiveCamera`：模型加载完成、算好机位后**再加入相机实体**；`ARView` 的 `.nonAR` 自定义相机在 iOS 18+ 会被忽略，不要使用。

真机截图确认：形象完整显示在画面中央，位置稳定，头部有细微待机运动。
