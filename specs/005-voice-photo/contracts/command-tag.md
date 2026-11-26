# Contract: 指令标签 `<cmd:…>`

**Module**: `MMCore`（`AssistantCommand`、`ConversationEvent`）、`MMConversation`（`TagParser`、对话引擎） | **Feature**: `005-voice-photo`（2026-11-26 按两轮外部评审修订）

本契约是对 003 `contracts/tag-protocol.md` 与 `contracts/conversation-engine.md` 的扩展，已于 2026-11-26 合并到这两份文档中，以 003 文档为准。

## 语法扩展

```
item        := emo_tag | act_tag | cmd_tag | text
cmd_tag     := "<cmd:" AssistantCommand ">"
```

- 取值见 data-model.md `AssistantCommand`：`photo`、`photoReady`、`photoCancel`。
- `<cmd:…>` 可以出现在回答中的任何位置（包括最前面、`<user:…>` 之后）；它不是位置标记，不与任何文字绑定。

## 示例

```
<user:happy><emo:happy>好呀～<cmd:photo>
<user:happy><emo:playful>好嘞～<cmd:photoReady>          # 确认环节："好了，拍吧"
<user:calm><emo:gentle>好，不急～                    # 确认环节："还没好，等一下"
<user:calm><emo:gentle>好，不拍啦<cmd:photoCancel>
<user:happy><cmd:photo>
<user:calm><emo:playful>哇，你拍了什么呀？      # 只是提到拍照：不输出 cmd
```

## 解析器行为（在 003 T-1–T-7 之后追加）

| 编号 | 输入情况 | 行为 |
|---|---|---|
| T-8 | 合法 `<cmd:…>` | 产出 `TaggedSegment.command(AssistantCommand)`；不产出文字，不影响分句 |
| T-9 | 未知指令值（如 `<cmd:video>`） | 同 T-3：丢弃并记录一次警告 |
| T-10 | 同一轮出现多个指令（相同或不同） | 每个都按出现顺序立即产出，解析层不去重、不取舍 |

流式解析器无法预知后面是否还有指令，所以"重复指令只执行一次""多个结论以最后一个为准"由消费方处理（photo-flow.md PF-1：非 `idle` 时重复的 `photo` 被忽略；确认环节中后到的指令覆盖先到的）。

T-1（标签跨增量切分）与 T-2（24 字符上限）对 `<cmd:…>` 同样适用；`<cmd:photoCancel>` 共 17 个字符，在上限之内。

## 事件顺序（对 003 conversation-engine.md 的扩展）

| 编号 | 约定 |
|---|---|
| C-1 | `assistantCommand` 在解析到时立即发出，不等待音频播放；保证位于同一轮的 `userSpeechEnded` 之后、`assistantSpeechEnded` 之前 |
| C-2 | 被打断的一轮（E-2）中，在打断之前已发出的 `assistantCommand` 不撤回；打断之后，旧一轮不再发出任何指令。消费方须自行决定已收到的指令是否仍然有效（拍照流程在用户开口时清空尚未生效的结论，photo-flow.md PF-4） |
| C-3 | 回答中没有可播文字（如只有 `<user:happy><cmd:photo>`）时，引擎 MUST 在回答结束时依次发出 `assistantSpeechStarted`、`assistantSpeechEnded`，保证消费者总能收到"本轮结束"；暂缓期间（photo-flow.md RH-1）这两个事件推迟到释放后，被丢弃的回应不发出 |
| C-4 | `OfflineConversationEngine`（004）不发出 `assistantCommand` |

## 写给模型的说明（追加到 003 instructions 第 5 条之后）

```
6. 只有当用户明确要求你"现在"给他拍照时（例如"给我拍张照""帮我拍一张""来张自拍"），
   在回答末尾插入 <cmd:photo>，回答只说一句很短的话（如"好呀～"），不要问用户是否准备好。
   用户只是聊到照片或拍照（例如"我昨天拍了好多照片"）时，绝对不要插入。
   插入 <cmd:photo> 之后，App 会用你的声音问用户"准备好了吗"（这句你听不到），然后：
   - 用户表示准备好了（"好了""可以了""拍吧""来吧"），插入 <cmd:photoReady>，只说两三个字或不说；
   - 用户表示还没好（"还没""等一下""稍等"），不插入任何指令，简短回应（如"好，不急～"）；
   - 用户表示不拍了（"不拍了""算了""不要了"），插入 <cmd:photoCancel>，并且一定要说一句简短的确认（如"好，不拍啦"）。
   拍照由 App 完成，你看不到照片，不要描述或评价照片内容。
```

确认环节中不向模型额外注入"正在等待确认"的状态：上述说明加上上一轮刚输出过的 `<cmd:photo>`，模型可以从本会话上下文中判断（research D6）。若 R6 实测识别率不足（SC-011），再评估给 `ConversationEngine` 增加上下文附加接口（需改 003 契约）。

## 测试要求

- T-8–T-10 每条至少一个用例（三个指令值都要覆盖）；`<cmd:…>` 纳入 003 的随机切分参数化测试。
- 引擎测试（`ScriptedRealtimeSession` 回放）覆盖 C-1、C-2、C-3。
