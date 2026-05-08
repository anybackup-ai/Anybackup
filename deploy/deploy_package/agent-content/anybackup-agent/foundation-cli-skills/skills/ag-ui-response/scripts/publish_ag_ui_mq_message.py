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
    load_json_text,
    publish_validated_message,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Publish a validated Markdown response MQ message to RabbitMQ."
    )
    parser.add_argument("--message-json", required=True, help="Message JSON string to publish.")
    parser.add_argument("--rabbitmq-url", required=True, help="RabbitMQ connection URL.")
    parser.add_argument("--exchange", default=DEFAULT_EXCHANGE, help="Exchange name.")
    parser.add_argument("--routing-key", default=DEFAULT_ROUTING_KEY, help="Routing key.")
    parser.add_argument("--trace-id", default="", help="Optional trace id.")
    parser.add_argument("--correlation-id", default="", help="Optional correlation id.")
    args = parser.parse_args(argv)

    try:
        asyncio.run(
            publish_validated_message(
                load_json_text(args.message_json),
                rabbitmq_url=args.rabbitmq_url,
                exchange=args.exchange,
                routing_key=args.routing_key,
                headers=_headers(args),
            )
        )
    except ContractValidationError as exc:
        for issue in exc.errors:
            print(issue, file=sys.stderr)
        return 1

    print(f"published: exchange={args.exchange} routing_key={args.routing_key}")
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
