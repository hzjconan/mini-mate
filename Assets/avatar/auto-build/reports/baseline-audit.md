# 基线素材审计

- 源文件：`/Users/hzjconan/workspace/mini-mate/Assets/avatar/VRoid_V110_Female_v1.1.3.vrm`
- Blender：5.3.0
- VRM 插件：`bl_ext.user_default.vrm`
- 尺寸：[-0.6933, -0.1487, 0.0009] – [0.6928, 0.1918, 1.6189]，高 1.618 m

## 网格与形态键

| 网格 | 顶点 | 三角面 | 形态键 | 材质数 |
|---|---:|---:|---:|---:|
| `Face` | 4709 | 8280 | 125 | 8 |
| `Body` | 9158 | 15286 | 0 | 5 |
| `Hair001` | 8154 | 9348 | 0 | 1 |

## ARKit 52 名称检查

- `Face`：124 个目标形态键，ARKit 52/52，缺失：无

## 骨架

- `Armature`：118 根骨骼
  - `J_Bip_C_Head` 存在
  - `J_Bip_C_Neck` 存在
  - `J_Bip_C_Hips` 存在
  - `J_Bip_L_UpperArm` 存在
  - `J_Bip_R_UpperArm` 存在

## 材质与贴图

- `MToon Outline (N00_000_00_Body_00_SKIN)`：`_10`, `Shader_NoneBlack`, `MatcapWarp_01`, `_11`
- `MToon Outline (N00_000_00_Face_00_SKIN)`：`_04`, `Shader_NoneBlack`, `MatcapWarp_01`, `_05`, `N00_000_00_Face_00_out`
- `MToon Outline (N00_000_Hair_00_HAIR)`：`_16`, `_17`, `MatcapWarp_02`, `N00_000_Hair_00_nml`
- `MToon Outline (N00_001_01_Bottoms_01_CLOTH)`：`_13`, `Shader_NoneBlack`, `MatcapWarp_01`, `Shader_NoneNormal`
- `MToon Outline (N00_004_01_Shoes_01_CLOTH)`：`_15`, `Shader_NoneBlack`, `MatcapWarp_01`, `Shader_NoneNormal`
- `MToon Outline (N00_004_01_Tops_01_CLOTH)`：`_14`, `Shader_NoneBlack`, `MatcapWarp_01`, `Shader_NoneNormal`
- `N00_000_00_Body_00_SKIN`：`_10`, `Shader_NoneBlack`, `MatcapWarp_01`, `_11`
- `N00_000_00_EyeHighlight_00_EYE`：`_03`, `Shader_NoneBlack`, `Shader_NoneNormal`
- `N00_000_00_EyeIris_00_EYE`：`_02`, `Shader_NoneBlack`, `Shader_NoneNormal`
- `N00_000_00_EyeWhite_00_EYE`：`_06`, `Shader_NoneBlack`, `Shader_NoneNormal`
- `N00_000_00_Face_00_SKIN`：`_04`, `Shader_NoneBlack`, `MatcapWarp_01`, `_05`, `N00_000_00_Face_00_out`
- `N00_000_00_FaceBrow_00_FACE`：`_07`, `Shader_NoneBlack`, `MatcapWarp_01`, `Shader_NoneNormal`
- `N00_000_00_FaceEyelash_00_FACE`：`_08`, `Shader_NoneBlack`, `MatcapWarp_01`, `Shader_NoneNormal`
- `N00_000_00_FaceEyeline_00_FACE`：`_09`, `Shader_NoneBlack`, `MatcapWarp_01`, `Shader_NoneNormal`
- `N00_000_00_FaceMouth_00_FACE`：`_01`, `Shader_NoneBlack`, `Shader_NoneNormal`
- `N00_000_00_HairBack_00_HAIR`：`_12`, `Shader_NoneBlack`, `N00_000_00_HairBack_00_nml`
- `N00_000_Hair_00_HAIR`：`_16`, `_17`, `MatcapWarp_02`, `N00_000_Hair_00_nml`
- `N00_001_01_Bottoms_01_CLOTH`：`_13`, `Shader_NoneBlack`, `MatcapWarp_01`, `Shader_NoneNormal`
- `N00_004_01_Shoes_01_CLOTH`：`_15`, `Shader_NoneBlack`, `MatcapWarp_01`, `Shader_NoneNormal`
- `N00_004_01_Tops_01_CLOTH`：`_14`, `Shader_NoneBlack`, `MatcapWarp_01`, `Shader_NoneNormal`

## 原始贴图

已提取到 `work/base/textures/`：

| 图像 | 尺寸 | 保存为 |
|---|---|---|
| `_01` | 512×512 | `work/base/textures/_01.png` |
| `_02` | 1024×512 | `work/base/textures/_02.png` |
| `_03` | 1024×512 | `work/base/textures/_03.png` |
| `_04` | 1024×1024 | `work/base/textures/_04.png` |
| `_05` | 1024×1024 | `work/base/textures/_05.png` |
| `_06` | 1024×512 | `work/base/textures/_06.png` |
| `_07` | 1024×256 | `work/base/textures/_07.png` |
| `_08` | 1024×256 | `work/base/textures/_08.png` |
| `_09` | 1024×256 | `work/base/textures/_09.png` |
| `_10` | 2048×2048 | `work/base/textures/_10.png` |
| `_11` | 2048×2048 | `work/base/textures/_11.png` |
| `_12` | 1024×1024 | `work/base/textures/_12.png` |
| `_13` | 1024×1024 | `work/base/textures/_13.png` |
| `_14` | 1024×2048 | `work/base/textures/_14.png` |
| `_15` | 512×512 | `work/base/textures/_15.png` |
| `_16` | 512×1024 | `work/base/textures/_16.png` |
| `_17` | 512×1024 | `work/base/textures/_17.png` |
| `MatcapWarp_01` | 512×512 | `work/base/textures/MatcapWarp_01.png` |
| `MatcapWarp_02` | 512×512 | `work/base/textures/MatcapWarp_02.png` |
| `N00_000_00_Face_00_out` | 256×256 | `work/base/textures/N00_000_00_Face_00_out.png` |
| `N00_000_00_HairBack_00_nml` | 512×512 | `work/base/textures/N00_000_00_HairBack_00_nml.png` |
| `N00_000_Hair_00_nml` | 512×1024 | `work/base/textures/N00_000_Hair_00_nml.png` |
| `Shader_NoneBlack` | 8×8 | `work/base/textures/Shader_NoneBlack.png` |
| `Shader_NoneNormal` | 8×8 | `work/base/textures/Shader_NoneNormal.png` |
| `Thumbnail` | 2048×2048 | `work/base/textures/Thumbnail.png` |
