# Quickstart: M1 感知与形象

**Feature**: `002-m1-presence`

## 前置条件

- 001 已完成，App 可在真机运行
- 形象素材由 `Assets/avatar/auto-build/` 自动构建并导出为 `App/MiniMate/Resources/Avatar/minimate.usdz` + `minimate.actions.json`（两个文件必须一起复制）
- 手机竖放在支架上，距离脸 30–80 cm，室内正常照明

## 一、素材验证（V10 / SC-001）

1. 打开 App > 调试面板 > "表情系数"。
2. 逐个拖动 52 个滑杆到 1.0 再回 0，确认形象对应部位有可见变化。记录无变化的项。
3. 切到"动作"，逐个点播 8 个动作，确认完整播放并平滑回到待机。
4. 结果写入 `research.md`。

## 二、"它在看我"（US2 / SC-002）

1. 回到主界面，先不看屏幕，观察形象 Idle（呼吸、眨眼、四处看）。
2. 看向屏幕：形象应在 0.5 s 内看向你。
3. 左右慢慢移动头部，再快速移动：视线与头部应平滑跟随，无明显滞后或抖动。
4. 离开画面 5 秒再回来：应先四处张望，回来时有"注意到你"的反应。
5. 快速把脸凑近屏幕：形象应后仰或惊讶。
6. 调试面板 > 指标：记录 M_track 的 p50 / p90。

## 三、"它回应我"（US3 / SC-003 / SC-004）

1. 对形象微笑并保持约 1 秒：形象应稍后用它自己的方式笑，约 1.5 秒后恢复。
2. 立刻再笑一次：不应重复同样的回应（冷却中）。
3. 皱眉：形象应露出关切，而不是皱眉。
4. 做惊讶表情：形象应惊讶。
5. 调试面板 > "镜像检测"：自由做 30 秒各种表情，读取相关系数（应 < 0.3）。
6. 记录 M_reflex 落在 300–800 ms 的比例。

## 四、手势（US4 / SC-005）

1. 挥手、比心、点赞各做 10 次，记录正确触发次数。
2. 正常说话、摸脸、抬手 1 分钟，记录误触发次数。

## 五、对话状态（US5）

1. 调试面板 > "对话事件"，依次注入：用户开始说话 → 用户结束说话 → `<user:sad>` → 助手开始说话 + `<emo:gentle>` → 助手结束说话。
2. 观察状态显示依次为 Listening → Thinking → Thinking（关切）→ Speaking(gentle) → Attending。
3. 在 Speaking 时对形象微笑：说话表情不应被打断。

## 六、稳定性（SC-006）

1. 连续运行 10 分钟，期间正常交互。
2. 记录 Xcode Debug Navigator 中的帧率、内存，以及 `thermalState` 的变化。

## 七、Mac 上测试

```bash
cd Packages/MiniMateKit
swift test --filter "MMEmotionTests|MMPerceptionTests|MMCoreTests"
```

## 验收清单

- [x] SC-001 素材全部可驱动
- [x] SC-002 M_track p50 < 100 ms、p90 < 150 ms（真机交互验收通过，精确统计值与口径说明已写入 `research.md`）
- [x] SC-003 M_reflex 区间命中率 ≥ 90%（真机 US3 验收通过，两组精确统计值已写入 `research.md`）
- [x] SC-004 相关系数 < 0.3（自动化 1800 帧 `< 0.3` 通过，真机 30 s `meanAbsR = 0.1248` 与通道说明已写入 `research.md`）
- [x] SC-005 手势 ≥ 8/10，误触发 ≤ 1 次/分钟
- [x] SC-006 10 分钟 ≥ 55 fps、内存 < 1 GB（实测 avg 59.95 fps、max 518.2 MiB、全程 nominal）
- [x] SC-007 主观："它在看我，且在回应我"
- [x] 实测数据已写入 `research.md`
