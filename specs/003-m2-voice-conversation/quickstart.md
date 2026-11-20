# Quickstart: M2 语音对话

**Feature**: `003-m2-voice-conversation`

## 前置条件

- 001、002 已完成（形象与状态机可用）
- 已开通候选厂商账号并拿到 API Key
- 已在 `Assets/voice-samples/` 录好 9 个语气样本（research.md 列表）

## 一、M2a：厂商验证（Mac）

```bash
cd Packages/MiniMateKit
export MM_QWEN_KEY=...        # 只在当前终端有效，不要写进文件
export MM_DOUBAO_KEY=...

swift run mm-probe realtime --vendor qwen --input ../../Assets/voice-samples/ok-sad.wav
swift run mm-probe tone-suite --vendor qwen
swift run mm-probe tone-suite --vendor doubao
swift run mm-probe tts --vendor cosyvoice --text "今天累坏了吧？先歇会儿。" --all-emotions --out /tmp/tts-cosy
swift run mm-probe tts --vendor doubao    --text "今天累坏了吧？先歇会儿。" --all-emotions --out /tmp/tts-doubao
```

1. 检查 `tone-suite` 输出：同一句话三种语气的 `<user>` 与回答是否不同（SC-002）。
2. 试听 `/tmp/tts-*` 下的音频：是否同一音色、情绪是否可辨。
3. 把结果填入 `research.md` 的"M2a 厂商对比"，写出选型结论（SC-001）。
4. 填写 `Resources/tts-emotion-<vendor>.json` 与 `contracts/realtime-session.md` 的厂商附录。
5. 若结论为方案 C，转到 tasks.md 的 US7。

## 二、App 配置

1. App > 设置，填入选定厂商的 Key。
2. 回到主界面，允许麦克风权限。

## 三、基本对话与回声（US2 / SC-003 / SC-004）

1. 手机立在支架上，外放音量调到平时使用的大小。
2. 看着形象直接说话，例如"你好呀，今天过得怎么样？"。
3. 观察：说话时形象 Listening；说完立刻 Thinking；随后用固定音色回答。
4. 连续聊 10 轮，话题前后相关（如先说"我养了一只猫"，几轮后问"我养的是什么？"）。
5. 记录：自问自答次数、误打断次数（SC-003）。
6. 调试面板 > 对话：查看 M_feedback、M_answer 的 p50/p90。

## 四、语气（US3）

用三种语气分别说"我没事"：开心、平淡、低落。观察形象在开口前的神情、`<user>` 值（调试面板显示）与回答内容。

## 五、打断与误触发（US4 / US5 / SC-006 / SC-007 / SC-008）

1. 问一个需要较长回答的问题，在它说话时插话，重复 10 次，记录 M_bargein。
2. 打开电视（正常音量），转头不看屏幕 5 分钟，记录误触发次数。
3. 离开画面 30 秒以上，确认调试面板显示 `paused`；回来看屏幕后恢复。
4. 点击静音，说话确认不触发；形象应为静音姿态。
5. 安静环境 1 分钟不说话，查看调试面板"已上传音频字节数"应为 0。

## 六、形象联动（US6 / SC-009）

1. 观察说话时口型是否随声音开合。
2. 说"笑一个""转个圈""挥挥手"，确认动作执行。
3. 10 轮对话中记录表情与语气不一致的句子数。

## 七、高峰时段

在晚间高峰（20:00–22:00）再跑 20 轮，记录 M_answer，填入 research.md。

## 八、Mac 上测试

```bash
cd Packages/MiniMateKit
swift test --filter "MMConversationTests|MMAudioTests"
```

## 验收清单

- [ ] SC-001 厂商与方案结论已写入 research.md
- [ ] SC-002 语气组 ≥ 2/3 通过
- [ ] SC-003 10 轮外放：自问自答 0、误打断 0
- [ ] SC-004 M_feedback p50 < 100 ms
- [ ] SC-005 M_answer 常态与高峰基准已记录
- [ ] SC-006 插话 10/10 停止，M_bargein p50 < 300 ms
- [ ] SC-007 电视背景 5 分钟误触发 0
- [ ] SC-008 静默 1 分钟上传 0 字节
- [ ] SC-009 表情与语气不一致 ≤ 1 句
