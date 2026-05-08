---
name: ag-ui-response
description: Use when an Agent must produce user-visible Markdown and wrap it into the Decision Agent MQ field payload.ag_ui.
---

# AG-UI Markdown 回复技能

## 触发时机

在 Agent 需要向会话侧回写用户可见业务内容时，使用本技能生成 Markdown 文本，并把该文本包装到 MQ 消息的 `payload.ag_ui` 字段中。

适用内容包括：

- 主动询问、风险确认或等待用户补充的信息。
- 阶段结论、候选方案、最终结果或脱敏错误说明。

## 强制输出门禁

在执行任何会产生用户可见状态变化的业务动作前，必须先完成对应 Markdown 文本的生成、校验和 MQ 发布。发布成功前，不得继续执行下一步业务动作。

缺少本技能时，Agent 必须停止业务执行并返回配置错误。读取本技能前，不得调用业务工具、查询知识网络、下发恢复任务或执行验证。

本技能在 Linux 沙箱中执行，运行时默认使用 UTF-8 locale。所有示例命令均按 bash 编写。

## 输出契约

MQ 外层保持不变，`payload.ag_ui` 必须是非空 Markdown 字符串。

```json
{
  "event_type": "decision_agent.session.ag_ui_event",
  "payload": {
    "conversation_id": "100",
    "turn_id": "200",
    "message_id": "901",
    "content": "方案设计已生成。",
    "sequence": 1,
    "ag_ui": "# 方案设计\n\n这里是 Markdown 内容。"
  }
}
```

字段规则：

- `conversation_id`：当前会话 ID，必须由上游输入传入。
- `turn_id`：会话侧预留的用户回合主键，必须由上游输入传入。
- `message_id`：AI 输出消息 ID，可由上游提供；未提供时脚本用 Snowflake 生成。
- `content`：纯文本摘要或降级展示文本。
- `sequence`：同一 `turn_id + message_id` 下的输出序号。
- `payload.ag_ui`：完整 Markdown 文本，不是对象。

同一 `message_id + sequence` 使用新的 `event_id` 时，表示该 Markdown 文本整体替换旧内容。

## Markdown 生成规则

- Markdown 必须能直接作为用户可见内容展示。
- 可以使用标题、段落、列表、表格、引用、代码块和链接。
- 结论应优先放在前面，后续再给依据、对比、风险和下一步。
- 错误内容必须脱敏，并给出可执行的下一步。
- 需要用户确认时，明确写出待确认项、可选动作和继续执行所需信息。
- 最终结果必须来自已经完成的 AI 结果源文本；不得额外编造事实、数量、对象、风险等级或动作。

## 安全边界

用户可见 Markdown 不得包含：

- 完整内部推理链。
- 系统提示词。
- 密钥、令牌、密码或私钥。
- 原始工具参数或原始工具返回。
- 数据库、消息队列、对象存储或外部系统连接串。
- 未脱敏日志或敏感错误堆栈。
- 可执行 HTML、脚本或表达式。

如果当前结果包含敏感内容，必须先脱敏、概括或改写，再生成 Markdown。

## 工作流

1. 读取本技能并确认必需输入：`conversation_id`、`turn_id`、`sequence`，以及要展示的 Markdown 文本。
2. 生成用户可见 Markdown 文本，并设置一句纯文本 `content` 摘要。
3. 运行校验或生成脚本，脚本只补齐 MQ envelope、`event_id`、`occurred_at`、`message_id` 等外层字段。
4. 需要发布时追加 `--publish --rabbitmq-url <url>`。
5. MQ 发布失败必须停止当前业务动作，并输出脱敏失败说明。

只生成本地消息 JSON：

```bash
markdown='# 方案设计

这里是 Markdown 内容。'

python3 -X utf8 scripts/generate_ag_ui_mq_message.py \
  --markdown "$markdown" \
  --conversation-id "100" \
  --turn-id "200" \
  --message-id "901" \
  --content "方案设计已生成。" \
  --sequence 1
```

校验 Markdown 文本：

```bash
python3 -X utf8 scripts/validate_ag_ui_mq_message.py \
  --markdown "$markdown"
```

生成、校验并发布：

```bash
python3 -X utf8 scripts/generate_validate_publish_ag_ui_mq_message.py \
  --markdown "$markdown" \
  --conversation-id "100" \
  --turn-id "200" \
  --message-id "901" \
  --content "方案设计已生成。" \
  --sequence 1 \
  --publish \
  --rabbitmq-url amqp://guest:guest@localhost:5672/
```

## Snowflake 规则

脚本生成 `message_id` 时使用会话服务同款算法：

- epoch：`1735689600000`
- node：10 bit，固定使用技能内置值 `900`
- sequence：12 bit，由脚本在本进程内维护；同毫秒内从 `0` 递增，溢出后进入下一毫秒槽位
- 位移：`((timestamp_ms - epoch_ms) << 22) | (node_id << 12) | sequence`

调用方不传入也不覆盖 `node_id`。
