# 小瓜形象自动化重建 — 任务计划书

**状态**：Phase 0 已通过（2.54）；Phase 1 已通过；Phase 1.2 复审（脖子/猫耳）2.87 已确认；眼睛/嘴巴/服色修订（瞳孔再内收 2 px、无唇线/唇阴影，单一深色内口腔 + idle 小张口（无贯穿横线/悬空上唇线/突兀阴影；sad/concerned 不笑、surprised 小 o、happy 张口、playful 张嘴；吐舌待单独舌头层）、连帽衫按原稿取色）待复审；之后可进入 Phase 3 接入 App（Phase 2 可选）
**日期**：2026-11-21
**工作目录**：`Assets/avatar/auto-build/`
**输入**：`Assets/avatar/VRoid_V110_Female_v1.1.3.vrm`、`Assets/avatar/reference/`、`Assets/avatar/vroid-recipe.md`
**最终产物**：候选 `minimate.vrm` / `minimate.usdz`、贴图、对比渲染、验证报告
**边界**：本计划只改形象素材，不改 App / Swift Package / 既有 spec；最终替换 `App/MiniMate/Resources/Avatar/minimate.usdz` 必须单独批准。

---

## 1. 为什么做

### 1.1 现状

- 2D 设计原图已确认：`Assets/avatar/reference/three-view.jpg`（正/侧/背三视图）与 `expression-sheet.jpg`（6 组表情）。
- `Assets/avatar/vroid-recipe.md` 已经把设计拆成色值、比例、发型、服装和表情参数，但仍是“给人看的配方”，需要手工在 VRoid 里操作。
- 当前 `Assets/avatar/VRoid_V110_Female_v1.1.3.vrm` 是临时占位形象：标准头身比、灰发、白 T 恤、黑短裤，与设计差异大。
- 当前 `App/MiniMate/Resources/Avatar/minimate.usdz` 已验证：**124 个 blendShape 目标（Basis 不计）、52 个 ARKit 名称齐全、8 条 SkelAnimation 齐全**。导出管线本身不会丢形态键。
- 底座模型实测：`Face` 网格 125 个形态键（含 Basis）、118 根骨骼；脸/身体/头发/衣服分开；贴图是 VRoid 标准图集（`_01`–`_17`），UV 布局固定。

### 1.2 为什么不能“自动操作 VRoid”

VRoid Studio 没有公开 API / CLI。现有自动化方案都不适合当前 macOS 环境：

| 方案 | 结论 | 原因 |
|---|---|---|
| 手动 VRoid Studio | 排除 | 用户明确不想手工操作 |
| `vroid-studio-mcp`（BepInEx 注入内部 API） | 排除 | Windows 正式支持、Linux 走 Wine，macOS 未发布；只能改预设/滑杆/颜色，不做贴图、发型分组、Perfect Sync；只保存 `.vroid` |
| `mcp-vroid`（截图 + OCR + 点击） | 排除 | 仅 Linux/Wayland；对 macOS 原生 VRoid 不可用 |
| AI 一键出 VRM（Charakuru / Meshy 等） | 只适合原型 | 默认没有 52 个 ARKit 形态键，脸部/拓扑/绑定不适配现有 App 契约；换模型等于重做表情系统 |
| Blender 无头脚本改现有模型 | **采用** | 保留 52 形态键；标准 UV 可脚本重绘；现有 `export_avatar.py` 已能导出 USDZ |

### 1.3 为什么必须保留现有 `Face` 网格

52 个 ARKit 名称落在 `Face` 网格上。设计里的“像不像”大部分由**脸部贴图 + 头身比 + 发型轮廓**决定，不需要重做脸部拓扑。保留 `Face` 是同时满足“接近设计”和“不丢 52 键”的最低风险路径。

### 1.4 这次为什么能自动化

- VRoid 标准贴图集，UV 固定，适合程序化重绘。
- 头发、身体、衣服是独立网格；新增猫耳发箍、呆毛、连帽衫不会碰到 `Face`。
- Blender 5.3 已安装，VRM 插件已可用；`pxr` 随 Blender 提供，能直接检查 USDZ。
- 现有 `Assets/avatar/export_avatar.py` 已打通 VRM → USDZ，并保留形态键与 8 条动作。

---

## 2. 目标与边界

### 2.1 目标

1. 在 `Assets/avatar/auto-build/` 内完成全部自动化构建，不手工打开 VRoid。
2. 产出与 2D 设计“可辨认地接近”的形象：Q 版比例、银白→淡蓝 bob、猫耳、呆毛、琥珀色大眼、ω 形小嘴、白蓝渐变连帽衫、浅蓝短裤、白袜与运动鞋。
3. 严格保留 52 个 ARKit blendShape 名称、8 个动作、`Head` / `Neck` 骨骼。
4. 输出可被现有 `AvatarRenderer` 契约加载的 USDZ；最终在真机调试面板通过 52 滑杆与 8 动作验收。
5. 每一步可重复运行、可验证；生成物与验证报告都落在工作目录内。

### 2.2 非目标

- 不做像素级 / 原画级还原；2D 线稿、喷枪渐变、布料褶皱不追求完全一致。
- 不重新绑定骨架、不重做 52 个 ARKit 形态键。
- 不生成可在 VRoid Studio 里继续拖滑杆的 `.vroid` 工程。
- 不新增表情、动作或物理弹簧骨；沿用现有 8 个动作与 52 个 ARKit 名称。
- Phase 0 / Phase 1 不改 App 代码；Phase 3 只在批准后替换 App 资源。
- 不使用来源或许可不明的外部模型/服装素材作为默认方案。

### 2.3 成功标准

**硬门禁（每次构建必须通过）**

| # | 检查 | 通过条件 |
|---|---|---|
| G-1 | ARKit 形态键 | `Face` 含全部 52 个 ARKit 名称，大小写完全一致 |
| G-2 | 动作 | 8 条动画，名称与 `ActionTag.rawValue` 完全一致 |
| G-3 | 骨骼 | 存在 `Head`、`Neck`（允许 `J_Bip_C_Head` / `J_Bip_C_Neck` 后缀匹配） |
| G-4 | 面数 | 三角面 < 50k |
| G-5 | 贴图 | 单张贴图 ≤ 2048²，无缺失引用 |
| G-6 | USDZ | 可由 pxr 打开；52 名称、8 动作、贴图引用都在 |
| G-7 | 真机 | `BlendShapeIndex.missingNames` 为空；52 滑杆与 8 动作可用 |

**视觉门禁（人工评审）**

- 三视图并排对比：正面、侧面、背面。
- 设计特征清单逐项确认：头身比、发色渐变、猫耳发箍（含内耳渐变与侧面连接件）、呆毛、琥珀色虹膜与高光、细平眉、ω 形嘴、肤色/腮红、连帽衫渐变与抽绳/口袋、短裤白边、白袜、鞋色、整体 pastel 质感。
- 8 个动作播放时无明显穿模、断手、头发/衣服穿插。

**“接近”的量化口径**

- 以 App 常用展示尺寸（形象占屏高约 1/2–2/3）为准，不以放大原画为准。
- 主观目标：Phase 0 达到 70–80%，Phase 1 达到 80–90%，Phase 2（如需要）争取 85–92%。这是评审估计值，最终以并排渲染和你的确认为准。

---

## 3. 硬约束与不变量

| # | 约束 | 执行方式 |
|---|---|---|
| I-1 | 不修改 `Face` 拓扑 | Phase 0/1 禁止 Remesh、Decimate、Boolean、Subdivision 应用、Join 到其他网格、换脸 |
| I-2 | 新增网格与 `Face` 分离 | 猫耳发箍、呆毛、连帽衫、鞋子附件都作为独立对象，挂到 `Head` 或对应骨骼 |
| I-3 | 只做保形态键的变换 | 贴图替换、材质修改、对象级缩放、骨骼级缩放/平移；不做会重排顶点的编辑 |
| I-4 | 脸型调整只在 Phase 2 | 若 Phase 0/1 脸型仍不够，必须另开评审；脚本对 Basis + 全部形态键施加同一变形场，不换拓扑 |
| I-5 | 动作名称不可变 | 继续使用 `nod`、`wave`、`spin`、`heart`、`shyCover`、`leanBack`、`lookAround`、`notice` |
| I-6 | 不引入 App 运行时依赖 | Blender / numpy / pxr / usdzip 只在开发机使用，不进入 App |
| I-7 | 源素材不入库 | `.vrm`、`.blend`、设计图、生成贴图/渲染默认不提交；仅计划、脚本、配置、验证报告可入库 |
| I-8 | 最终替换需批准 | 候选 USDZ 先放 `auto-build/out/`；真机验收通过并获批准后才复制到 App |

---

## 4. 怎么做

### 4.1 数据流

```text
设计三视图 + 表情表 + vroid-recipe.md
                │
                ▼
        config/avatar.json（色值、比例、开关）
                │
   ┌────────────┼─────────────┬──────────────┐
   ▼            ▼             ▼              ▼
00_audit    10_textures    20_build      30_validate
底座审计      贴图生成       网格/骨骼/材质   硬门禁检查
   │            │             │              │
   └────────────┴──────┬──────┴──────────────┘
                       ▼
               out/minimate_phaseN.vrm
                       │
                export_usdz.py
                       ▼
               out/minimate_phaseN.usdz
                       │
             40_render + 人工评审
                       ▼
              reports/validation-phaseN.md
                       │
               （批准后）替换 App 资源
```

### 4.2 工作目录

全部新增文件都在 `Assets/avatar/auto-build/` 内；父目录的 VRM、设计图、配方只读，不移动、不覆盖。

```text
Assets/avatar/auto-build/
├── PLAN.md                     # 本文件
├── README.md                   # 后续补：如何运行、如何复现
├── .gitignore                  # 忽略 work/ textures/ renders/ out/
├── config/
│   └── avatar.json             # 唯一参数源
├── scripts/
│   ├── audit_base.py           # 导入底座，审计形态键/骨骼/材质/贴图
│   ├── generate_textures.py    # 生成标准 UV 贴图
│   ├── build_avatar.py         # 比例、发型、猫耳发箍、呆毛、服装、材质
│   ├── export_usdz.py          # 复用/包装现有导出管线，带校验钩子
│   ├── validate_avatar.py      # Blender 场景 + USDZ 双重门禁
│   └── render_compare.py       # 三视图/表情/动作渲染，生成对比图
├── work/                       # 中间 .blend、提取的原始贴图、日志（不入库）
├── textures/                   # 生成的贴图（不入库，按 phase 分目录）
├── renders/                    # 评审渲染（不入库）
├── out/                        # 候选 VRM / USDZ（不入库）
└── reports/                    # 审计与验证报告（文本，可入库）
```

### 4.3 配置

使用 JSON（Python 标准库可读，不引入 YAML 依赖）。所有可调参数集中在 `config/avatar.json`，脚本不硬编码色值。

```json
{
  "source": {
    "vrm": "../VRoid_V110_Female_v1.1.3.vrm",
    "threeView": "../reference/three-view.jpg",
    "expressionSheet": "../reference/expression-sheet.jpg",
    "recipe": "../vroid-recipe.md"
  },
  "palette": {
    "skinBase": "#F7DCD3",
    "skinShadow": "#E8BFB4",
    "blush": "#F3B3AD",
    "hairRoot": "#F4F1EC",
    "hairMid": "#E3E4EC",
    "hairTip": "#9CB6CE",
    "irisTop": "#8A5A3A",
    "irisCenter": "#C08F73",
    "irisBottom": "#E8C79B",
    "hoodieTop": "#F7F6F4",
    "hoodieBottom": "#CAD7EA",
    "shorts": "#C7D1E9",
    "shoeAccent": "#AFC6E6"
  },
  "proportions": {
    "headScale": 1.35,
    "eyeScale": 1.25,
    "totalHeight": 1.1,
    "legLengthScale": 0.75,
    "armLengthScale": 0.8
  },
  "features": {
    "catEars": true,
    "ahoge": true,
    "headband": true,
    "hoodie": "phase1"
  },
  "textures": { "maxSize": 2048 },
  "validation": { "arkitCount": 52, "actionCount": 8, "maxTriangles": 50000 }
}
```

上述比例是初始值，Phase 0 会用渲染迭代确定最终值。

### 4.4 工具链

| 工具 | 用途 | 是否进入 App |
|---|---|---|
| Blender 5.3 + VRM Add-on | 导入、改模、渲染、导出 | 否 |
| Blender 自带 Python + numpy | 生成贴图、批量改网格/权重 | 否 |
| Blender 自带 pxr | 检查 USDZ 结构 | 否 |
| macOS `usdzip` | 打包 USDZ | 否 |
| 现有 `Assets/avatar/export_avatar.py` | 导出参考；必要时在工作目录内复制一份并加校验 | 否 |

不新增 Pillow、OpenCV 等依赖；贴图用 numpy 在 Blender Python 内生成。

### 4.5 脚本职责

| 脚本 | 输入 | 输出 | 关键检查 |
|---|---|---|---|
| `audit_base.py` | 底座 VRM | `reports/baseline-audit.md`、`work/base/*.png` | 52 名称、125 形态键、118 骨骼、贴图 UV/尺寸 |
| `generate_textures.py` | 底座贴图 + 配置 | `textures/phaseN/*.png` | 尺寸 ≤2048、文件名与 VRoid 图集对应、无透明通道错误 |
| `build_avatar.py` | 底座 VRM + 贴图 + 配置 | `work/phaseN/minimate_phaseN.blend` | 不触碰 `Face` 拓扑；所有新增网格独立；动作名称正确 |
| `export_usdz.py` | phase `.blend` | `out/minimate_phaseN.usdz` | 52 名称、8 动作、骨骼、贴图打包 |
| `validate_avatar.py` | phase `.blend` + `.usdz` | `reports/validation-phaseN.md` | 全部硬门禁 G-1–G-6 |
| `render_compare.py` | phase `.blend` + 参考图 | `renders/phaseN/`：三视图对比、脸部特写、表情网格、ARKit 冒烟网格、动作抽帧表、转台视频、`review.html` | 同一相机/光照；参考图与模型同高并排；8 动作抽帧有名称 |

### 4.6 贴图策略

- 以现有 VRoid 图集为 UV 布局模板，**不重新 UV**。
- 用 numpy 分层绘制：底色 → 渐变 → 五官/服装细节 → 高光/阴影；每个 phase 输出一套完整图集。
- 重点图集：
  - 脸/五官：`_01` 嘴、`_02` 虹膜、`_03` 高光、`_04` 脸、`_07` 眉、`_08` 睫毛、`_09` 眼线；
  - 头发：`_12` 后发、`_16`/`_17` 头发；
  - 服装：`_13` 短裤、`_14` 上衣、`_15` 鞋。
- 设计图只用于配色/轮廓参考；色值以 `vroid-recipe.md` 为准，避免从截图取色受光照影响。
- 贴图生成后先在 Blender 中直接预览，不依赖 VRoid 的材质系统。

### 4.7 几何策略

| 部位 | Phase 0 | Phase 1 | 风险 |
|---|---|---|---|
| 头身比 | 骨骼/对象级缩放头、眼、四肢；目标接近 1:2.5 | 按渲染微调 | 颈/肩蒙皮拉伸 |
| 脸型 | 不改拓扑；靠贴图 + 头身比 | 必要时 Phase 2 做全形态键一致变形 | 相似度上限 |
| 头发 | 现有 bob 改形（无形态键，可安全编辑）+ 渐变贴图 | 调整刘海/发束轮廓 | 发束感不足 |
| 猫耳发箍/呆毛 | 程序化网格，挂 `Head` 骨 | 细化内耳、材质 | 与头发穿插 |
| 连帽衫 | 先把上衣改成目标配色（仍是 T 恤轮廓） | 程序化帽子/长袖/抽绳/口袋，或合并许可明确的免费素材 | 最大质量风险 |
| 短裤/袜/鞋 | 改色 + 白边/蓝灰细节 | 调整长度与鞋型 | 低 |
| 52 键 | 不动 `Face` 拓扑 | 同左 | 受 I-1 保护 |

### 4.8 动作策略

- 继续使用 `export_avatar.py` 的 8 个程序化动作。
- 比例缩短后重新检查 `wave`、`heart`、`shyCover` 的手部到达位置与穿模；必要时在 `build_avatar.py` 中调整关键帧，但动作名称不变。
- 不新增动作；M2 的口型层不在此计划内。

### 4.9 导出与验证

1. `build_avatar.py` 保存 phase `.blend`。
2. `export_usdz.py` 调用 Blender USD 导出；沿用现有“逐个动作导出 → 合并 SkelAnimation → 相对化贴图 → usdzip”的流程。
3. `validate_avatar.py` 在 Blender 内检查 `.blend`，再用 pxr 检查 `.usdz`。
4. 任一硬门禁失败即停止，不出候选包。
5. 通过后生成 `reports/validation-phaseN.md`，再进入人工评审。

---

## 5. 分阶段任务

### Phase 0 — 底座审计 + 第一版相似度（不动 `Face` 拓扑）

| 任务 | 内容 | 产出 | 完成条件 |
|---|---|---|---|
| T0.1 | 建立工作目录、`config/avatar.json`、`.gitignore` | 目录骨架 | 所有生成物路径固定在 `auto-build/` 内 |
| T0.2 | `audit_base.py`：审计底座并提取贴图 | `reports/baseline-audit.md`、`work/base/` | 记录 52 名称、125 形态键、118 骨骼、贴图尺寸/UV |
| T0.3 | 渲染当前占位形象三视图 | `renders/baseline/` | 作为对比基线 |
| T0.4 | `generate_textures.py`：生成 Phase 0 全套贴图 | `textures/phase0/` | 尺寸、命名、UV 对齐检查通过 |
| T0.5 | `build_avatar.py`：换贴图 + Q 版比例 + 猫耳发箍/呆毛 | `work/phase0/*.blend` | `Face` 拓扑未变；52 名称仍在 |
| T0.6 | `export_usdz.py` + `validate_avatar.py` | `out/minimate_phase0.usdz`、验证报告 | G-1–G-6 全通过 |
| T0.7 | `render_compare.py`：三视图对比、脸部特写、表情网格、动作抽帧、转台视频、`review.html` | `renders/phase0/` | 正/侧/背同高并排；8 动作抽帧有名称；审核页可在浏览器打开 |
| T0.8 | 人工评审 | 评审记录 | 你确认方向或提出修改 |

**Phase 0 不包含**：连帽衫建模、脸型变形、最终材质调优。

### Phase 1 — 服装与轮廓

| 任务 | 内容 | 产出 | 完成条件 |
|---|---|---|---|
| T1.1 | 连帽衫网格：帽子、长袖、抽绳、口袋、下摆 | `work/phase1/` | 穿上后无明显穿模；权重随骨骼 |
| T1.2 | 短裤白边、袜口、鞋面蓝灰细节 | 贴图/网格 | 与设计特征一致 |
| T1.3 | 头发刘海/发束轮廓细化 | 网格 | bob 轮廓更接近设计 |
| T1.4 | 8 动作兼容性检查与关键帧修正 | 动作数据 | 手部到位、无断手/穿模 |
| T1.5 | 导出 + 验证 + 全套审核材料（三视图、表情、动作、转台、`review.html`） | `out/minimate_phase1.usdz`、`renders/phase1/` | 硬门禁全通过 |
| T1.6 | 人工评审 | 评审记录 | 你确认或提出修改 |

**Phase 1 当前进度（2026-11-22）**：首轮评审 2.43；已按反馈修正猫耳、袜子长度、手脚肤色和连帽衫蓬松度（Phase 1.1）。T1.1、T1.2、T1.5 完成，硬门禁 G-1–G-6 全通过；T1.4 已检查（未重调幅度）；T1.3 发束细化暂缓（Phase 0 发型评分 3/3）。T1.6 已通过（Phase 1.1 平均 2.64，无备注）。Phase 1.2 复审：猫耳加宽曲边；头部抬高 4 cm、Body 颈部皮肤跟随（无独立圆柱）、T 恤前片 V 领真正剪开（Body 胸口皮肤）；硬门禁仍通过（38,392 三角面）。眼睛修订：虹膜/高光壳外移 5 mm（125 个形态键同步），瞳孔/高光画到可见虹膜中心，高光改为设计稿同光向；52/8/USDZ 校验通过。嘴巴修订：`_04` 不画唇线/唇阴影，FaceMouth 用单一深色内口腔，`jawOpen 0.15` 烘进 Basis 让小张口，face/head closeup 无横线；瞳孔贴图再内收 2 px；连帽衫按原稿取样（上 #E7ECF7、下 #DEE8F5）；呆毛改为更短、更大卷曲的圆环状；52/8/USDZ 校验通过（38,392 三角面），待复审。详见 `reports/phase1-review.md`。

### Phase 2 — 条件性脸型与最终材质（需单独批准）

| 任务 | 内容 | 产出 | 完成条件 |
|---|---|---|---|
| T2.1 | 评估 Phase 0/1 的脸型差距 | 评估记录 | 判断是否值得做 |
| T2.2 | 若批准：对 Basis + 全部形态键施加同一变形场，圆脸颊/短下巴 | 变形后的 `Face` | 52 名称不变；逐表情渲染检查 |
| T2.3 | RealityKit 材质近似（烘焙阴影 / ShaderGraph 评估） | 材质方案 | 真机观感接近 pastel |
| T2.4 | 最终导出 + 全量验证 | `out/minimate_final.usdz` | G-1–G-6 全通过 |
| T2.5 | 真机验收 | `reports/device-validation.md` | G-7 通过 |

### Phase 3 — 替换 App 资源（需单独批准）

| 任务 | 内容 | 完成条件 |
|---|---|---|
| T3.1 | 将最终 USDZ 复制到 `App/MiniMate/Resources/Avatar/minimate.usdz` | 你明确批准 |
| T3.2 | Xcode 模拟器编译 + 真机 52 滑杆 / 8 动作验收 | 通过 |
| T3.3 | 更新 `Assets/avatar/README.md` 与 `research.md` 实测记录 | 文档同步 |

---

## 6. 预期效果

### 6.1 三个阶段的观感

| 阶段 | 预期 |
|---|---|
| 基线 | 标准头身比、灰发、白 T 恤、黑短裤；与设计明显不同 |
| Phase 0 | 银白→淡蓝 bob、猫耳发箍、呆毛、琥珀色大眼、ω 形嘴、Q 版比例；上衣仍是改色 T 恤轮廓；App 尺寸下约 70–80% |
| Phase 1 | 白蓝渐变连帽衫、长袖、帽子、抽绳、口袋；浅蓝短裤、白袜、蓝灰运动鞋；App 尺寸下约 80–90% |
| Phase 2 | 脸型/材质进一步接近；约 85–92%；仍不是原画级 |

### 6.2 设计特征清单（评审用）

- [ ] 头身比约 1:2.5，头大、四肢短
- [ ] 银白→淡蓝渐变 bob，发尾到下颌
- [ ] 猫耳 + 内耳虹彩渐变
- [ ] 头顶呆毛：更短、更大卷曲（参考稿圆环状）
- [ ] 猫耳发箍侧面连接件
- [ ] 琥珀色大眼、虹膜占眼高约 70%、两点高光
- [ ] 细平眉、颜色比头发深一档
- [ ] 小鼻、ω 形小嘴
- [ ] 肤色 `#F7DCD3`、阴影 `#E8BFB4`、腮红 `#F3B3AD`
- [ ] 白蓝渐变连帽衫、白色抽绳、口袋
- [ ] 浅蓝短裤、白色裤脚边
- [ ] 白袜、白/蓝灰运动鞋
- [ ] 柔和 pastel 质感

### 6.3 明确做不到的部分

- 2D 线稿的笔触、喷枪渐变、发丝细节、布料褶皱不会 1:1 还原。
- VRoid 基础脸与 Q 版设计脸型有差异；Phase 0/1 靠贴图和头身比缩小差距，Phase 2 才可能进一步接近。
- MToon 在 USDZ 中退化为 PBR，RealityKit 里可能比 Blender 渲染更平/更亮；最终以真机为准。
- 设计图里的脸红、泪眼不在 ARKit 52 内；需要额外贴图/材质或额外形态键，不影响 52 名称完整性。

### 6.4 交付物

| 交付物 | 位置 |
|---|---|
| 计划书、配置、脚本、README | `Assets/avatar/auto-build/` |
| 基线审计、每阶段验证报告 | `reports/` |
| 阶段审核材料（三视图对比、脸部特写、表情网格、动作抽帧表、转台视频、`review.html`） | `renders/phaseN/` |
| 候选 VRM/USDZ | `out/` |
| 最终 App 资源 | 仅在 Phase 3 批准后替换 |

---

## 7. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 脸型相似度受底座限制 | 中高 | 贴图 + 头身比优先；Phase 2 才动脸型，且保持 52 键 |
| Q 版比例导致颈/肩蒙皮拉伸 | 中 | 先做小步比例实验；必要时修正权重；8 动作逐条检查 |
| 连帽衫程序化建模质量不足 | 高 | Phase 1 单独迭代；可退化为近似轮廓；不引入许可不明素材 |
| MToon → PBR 退化和差异 | 中 | 阴影/高光烘焙进贴图；必要时评估 ShaderGraphMaterial；真机验收 |
| 误操作丢失形态键 | 高 | I-1–I-4 约束 + 每次构建自动门禁；Face 不 Join/不 Remesh |
| 贴图 UV 错位/接缝 | 中 | 以现有图集为布局模板；生成后先在 Blender 预览 |
| Blender/插件版本漂移 | 低 | 固定 Blender 5.3；`audit_base.py` 报告版本；README 记录环境 |
| 面数/贴图超预算 | 低 | G-4/G-5 门禁；猫耳/服装保持低模；必要时减面 |
| 外部素材许可 | 中 | 默认全程序化；若用外部素材，先记录来源/许可，再合并 |
| 评审轮次过多 | 中 | 每阶段先出低成本渲染，再细化；不一次做满 |

---

## 8. Constitution Check

| 原则 | 适用性 | 结论 |
|---|---|---|
| I. 陪伴而非镜像 | 不适用于素材制作；不改变状态机与 `AvatarPose` | ✅ 无影响 |
| II. 感知在本地 | 不涉及摄像头/网络；只处理本地设计图 | ✅ 无网络 |
| III. 度量先于假设 | 52 键、8 动作、面数、贴图、真机缺失项都实测并写报告 | ✅ 门禁 G-1–G-7 |
| IV. 可替换边界 | 不改变 `AvatarRenderer` 协议；最终素材必须满足现有契约 | ✅ 遵守 `contracts/avatar-renderer.md` |
| V. 纯逻辑可测 | 不新增 Swift 逻辑；构建脚本可重复运行，验证脚本自动断言 | ✅ 无 App 逻辑改动 |
| VI. 简单优先 | 不新增 App 运行时依赖；Blender/VRM 插件已在本项目素材管线中使用；numpy/pxr 随 Blender 提供 | ✅ 无新运行时依赖 |
| VII. 隐私与密钥 | 不涉及 Key/网络；设计图与生成物默认不入库 | ✅ 遵守 |

**违反项**：无。无需 Complexity Tracking 新增项；Blender + VRM 插件的开发机依赖已在 002 plan 中记录。

---

## 9. 需要你审核的决策

| # | 决策 | 默认值 |
|---|---|---|
| D-1 | 工作目录使用 `Assets/avatar/auto-build/` | 采用 |
| D-2 | Phase 0 只做贴图、比例、猫耳发箍/呆毛，不动 `Face` 拓扑 | 采用 |
| D-3 | Phase 2 脸型变形是否预先授权 | 默认不预授权；Phase 0/1 评审后再决定 |
| D-4 | 最终替换 App 资源 | 必须单独批准，不自动替换 |
| D-5 | 生成物是否入库 | 默认只入库 PLAN/README/config/scripts/reports；`work/`、`textures/`、`renders/`、`out/` 忽略 |

---

## 10. 你如何肉眼审核

审核不靠“我说像”，而靠同一相机、同一光照下的可对比材料。每个 phase 结束时，`renders/phaseN/` 会生成一套审核材料：

| 材料 | 文件 | 用途 |
|---|---|---|
| 三视图对比 | `compare_front.png` / `compare_side.png` / `compare_back.png` | 左：设计原图裁剪；右：模型同角度渲染，同高、同背景 |
| 脸部特写 | `face_closeup.png` | 看眼睛、眉毛、嘴、肤色、腮红、猫耳内耳 |
| 表情表 | `expression_grid.png` | 8 组 `ExpressionPreset` 各渲染一帧 |
| ARKit 冒烟网格 | `arkit_smoke_grid.png` | `eyeBlink`、`mouthSmile`、`jawOpen`、`eyeWide`、`browInnerUp`、`tongueOut` 等极端值，检查形态键是否真的生效 |
| 动作表 | `actions_contact_sheet.png` | 8 个动作 × 4 个关键帧，带动作名 |
| 转台视频 | `turntable.mp4` | 360° 旋转，检查整体轮廓、头发/衣服穿插 |
| 审核页 | `review.html` | 把以上材料按 phase 组织，附设计特征清单和通过/待修标记 |

**打开方式**

1. 在 VSCode 中直接点开图片文件。
2. 或运行：
   ```bash
   open Assets/avatar/auto-build/renders/phase0/review.html
   ```
3. 3D 整体感可用 Quick Look 旋转查看：
   ```bash
   qlmanage -p Assets/avatar/auto-build/out/minimate_phase0.usdz
   ```
   或在 Finder 中选中 USDZ 按空格。
4. 想在手机上看 AR：把 `out/minimate_phase0.usdz` AirDrop 到 iPhone，用“文件”打开，走 AR Quick Look。**注意**：Quick Look 只用于看外形，不驱动 52 个形态键和 8 个动作。

**审核节奏**

| 阶段 | 你重点看什么 | 不用于最终判断的部分 |
|---|---|---|
| Phase 0 | 三视图、脸部特写、猫耳/呆毛、Q 版比例、整体配色 | 上衣仍是改色 T 恤轮廓，连帽衫在 Phase 1 |
| Phase 1 | 连帽衫、短裤、鞋袜、头发轮廓、动作穿模 | 材质最终效果仍以真机为准 |
| Phase 2（如启用） | 脸型、材质、整体观感 | — |
| Phase 3 | 真机 `AvatarDebugPanel`：52 个滑杆 + 8 个动作按钮 | 这是最终验收 |

**评分口径**

每个设计特征按 0–3 打分：

- 0 = 缺失
- 1 = 明显不同
- 2 = 接近但有瑕疵
- 3 = App 常用尺寸下一致

关键特征不得出现 0/1；整体平均 ≥ 2.5 且你确认，才进入下一 phase。特征清单见 6.2。

**你只需要回复**：`通过`、`某项要改` 或 `整体方向不对`，可以附上圈注截图或文字。每轮我会保留上一轮渲染，方便对比“改前/改后”。

**自动门禁和肉眼审核的关系**

- 自动门禁：52 名称、8 动作、骨骼、面数、贴图尺寸、USDZ 结构；由脚本断言，失败即停止。
- 肉眼审核：像不像、穿不穿模、材质是否可接受。
- 两者都过，才算 phase 通过。

**避免误判**

- Blender 渲染使用固定相机和中性光；RealityKit 是 PBR，材质可能更平/更亮，最终以 Phase 3 真机为准。
- Quick Look 只用于外形，不用于形态键/动作验收；形态键/动作看 `expression_grid.png`、`actions_contact_sheet.png` 和真机调试面板。
- 不以放大原画的细节为准；以 App 常用展示尺寸为准。

## 11. 审核通过后的第一步

1. 建立 `config/avatar.json`、`.gitignore`、`README.md`。
2. 运行 `audit_base.py`，产出基线审计与当前占位形象三视图。
3. 运行 `generate_textures.py` 与 `build_avatar.py`，产出 Phase 0 第一版。
4. 运行 `validate_avatar.py` 与 `render_compare.py`，把验证报告和并排渲染交给你评审。

在你批准本计划前，我不会开始写实现脚本，也不会修改 `App/` 或 `Packages/` 中的任何文件。

---

## 附录 A：方案对比与参考

| 方案 | 链接 | 结论 |
|---|---|---|
| mcp-vroid（Linux GUI 自动化） | https://github.com/nhodges/mcp-vroid | 排除 |
| vroid-studio-mcp（Windows/Wine 内部 API） | https://market.lobehub.com/s/plugins/brainrom-vroid-studio-mcp | 排除 |
| Charakuru（2D 图 → VRM 套件） | https://github.com/nanocle/Charakuru | 仅原型 |
| Meshy VRM Avatar（身体 rig，无面部） | https://www.meshy.ai/sv/use-cases/3d-avatar/vrm | 仅原型 |
| Seiðr-Smiðja（无头 VRM 生成器） | https://github.com/hrabanazviking/Seidr-Smidja | 参考思路 |

本地参考：

- `specs/002-m1-presence/contracts/avatar-renderer.md`
- `specs/002-m1-presence/research.md`（D3、V10）
- `Assets/avatar/README.md`
- `Assets/avatar/vroid-recipe.md`
- `Assets/avatar/export_avatar.py`

## 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1 | 2026-11-21 | 初稿，待审核 |
| v0.2 | 2026-11-21 | 增加肉眼审核方式：三视图对比、脸部特写、表情/ARKit 网格、动作抽帧表、转台视频、`review.html`、评分口径与真机验收 |
