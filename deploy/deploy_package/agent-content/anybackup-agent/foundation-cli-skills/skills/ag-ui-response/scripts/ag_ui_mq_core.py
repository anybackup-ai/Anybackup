from __future__ import annotations

import json
from collections.abc import Callable
from copy import deepcopy
from datetime import UTC, datetime
from pathlib import Path
from threading import Lock
from time import time
from typing import Any

DEFAULT_EXCHANGE = "decision_agent.ag_ui.events"
DEFAULT_ROUTING_KEY = "decision_agent.session.ag_ui_event.v1"
DEFAULT_SOURCE_SERVICE = "decision_agent_session"
DEFAULT_MESSAGE_TYPE = "decision_agent.session.ag_ui_event"
DEFAULT_SNOWFLAKE_EPOCH_MS = 1_735_689_600_000
DEFAULT_SNOWFLAKE_NODE_ID = 900
_SNOWFLAKE_NODE_ID_BITS = 10
_SNOWFLAKE_SEQUENCE_BITS = 12
_SNOWFLAKE_MAX_NODE_ID = (1 << _SNOWFLAKE_NODE_ID_BITS) - 1
_SNOWFLAKE_MAX_SEQUENCE = (1 << _SNOWFLAKE_SEQUENCE_BITS) - 1
_SNOWFLAKE_NODE_SHIFT = _SNOWFLAKE_SEQUENCE_BITS
_SNOWFLAKE_TIME_SHIFT = _SNOWFLAKE_NODE_ID_BITS + _SNOWFLAKE_SEQUENCE_BITS
_snowflake_lock = Lock()
_snowflake_last_timestamp_ms = -1
_snowflake_sequence = 0
if DEFAULT_SNOWFLAKE_NODE_ID < 0 or DEFAULT_SNOWFLAKE_NODE_ID > _SNOWFLAKE_MAX_NODE_ID:
    raise RuntimeError("DEFAULT_SNOWFLAKE_NODE_ID must be between 0 and 1023")

SKILL_ROOT = Path(__file__).resolve().parents[1]
REFERENCES_DIR = SKILL_ROOT / "references"
SCHEMAS_DIR = REFERENCES_DIR / "schemas"

_ALLOWED_MESSAGE_FIELDS = frozenset(
    {"event_id", "event_type", "occurred_at", "source_service", "payload"}
)
_ALLOWED_PAYLOAD_FIELDS = frozenset(
    {"conversation_id", "turn_id", "message_id", "content", "sequence", "ag_ui"}
)
_SENSITIVE_MARKDOWN_MARKERS = (
    "完整内部推理链",
    "内部推理链",
    "系统提示词",
    "原始工具参数",
    "原始工具返回",
    "未脱敏日志",
    "敏感错误堆栈",
    "连接串",
    "password=",
    "passwd=",
    "secret=",
    "api_key=",
    "apikey=",
    "access_token=",
    "bearer ",
    "postgresql://",
    "mysql://",
    "mongodb://",
    "redis://",
    "-----begin private key-----",
)


class ContractValidationError(ValueError):
    def __init__(self, errors: list[str]) -> None:
        self.errors = tuple(errors)
        super().__init__("\n".join(self.errors))


def load_json_text(value: str) -> Any:
    try:
        return json.loads(value)
    except json.JSONDecodeError as exc:
        raise ContractValidationError([f"JSON string is invalid: {exc.msg}"]) from exc


def dump_json(payload: Any) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2)


def load_schema(schema_name: str) -> dict[str, Any]:
    schema_path = SCHEMAS_DIR / schema_name
    return json.loads(schema_path.read_text(encoding="utf-8"))


def validate_markdown_text(markdown: object, *, field_name: str = "markdown") -> str:
    errors: list[str] = []
    if not isinstance(markdown, str):
        raise ContractValidationError([f"{field_name} must be a string"])
    if not markdown.strip():
        errors.append(f"{field_name} must be a non-empty Markdown string")

    normalized = markdown.lower()
    for marker in _SENSITIVE_MARKDOWN_MARKERS:
        if marker in normalized or marker in markdown:
            errors.append(f"{field_name} contains sensitive content marker: {marker}")

    if errors:
        raise ContractValidationError(errors)
    return markdown


def build_message_from_markdown(
    *,
    markdown: object,
    conversation_id: object,
    turn_id: object,
    sequence: object,
    message_id: object | None = None,
    content: object | None = None,
    event_id: object | None = None,
    occurred_at: object | None = None,
    source_service: object = DEFAULT_SOURCE_SERVICE,
    now_ms: int | None = None,
    snowflake_epoch_ms: int = DEFAULT_SNOWFLAKE_EPOCH_MS,
) -> dict[str, Any]:
    errors: list[str] = []
    markdown_text = _validate_markdown_collect(markdown, "markdown", errors)
    conversation_id_text = _coerce_non_empty_id(
        conversation_id, "conversation_id", errors
    )
    turn_id_text = _coerce_non_empty_id(turn_id, "turn_id", errors)
    sequence_value = _coerce_positive_int(sequence, "sequence", errors)
    message_id_text = (
        _coerce_non_empty_id(message_id, "message_id", errors)
        if message_id is not None
        else None
    )
    content_text = (
        _coerce_non_empty_string(content, "content", errors)
        if content is not None
        else _derive_content_summary(markdown_text)
    )
    event_id_text = (
        _coerce_non_empty_string(event_id, "event_id", errors)
        if event_id is not None
        else None
    )
    source_service_text = _coerce_non_empty_string(
        source_service, "source_service", errors
    )
    current_ms = _current_time_ms() if now_ms is None else now_ms
    if isinstance(current_ms, bool) or not isinstance(current_ms, int) or current_ms < 0:
        errors.append("now_ms must be a non-negative integer when provided")

    occurred_at_text: str | None
    if occurred_at is None:
        occurred_at_text = _ms_to_iso(current_ms if isinstance(current_ms, int) else 0)
    else:
        occurred_at_text = _coerce_non_empty_string(occurred_at, "occurred_at", errors)
        if occurred_at_text is not None:
            _validate_iso_timestamp(occurred_at_text, "occurred_at", errors)

    if errors:
        raise ContractValidationError(errors)

    assert conversation_id_text is not None
    assert turn_id_text is not None
    assert sequence_value is not None
    assert markdown_text is not None
    assert content_text is not None
    assert source_service_text is not None
    assert occurred_at_text is not None

    if message_id_text is None:
        message_id_text = str(
            _next_snowflake_id(
                current_ms,
                node_id=DEFAULT_SNOWFLAKE_NODE_ID,
                epoch_ms=snowflake_epoch_ms,
            )
        )
    if event_id_text is None:
        event_id_text = (
            f"decision-agent.markdown.{conversation_id_text}.{sequence_value}.{current_ms}"
        )

    message = {
        "event_id": event_id_text,
        "event_type": DEFAULT_MESSAGE_TYPE,
        "occurred_at": occurred_at_text,
        "source_service": source_service_text,
        "payload": {
            "conversation_id": conversation_id_text,
            "turn_id": turn_id_text,
            "message_id": message_id_text,
            "content": content_text,
            "sequence": sequence_value,
            "ag_ui": markdown_text,
        },
    }
    validate_message(message)
    return message


def generate_valid_message_from_markdown(
    *,
    markdown: object,
    conversation_id: object,
    turn_id: object,
    sequence: object,
    message_id: object | None = None,
    content: object | None = None,
    event_id: object | None = None,
    occurred_at: object | None = None,
    source_service: object = DEFAULT_SOURCE_SERVICE,
    attempts: int = 3,
    now_ms: int | None = None,
    snowflake_epoch_ms: int = DEFAULT_SNOWFLAKE_EPOCH_MS,
) -> dict[str, Any]:
    if attempts < 1:
        raise ValueError("attempts must be at least 1")
    collected_errors: list[str] = []
    for attempt in range(1, attempts + 1):
        try:
            return build_message_from_markdown(
                markdown=markdown,
                conversation_id=conversation_id,
                turn_id=turn_id,
                sequence=sequence,
                message_id=message_id,
                content=content,
                event_id=event_id,
                occurred_at=occurred_at,
                source_service=source_service,
                now_ms=now_ms,
                snowflake_epoch_ms=snowflake_epoch_ms,
            )
        except ContractValidationError as exc:
            collected_errors.extend([f"attempt {attempt}: {issue}" for issue in exc.errors])
            break
    raise ContractValidationError(
        collected_errors or ["unable to generate a valid Markdown MQ message"]
    )


def validate_draft(draft: object) -> dict[str, Any]:
    del draft
    raise ContractValidationError(
        ["legacy structured input is no longer supported at runtime; pass Markdown via --markdown"]
    )


def generate_valid_message_from_draft(
    draft: object,
    **_: Any,
) -> dict[str, Any]:
    del draft
    raise ContractValidationError(
        ["legacy structured input is no longer supported at runtime; pass Markdown via --markdown"]
    )


def validate_message(message: object) -> dict[str, Any]:
    if not isinstance(message, dict):
        raise ContractValidationError(["message must be a JSON object"])

    errors: list[str] = []
    _reject_unexpected_fields(message, _ALLOWED_MESSAGE_FIELDS, "message", errors)
    _expect_non_empty_string(message.get("event_id"), "message.event_id", errors)
    if message.get("event_type") != DEFAULT_MESSAGE_TYPE:
        errors.append(f"message.event_type must be {DEFAULT_MESSAGE_TYPE!r}")
    _validate_iso_timestamp(message.get("occurred_at"), "message.occurred_at", errors)
    _expect_non_empty_string(message.get("source_service"), "message.source_service", errors)

    payload = message.get("payload")
    if not isinstance(payload, dict):
        errors.append("message.payload must be an object")
    else:
        _reject_unexpected_fields(payload, _ALLOWED_PAYLOAD_FIELDS, "message.payload", errors)
        _expect_non_empty_string(
            payload.get("conversation_id"), "message.payload.conversation_id", errors
        )
        _expect_non_empty_string(payload.get("turn_id"), "message.payload.turn_id", errors)
        _expect_non_empty_string(payload.get("message_id"), "message.payload.message_id", errors)
        _expect_non_empty_string(payload.get("content"), "message.payload.content", errors)
        _expect_positive_int(payload.get("sequence"), "message.payload.sequence", errors)
        _validate_markdown_collect(payload.get("ag_ui"), "message.payload.ag_ui", errors)

    if errors:
        raise ContractValidationError(errors)
    return deepcopy(message)


async def publish_validated_message(
    message: object,
    *,
    publisher: Callable[..., Any] | None = None,
    exchange: str = DEFAULT_EXCHANGE,
    routing_key: str = DEFAULT_ROUTING_KEY,
    rabbitmq_url: str | None = None,
    headers: dict[str, Any] | None = None,
) -> dict[str, Any]:
    validated = validate_message(message)
    publish_headers = _normalize_headers(headers)

    if publisher is not None:
        await publisher(
            validated,
            exchange=exchange,
            routing_key=routing_key,
            rabbitmq_url=rabbitmq_url,
            headers=publish_headers,
        )
        return validated

    if not rabbitmq_url:
        raise ValueError("rabbitmq_url is required when publisher is not provided")

    try:
        import aio_pika
        from aio_pika import DeliveryMode, ExchangeType, Message
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError("Publishing requires aio-pika in the runtime environment.") from exc

    connection = await aio_pika.connect_robust(rabbitmq_url)
    try:
        channel = await connection.channel(publisher_confirms=True)
        exchange_obj = await channel.declare_exchange(
            exchange,
            ExchangeType.TOPIC,
            durable=True,
        )
        payload = Message(
            body=json.dumps(validated, ensure_ascii=False, indent=2).encode("utf-8"),
            content_type="application/json",
            delivery_mode=DeliveryMode.PERSISTENT,
            message_id=str(validated["event_id"]),
            headers=publish_headers,
        )
        await exchange_obj.publish(payload, routing_key=routing_key, mandatory=True)
    finally:
        await connection.close()
    return validated


def _validate_markdown_collect(
    markdown: object, field_name: str, errors: list[str]
) -> str | None:
    try:
        return validate_markdown_text(markdown, field_name=field_name)
    except ContractValidationError as exc:
        errors.extend(exc.errors)
        return None


def _reject_unexpected_fields(
    payload: dict[str, Any],
    allowed_fields: frozenset[str],
    prefix: str,
    errors: list[str],
) -> None:
    unexpected = sorted(set(payload) - allowed_fields)
    for field_name in unexpected:
        errors.append(f"{prefix}.{field_name} is not supported")


def _expect_non_empty_string(value: object, field_name: str, errors: list[str]) -> None:
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{field_name} must be a non-empty string")


def _expect_positive_int(value: object, field_name: str, errors: list[str]) -> None:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        errors.append(f"{field_name} must be a positive integer")


def _coerce_non_empty_id(
    value: object, field_name: str, errors: list[str]
) -> str | None:
    if isinstance(value, bool):
        errors.append(f"{field_name} must be a non-empty string or integer")
        return None
    if isinstance(value, int):
        return str(value)
    return _coerce_non_empty_string(value, field_name, errors)


def _coerce_non_empty_string(
    value: object, field_name: str, errors: list[str]
) -> str | None:
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{field_name} must be a non-empty string")
        return None
    return value


def _coerce_positive_int(
    value: object, field_name: str, errors: list[str]
) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        errors.append(f"{field_name} must be a positive integer")
        return None
    return value


def _validate_iso_timestamp(value: object, field_name: str, errors: list[str]) -> None:
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{field_name} must be an ISO-8601 timestamp string")
        return
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        errors.append(f"{field_name} must be an ISO-8601 timestamp string")
        return
    if parsed.tzinfo is None:
        errors.append(f"{field_name} must include timezone information")


def _derive_content_summary(markdown: str | None) -> str:
    if markdown is None:
        return "Markdown response generated."
    for line in markdown.splitlines():
        normalized = line.strip()
        if not normalized:
            continue
        normalized = normalized.lstrip("#> -*0123456789.").strip()
        if normalized:
            return normalized[:200]
    return "Markdown response generated."


def _normalize_headers(headers: dict[str, Any] | None) -> dict[str, str]:
    normalized: dict[str, str] = {}
    for key, value in (headers or {}).items():
        if value is None:
            continue
        normalized[str(key)] = str(value)
    return normalized


def _current_time_ms() -> int:
    return int(time() * 1000)


def _ms_to_iso(milliseconds: int) -> str:
    return datetime.fromtimestamp(milliseconds / 1000, tz=UTC).isoformat().replace(
        "+00:00", "Z"
    )


def _next_snowflake_id(
    timestamp_ms: int,
    *,
    node_id: int,
    epoch_ms: int,
) -> int:
    if node_id < 0 or node_id > _SNOWFLAKE_MAX_NODE_ID:
        raise ValueError("node_id must be between 0 and 1023")
    if timestamp_ms < epoch_ms:
        raise ValueError("timestamp_ms must be greater than or equal to epoch_ms")

    global _snowflake_last_timestamp_ms, _snowflake_sequence
    with _snowflake_lock:
        if timestamp_ms < _snowflake_last_timestamp_ms:
            timestamp_ms = _snowflake_last_timestamp_ms
        if timestamp_ms == _snowflake_last_timestamp_ms:
            _snowflake_sequence = (_snowflake_sequence + 1) & _SNOWFLAKE_MAX_SEQUENCE
            if _snowflake_sequence == 0:
                timestamp_ms += 1
        else:
            _snowflake_sequence = 0
        _snowflake_last_timestamp_ms = timestamp_ms
        elapsed = timestamp_ms - epoch_ms
        return (
            (elapsed << _SNOWFLAKE_TIME_SHIFT)
            | (node_id << _SNOWFLAKE_NODE_SHIFT)
            | _snowflake_sequence
        )
