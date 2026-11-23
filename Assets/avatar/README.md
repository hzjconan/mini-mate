# 形象素材

`App/MiniMate/Resources/Avatar/minimate.usdz` 的来源、许可与运行时约定。构建方式见 `auto-build/PLAN.md` 与 `auto-build/README.md`；源文件（`.vrm`、`.blend`）不进 App bundle，也不提交到仓库；只有导出后的 USDZ 随 App 打包。

## 来源与许可

| 项 | 内容 |
|---|---|
| 模型名称 | `VRoid_V110_Female_v1.1.3.vrm`（`auto-build/` 的底座模型） |
| 来源 / 作者 | [hinzka/52blendshapes-for-VRoid-face](https://github.com/hinzka/52blendshapes-for-VRoid-face)，VRoid Studio 官方素体的个人改版 |
| 许可（是否允许个人使用、修改、再分发） | 个人与商用均可，允许再分发，无需署名（见仓库 README） |
| 是否带 Perfect Sync（52 个 ARKit blendShape） | 是。全部落在 `Face` 网格，共 125 个形态键，52 个 ARKit 名称零缺失 |

选型要求见 `specs/002-m1-presence/research.md` D3。

## 运行时约定

- Xcode 文件系统同步组把资源平铺进 bundle，运行时路径是 `minimate.usdz`（没有 `Resources/Avatar/` 子目录）。
- RealityKit 暴露的动画名可能带骨骼前缀（如 `Armature|nod`），`RealityKitAvatarRenderer` 需按后缀匹配。
- 52 个 ARKit 形态键全部落在 `Face` 网格，`BlendShapeIndex.missingNames` 应为空。

## 已知风险

- MToon 卡通材质在 USDZ 中会退化为 PBR，描边网格可能变成黑色外壳，眼白/瞳孔的透明混合也可能丢失；验证结果记入 `specs/002-m1-presence/research.md`（V10）。
- 形态键分布在多个网格时，若某个网格缺少某个键，该部位不会响应（`BlendShapeIndex` 的 `missingNames` 只反映传入的那个网格）。
