# Avatar Auto-Build

小瓜形象的自动化构建工作目录。计划与审核方式见 [`PLAN.md`](./PLAN.md)。

## 2026-11-25 Phase 1.4 真机精修（直腿 / 厚掌 / 微弯手 / 白袜）

- 小腿直腿：`slim_calves()` 在 `z ∈ (0.075, 0.355)` 收窄并压平后侧小腿肚凸包（峰值 `w_x 9.57→7.62 cm`、`d_y 11.93→8.89 cm`），袜子基于新直腿重采样零透肤。
- 手掌加厚：`thicken_hands()` 沿掌面法向将掌心厚度由 `2.42 cm` 增至 `3.31 cm`（左右对称），腕部平滑归 `1.0×` 零穿袖口。
- 静置微弯：`curl_rest_hands()` 在网格空间绕解剖关节烘焙自然递增微弯（食指→小指 `22°→38°`），不动骨架 `skeletonRestPoses`，并收敛 `wave`/`shyCover` 附加手指弯曲防穿模。
- 袜子提白：为 `SockL`/`SockR` 新建独立 `SockWhite` 材质（纯白漫反射 + `0.70` 线性 HDR 自发光 + `0.85` 粗糙度），在 `export_phase1.py` 保留自定义粗糙度并加入不透明白名单；同时在 `build_phase1.py` 补齐 `ac.make_actions(armature, 30)` 防止动作漂移。

详见 `reports/phase1-review.md`「Phase 1.4 真机精修（2026-11-25）」。

## 2026-11-24 真机颜色修订

- 腿肤色：真机主光被短裤下摆投成整片阴影；App 场景关闭两盏方向光的实时阴影，腿部与脸部接受同样的主光 + 补光。
- 抽绳/绳头：改为独立的无光照纯白材质 `DrawstringWhite`，PBR 光照不再把它染成灰蓝。
- 袜子：下沿延伸进鞋口并贴合脚踝/脚背皮肤，鞋口处外扩填缝，袜口改为内收圆润卷边。

详见 `reports/phase1-review.md`「Phase 1.3 真机颜色修订」。

## Phase 1.2 表情复审状态（2026-11-22）

Phase 1 **已通过**；Phase 1.2 复审（脖子/猫耳）平均 **2.87**；眼睛/嘴巴/服色/呆毛修订已定稿（2026-11-23 你确认“可以了”）。眼睛/嘴巴/服色修订已完成：虹膜壳 5 mm，瞳孔贴图再向鼻梁 2 px；嘴巴不画唇线/唇阴影，只用单一深色内口腔 + idle 小张口：消除横线、悬空上唇线和突兀阴影；sad/concerned 不笑，surprised 小 o，happy 张口，playful 张嘴；吐舌仍待单独舌头层，happy / surprised / playful 单嘴；连帽衫按原稿取色，上半不再纯白。首轮产物保留在 `renders/phase1_before/`。先看：

```bash
open renders/phase1/review.html
```

产物：

- 候选 USDZ：`out/minimate_phase1.usdz`（约 13 MB；8 个动作合并为一条名为 `actions` 的 `SkelAnimation` 时间线）
- 动作清单：`out/minimate_phase1.actions.json`（`tag → startFrame/endFrame`，运行时据此裁剪）
- Blender 场景：`work/phase1/minimate_phase1.blend`
- 验证报告：`reports/validation-phase1.md`
- 审核说明：`reports/phase1-review.md`
- 0–3 分评分表：`renders/phase1/scorecard.html`

眼睛/嘴巴/服色修订：虹膜/高光壳外移 5 mm，瞳孔贴图再向鼻梁约 2 px；皮肤开口微笑 + 白牙 + 细上唇线，FaceMouth 用珊瑚粉内口腔材质，表情下单一嘴型、无黑圈/红线；连帽衫按 `three-view.jpg` 取样，上 #E7ECF7、下 #DEE8F5。保留已确认的脖子（头部抬高 4 cm、Body 颈部皮肤、V 领剪开）、曲边猫耳、发箍带、罗纹和泡泡袖。

硬门禁已通过：52 个 ARKit 名称、8 条动作、38,392 三角面、贴图 ≤ 2048²、USDZ pxr 校验通过。

已知差距：头部抬高 4 cm 使头身比轻微变化；V 领仍有白色领口滚边/collar 叠层；猫耳侧后仍部分被头发遮挡；连帽衫没有布料褶皱/法线细节；手指偏细长；动作幅度未重调；USDZ PBR 与 Blender 不同。素材侧已定稿，可进入 Phase 3 接入 App（需单独批准）；详见 `reports/phase1-review.md`。

## Phase 0 状态（2026-11-21）

Phase 0 已通过（2026-11-21，平均 2.54）。先看：

```bash
open renders/phase0/review.html
```

产物：

- 候选 USDZ：`out/minimate_phase0.usdz`
- Blender 场景：`work/phase0/minimate_phase0.blend`
- 验证报告：`reports/validation-phase0.md`
- 审核说明：`reports/phase0-review.md`
- 0–3 分评分表：`renders/phase0/scorecard.html`

硬门禁已通过：52 个 ARKit 名称、8 条动作、33,076 三角面、贴图 ≤ 2048²、USDZ pxr 校验通过。真机验收在 Phase 3。

已知差距：上衣仍是 T 恤、下装仍是底模长裤形状、脸型仍是 VRoid 底模、猫耳发箍为程序化近似、动作幅度待调。详见 `reports/phase0-review.md`。

## 环境

- Blender 5.3（`/opt/homebrew/bin/blender`）
- VRM Add-on for Blender（已安装在 Blender 用户扩展中）
- macOS `usdzip`

所有脚本都以本目录为根解析路径，可从任意位置运行。

## 运行顺序

```bash
cd Assets/avatar/auto-build

# 1. 底座审计 + 提取原始贴图
blender --background --factory-startup --python scripts/audit_base.py

# 2. 生成 Phase 0 贴图
blender --background --factory-startup --python scripts/generate_textures.py

# 3. 构建 Phase 0 模型
blender --background --factory-startup --python scripts/build_avatar.py

# 4. 导出 USDZ + 验证
blender --background --factory-startup --python scripts/export_usdz.py
blender --background --factory-startup --python scripts/validate_avatar.py

# 5. 生成审核材料（Blender 渲染 + USDZ 近似预览）
blender --background --factory-startup --python scripts/render_usd_preview.py
blender --background --factory-startup --python scripts/render_compare.py
open renders/phase0/review.html

# 6. Phase 1（从 Phase 0 blend 构建连帽衫/短裤/袜子）
blender --background --factory-startup --python scripts/build_phase1.py
blender --background --factory-startup --python scripts/export_phase1.py
blender --background --factory-startup --python scripts/validate_phase1.py
blender --background --factory-startup --python scripts/render_usd_preview_phase1.py
blender --background --factory-startup --python scripts/render_phase1.py
open renders/phase1/review.html
```

## 约定

- 输入文件（底座 VRM、设计图、配方）只读，不移动、不覆盖。
- `Face` 网格拓扑不可修改；新增部件全部为独立网格。
- 任何阶段构建失败即停止；先看对应阶段的 `reports/validation-phaseN.md`。
- 生成物（`work/`、`textures/`、`renders/`、`out/`）默认不入库。
