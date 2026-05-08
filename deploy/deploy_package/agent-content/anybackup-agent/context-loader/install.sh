#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TOOLSET_FILE="$SCRIPT_DIR/toolset/context_loader_toolset.adp"
DEFAULT_DEP_TOOLBOX_FILE="$SCRIPT_DIR/tool-deps/execution_factory_tools.adp"

usage() {
  cat <<'EOF'
Usage:
  ./install.sh --base-url <url> [options]

Options:
  --base-url <url>        KWeaver service base URL.
  --biz-domain <value>    Business domain ID (default: bd_public).
  --toolbox-file <path>   ContextLoader toolbox .adp file. Can be repeated.
  --mode <value>          Import mode: create | upsert (default: upsert).
  --toolbox-name <value>  Toolbox name to verify after import.
  --insecure              Skip TLS verification for curl.
  --skip-verify           Do not verify imported toolboxes with export API.
  -h, --help              Show this help.

Environment variables:
  KWEAVER_BASE_URL
  KWEAVER_BUSINESS_DOMAIN
  CONTEXTLOADER_TOOLBOX_FILES
  CONTEXTLOADER_IMPORT_MODE
  CONTEXTLOADER_TOOLBOX_NAME
  KWEAVER_INSECURE
  CONTEXTLOADER_SKIP_VERIFY
EOF
}

log() {
  printf '[INFO] %s\n' "$*"
}

error() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || error "Required command not found: $1"
}

get_kweaver_token() {
  local value
  value="$(kweaver token 2>/dev/null | tail -n 1 | tr -d '\r\n' || true)"
  if [[ -z "$value" ]]; then
    value="$(kweaver auth token 2>/dev/null | tail -n 1 | tr -d '\r\n' || true)"
  fi
  [[ -n "$value" ]] || return 1
  printf '%s\n' "$value"
}

normalize_base_url() {
  local raw="$1"
  raw="${raw%/}"
  [[ -n "$raw" ]] || error "--base-url or KWEAVER_BASE_URL is required."
  printf '%s\n' "$raw"
}

read_toolbox_ids() {
  python3 - "$@" <<'PY'
import json
import sys
from pathlib import Path

for arg in sys.argv[1:]:
    path = Path(arg)
    data = json.loads(path.read_text(encoding="utf-8"))
    for cfg in data.get("toolbox", {}).get("configs", []):
        box_id = cfg.get("box_id")
        if box_id:
            print(box_id)
PY
}

KWEAVER_BASE_URL="${KWEAVER_BASE_URL:-}"
KWEAVER_BUSINESS_DOMAIN="${KWEAVER_BUSINESS_DOMAIN:-bd_public}"
TOOLBOX_FILES=()
if [[ -n "${CONTEXTLOADER_TOOLBOX_FILES:-}" ]]; then
  IFS=',' read -r -a TOOLBOX_FILES <<< "$CONTEXTLOADER_TOOLBOX_FILES"
else
  TOOLBOX_FILES=("$DEFAULT_TOOLSET_FILE" "$DEFAULT_DEP_TOOLBOX_FILE")
fi
IMPORT_MODE="${CONTEXTLOADER_IMPORT_MODE:-upsert}"
CONTEXTLOADER_TOOLBOX_NAME="${CONTEXTLOADER_TOOLBOX_NAME:-contextloader工具集_060}"
KWEAVER_INSECURE="${KWEAVER_INSECURE:-0}"
CONTEXTLOADER_SKIP_VERIFY="${CONTEXTLOADER_SKIP_VERIFY:-0}"
CONTEXTLOADER_IMPORT_RETRIES="${CONTEXTLOADER_IMPORT_RETRIES:-5}"
CONTEXTLOADER_IMPORT_RETRY_DELAY="${CONTEXTLOADER_IMPORT_RETRY_DELAY:-6}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url|--url)
      KWEAVER_BASE_URL="${2:-}"
      shift 2
      ;;
    --biz-domain)
      KWEAVER_BUSINESS_DOMAIN="${2:-}"
      shift 2
      ;;
    --toolbox-file)
      TOOLBOX_FILES+=("${2:-}")
      shift 2
      ;;
    --mode)
      IMPORT_MODE="${2:-}"
      shift 2
      ;;
    --toolbox-name)
      CONTEXTLOADER_TOOLBOX_NAME="${2:-}"
      shift 2
      ;;
    --insecure)
      KWEAVER_INSECURE="1"
      shift
      ;;
    --skip-verify)
      CONTEXTLOADER_SKIP_VERIFY="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown argument: $1"
      ;;
  esac
done

require_command kweaver
require_command curl
require_command python3

for TOOLBOX_FILE in "${TOOLBOX_FILES[@]}"; do
  [[ -f "$TOOLBOX_FILE" ]] || error "ContextLoader toolbox file not found: $TOOLBOX_FILE"
done
case "$IMPORT_MODE" in
  create|upsert) ;;
  *) error "Unsupported import mode: $IMPORT_MODE" ;;
esac

KWEAVER_BASE_URL="$(normalize_base_url "$KWEAVER_BASE_URL")"
import_url="${KWEAVER_BASE_URL}/api/agent-operator-integration/v1/impex/import/toolbox"

log "Importing ContextLoader toolboxes..."
log "Business domain: $KWEAVER_BUSINESS_DOMAIN"

token="$(get_kweaver_token)"
[[ -n "$token" ]] || error "Failed to get KWeaver token from CLI."

curl_base_args=(-sS -f)
curl_import_args=(-sS)
if [[ "$KWEAVER_INSECURE" == "1" ]]; then
  curl_base_args=(-k "${curl_base_args[@]}")
  curl_import_args=(-k "${curl_import_args[@]}")
fi

for TOOLBOX_FILE in "${TOOLBOX_FILES[@]}"; do
  log "Toolbox file: $TOOLBOX_FILE"
  response=""
  for attempt in $(seq 1 "$CONTEXTLOADER_IMPORT_RETRIES"); do
    response_file="$(mktemp)"
    http_status="$(
      curl "${curl_import_args[@]}" \
        -o "$response_file" \
        -w '%{http_code}' \
        -X POST \
        "$import_url" \
        -H "Authorization: Bearer ${token}" \
        -H "x-business-domain: ${KWEAVER_BUSINESS_DOMAIN}" \
        -F "data=@${TOOLBOX_FILE}" \
        -F "mode=${IMPORT_MODE}"
    )"
    response="$(cat "$response_file")"
    rm -f "$response_file"
    if [[ "$http_status" =~ ^2 ]]; then
      printf '%s\n' "$response"
      break
    fi
    if [[ "$http_status" != "500" && "$http_status" != "502" && "$http_status" != "503" && "$http_status" != "504" ]]; then
      printf '%s\n' "$response" >&2
      error "ContextLoader toolbox import failed with HTTP $http_status"
    fi
    if [[ "$attempt" -ge "$CONTEXTLOADER_IMPORT_RETRIES" ]]; then
      printf '%s\n' "$response" >&2
      error "ContextLoader toolbox import failed with HTTP $http_status after $attempt attempts"
    fi
    log "ContextLoader import returned HTTP $http_status, retrying in ${CONTEXTLOADER_IMPORT_RETRY_DELAY}s ($attempt/${CONTEXTLOADER_IMPORT_RETRIES})"
    sleep "$CONTEXTLOADER_IMPORT_RETRY_DELAY"
  done
done

if [[ "$CONTEXTLOADER_SKIP_VERIFY" == "1" ]]; then
  log "Skipped ContextLoader toolbox verification."
  exit 0
fi

log "Verifying imported ContextLoader toolboxes..."
while IFS= read -r box_id; do
  [[ -n "$box_id" ]] || continue
  curl "${curl_base_args[@]}" \
    -o /dev/null \
    "$KWEAVER_BASE_URL/api/agent-operator-integration/v1/impex/export/toolbox/${box_id}" \
    -H "Authorization: Bearer ${token}" \
    -H "x-business-domain: ${KWEAVER_BUSINESS_DOMAIN}"
  log "Toolbox is exportable: ${box_id}"
done < <(read_toolbox_ids "${TOOLBOX_FILES[@]}")

for TOOLBOX_FILE in "${TOOLBOX_FILES[@]}"; do
  if grep -q "$CONTEXTLOADER_TOOLBOX_NAME" "$TOOLBOX_FILE"; then
    log "ContextLoader toolbox is packaged and imported: $CONTEXTLOADER_TOOLBOX_NAME"
    exit 0
  fi
done

error "ContextLoader toolbox import finished, but expected toolbox name was not found in imported files: $CONTEXTLOADER_TOOLBOX_NAME"
