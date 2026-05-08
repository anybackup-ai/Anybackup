from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from ag_ui_mq_core import (  # noqa: E402
    DEFAULT_EXCHANGE,
    DEFAULT_ROUTING_KEY,
    ContractValidationError,
    dump_json,
    generate_valid_message_from_markdown,
    publish_validated_message,
    validate_message,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Generate, validate, and optionally publish an MQ message whose "
            "payload.ag_ui is a Markdown string."
        )
    )
    parser.add_argument("--markdown", required=True, help="User-visible Markdown text.")
    parser.add_argument("--conversation-id", required=True, help="Conversation id.")
    parser.add_argument("--turn-id", required=True, help="Source user turn/message id.")
    parser.add_argument("--sequence", type=int, required=True, help="Positive output sequence.")
    parser.add_argument("--message-id", default=None, help="Assistant message id.")
    parser.add_argument("--content", default=None, help="Plain text summary/fallback.")
    parser.add_argument("--event-id", default=None, help="MQ event id.")
    parser.add_argument("--occurred-at", default=None, help="ISO-8601 event timestamp.")
    parser.add_argument("--now-ms", type=int, default=None, help="Fixed millisecond timestamp.")
    parser.add_argument(
        "--source-service",
        default="decision_agent_session",
        help="Message source_service.",
    )
    parser.add_argument(
        "--snowflake-epoch-ms",
        type=int,
        default=1_735_689_600_000,
        help="Snowflake epoch milliseconds shared with the conversation service.",
    )
    parser.add_argument(
        "--publish",
        action="store_true",
        help="Publish after generation and validation.",
    )
    parser.add_argument("--rabbitmq-url", default="", help="RabbitMQ connection URL.")
    parser.add_argument("--exchange", default=DEFAULT_EXCHANGE, help="Exchange name.")
    parser.add_argument("--routing-key", default=DEFAULT_ROUTING_KEY, help="Routing key.")
    parser.add_argument("--trace-id", default="", help="Optional trace id.")
    parser.add_argument("--correlation-id", default="", help="Optional correlation id.")
    args = parser.parse_args(argv)

    try:
        message = generate_valid_message_from_markdown(
            markdown=args.markdown,
            conversation_id=args.conversation_id,
            turn_id=args.turn_id,
            message_id=args.message_id,
            content=args.content,
            sequence=args.sequence,
            event_id=args.event_id,
            occurred_at=args.occurred_at,
            now_ms=args.now_ms,
            source_service=args.source_service,
            snowflake_epoch_ms=args.snowflake_epoch_ms,
        )
        validate_message(message)
        if args.publish:
            if not args.rabbitmq_url:
                parser.error("--rabbitmq-url is required when --publish is set")
            asyncio.run(
                publish_validated_message(
                    message,
                    rabbitmq_url=args.rabbitmq_url,
                    exchange=args.exchange,
                    routing_key=args.routing_key,
                    headers=_headers(args),
                )
            )
            print(
                "generated, validated, published: "
                f"{args.exchange}:{args.routing_key}"
            )
        else:
            print(dump_json(message))
    except ContractValidationError as exc:
        for issue in exc.errors:
            print(issue, file=sys.stderr)
        return 1

    return 0


def _headers(args: argparse.Namespace) -> dict[str, str]:
    headers: dict[str, str] = {}
    if args.trace_id:
        headers["trace_id"] = args.trace_id
    if args.correlation_id:
        headers["correlation_id"] = args.correlation_id
    return headers


if __name__ == "__main__":
    raise SystemExit(main())
