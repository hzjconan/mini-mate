# Phase 0 审核说明

**日期**：2026-11-21
**状态**：Phase 0 通过（2026-11-21，平均 2.54）
**审核入口**：`renders/phase0/review.html`
**评分表**：`renders/phase0/scorecard.html`

## 本轮产物

| 产物 | 位置 |
|---|---|
| 候选 USDZ | `out/minimate_phase0.usdz` |
| 可编辑 Blender 场景 | `work/phase0/minimate_phase0.blend` |
| 审核页 | `renders/phase0/review.html` |
| 验证报告 | `reports/validation-phase0.md` |
| 底座审计 | `reports/baseline-audit.md` |
| 生成贴图 | `textures/phase0/`、`out/textures/` |

## 硬门禁结果

| 检查 | 结果 |
|---|---|
| Face 的 52 个 ARKit 名称 | ✅ 零缺失 |
| Face 目标形态键 | ✅ 124 个（Basis 不计） |
| 8 条动作 | ✅ 名称与 `ActionTag` 一致 |
| `Head` / `Neck` 骨骼 | ✅ |
| 三角面 | ✅ 33,076（< 50k） |
| 贴图尺寸 | ✅ 全部 ≤ 2048² |
| USDZ 52 名称 / 8 动作 / 骨架 | ✅ pxr 校验通过 |
| 真机 `missingNames` | ⏳ Phase 3 真机验收 |

## 用户评分（2026-11-21）

| 评分项 | 分数 |
|---|---:|
| 头身比约 1:2.5，头大、四肢短 | 3 |
| 银白→淡蓝渐变 bob，发尾到下颌 | 3 |
| 猫耳发箍（耳朵 + 内耳渐变 + 侧面连接件） | 2 |
| 头顶呆毛，向右侧弯 | 3 |
| 琥珀色大眼、虹膜占眼高约 70%、两点高光 | 3 |
| 细平眉、颜色比头发深一档 | 3 |
| 小鼻、ω 形小嘴 | 2 |
| 脸型圆润、脸颊饱满、下巴短 | 2 |
| 肤色/阴影/腮红 | 3 |
| 白蓝渐变连帽衫、白色抽绳、口袋 | 2 |
| 浅蓝短裤、白色裤脚边 | 2 |
| 白袜、白/蓝灰运动鞋 | 3 |
| 柔和 pastel 质感 | 2 |

**平均 2.54；关键特征无 0/1，Phase 0 通过。** 剩余 2 分项按计划进入 Phase 0.1 / Phase 1 / Phase 2。

## 本轮完成的内容

- 重绘脸、眼、眉、嘴、发色、上衣、短裤、鞋、身体皮肤贴图；保持 VRoid 标准 UV。
- Q 版比例：`headScale 1.55`、`bodyScale 0.62`、`bodyWidthScale 1.12`、`armLengthScale 0.72`。
- 烘焙 A-pose，手臂缩短并下垂，避免 T-pose。
- 新增猫耳发箍（外耳渐变/内耳纯色/侧面连接件与青色发光）和呆毛；呆毛使用与发色一致的银白→淡蓝渐变，不再单独画成白色。
- 眼睛改为琥珀色，嘴改为 ω 形，增加腮红。
- 保留 `Face` 网格拓扑；52 个 ARKit 名称在 Blender 和 USDZ 中均存在。
- 修复 USDZ 导出问题：
  - 删除 6 组重复的 material-subset mesh（避免重叠/渲染异常）；
  - 将 MToon 兼容 Principled 的 `metallic=1` 改为 0，避免 USDZ 发黑/金属感；
  - 对不透明材质强制 `opacity=1`，并填充贴图透明背景，避免短裤/下摆被肤色/黑色透出；
  - 每次导出强制覆盖 `out/textures`，避免旧贴图混入。

## 已知差距（Phase 1 / 2 处理）

1. **上衣仍是 T 恤几何**，不是设计的白蓝渐变连帽衫；抽绳/口袋目前只在贴图上。
2. **下装仍是底模的七分/长裤形状**，不是设计短裤；白边/袜口需要 Phase 1 重做几何。
3. **脸型仍是 VRoid 底模**，没有设计里更圆的脸颊/短下巴；Phase 2 才做保形态键的脸型变形。
4. **猫耳发箍、呆毛是程序化近似**；内耳目前是纯色，不是虹彩渐变。
5. **手臂/手指偏细长**，袖口和手部需要 Phase 1 连帽衫袖子覆盖。
6. **`wave` / `spin` 等动作在 A-pose 下幅度偏小**，需要 Phase 1 重新调关键帧。
7. **USDZ 的 PBR 观感**与 Blender 的 MToon 渲染不同；`review.html` 里的 USDZ 预览是 usdrecord 近似图，最终以 Phase 3 真机为准。
8. **尚未真机验证**：当前只完成 Blender + pxr + usdrecord 验证；Phase 3 才复制到 App 并检查 52 滑杆/8 动作。

## 审核方式

1. 打开 `renders/phase0/review.html`：
   ```bash
   open Assets/avatar/auto-build/renders/phase0/review.html
   ```
2. 重点看：
   - 三视图对比（正面/侧面/背面）；
   - 脸部特写与含猫耳/呆毛的头部特写；
   - 表情冒烟、8 动作抽帧、转台；
   - USDZ PBR 预览（与 Blender 渲染不同，仅作资产外观参考）。
3. 打开 `renders/phase0/scorecard.html` 打分：每个特征 0–3 分，分数只存本页浏览器；点“复制评分”把 Markdown 贴给我。
4. Quick Look 旋转候选 USDZ：
   ```bash
   qlmanage -p Assets/avatar/auto-build/out/minimate_phase0.usdz
   ```
   或在 Finder 中选中 USDZ 按空格。Quick Look 只用于看外形，不用于形态键/动作验收。
5. 按评分表逐项打分；回复“通过 / 某项要改 / 整体方向不对”。

## 关于“在 App 里看”

当前 `App/MiniMate/Screens/AvatarScreen.swift` 仍使用 `PlaceholderAvatarScene`（粉色球体占位），`RealityKitAvatarRenderer`（T014）尚未实现，候选 USDZ 也尚未放进 App。因此 Phase 0 评分里的“App 常用尺寸”是评分表的尺寸模拟图（约 360 px 高），不是真实 App 截图；真实 App/真机画面在 Phase 3 接入后才会出现。若希望提前在 App 内看候选 USDZ，需要先做 T014 或一个临时预览页，这会修改 `App/` 与 `Packages/`，需要单独批准。

## 下一步

Phase 1：连帽衫几何（帽子、长袖、抽绳、口袋、下摆）、短裤/袜子/鞋的几何修正、头发轮廓细化、8 动作关键帧调整。Phase 0 的 52 键和 8 动作基线保持不变。
