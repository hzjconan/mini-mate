# Phase 1.4 验证报告

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
| Body 网格存在 | ✅ |  |
| Phase 1.4 直腿轮廓达标 | ✅ | L(wx=0.0762,dy=0.0889,ymax=0.0674) R(wx=0.0762,dy=0.0889,ymax=0.0674) |
| Phase 1.4 踝/大腿衔接与袜子法线 | ✅ | max_disp=0.000000 SockL(v=280,inward=0) SockR(v=280,inward=0) |
| Phase 1.4 手掌厚度达标 | ✅ | L=0.0331 R=0.0331 diff=0.0000 |
| Phase 1.4 静置手型自然微弯 | ✅ | R_Index(dx=+0.0106,dL=0.002) R_Middle(dx=+0.0139,dL=0.002) R_Ring(dx=+0.0149,dL=0.002) R_Little(dx=+0.0159,dL=0.007) L_Index(dx=-0.0106,dL=0.002) L_Middle(dx=-0.0139,dL=0.002) L_Ring(dx=-0.0149,dL=0.002) L_Little(dx=-0.0159,dL=0.007) |
| Phase 1.4 动作防穿模间隙 | ✅ | shyCover_hand_face=0.0023m heart_hands=0.0410m |
| Phase 1.4 最新动作已同步 | ✅ | shyCover_R_UpperArm_diff=0.000deg |
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
| Phase 1.4 USDZ 白袜材质契约 | ✅ | bindings={'SockR': 'SockWhite', 'SockL': 'SockWhite'} opacity=1.0 metallic=0.0 roughness=0.8500000238418579 emissive=(0.699999988079071, 0.699999988079071, 0.699999988079071) diffuse=(1.0, 1.0, 1.0) |

## 失败项

- 无
