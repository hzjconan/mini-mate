# Contract: 模型输出标签协议

**Module**: `MMConversation`（`TagParser`、`SentenceSplitter`） | **Feature**: `003-m2-voice-conversation`

## 语法

```
output      := user_tag? item*
user_tag    := "<user:" UserEmotion ">"
item        := emo_tag | act_tag | text
emo_tag     := "<emo:" EmotionTag ">"
act_tag     := "<act:" ActionTag ">"
text        := 任意不含 "<" 的字符序列
```

- 枚举值见 002 `data-model.md`（`UserEmotion`、`EmotionTag`、`ActionTag` 的 rawValue）。
- `<user:…>` 每轮最多一个，且 MUST 位于回答最前面。
- `<emo:…>` 作用于其后直到下一个 `<emo:…>` 为止的文字。
- `<act:…>` 是位置标记，在其后第一个字的音频播放时触发。

## 示例

```
<user:tired><emo:gentle>今天累坏了吧？<act:nod>先歇会儿，我陪着你。
<user:happy><emo:happy>哇，真的吗！<act:spin>那我给你转个圈庆祝一下～
<emo:playful>你猜？
```

## 解析器行为（`TagParser`，流式）

| 编号 | 输入情况 | 行为 |
|---|---|---|
| T-1 | 标签被切在两个增量之间（如 `<em` + `o:happy>`） | 缓存未闭合的 `<…`，等待后续增量 |
| T-2 | 未闭合的 `<` 超过 24 个字符仍无 `>` | 视为普通文字输出 |
| T-3 | 未知标签类型或未知枚举值（如 `<emo:excited>`） | 丢弃该标签，记录一次警告；不输出为文字 |
| T-4 | 本轮没有 `<user:…>` | 不发出 `userEmotion` |
| T-5 | `<user:…>` 出现在文字之后 | 丢弃 |
| T-6 | 文字中出现 `<` 但不构成标签（如"1<2"） | 按 T-2 作为文字输出 |
| T-7 | 回答结束时仍有缓存 | 按 T-2 规则刷出 |

## 分句器行为（`SentenceSplitter`，流式）

| 编号 | 规则 |
|---|---|
| S-1 | 句末标点：`。` `！` `？` `…` `~` `～` 及其英文形式，连续标点视为一个 |
| S-2 | 首句：达到 6 个字后，遇到 `，` `、` 也可切分（首句提速） |
| S-3 | 任意句超过 40 个字仍无标点：在最近的逗号处切分，否则在第 40 个字处强制切分 |
| S-4 | 每句的 `emotion` 取该句第一个字生效时的 `<emo>`；若句中出现新的 `<emo>`，在该处强制切分 |
| S-5 | `<act>` 记录为句内字符偏移 |
| S-6 | 去除空白句与只有标点的句子 |
| S-7 | 回答结束时刷出剩余文字为最后一句 |

## 写给模型的说明（注入会话 instructions）

```
你在每次回答时必须遵守以下输出格式：
1. 回答最前面用 <user:情绪> 标注你从用户的语气（不只是文字）中听出的情绪，
   取值只能是：happy, calm, sad, tired, angry, anxious。
2. 每句话前用 <emo:情绪> 标注你说这句话时的情绪，
   取值只能是：happy, gentle, sad, surprised, shy, playful, concerned, neutral。
3. 需要做动作时，在对应位置插入 <act:动作>，
   取值只能是：nod, wave, spin, heart, shyCover, leanBack, lookAround, notice。
   用户让你做动作（如"转个圈""笑一个"）时，必须插入对应动作。
4. 标签不会被念出来，不要解释标签。
5. 当用户的语气和文字含义不一致时（例如低落地说"我没事"），以语气为准来回应。
```

## 测试要求

- T-1 至 T-7、S-1 至 S-7 每条至少一个用例；以参数化测试覆盖随机切分（同一输出按任意位置切成增量，解析结果必须一致）。
