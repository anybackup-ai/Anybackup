from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from ag_ui_mq_core import (  # noqa: E402
    ContractValidationError,
    load_json_text,
    validate_markdown_text,
    validate_message,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate a Markdown payload or a generated Decision Agent MQ message."
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--markdown", help="Markdown text to validate.")
    group.add_argument("--json", help="Generated MQ message JSON string to validate.")
    args = parser.parse_args(argv)

    try:
        if args.markdown is not None:
            validate_markdown_text(args.markdown)
            print("valid markdown")
        else:
            validate_message(load_json_text(args.json))
            print("valid message")
    except ContractValidationError as exc:
        for issue in exc.errors:
            print(issue, file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
