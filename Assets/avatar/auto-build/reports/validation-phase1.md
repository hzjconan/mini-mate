# Phase 1.2 验证报告

- 模型：`/Users/hzjconan/workspace/mini-mate/Assets/avatar/auto-build/work/phase1/minimate_phase1.blend`
- USDZ：`/Users/hzjconan/workspace/mini-mate/Assets/avatar/auto-build/out/minimate_phase1.usdz`
- 结果：通过

| 检查 | 结果 | 详情 |
|---|---|---|
| Face 网格存在 | ✅ |  |
| ARKit 52 名称 | ✅ | missing=[] |
| Face 形态键目标数 | ✅ | targets=124 |
| 8 个动作 | ✅ | missing=[] |
| Head 骨骼 | ✅ |  |
| Neck 骨骼 | ✅ |  |
| 三角面 < 50k | ✅ | triangles=39032 |
| 贴图 ≤ 2048² | ✅ | too_large=[] |
| Phase 1.2 服装部件 | ✅ | missing=[] |
| USDZ 存在 | ✅ | /Users/hzjconan/workspace/mini-mate/Assets/avatar/auto-build/out/minimate_phase1.usdz |
| 动作清单存在 | ✅ | /Users/hzjconan/workspace/mini-mate/Assets/avatar/auto-build/out/minimate_phase1.actions.json |
| 清单 8 个片段 | ✅ | clips=['heart', 'leanBack', 'lookAround', 'nod', 'notice', 'shyCover', 'spin', 'wave'] |
| USDZ 单条动作时间线 | ✅ | animations=['actions'] |
| USDZ 动作已绑定 | ✅ | animationSource=[Sdf.Path('/root/Armature/Armature/actions')] |
| 时间线逐帧连续 | ✅ | samples=295 range=[1]..[295] totalFrames=295 |
| 时间码与清单一致 | ✅ | fps=30.0 end=295.0 |
| 时间线不含形态键动画 | ✅ |  |
| 片段区间合法 | ✅ | invalid=[] |
| upAxis=Y | ✅ | Y |
| metersPerUnit=1 | ✅ | 1.0 |
| USDZ ARKit 52 名称 | ✅ | missing=[] |
| USDZ 骨架 | ✅ | skeletons=['Armature'] |
| USDZ 可打开 | ✅ |  |
| USDZ 含连帽衫网格 | ✅ | hood_meshes=['HoodieCollar', 'HoodieCuffL', 'HoodieCuffR', 'HoodieHemBand', 'HoodieHemExtension', 'HoodieHood', 'HoodieHoodFoldL', 'HoodieHoodFoldR'] |

## 失败项

- 无
