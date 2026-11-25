# Phase 0 验证报告

- 模型：`/Users/hzjconan/workspace/mini-mate/Assets/avatar/auto-build/work/phase0/minimate_phase0.blend`
- USDZ：`/Users/hzjconan/workspace/mini-mate/Assets/avatar/auto-build/out/minimate_phase0.usdz`
- 结果：通过

| 检查 | 结果 | 详情 |
|---|---|---|
| Face 网格存在 | ✅ |  |
| ARKit 52 名称 | ✅ | missing=[] |
| Face 形态键目标数 | ✅ | targets=124 |
| 8 个动作 | ✅ | missing=[] |
| Head 骨骼 | ✅ |  |
| Neck 骨骼 | ✅ |  |
| 三角面 < 50k | ✅ | triangles=33076 |
| 贴图 ≤ 2048² | ✅ | too_large=[] |
| USDZ 存在 | ✅ | /Users/hzjconan/workspace/mini-mate/Assets/avatar/auto-build/out/minimate_phase0.usdz |
| 动作清单存在 | ✅ | /Users/hzjconan/workspace/mini-mate/Assets/avatar/auto-build/out/minimate_phase0.actions.json |
| 清单 8 个片段 | ✅ | clips=['heart', 'leanBack', 'lookAround', 'nod', 'notice', 'shyCover', 'spin', 'wave'] |
| USDZ 单条动作时间线 | ✅ | animations=['actions'] |
| USDZ 动作已绑定 | ✅ | animationSource=[Sdf.Path('/root/Armature/Armature/actions')] |
| 时间线逐帧连续 | ✅ | samples=316 end=316.0 totalFrames=316 |
| 时间线不含形态键动画 | ✅ |  |
| USDZ ARKit 52 名称 | ✅ | missing=[] |
| USDZ 骨架 | ✅ | skeletons=['Armature'] |
| USDZ 可打开 | ✅ |  |

## 失败项

- 无
