# 002-m1-presence 小瓜 3D 形象建模与材质精修（4 项）执行单

- **状态**：已完成实施与独立复审（待用户真机验收）
- **Git 基线**：`main` @ `f6f1ec6`（工作区干净；上游 M1 US1 形象/动作管线与 US2 视线跟随均已合并）
- **关键基线**：
  - Blender `5.3.0`（`/opt/homebrew/bin/blender`，内建 Python 3.13、`numpy` 2.x、`pxr` USD SDK）、`/usr/bin/usdzip`
  - 冻结基线：`Assets/avatar/auto-build/work/phase0/minimate_phase0.blend`（Phase 0 已审定，含 `Face` 125 形态键 / 52 ARKit 与 118 骨骼）
  - 线上 App 资源：`App/MiniMate/Resources/Avatar/minimate.usdz`（13,160,657 bytes，118 骨骼、124 形态键目标 / 52 ARKit、单条 `actions` 时间线 295 帧 @ 30 fps）+ `minimate.actions.json`
  - Swift 工程：Swift 6 严格并发、Swift Testing、`RealityKitAvatarRenderer` 直接读取 USDZ `skeleton.joints.map(\.restPoseTransform)` 驱动静置与视线追踪
- **拍板决议摘要**：已按全部推荐项拍板（**1A / 2A / 3A / 4A**）：① 静置手型在网格空间绕解剖关节微弯（Index→Little `22°→38°`）并收敛 `wave`/`shyCover` 附加手指弯曲；② 为 `SockL`/`SockR` 新建独立材质 `SockWhite`（`Base Color=1.0` + `Emission=0.70` + `Roughness=0.85`）；③ 采用均衡二次元直腿与 `1.50×` 手掌加厚参数；④ 全量门禁通过后直接同步到 `App/MiniMate/Resources/Avatar/` 并运行 `swift test` 与 iOS Simulator 编译。

> **红线声明**
> - 严格遵守 `.specify/memory/constitution.md`（最高优先级）与 `AGENTS.md`：不引入任何 App 运行时第三方依赖；不修改 `AvatarRenderer` 协议及状态机/感知边界；不提交含个人隐私的 `Assets/voice-samples/*.wav` 或任何密钥。
> - 严格遵守 `Assets/avatar/auto-build/PLAN.md` 不变量 I-1–I-8：**`Face` 网格拓扑与 52 个 ARKit 形态键（124 目标）严禁触碰**；8 个动作名称（`nod`/`wave`/`spin`/`heart`/`shyCover`/`leanBack`/`lookAround`/`notice`）不可变；原始只读输入（`Assets/avatar/VRoid_V110_Female_v1.1.3.vrm`、`Assets/avatar/reference/*`）只读不改；`work/`、`textures/`、`renders/`、`out/` 默认不入库（已由 `Assets/avatar/auto-build/.gitignore` 忽略）。
> - 收口策略：未经用户明确确认验收，不得勾选任何任务清单，不得 `git commit`，不得 `git push`。

---

## 上篇：面向用户决策

### 1. 任务目标与选择理由

- **本次任务**：围绕用户真机验收反馈，在 `Assets/avatar/auto-build/` 自动化管线内完成**小瓜 3D 形象 4 项建模与材质精修**，并在 52/52 ARKit 形态键与 8/8 动作零回归的前提下重新导出验证：
  1. **小腿改美少女直腿**：消除 `spin` 侧/背面可见的粗大腓肠肌凸包，改为纤细笔直的二次元美少女直腿；
  2. **手掌加厚**：修复手掌薄如纸片的扁平问题，使其厚实圆润；
  3. **静置手型自然微弯**：将静置时绷直的手掌/五指改为自然微弯的放松手型；
  4. **袜子颜色提白**：解决真机上白袜偏灰的问题，在保留立体感前提下提亮至干净纯白。
- **为何作为独立精修任务执行**：4 项均为 Phase 1 自动化构建链路（`build_phase1.py` → `export_phase1.py` → `validate_phase1.py` → `render_phase1.py`）内的纯资产层迭代，不涉及任何 Swift 业务逻辑变更；一次性合批精修并重新导出 USDZ，可避免反复重跑导出与多轮真机重装，直接为后续 M1 US3（表情回应）提供终版形象资产。
- **摸底关键发现（均经只读实测确认）**：
  1. **需求 #1 与 #2 的共同数学根因**：`build_avatar.py:133-135` 做 Q 版头身比缩放时将全身 Z 轴压为 `0.62×`、X/Y 扩为 `1.12×`（`1.81×` 纵横畸变）：① 把成人解剖小腿肚压矮拉宽，导致 `z=0.22–0.26 m` 处后侧（`+Y`）向后突出达 `+0.0959 m`（比膝盖后缘 `+0.0645 m` 猛凸 **3.14 cm**），宽 `9.57 cm`、厚 `11.93 cm`（比膝盖还粗）；② T-pose 下手掌厚度沿世界 Z 轴，被硬压成 `0.62×` 而掌宽扩至 `1.12×`，同口径 PCA 实测 `phase0.blend` 掌心厚度仅 **`2.42 cm`**（指根厚度仅 `1.1–1.4 cm`），视觉上薄如纸片。
  2. **需求 #3 的两大架构/骨架深坑**：① `RealityKitAvatarRenderer.swift:470-486, 504, 551-562` 在静置与动作结束时直接写回 USDZ 的 `skeletonRestPoses`，因此静置手型**必须落在 Rest Pose 中**而非单独改动作末帧或新增动画层；② 只读实测发现 `phase0.blend`/`phase1.blend` 的手指骨骼存在严重反向与枢轴偏移——`J_Bip_{L,R}_{Index,Middle,Ring,Little}1` 尾部指向 `+Z`（向上指回手腕），导致局部 X 轴与其他指节反向（`Index1 rotX(-20°)` 反而向手背反折），且 `Index2/3` 骨骼 `head` 漂移至腕/掌区 `z=0.51/0.50 m`。**严禁**对这些畸变指骨做 Pose Mode `armature_apply()`，必须改在 `Body` 网格空间绕各指节真实解剖关节中心做平滑微弯，既自然又 100% 兼容现有 `skeletonRestPoses` 与 8 个动作。
  3. **需求 #4 的真实根因与管线防回归发现**：① `SockL`/`SockR` 的贴图 `solid_trim.png` 已是纯白 `#FFFFFF` 且法线 100% 朝外，真机显灰的根因是共享的 `TrimWhite` 在 USDZ 中为纯 PBR 漫反射（`emissive=0`），经双方向光圆柱余弦衰减与 RealityKit ACES 色调映射后沦为灰白（与 Phase 1.3 抽绳变灰同因）；② 发现一处严重管线漂移——`build_phase1.py` 打开旧版 `phase0.blend` 后**从未重新调用 `ac.make_actions(armature, 30)`**，直接重跑会把已验收的 8 个动作（尤其是提交 `3862e508` 的 `shyCover`）静默回退到 11-23 旧版！本轮必须先在 `build_phase1.py` 补齐 `ac.make_actions(armature, 30)` 调用。

### 2. 已拍板决策（1A / 2A / 3A / 4A）

1. **静置手型自然微弯与动作手指叠加策略（1A）**：在 `build_phase1.py` 中对 `Body` 左右五指网格绕各自真实 MCP/PIP/DIP 解剖关节中心做自然递增微弯（食指→小指约 `22°→38°`，拇指柔和内收 `~14°`），不动骨架朝向与 `skeletonRestPoses`；同时在 `avatar_common.py` 中将 `wave` 的附加弯曲由 `finger_curl(-12, -10)` 收敛为 `finger_curl(-4, -3)`（过渡帧 `(-2, -1.5)`）、移除 `shyCover` 的 `-5°` 附加弯曲（由新 rest 微弯自然承担），其余 6 个动作零改动。
2. **袜子提白材质方案（2A）**：为 `SockL`/`SockR` 新建独立材质 `SockWhite`（`Principled BSDF`，`Base Color = (1, 1, 1)` + 线性 HDR `Emission Color = (0.70, 0.70, 0.70)` + `Roughness = 0.85`），在 `export_phase1.py` 中保留非 MToon 材质的自定义粗糙度并加入 `opaque_materials` 白名单；`ShortsHemL`/`ShortsHemR` 保持原 `TrimWhite`。
3. **小腿直腿与手掌加厚的目标尺度（3A）**：① 小腿在 `z ∈ (0.075, 0.355)` 压平后侧（`+Y`）72% 的腓肠肌凸包并把截面中心拉回膝-踝直线，使 `z=0.22–0.26 m` 峰值宽度 `w_x` 由 `9.57 cm` 降至 `7.62 cm`、前后径 `d_y` 由 `11.93 cm` 降至 `8.89 cm`，袜子基于新皮肤重采样并将中段径向偏置微调至 `3.8 mm`（`z=0.164` 处 `4.8 mm`）消除透肤；② 手掌沿掌面法向将掌心厚度由 `2.42 cm` 增至 `3.31 cm`（手背 `1.56×` / 掌心 `1.44×`），向指节平滑过渡并在腕部归 `1.0×`。
4. **同步 App 资源与验证（4A）**：门禁全绿后将 `out/minimate_phase1.usdz` 与 `out/minimate_phase1.actions.json` 直接复制到 `App/MiniMate/Resources/Avatar/`，并运行 `swift test` 与 iOS Simulator 编译验证（验收确认前不 `git commit`）。

---

## 下篇：面向实施方的零歧义施工图

### 3. 现状锚点与环境陷阱预警

#### 3.1 现有代码与资产锚点

| 模块/符号 | 精确位置 | 职责与复用/约束说明 |
| :--- | :--- | :--- |
| `avatar_common.make_actions` | `Assets/avatar/auto-build/scripts/avatar_common.py:71-452` | 8 条动作唯一事实源（含提交 `3862e508` 的 `shy_pose`、`heart_pose`、`wave` `finger_curl`、`spin` 等）；末帧与首帧偏差须 `≤ 1°`（由 `_read_track` 第 542 行断言） |
| `avatar_common.build_animation_timeline` | `Assets/avatar/auto-build/scripts/avatar_common.py:623-728` | 将 8 个动作拼成单条 `actions` `SkelAnimation` 时间线（总计 295 帧，间隔 2 帧）并生成 `.actions.json` |
| `build_avatar.scale_meshes` / `apply_a_pose` | `Assets/avatar/auto-build/scripts/build_avatar.py:106-209` | Phase 0 缩放（`bodyScale=0.62`, `bodyWidthScale=1.12`, `armLengthScale=0.72`）与 A-pose 烘焙；**本轮不修改、不重跑**，作为根因参照 |
| `build_phase1.make_emissive_color_material` | `Assets/avatar/auto-build/scripts/build_phase1.py:194-220` | 现有无光照 HDR 自发光材质构造函数（用于 `DrawstringWhite`, `intensity=2.5`）；可参考其 USD `Emission Color` 乘系数模式 |
| `build_phase1.NearestSkinWeights` | `Assets/avatar/auto-build/scripts/build_phase1.py:796-827` | 基于 `Body` slot 0（皮肤）建 KDTree 采样权重，供 `add_shorts_hem_bands`、`add_socks`、`add_sleeves`、`add_v_neck` 复用；**必须在小腿/手部网格变形完成后再实例化** |
| `build_phase1.add_socks` | `Assets/avatar/auto-build/scripts/build_phase1.py:885-989` | 对 `Body` slot 0 建 `BVHTree` 并逐层（`z=0.048..0.1835`）水平射线采样生成 `SockL`/`SockR`（各 280 顶 / 260 面，法线全朝外）；**必须在 `slim_calves` 之后调用**以自动贴合新直腿 |
| `build_phase1.main` | `Assets/avatar/auto-build/scripts/build_phase1.py:1578-1677` | 打开 `work/phase0/minimate_phase0.blend`，依次执行头部/虹膜/嘴/呆毛/材质/服装构建并保存 `work/phase1/minimate_phase1.blend` |
| `export_phase1.fix_preview_surface` | `Assets/avatar/auto-build/scripts/export_phase1.py:28-42` | 导出 USD 前遍历全部材质的 `BSDF_PRINCIPLED` 节点强制覆盖 `Metallic=0.0`、`Roughness=0.7`、`Specular=0.5` |
| `export_phase1.clean_stage` | `Assets/avatar/auto-build/scripts/export_phase1.py:45-102` | 清理重复子网与相机，并按 `opaque_materials` 白名单（49–74 行）强制 `opacity=1.0` |
| `validate_phase1.main` | `Assets/avatar/auto-build/scripts/validate_phase1.py:51-236` | 双重校验 `minimate_phase1.blend` + `minimate_phase1.usdz` + `.actions.json`（52 ARKit、124 形态键、8 动作、295 帧、`<50k` 三角面、`≤2048²` 贴图等），写 `reports/validation-phase1.md` |
| `render_phase1.main` | `Assets/avatar/auto-build/scripts/render_phase1.py:471-511` | EEVEE 渲染三视图对比、脸部/头部特写、表情/动作/转台并生成 `renders/phase1/review.html` |
| `render_usd_preview_phase1.main` | `Assets/avatar/auto-build/scripts/render_usd_preview_phase1.py:46-70` | 用 macOS `usdrecord` 渲染 `usd_preview_front.png` 与 `usd_preview_back.png` |
| `RealityKitAvatarRenderer` | `Packages/MiniMateKit/Sources/MMAvatar/RealityKitAvatarRenderer.swift:422-488, 504, 551-562` | 静置与视线追踪写 `skeletonRestPoses`；动作首帧必须等于 rest pose（`transitionDuration: 0`）；本轮**严禁修改** |
| `AvatarScreen` 光照配置 | `App/MiniMate/Screens/AvatarScreen.swift:97-98, 135-148` | 主光 `intensity=2000`（`-45°`）、补光 `intensity=900`（`+30°`），均 `shadow = nil`；本轮**严禁修改** |

#### 3.2 环境与管线实测陷阱（必读，严禁踩坑）

1. **陷阱 1 · `build_phase1.py` 缺失 `ac.make_actions` 导致动作静默倒退**：
   - **实测表现**：`work/phase0/minimate_phase0.blend` 中的动作停留在 2026-11-23 旧版（`shyCover` frame 15 `J_Bip_R_UpperArm = (0.8152, 0.4713, -0.1458, -0.2131)`），而 `avatar_common.py:162` HEAD 是 `(0.8345, 0.2090, -0.3722, 0.3484)`。当前 `build_phase1.py` 打开 `phase0.blend` 后未调用 `ac.make_actions`，直接重跑会把全部 8 个动作回退到旧版！
   - **必须采用的写法**：在 `build_phase1.py:main()` 保存 `OUT_BLEND` 之前必须显式调用 `ranges = ac.make_actions(armature, 30)`，并设置 `armature.animation_data.action = None`、`scene.render.fps = 30`、`scene.frame_start = 1`、`scene.frame_end = max(ranges.values())`。
2. **陷阱 2 · 手指骨骼反向且次节枢轴错位（绝对禁止用 Pose Mode `armature_apply` 弯手指）**：
   - **实测表现**：在 `phase0.blend`/`phase1.blend` 中，`J_Bip_R_Index1` `head=( -0.2820, -0.0361, 0.4549 )`、`tail=( -0.2841, -0.0426, 0.5105 )`（指向上方腕部！），其局部 X 轴 `(+0.52, -0.85, -0.08)` 与 `Index2` `(-0.05, +0.99, -0.10)` 近乎相反；旋转 `Index1 rotX(-20°)` 会导致指尖沿 `-X` 向手背反折；同时 `Index2.head` 在 `z=0.5105`、`Index3.head` 在 `z=0.4986`（高出真实指节 7–8 cm）。
   - **必须采用的写法**：禁止对任何手指骨骼执行 `bpy.ops.pose.armature_apply()` 或修改 `edit_bones`；改为在 `Body` 网格空间直接基于各指节顶点组的真实几何质心/分界平面构建解剖关节枢轴（MCP/PIP/DIP）并旋转顶点，保持骨架关节矩阵、`skeletonRestPoses` 及 8 条动作四元数 100% 兼容。
3. **陷阱 3 · `export_phase1.py` 无差别覆写 `Roughness/Specular` 及 `opaque_materials` 漏加白名单**：
   - **实测表现**：`export_phase1.py:28-42` 的 `fix_preview_surface()` 会把所有 `BSDF_PRINCIPLED` 节点强行写成 `Roughness=0.7, Specular=0.5`（导致此前 `DrawstringWhite` 在 `build_phase1.py` 设的 `Roughness=1.0, Specular=0.0` 在 USDZ 中失效）；同时 `clean_stage()` 第 49–74 行仅对白名单材质强制 `opacity=1.0`。
   - **必须采用的写法**：`fix_preview_surface()` 仅修复 MToon 兼容节点（`node.name == "Mtoon1Material.CompatibleShader"` 或 `metallic > 0.5`），不得覆盖自定义 Principled 材质（如 `SockWhite`/`DrawstringWhite`/`MouthInner`）的 `Roughness` 与 `Specular IOR Level`；同时将 `"SockWhite"` 加入 `clean_stage()` 的 `opaque_materials` 集合。
4. **陷阱 4 · Blender 5.3 内置 NumPy 2.x API 变化**：
   - **实测表现**：Blender 5.3.0 内建 Python 3.13 + NumPy 2.x，调用 `ndarray.ptp()` 会直接抛 `AttributeError: 'ptp' was removed from the ndarray class in NumPy 2.0`。
   - **必须采用的写法**：凡涉及范围计算必须使用 `float(np.ptp(arr))` 或 `arr.max() - arr.min()`。
5. **陷阱 5 · 沙盒下 VRM Add-on 不可用，但 Phase 1 全链路零依赖 VRM 插件**：
   - **实测表现**：在沙盒中调用 `ac.enable_vrm_addon()` 会因无法访问 `~/Library/Application Support/Blender/5.3/extensions/` 失败；但 `build_phase1.py` / `export_phase1.py` / `validate_phase1.py` / `render_phase1.py` 均直接打开 `.blend`，不调用 `enable_vrm_addon()`，**全部可在标准沙盒内无权限弹窗运行**。严禁把改动放进需要重跑 VRM 导入的 `build_avatar.py`。
6. **陷阱 6 · `shyCover` 手脸间隙仅 `10.6 mm` & `Body` 顶点法线更新**：
   - **实测表现**：① 当前 `shyCover` 第 15 帧右手网格距 `Face` 最近欧氏距离仅 `0.0106 m`（`10.6 mm`）；若掌心侧过度加厚或手指再大幅向内叠弯，极易穿入嘴部/下巴。② `Body` 网格 `has_custom_normals == True`，实测修改 `mesh.vertices[i].co` 后调用 `mesh.update()` 会动态更新法线（`diff = 0.1207`），无需清空自定义法线以免破坏 VRM 皮肤平滑过渡。
   - **必须采用的写法**：手掌加厚对掌心侧增厚量严格控制在 `≤ 5.5 mm`（总厚 `~3.36 cm`），并在 `validate_phase1.py` 中新增 `shyCover` 手-脸最小欧氏距离与 `heart` 双手最小距离的确定性校验门禁。

---

### 4. 改动范围表与明确不做清单（Non-Goals）

#### 4.1 文件改动表

| 文件路径 | 操作 | 精确职责 |
| :--- | :--- | :--- |
| `Assets/avatar/auto-build/scripts/build_phase1.py` | 修改 | 新增 `slim_calves`、`thicken_hands`、`curl_rest_hands`、`make_sock_white_material`；微调 `add_socks` 中段径向偏置（`0.0025→0.0038`，`z=0.164` 处 `0.0040→0.0048`）消除透肤；在 `main()` 中按正确依赖顺序接入并把 `SockL`/`SockR` 绑定至 `SockWhite`；保存前调用 `ac.make_actions(armature, 30)` 同步全部 8 条最新动作 |
| `Assets/avatar/auto-build/scripts/avatar_common.py` | 微调 | 仅微调 `wave` 的 `finger_curl` 峰值由 `(-12, -10)` 收敛为 `(-4, -3)`（过渡帧 `(-2, -1.5)`）并移除 `shyCover` 冗余 `-5°` 附加手指弯曲；其余动作与全部导出/拼接逻辑零改动 |
| `Assets/avatar/auto-build/scripts/export_phase1.py` | 微调 | `fix_preview_surface()` 仅修正 MToon 兼容节点（保护 `SockWhite`/`DrawstringWhite` 自定义 `Roughness`/`Specular`）；`clean_stage()` 的 `opaque_materials` 新增 `"SockWhite"` |
| `Assets/avatar/auto-build/scripts/validate_phase1.py` | 修改 | 在保留全部 24 项既有硬门禁基础上，新增 8 项确定性验收断言（共 32 项）：`Body` 网格存在性（含缺失显式失败分支）、小腿直腿截面指标、踝/大腿边界衔接与袜子法线、掌心厚度指标、静置手指微弯方向与幅度指标、动作防穿模间隙（`shyCover`/`heart`）、`shyCover` 动作与 `avatar_common.py` 同步、`SockWhite` USDZ 材质与自发光契约 |
| `Assets/avatar/auto-build/scripts/render_phase1.py` | 微调 | 新增 3 张局部特写审核图（`leg_side_closeup.png`、`leg_back_closeup.png`、`hand_closeup.png`）并接入 `review.html`，便于肉眼逐项核对 4 项精修效果 |
| `App/MiniMate/Resources/Avatar/minimate.usdz` | 更新 | 从通过全部门禁的 `Assets/avatar/auto-build/out/minimate_phase1.usdz` 同步复制 |
| `App/MiniMate/Resources/Avatar/minimate.actions.json` | 同步核对 | 从 `Assets/avatar/auto-build/out/minimate_phase1.actions.json` 同步复制并确认字节一致 |
| `Assets/avatar/auto-build/reports/validation-phase1.md` | 自动重新生成 | 由 `validate_phase1.py` 自动写出最新全量门禁报告 |
| `Assets/avatar/auto-build/reports/phase1-review.md` | 追加记录 | 追加「Phase 1.4 真机精修（直腿 / 厚掌 / 微弯手 / 白袜）」实测数据与对比说明 |
| `Assets/avatar/auto-build/README.md` | 微调 | 顶部补充 Phase 1.4 精修摘要 |

#### 4.2 明确不做清单（Non-Goals）

- **严禁修改** `Face` 网格的任何顶点、拓扑、UV 或 125 个形态键（受 I-1 绝对保护）。
- **严禁修改** `Assets/avatar/auto-build/scripts/build_avatar.py`、`generate_textures.py`、`export_usdz.py`、`validate_avatar.py` 及 `work/phase0/minimate_phase0.blend`（冻结的 Phase 0 基线）。
- **严禁修改** 任何 Swift 源码与测试（`Packages/MiniMateKit/**`、`App/MiniMate/**/*.swift`、`App/MiniMate.xcodeproj/**`），尤其是 `RealityKitAvatarRenderer.swift` 与 `AvatarScreen.swift` 的光照/骨架驱动逻辑。
- **严禁修改** 原始只读输入（`Assets/avatar/VRoid_V110_Female_v1.1.3.vrm`、`Assets/avatar/reference/*`）与 `specs/002-m1-presence/tasks.md` / `research.md`。
- **严禁新增** 第 9 个动作、修改 8 个动作名称或更改 `minimate.actions.json` schema 版本（`version: 1`）。

---

### 5. 精确接口与行为契约

#### 5.1 `slim_calves`（需求 #1：小腿改美少女直腿）

- **位置与精确签名**：`Assets/avatar/auto-build/scripts/build_phase1.py` →
  ```python
  def slim_calves(
      body,
      z_min: float = 0.075,
      z_max: float = 0.355,
      calf_peak_z: float = 0.230,
      max_width_shrink: float = 0.22,
      max_back_flatten: float = 0.72,
      max_front_trim: float = 0.25,
      center_shift_y: float = -0.008,
  ) -> dict[str, float]:
  ```
- **精确几何契约**：
  1. **作用对象限定**：仅处理 `body.data` 中属于 `material_index == 0`（`N00_000_00_Body_00_SKIN`）且满足 `z_min < world.z < z_max`、`abs(world.x) > 0.01`、`abs(world.y) < 0.15` 的顶点；鞋（slot 4，`z ≤ 0.066`）、短裤（slot 2，`z ≥ 0.375`）及脚踝以下（`z ≤ 0.075`）零变动。
  2. **左右独立直腿轴线**：对每侧（`sign = +1` 左腿、`sign = -1` 右腿），实测踝部锚点（`z ∈ [0.082, 0.098]`）与膝上锚点（`z ∈ [0.322, 0.342]`）的皮肤质心 `(cx_lo, cy_lo)` 与 `(cx_hi, cy_hi)`，以及膝-踝后缘线性包络 `y_back_line(z)`（由两锚点 `max(y)` 线性插值，约 `0.064 → 0.058`）。对每个待变形顶点，按 `t = (z - 0.090) / (0.330 - 0.090)` 夹紧至 `[0, 1]` 求线性直腿中心 `(cx(z), cy(z))`。
  3. **平滑包络（$C^1$ 零接缝）**：使用端点值为 0 且导数为 0 的平滑窗函数：
     - 上下端归零窗：`edge_env = smoothstep((z - z_min) / 0.045) * smoothstep((z_max - z) / 0.050)`（在 `z ≤ 0.075` 与 `z ≥ 0.355` 严格为 `0.0`）；
     - 腓肠肌钟形权重：`bell = math.exp(-((z - calf_peak_z) / 0.068) ** 2)`；
     - 组合强度：`w = edge_env * bell`。
  4. **三向直腿塑形（均在世界坐标计算后再逆变换写回 `vertex.co`）**：
     - **横向收窄（`X`）**：`new_x = cx + (world.x - cx) * (1.0 - max_width_shrink * w)`（将峰值 `w_x` 由 `0.0957 m` 收至 `0.0762 m`，窄于膝盖 `0.083 m`）；
     - **轴心前拉（消香蕉弯）**：`shifted_y = world.y + center_shift_y * w`；
     - **后侧腓肠肌压平（`+Y`）**：若 `shifted_y > y_back_line(z)`，按 `excess = shifted_y - y_back_line(z)` 压回 `new_y = y_back_line(z) + excess * (1.0 - max_back_flatten * edge_env)`；否则对前侧（`shifted_y < cy`）做平滑收紧 `new_y = cy + (shifted_y - cy) * (1.0 - max_front_trim * w)`。
  5. **调用顺序铁律**：必须在 `NearestSkinWeights(body)` 与 `add_socks(...)` **之前**调用；完成后调用 `body.data.update()` 并打印 `CALVES_SLIMMED` 日志（含变形前/后 `z=0.22..0.26` 处 `wx`, `dy`, `y_back`）。
- **边界与异常口径**：若任一侧在锚点区间顶点数 `< 4`，抛 `SystemExit("小腿锚点采样不足，无法执行直腿塑形")`，禁止静默跳过。

#### 5.2 `thicken_hands`（需求 #2：手掌加厚）

- **位置与精确签名**：`Assets/avatar/auto-build/scripts/build_phase1.py` →
  ```python
  def thicken_hands(
      armature,
      body,
      dorsal_scale: float = 1.56,
      palmar_scale: float = 1.44,
      proximal_finger_scale: float = 1.28,
      distal_finger_scale: float = 1.16,
      thumb_scale: float = 1.22,
  ) -> dict[str, float]:
  ```
- **精确几何契约**：
  1. **掌面法向与中平面确定性提取**（按 `side in ("R", "L")` 独立计算）：
     - 收集 `J_Bip_{side}_Hand` 权重 `> 0.5` 且排除拇指球（`world.y > -0.045`）的核心掌面顶点（约 50–70 个），以 `np.linalg.eigh(np.cov(...))` 取最小特征值对应特征向量 `palm_normal`；
     - **强制法向朝向约定**：令 `palm_normal` 指向**手背外侧**——即对右手（`-X` 侧）要求 `palm_normal.x < 0`，对左手（`+X` 侧）要求 `palm_normal.x > 0`（不满足则取反），确保左右完全镜像且手背（`d > 0`）/掌心（`d < 0`）语义绝对确定。
  2. **分区域平滑增厚（消除指根台阶、零穿袖口、保护 `shyCover` 间隙）**：
     - 对 `Body` slot 0 中受 `{J_Bip_{side}_Hand, J_Bip_{side}_Thumb1..3, Index/Middle/Ring/Little 1..3}` 影响的顶点，读取其各组权重：`w_hand`（手掌）、`w_arm`（`J_Bip_{side}_LowerArm`）、`w_p1`（四指第 1 节）、`w_p23`（四指第 2/3 节）、`w_thumb`（拇指 1/2/3 节）。
     - **参考中平面选择**：
       - 掌心与四指区：预先按四指各自的 `1`/`2`/`3` 节质心拟合对应局部 `d_ref`（避免因手掌微倾导致手指整体平移），并与掌心中平面 `d_palm = palm_center.dot(palm_normal)` 按 `w_hand` 权重平滑插值；
       - 拇指区（`w_thumb > 0.5`）：以拇指对应指节质心的 `thumb_center.dot(palm_normal)` 为 `d_ref`，仅沿 `palm_normal` 对称增厚 `thumb_scale`，不平移拇指位置！
     - **目标倍率合成**：
       - 掌面侧别倍率：`hand_s = dorsal_scale if signed_d >= 0 else palmar_scale`（手背 `1.56×` / 掌心 `1.44×`，平均 `1.50×`，同口径 PCA 实测掌心厚度由 `2.42 cm` → `3.31 cm`，为 `shyCover` 留足安全间隙）；
       - 按顶点权重加权合成：`target_scale = (w_hand * hand_s + w_p1 * proximal_finger_scale + w_p23 * distal_finger_scale + w_thumb * thumb_scale + w_arm * 1.0) / total_w`（腕部 `w_arm` 趋近 1 时自然衰减回 `1.0×`，绝不穿破 `HoodieCuff`）；
       - `new_world = world + palm_normal * signed_d * (target_scale - 1.0)`，逆变换写回 `vertex.co`。
  3. **调用顺序铁律**：必须在 `curl_rest_hands(...)` **之前**调用（手掌尚平直时法向 PCA 最精确），且在 `NearestSkinWeights(body)` 之前调用。完成后调用 `body.data.update()` 并打印 `HANDS_THICKENED` 日志（记录增厚前/后左右掌心厚度）。
- **边界与异常口径**：若任一侧核心掌面顶点数 `< 12` 或增厚前厚度 `< 0.005 m`，抛 `SystemExit("手掌核心顶点采样异常")`。

#### 5.3 `curl_rest_hands`（需求 #3：静置手型自然微弯）

- **位置与精确签名**：`Assets/avatar/auto-build/scripts/build_phase1.py` →
  ```python
  def curl_rest_hands(
      armature,
      body,
      finger_angles_deg: dict[str, tuple[float, float, float]] | None = None,
      thumb_angles_deg: tuple[float, float] = (8.0, 12.0),
  ) -> dict[str, float]:
  ```
- **默认值（1A 推荐自然微弯，单位：度，正值代表向掌心方向弯曲）**：
  ```python
  DEFAULT_FINGER_CURL_DEG = {
      "Index":  (6.0, 9.0, 7.0),   # 累计 22°：食指最舒展
      "Middle": (7.5, 11.0, 8.5),  # 累计 27°
      "Ring":   (9.5, 13.0, 10.0), # 累计 32.5°
      "Little": (11.5, 15.0, 11.5),# 累计 38°：小指最柔和收拢
  }
  ```
- **精确解剖弯曲契约（彻底规避畸变指骨陷阱）**：
  1. **不改动任何骨骼 Rest Pose**：不进入 Pose/Edit Mode，不改 `armature.data.bones`，确保 `skeletonRestPoses` 与 8 条动作四元数零破坏。
  2. **构建真实解剖铰链轴**：对每侧 `side in ("R", "L")`，复用 `thicken_hands` 相同的掌面法向 `palm_normal`（指向手背）与指伸方向 `finger_dir`（从 `J_Bip_{side}_Hand` 质心指向 `Middle2` 质心的单位向量），定义向掌心弯曲的统一旋转轴：
     - `bend_axis = finger_dir.cross(palm_normal).normalized()`
     - **强制方向自检（防止正负号写反成手背反折）**：取 `finger_dir` 绕 `bend_axis` 旋转 `+0.1 rad` 后的**位移向量**，必须满足 `((rot @ finger_dir) - finger_dir).dot(-palm_normal) > 0`（即向掌心侧移动），否则 `bend_axis = -bend_axis`！
  3. **三级解剖关节递进旋转（对四指 `Index`/`Middle`/`Ring`/`Little` 各自独立执行）**：
     - 由该指 3 个顶点组（`f"J_Bip_{side}_{finger}{1,2,3}"` 权重 `> 0.5`）的当前世界坐标质心 `c1, c2, c3` 计算三个真实关节枢轴：
       - `p_mcp`：`1` 节最靠近掌心的端面中心（沿 `finger_dir` 取 `1` 节顶点投影的 15% 分位点，约 `z≈0.453`）；
       - `p_pip`：`1` 节与 `2` 节质心中点（约 `z≈0.432`）；
       - `p_dip`：`2` 节与 `3` 节质心中点（约 `z≈0.413`）。
     - 对该指涉及的每个顶点（仅针对在 `finger1/2/3` 上权重和 `w_f > 0.01` 的 `Body` slot 0 顶点），按顶点沿 `finger_dir` 相对 `p_mcp`/`p_pip`/`p_dip` 的平滑分段进度 `s1, s2, s3 ∈ [0, 1]`（用 8 mm 宽 `smoothstep` 过渡避免关节折痕，并乘以 `min(1.0, w_f)` 权重系数以在掌指交界处无缝过渡）：
       - 按前向运动学（FK）远端到近端顺序依次施加绕 `(p_dip, bend_axis, a3 * s3)` → `(p_pip, bend_axis, a2 * s2)` → `(p_mcp, bend_axis, a1 * s1)` 的刚体旋转（确保各指节长度严格刚体保持、无枢轴漂移或剪切断裂）。
  4. **拇指柔和内收（`Thumb1/2/3`）**：
     - 实测当前右拇指沿 `-Y` 伸直（`Thumb3` 在 `y=-0.0964`），以 `Thumb2` 近端（`Thumb1` 与 `Thumb2` 质心中点）与 `Thumb3` 近端（`Thumb2` 与 `Thumb3` 质心中点）为枢轴，按 `p_t3 → p_t2` FK 顺序向掌心与食指内侧方向做柔和内收（`thumb_angles_deg = (8°, 12°)`），保证拇指自然贴合微弯手势且不与 `Index` 穿模（校验 `min_dist(Thumb3, Index) >= 0.010 m`）。
  5. 完成后调用 `body.data.update()` 并打印 `HANDS_CURLED` 日志（含每侧 `Index3`/`Middle3`/`Ring3`/`Little3`/`Thumb3` 沿 `-palm_normal` 朝掌心侧位移量与指长变化率）。
- **边界与异常口径**：若任一指尖朝掌心侧位移 `<= 0`（方向反了！）或手指总长变化超过 `10%`，立即抛 `SystemExit("静置手型弯曲方向或长度畸变")` 阻断构建。
- **`avatar_common.py` 兼容同步**：
  - `Assets/avatar/auto-build/scripts/avatar_common.py:166-168`（`shy_pose`）：移除四指额外 `rotX(-5°)`，由新 rest pose 微弯自然呈现遮嘴柔美手型，并消除向脸部额外叠弯的穿模风险；
  - `Assets/avatar/auto-build/scripts/avatar_common.py:203, 214, 225, 236, 247, 258`（`wave`）：过渡帧由 `finger_curl(-6, -5)` 调为 `finger_curl(-2, -1.5)`，挥手峰值帧由 `finger_curl(-12, -10)` 调为 `finger_curl(-4, -3)`，保持挥手舒展自然、不攥拳；`0.0` / `1.28` / `1.4` 首尾帧仍严格保持 `finger_curl(0, 0)`，完全满足 `_read_track` 首末帧偏差 `≤ 1°` 契约。

#### 5.4 `make_sock_white_material` 与导出白名单（需求 #4：袜子提白）

- **位置与精确签名**：`Assets/avatar/auto-build/scripts/build_phase1.py` →
  ```python
  def make_sock_white_material(
      name: str = "SockWhite",
      diffuse_color: tuple[float, float, float] = (1.0, 1.0, 1.0),
      emission_intensity: float = 0.70,
      roughness: float = 0.85,
  ):
  ```
- **精确材质节点契约（兼顾 Blender EEVEE 与 RealityKit ACES）**：
  - 创建全新 `ShaderNodeBsdfPrincipled` 材质（不复用 MToon 克隆，避免导出时附带 `Shader_NoneBlack.png` 覆盖 `emissiveColor`）：
    - `Base Color` = `(*diffuse_color, 1.0)`（纯白漫反射，保留袜面圆柱体受光面与背光面 3D 体积感及袜口卷边层次）；
    - `Emission Color` = `(emission_intensity, emission_intensity, emission_intensity, 1.0)`、`Emission Strength = 1.0`（遵循 `build_phase1.py:197-198` 既有 USD 导出约定：USD 无独立 emission strength 输入，必须把线性 HDR 强度写入 `Emission Color`）；
    - `Roughness` = `roughness`（`0.85`，柔和哑光棉袜，无塑料反光）；
    - `Metallic` = `0.0`；`Specular IOR Level` = `0.15`（若存在该输入）。
  - 在 `build_phase1.py` 中将 `add_socks(armature, body, nearest, trim_material)` 改为 `add_socks(armature, body, nearest, sock_material)`（其中 `sock_material = make_sock_white_material()`），同时将 `add_socks` 中段（`z=0.090..0.158`）径向偏置由 `0.0025` 微调为 `0.0038`（`z=0.164` 由 `0.0040` 调为 `0.0048`）消除直腿重采样后的局部透肤；`ShortsHemL`/`ShortsHemR` 继续使用 `trim_material`。
- **`export_phase1.py` 配套契约**：
  - `fix_preview_surface()`（第 28–42 行）：仅对 MToon 兼容节点执行修复（判断条件：`node.name == "Mtoon1Material.CompatibleShader"` 或 `node.inputs["Metallic"].default_value > 0.5`），防止覆写 `SockWhite`/`DrawstringWhite`/`MouthInner` 显式配置的 `Roughness` 与 `Specular IOR Level`；
  - `clean_stage()`（第 49–74 行）：`opaque_materials` 集合新增 `"SockWhite"`，保证导出后 `UsdPreviewSurface.opacity = 1.0`。

#### 5.5 `build_phase1.main` 执行顺序契约

`Assets/avatar/auto-build/scripts/build_phase1.py:1653-1676` 必须严格遵循以下依赖序：
1. `cut_shorts` → `inflate_tops` → `set_tops_uvs`（保持既有逻辑）；
2. `slim_calves(body)`（先修直小腿皮肤）；
3. `thicken_hands(armature, body)`（在平直手掌上精确计算法向并加厚）；
4. `curl_rest_hands(armature, body)`（在加厚后的手上绕真实关节做自然微弯）；
5. `nearest = NearestSkinWeights(body)`（基于全部变形完成后的最终皮肤重建 KDTree）；
6. `add_shorts_hem_bands` → `add_socks(armature, body, nearest, sock_material)`（袜子自动贴合直腿并使用 `SockWhite`）→ 其余既有服装/猫耳构建；
7. `ranges = ac.make_actions(armature, 30)` → `armature.animation_data.action = None` → 更新 `scene.render.fps = 30`、`scene.frame_start = 1`、`scene.frame_end = max(ranges.values())`（彻底消除动作漂移！）；
8. `bpy.context.view_layer.update()` → 保存 `OUT_BLEND`。

#### 5.6 `validate_phase1.py` 新增确定性检查契约

在 `Assets/avatar/auto-build/scripts/validate_phase1.py` 保留全部 24 项既有检查的前提下，追加以下 8 项硬门禁检查（合计 **32 项**，任一失败即退出码 `1` 并写入 `reports/validation-phase1.md`）：
1. **`Body` 网格存在性**：显式断言 `Body` 网格存在（缺失时在 `else` 分支显式失败，杜绝静默跳过）；
2. **直腿轮廓达标**：采样左右小腿皮肤 `z ∈ [0.22, 0.26]` 切片，断言 `w_x <= 0.082 m`、`d_y <= 0.095 m`、`max(y) <= 0.075 m`；
3. **踝/大腿衔接与袜子法线**：断言踝底 `z ∈ [0.055, 0.068]` 与大腿上缘 `z ∈ [0.358, 0.370]` 相对 `phase0.blend` 最大位移 `< 1e-4 m`，且 `SockL`/`SockR` 存在、顶点数正常、法线 100% 朝外；
4. **手掌厚度达标**：对左右手核心掌面（`J_Bip_{L,R}_Hand > 0.5, y > -0.045`）做 PCA 测厚，断言厚度 `∈ [0.029, 0.042] m`（相对 `phase0.blend` 原 `0.0242 m` 显著加厚）且左右对称差 `< 0.002 m`；
5. **静置手型自然微弯**：相对 `work/phase0/minimate_phase0.blend` 同索引顶点对比，断言左右手 `Index3`/`Middle3`/`Ring3`/`Little3` 质心均向掌心侧内弯（右手 `dx > +0.004 m`，左手 `dx < -0.004 m`），且递增顺序 `|dx(Index3)| < |dx(Little3)|`、单指长度变化 `< 10%`；
6. **动作防穿模间隙**：在 `minimate_phase1.blend` 中评估 `shyCover` 第 15 帧与 `heart` 第 15 帧，断言 `shyCover` 右手到 `Face` 最小欧氏距离 `>= 0.002 m`、`heart` 左右手最小欧氏距离 `>= 0.015 m`；
7. **最新动作已同步**：断言 `shyCover` 第 15 帧 `J_Bip_R_UpperArm` 与 `avatar_common.py` 中 `shy_pose` 夹角 `< 0.5°`（防止再次静默导出旧动作）；
8. **USDZ 白袜材质契约**：在打开的 `minimate_phase1.usdz` Stage 中断言存在 `/root/_materials/SockWhite`、`SockL`/`SockR` 绑定到 `SockWhite`，且其 `UsdPreviewSurface` 满足 `opacity == 1.0`、`metallic == 0.0`、`roughness >= 0.80`、`emissiveColor` 各通道 `>= 0.55`、`diffuseColor` 各通道 `>= 0.15`。

---

### 6. 原子化施工步骤（自底向上）

- **Step 1：修补 `export_phase1.py` 材质白名单与 MToon 精准修复**
  - 改动文件：`Assets/avatar/auto-build/scripts/export_phase1.py`
  - 改动要点：按 §5.4 调整 `fix_preview_surface()` 仅修复 MToon 兼容节点，并将 `"SockWhite"` 加入 `clean_stage()` 的 `opaque_materials`。
  - 最小验证命令：
    ```bash
    python3 -m py_compile Assets/avatar/auto-build/scripts/export_phase1.py
    ```

- **Step 2：同步调整 `avatar_common.py` 动作手指叠加量**
  - 改动文件：`Assets/avatar/auto-build/scripts/avatar_common.py`
  - 改动要点：按 §5.3 收敛 `wave` 附加手指弯曲与移除 `shyCover` 冗余 `-5°` 叠弯，保持所有首末帧严格归零。
  - 最小验证命令：
    ```bash
    python3 -m py_compile Assets/avatar/auto-build/scripts/avatar_common.py
    ```

- **Step 3：在 `build_phase1.py` 实现 4 项精修函数并补齐 `ac.make_actions` 同步**
  - 改动文件：`Assets/avatar/auto-build/scripts/build_phase1.py`
  - 改动要点：依次实现 `slim_calves`、`thicken_hands`、`curl_rest_hands`、`make_sock_white_material`，并按 §5.5 依赖序接入 `main()`；运行构建脚本生成 `work/phase1/minimate_phase1.blend`。
  - 最小验证命令：
    ```bash
    cd Assets/avatar/auto-build && blender --background --factory-startup --python scripts/build_phase1.py
    ```
    检查标准输出包含 `CALVES_SLIMMED`、`HANDS_THICKENED`、`HANDS_CURLED`、`SOCK L`/`SOCK R`、`ACTIONS ['heart', 'leanBack', 'lookAround', 'nod', 'notice', 'shyCover', 'spin', 'wave']`、`SAVED ...minimate_phase1.blend`，退出码 0。

- **Step 4：导出新 USDZ + `.actions.json`**
  - 改动文件：无（运行导出脚本生成 `out/minimate_phase1.usdz` + `out/minimate_phase1.actions.json`）
  - 最小验证命令：
    ```bash
    cd Assets/avatar/auto-build && blender --background --factory-startup --python scripts/export_phase1.py
    ```
    检查标准输出包含 `TIMELINE ... frames=1-295`、`CLEANED_USD`、`USDZ ...minimate_phase1.usdz`，退出码 0。

- **Step 5：扩展并运行 `validate_phase1.py` 全量确定性门禁**
  - 改动文件：`Assets/avatar/auto-build/scripts/validate_phase1.py`
  - 改动要点：按 §5.6 追加 8 项确定性检查（共 32 项）并运行验证。
  - 最小验证命令：
    ```bash
    cd Assets/avatar/auto-build && blender --background --factory-startup --python scripts/validate_phase1.py
    ```
    检查标准输出 `VALIDATION_OK triangles=<...>` 且 `reports/validation-phase1.md` 失败项为 `- 无`。

- **Step 6：扩展 `render_phase1.py` 局部特写并生成审核对比材料**
  - 改动文件：`Assets/avatar/auto-build/scripts/render_phase1.py`
  - 改动要点：新增正交特写相机函数，输出 `leg_side_closeup.png`（`z=0.0..0.40` 侧面直腿+白袜特写）、`leg_back_closeup.png`（背面直腿+白袜特写）、`hand_closeup.png`（静置微弯与手掌厚度多角拼图），写入 `review.html`；同时重跑 `render_usd_preview_phase1.py` 生成 PBR 预览。
  - 最小验证命令：
    ```bash
    cd Assets/avatar/auto-build && blender --background --factory-startup --python scripts/render_usd_preview_phase1.py && blender --background --factory-startup --python scripts/render_phase1.py
    ```
    检查生成 `renders/phase1/{model_front,model_side,model_back,leg_side_closeup,leg_back_closeup,hand_closeup,actions_contact_sheet,usd_preview_front,usd_preview_back}.png` 与 `review.html`，并用 `read_file` 查看关键渲染图目视核验无明显畸变或穿模。

- **Step 7：同步 App 资源与运行 Swift / iOS 回归门禁 + 文档收尾**
  - 改动文件：`App/MiniMate/Resources/Avatar/minimate.usdz`、`App/MiniMate/Resources/Avatar/minimate.actions.json`、`Assets/avatar/auto-build/reports/phase1-review.md`、`Assets/avatar/auto-build/README.md`
  - 改动要点：复制验证通过的候选 USDZ 与 `.actions.json` 到 App 资源目录；更新 `phase1-review.md` 与 `README.md`；运行 Swift 单元测试与 iOS Simulator 编译门禁。
  - 最小验证命令：
    ```bash
    cp Assets/avatar/auto-build/out/minimate_phase1.usdz App/MiniMate/Resources/Avatar/minimate.usdz && \
    cp Assets/avatar/auto-build/out/minimate_phase1.actions.json App/MiniMate/Resources/Avatar/minimate.actions.json && \
    (cd Packages/MiniMateKit && swift test) && \
    xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
    ```

---

### 7. 确定性测试矩阵与验收门禁

#### 7.1 确定性验证矩阵（全部写入 `validate_phase1.py` 自动断言，严禁弱断言）

| 检查归属 | 覆盖类别 | 验证场景 | 必须写死的断言底线 |
| :--- | :--- | :--- | :--- |
| `validate_phase1.py` | 正例（直腿） | 左右小腿皮肤 `z ∈ [0.22, 0.26]` 截面 | 两侧均满足 `w_x <= 0.082 m`、`d_y <= 0.095 m`、`max(y) <= 0.075 m`（较 `phase0.blend` 原 `0.0957 / 0.1193 / +0.0959` 显著直化） |
| `validate_phase1.py` | 边界（鞋/裤衔接） | 踝底 `z ∈ [0.055, 0.068]` 与大腿上缘 `z ∈ [0.358, 0.370]` | 与 `phase0.blend` 同索引顶点最大位移 `< 1e-4 m`；`SockL`/`SockR` 存在、法线 100% 朝外、顶点数正常 |
| `validate_phase1.py` | 正例（厚掌） | 左右掌心核心顶点 PCA 厚度 | 两侧厚度均落在 `[0.029, 0.042] m`（较 `phase0.blend` 原 `0.0242 m` 显著加厚）；左右对称差 `< 0.002 m` |
| `validate_phase1.py` | 正例（微弯手） | 相对 `phase0.blend` 四指指尖质心位移 | 右手 `Index3..Little3` 均 `dx > +0.004 m`、左手均 `dx < -0.004 m`（确认向掌心弯而非反折）；满足 `|dx(Index3)| < |dx(Little3)|` 递进曲线；单指长度相对 `phase0` 变化 `< 10%` |
| `validate_phase1.py` | 异常反例（防穿模） | `shyCover` 第 15 帧 & `heart` 第 15 帧几何间隙 | `shyCover` 右手至 `Face` 最小欧氏距离 `>= 0.002 m`；`heart` 左右手最小欧氏距离 `>= 0.015 m` |
| `validate_phase1.py` | 正例（白袜材质） | USDZ `/root/_materials/SockWhite` 校验 | `SockL`/`SockR` 绑定至 `SockWhite`；`opacity == 1.0`；`metallic == 0.0`；`emissiveColor` 三通道均 `>= 0.55`；`diffuseColor` 三通道均 `>= 0.15`；`roughness >= 0.80`（确认未被 `fix_preview_surface` 误覆写为 0.7） |
| `validate_phase1.py` | 兼容回归（核心契约） | 52 ARKit + 124 形态键 + 8 动作 + 295 帧 + 面数/贴图 | `Face` 52 ARKit 零缺失、目标数 `== 124`；USDZ 单条 `actions` 时间线 1..295 连续、无 `blendShapeWeights`；`shyCover` frame 15 匹配 HEAD `avatar_common.py`（夹角 `< 0.5°`）；三角面 `< 50,000`；贴图全 `≤ 2048²` |
| `swift test` | 兼容回归（Swift 包） | `ActionClipManifestTests`、`BlendShapeIndexTests` 等全量单测 | 全部 Suite 零失败，验证 `minimate.actions.json` 格式与 52 ARKit 契约未破坏 |

#### 7.2 完整门禁命令清单

```bash
# 1. 重建 Phase 1 模型 + 导出 USDZ + 全量资产确定性门禁
cd Assets/avatar/auto-build && \
blender --background --factory-startup --python scripts/build_phase1.py && \
blender --background --factory-startup --python scripts/export_phase1.py && \
blender --background --factory-startup --python scripts/validate_phase1.py

# 2. 生成 USDZ PBR 预览与多视角/特写对比渲染
cd Assets/avatar/auto-build && \
blender --background --factory-startup --python scripts/render_usd_preview_phase1.py && \
blender --background --factory-startup --python scripts/render_phase1.py

# 3. 核对 App 资源与候选产物字节一致
cmp Assets/avatar/auto-build/out/minimate_phase1.usdz App/MiniMate/Resources/Avatar/minimate.usdz && \
cmp Assets/avatar/auto-build/out/minimate_phase1.actions.json App/MiniMate/Resources/Avatar/minimate.actions.json

# 4. Swift 纯逻辑全量单元测试
cd Packages/MiniMateKit && swift test

# 5. iOS Simulator App 编译验证（含资源打包）
xcodebuild -project App/MiniMate.xcodeproj -scheme MiniMate \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# 6. 仓库状态与只读基线核查（确认未误改 Swift 代码/Face/只读素材，且未 commit）
git status
```

#### 7.3 人工真机验收要点（实施完成后由用户在 iPhone 上确认）
1. **小腿直腿**：在调试面板播放 `spin`（建议调至 `0.5×` 慢速循环），检查正面、侧面、背面小腿是否纤细笔直、无小腿肚肌肉凸包，且袜口与鞋口无露肉或穿模；
2. **手掌加厚**：静置与 `wave` / `heart` 动作下观察左右手掌厚度，确认不再薄如纸片，且腕部与袖口过渡自然；
3. **静置微弯**：停止所有动作处于静置与视线追踪状态，观察双手呈自然柔和微弯；再逐一触发 `wave`、`heart`、`shyCover`、`spin`、`nod`、`leanBack`、`lookAround`、`notice`，确认动作起止零闪烁、无手脸穿模；
4. **白袜提白**：在浅色与深色系统外观下分别观察白袜正面及 `spin` 侧/背面，确认呈现干净白色且保留柔和立体阴影；
5. **基础零回归**：调试面板确认 `missingNames` 为空（52/52 形态键）、8/8 动作均正常播放。

---

### 8. 项目附加产出要求

- `Assets/avatar/auto-build/reports/phase1-review.md`：末尾追加「Phase 1.4 真机精修（2026-11-25）」一节，记录 4 项精修前后实测几何/材质数据及门禁结果；
- `Assets/avatar/auto-build/README.md`：顶部简要补充 Phase 1.4 精修状态。

---

### 9. 实施方偏差止损规则（固定条款）

- **可自决微调**：内部私有变量名、局部辅助函数拆分、注释与日志格式调整，以及在保证 §7.1 全部确定性断言全绿前提下的细微过渡窗宽调整（不改变对外契约、参数方向与断言底线）。
- **必须立即停工上报（严禁擅自绕过）**：
  1. 发现既定签名/契约与仓库现状冲突；
  2. 需要修改文件改动表之外的文件（尤其是任何 Swift 源码、`build_avatar.py` 或 `Face` 网格）；
  3. 需要改写既有测试或放宽 §7.1 任何硬门禁阈值（例如为绕过 `shyCover` 穿模而放宽最小间隙）；
  4. 实测出现目视可见的网格撕裂、指节扭曲、袜子脱离/穿模或 `Face` 形态键缺失；
  5. 实测发现新的 Blender/USD/Xcode 环境阻断问题。

---

## 复审闭环记录（实施后由 task-review-loop 追加）

- **复审机制**：单节点独立只读审查员（`reviewer`，**Gemini 4 Neon (High)**），两轮复审均核验 Git 字节级快照指纹确认审查员零修改。
- **闭环结果**：共 **2 轮**独立复审，**一致通过**（阻断项 = 0）。

### Round 1（结论：需修改）
- **核心复验通过**：独立只读 Blender/pxr 实测与渲染目视复验确认 4 项精修几何/材质/动作/USDZ 导出、52 ARKit / 124 形态键 / 8 动作 / 295 帧、零改骨、零透肤、零穿模与 `App/MiniMate/Resources/Avatar/` 字节一致性全部达标。
- **3 项阻断项及处置**：
  1. **执行单残留落选分支与契约漂移** → 已清理全部 `若拍板 1A/1B/2B/3B/4A` 与设计期表述，同步最终参数（`slim_calves` `0.72/0.25/-0.008`、`curl_rest_hands` FK 逆序 `DIP→PIP→MCP` 与位移方向自检、`add_socks` 径向偏置 `0.0038/0.0048`、同口径 `phase0.blend` 基线与 32 项门禁口径）。
  2. **`validate_phase1.py` 缺失 `Body` 存在性断言** → 已补充 `check("Body 网格存在", body is not None)` 及 `else` 显式失败分支，并采纳非阻断建议 #1 将报告标题更新为 `# Phase 1.4 验证报告`；重跑 `validate_phase1.py` 全部 **32/32** 项通过（`VALIDATION_OK triangles=39032`）。
  3. **`phase1-review.md` 门禁总数与实际不符（写 30 实为 31/32）** → 已逐字同步为 `32 项` / `32/32 项通过`。
- **留档的非阻断建议（不阻断验收）**：`thicken_hands` 拇指 `w_thumb > 0.5` 硬切分与 `curl_rest_hands` 指蹼重叠顶点顺序旋转（实测全手边长比 `[0.826, 1.429]`，特写平滑无畸变）；`validate_phase1.py` 动作防穿模目前校验第 15 帧（独立全帧实测 `1..35` 最小间隙 `shyCover=2.32 mm`、`heart=40.97 mm`，后续可按需扩至多帧抽检）。

### Round 2（结论：通过，阻断项 = 0）
- 复核 Round 1 全部 3 项阻断项彻底根治，`grep` 确认执行单落选分支零残留，`validation-phase1.md` 实测 `32` 项 ✅ / `0` 项 ❌ 与 `phase1-review.md` 逐字一致，未引入任何新回归。

### 最终验收门禁实测证据
- `validate_phase1.py`：`VALIDATION_OK triangles=39032`（`32/32` 通过，失败项 `- 无`）
- `cmp` 资源同步：`out/minimate_phase1.usdz` 与 `App/MiniMate/Resources/Avatar/minimate.usdz` 字节一致；`minimate_phase1.actions.json` 与 `App/MiniMate/Resources/Avatar/minimate.actions.json` 字节一致
- `swift test`（`Packages/MiniMateKit`）：**14 个 Suite / 76 条测试全部通过**（0 失败）
- `xcodebuild`（`MiniMate` iOS Simulator 无签名编译）：`** BUILD SUCCEEDED **`
- 收口状态：未勾选任务清单，未 `git commit`，未 `git push`，等待用户真机验收确认。
