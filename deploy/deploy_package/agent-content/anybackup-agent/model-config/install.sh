#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  install.sh --config-dir DIR --base-url URL --state-file FILE [options]

Options:
  --biz-domain BD        Business domain, recorded in state only. Default: bd_public
  --insecure             Pass --insecure to kweaver-admin
  --skip-small-models    Do not import small-model configs

The script is idempotent by model name. Existing models are reused and mapped
from source model_id to target model_id. API keys are read from environment
overrides when needed and are never printed.

Model role environment overrides:
  ANYBACKUP_LLM_NAME                Select the single LLM config to deploy
  ANYBACKUP_LLM_API_KEY             API key for the selected LLM when creating it
  ANYBACKUP_EMBEDDING_MODEL_NAME    Select the embedding small-model config
  ANYBACKUP_EMBEDDING_API_KEY       API key for embedding create/update
  ANYBACKUP_RERANKER_MODEL_NAME     Select the reranker small-model config
  ANYBACKUP_RERANKER_API_KEY        API key for reranker adapter code
USAGE
}

CONFIG_DIR=""
BASE_URL="${KWEAVER_BASE_URL:-}"
BIZ_DOMAIN="${KWEAVER_BUSINESS_DOMAIN:-bd_public}"
STATE_FILE=""
INSECURE=0
SKIP_SMALL_MODELS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-dir)
      CONFIG_DIR="${2:-}"
      shift 2
      ;;
    --base-url)
      BASE_URL="${2:-}"
      shift 2
      ;;
    --biz-domain)
      BIZ_DOMAIN="${2:-}"
      shift 2
      ;;
    --state-file)
      STATE_FILE="${2:-}"
      shift 2
      ;;
    --insecure)
      INSECURE=1
      shift
      ;;
    --skip-small-models)
      SKIP_SMALL_MODELS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$CONFIG_DIR" || -z "$BASE_URL" || -z "$STATE_FILE" ]]; then
  usage >&2
  exit 2
fi

if [[ ! -d "$CONFIG_DIR" ]]; then
  echo "Model config directory does not exist: $CONFIG_DIR" >&2
  exit 1
fi

if ! command -v kweaver-admin >/dev/null 2>&1; then
  echo "Required command is missing: kweaver-admin" >&2
  exit 1
fi

resolve_kweaver_token() {
  local value=""

  if [[ -n "${KWEAVER_ADMIN_TOKEN:-}" || -n "${KWEAVER_TOKEN:-}" ]]; then
    return 0
  fi

  if command -v kweaver >/dev/null 2>&1; then
    value="$(kweaver token 2>/dev/null | tail -n 1 | tr -d '\r\n' || true)"
    if [[ -z "$value" ]]; then
      value="$(kweaver auth token 2>/dev/null | tail -n 1 | tr -d '\r\n' || true)"
    fi
  fi

  if [[ -n "$value" ]]; then
    export KWEAVER_TOKEN="$value"
  fi
}

resolve_kweaver_token

mkdir -p "$(dirname "$STATE_FILE")"

python3 - "$CONFIG_DIR" "$BASE_URL" "$BIZ_DOMAIN" "$STATE_FILE" "$INSECURE" "$SKIP_SMALL_MODELS" <<'PY'
import json
import os
import re
import ssl
import subprocess
import sys
import urllib.error
import urllib.request
from urllib.parse import urlparse
from pathlib import Path

config_dir = Path(sys.argv[1])
base_url = sys.argv[2]
biz_domain = sys.argv[3]
state_file = Path(sys.argv[4])
insecure = sys.argv[5] == "1"
skip_small_models = sys.argv[6] == "1"
kweaver_config_path = Path(os.environ.get("KWEAVER_CONFIG_PATH", "/opt/v9-alpha-deploy/kweaver-config/config.yaml"))
kweaver_resource_namespace = os.environ.get("KWEAVER_RESOURCE_NAMESPACE", "resource")


def read_json(path: Path):
    raw = path.read_bytes()
    encodings = ("utf-8-sig", "utf-16", "utf-16-le", "gb18030")
    last_error = None
    for enc in encodings:
        try:
            return json.loads(raw.decode(enc))
        except Exception as exc:  # noqa: BLE001 - keep trying encodings
            last_error = exc
    raise ValueError(f"Unable to parse JSON file {path}: {last_error}") from last_error


def decode_text(path: Path):
    raw = path.read_bytes()
    encodings = ("utf-8-sig", "utf-16", "utf-16-le", "gb18030")
    last_error = None
    for enc in encodings:
        try:
            return raw.decode(enc)
        except Exception as exc:  # noqa: BLE001
            last_error = exc
    raise ValueError(f"Unable to decode file {path}: {last_error}") from last_error


def redact_secrets(value):
    if isinstance(value, dict):
        redacted = {}
        for key, item in value.items():
            key_name = str(key).lower().replace("-", "_")
            if key_name in {"api_key", "access_key", "secret_key", "token", "password"}:
                redacted[key] = "<redacted>" if item else item
            else:
                redacted[key] = redact_secrets(item)
        return redacted
    if isinstance(value, list):
        return [redact_secrets(item) for item in value]
    return value


def parse_json_text(text: str):
    text = text.strip()
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        starts = [pos for pos in (text.find("{"), text.find("[")) if pos >= 0]
        if not starts:
            raise
        return json.loads(text[min(starts):])


def extract_items(obj):
    if isinstance(obj, list):
        return obj
    if not isinstance(obj, dict):
        return []
    paths = (
        ("data", "items"),
        ("data", "records"),
        ("data", "list"),
        ("items",),
        ("records",),
        ("entries",),
        ("data",),
    )
    for path in paths:
        cur = obj
        for key in path:
            if not isinstance(cur, dict) or key not in cur:
                cur = None
                break
            cur = cur[key]
        if isinstance(cur, list):
            return cur
    return []


def first_value(obj, keys):
    if not isinstance(obj, dict):
        return ""
    for key in keys:
        value = obj.get(key)
        if value is not None and value != "":
            return str(value)
    return ""


def int_value(*values, default=None):
    for value in values:
        if value is None or value == "":
            continue
        return int(value)
    return default


def model_id(obj):
    return first_value(obj, ("model_id", "id", "modelId", "llm_id", "llmId"))


def model_name(obj):
    return first_value(obj, ("model_name", "name", "modelName"))


def looks_masked(value: str) -> bool:
    stripped = (value or "").strip()
    if not stripped:
        return True
    return bool(re.fullmatch(r"[*xX]+", stripped)) or stripped.startswith("***")


def jsonish_string(block: str, key: str):
    match = re.search(rf'"{re.escape(key)}"\s*:\s*"((?:\\.|[^"\\])*)"', block, re.S)
    if not match:
        return ""
    value = match.group(1)
    try:
        return json.loads(f'"{value}"')
    except Exception:  # noqa: BLE001
        return value


def jsonish_bool(block: str, key: str):
    match = re.search(rf'"{re.escape(key)}"\s*:\s*(true|false)', block)
    if not match:
        return False
    return match.group(1) == "true"


def jsonish_number(block: str, key: str):
    match = re.search(rf'"{re.escape(key)}"\s*:\s*(-?\d+|null)', block)
    if not match or match.group(1) == "null":
        return None
    return int(match.group(1))


def extract_small_models_lenient(path: Path):
    text = decode_text(path).lstrip("\ufeff")
    positions = [match.start() for match in re.finditer(r'"model_id"\s*:', text)]
    items = []
    for index, pos in enumerate(positions):
        start = text.rfind("{", 0, pos)
        end = positions[index + 1] if index + 1 < len(positions) else len(text)
        block = text[start:end]
        item = {
            "model_id": jsonish_string(block, "model_id"),
            "model_name": jsonish_string(block, "model_name"),
            "model_type": jsonish_string(block, "model_type"),
            "adapter": jsonish_bool(block, "adapter"),
            "batch_size": jsonish_number(block, "batch_size"),
            "max_tokens": jsonish_number(block, "max_tokens"),
            "embedding_dim": jsonish_number(block, "embedding_dim"),
            "model_config": {
                "api_model": jsonish_string(block, "api_model"),
                "api_url": jsonish_string(block, "api_url"),
                "api_key": jsonish_string(block, "api_key"),
            },
        }
        if item["model_id"] and item["model_name"]:
            items.append(item)
    return items


admin = ["kweaver-admin", "--json", "--base-url", base_url]
if insecure:
    admin.append("--insecure")

admin_plain = ["kweaver-admin", "--base-url", base_url]
if insecure:
    admin_plain.append("--insecure")


def run_json(args, *, check=True):
    proc = subprocess.run(args, text=True, capture_output=True, check=False)
    if check and proc.returncode != 0:
        stderr = proc.stderr.strip()
        raise RuntimeError(f"Command failed ({proc.returncode}): {' '.join(args[:5])} ... {stderr}")
    if proc.stdout.strip():
        return parse_json_text(proc.stdout)
    return None


def admin_token():
    for key in ("KWEAVER_ADMIN_TOKEN", "KWEAVER_TOKEN"):
        token = os.environ.get(key, "").strip()
        if token:
            return token
    proc = subprocess.run(admin_plain + ["auth", "token"], text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"Unable to read kweaver-admin token: {proc.stderr.strip()}")
    token = proc.stdout.strip().splitlines()[-1].strip()
    if not token:
        raise RuntimeError("kweaver-admin returned an empty token")
    return token


def post_json(path: str, body: dict):
    token = admin_token()
    url = base_url.rstrip("/") + path
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "x-business-domain": biz_domain,
        },
        method="POST",
    )
    context = ssl._create_unverified_context() if insecure else None
    try:
        with urllib.request.urlopen(request, context=context, timeout=60) as response:
            text = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        text = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} from {path}: {text}") from exc
    return parse_json_text(text) if text.strip() else None


def unquote_yaml_scalar(value: str):
    value = value.strip()
    if not value:
        return ""
    if "#" in value and not value.startswith(("'", '"')):
        value = value.split("#", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def read_yaml_block_values(path: Path, block_name: str):
    if not path.exists():
        raise RuntimeError(f"KWeaver config file does not exist: {path}")
    values = {}
    active = False
    block_indent = 0
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        if not active:
            if stripped == f"{block_name}:":
                active = True
                block_indent = indent
            continue
        if indent <= block_indent and re.match(r"^[A-Za-z0-9_-]+:", stripped):
            break
        if indent > block_indent and ":" in stripped:
            key, value = stripped.split(":", 1)
            values[key.strip()] = unquote_yaml_scalar(value)
    return values


def sql_literal(value):
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    escaped = str(value).replace("\\", "\\\\").replace("'", "''")
    return f"'{escaped}'"


def kubectl_stdout(args, *, input_text=None, description="kubectl command"):
    proc = subprocess.run(args, text=True, input=input_text, capture_output=True, check=False)
    if proc.returncode != 0:
        stderr = proc.stderr.strip()
        raise RuntimeError(f"{description} failed: {stderr}")
    return proc.stdout


def discover_mariadb_pod(namespace: str):
    output = kubectl_stdout(
        ["kubectl", "get", "pods", "-n", namespace, "-o", "name"],
        description="discover MariaDB pod",
    )
    for line in output.splitlines():
        name = line.strip()
        if "mariadb" in name:
            return name.removeprefix("pod/")
    raise RuntimeError(f"Unable to discover MariaDB pod in namespace {namespace}")


def patch_adapter_small_model_in_database(model_id_value: str, body: dict):
    rds = read_yaml_block_values(kweaver_config_path, "rds")
    db_user = rds.get("user")
    db_pass = rds.get("password")
    db_name = rds.get("database") or "kweaver"
    if not (db_user and db_pass and db_name):
        raise RuntimeError("Unable to resolve KWeaver MariaDB credentials from config")

    pod = discover_mariadb_pod(kweaver_resource_namespace)
    max_tokens = body.get("max_tokens")
    embedding_dim = body.get("embedding_dim")
    sql = f"""
SET NAMES utf8mb4;
UPDATE t_small_model
   SET f_model_name = {sql_literal(body["model_name"])},
       f_model_type = {sql_literal(body["model_type"])},
       f_model_config = {sql_literal("{}")},
       f_adapter = 1,
       f_adapter_code = {sql_literal(body["adapter_code"])},
       f_update_time = NOW(),
       f_batch_size = {sql_literal(body["batch_size"])},
       f_max_tokens = {sql_literal(max_tokens)},
       f_embedding_dim = {sql_literal(embedding_dim)}
 WHERE f_model_id = {sql_literal(model_id_value)};
"""
    kubectl_stdout(
        [
            "kubectl",
            "exec",
            "-i",
            "-n",
            kweaver_resource_namespace,
            pod,
            "--",
            "env",
            f"MYSQL_PWD={db_pass}",
            "mariadb",
            "-u",
            db_user,
            "-D",
            db_name,
            "--binary-mode",
        ],
        input_text=sql,
        description="patch adapter small model in database",
    )


def list_llms_by_name(name):
    obj = run_json(admin + ["llm", "list", "--size", "100", "--name", name])
    return [item for item in extract_items(obj) if model_name(item) == name]


def list_small_models_by_name(name):
    obj = run_json(admin + ["small-model", "list", "--size", "100", "--name", name])
    return [item for item in extract_items(obj) if model_name(item) == name]


models_path = config_dir / "models.json"
models_config = read_json(models_path) if models_path.exists() else {}
if not isinstance(models_config, dict):
    models_config = {}

roles_path = config_dir / "model-roles.json"
if models_config:
    model_roles = {
        "llm": models_config.get("llm") or {},
        "small_models": models_config.get("small_models") or {},
    }
else:
    model_roles = read_json(roles_path) if roles_path.exists() else {}
if not isinstance(model_roles, dict):
    model_roles = {}


def full_model_id(item: dict, fallback: str = ""):
    return first_value(item, ("source_model_id", "source_id", "model_id", "id", "modelId")) or fallback


def full_llm_item(item: dict):
    cfg = item.get("model_config") or {}
    if not isinstance(cfg, dict):
        cfg = {}
    source_id = full_model_id(item, first_value(item, ("role",)) or "primary")
    name = first_value(item, ("model_name", "name"))
    api_url = first_value(item, ("api_url", "api_base", "base_url", "url")) or first_value(
        cfg, ("api_url", "api_base", "base_url", "url")
    )
    api_model = first_value(item, ("api_model", "model")) or first_value(
        cfg, ("api_model", "model", "model_name")
    )
    series = first_value(item, ("model_series", "series"))
    if not (name and series and api_url and api_model):
        raise RuntimeError(
            "models.json llm requires model_name, model_series, api_url, and api_model"
        )
    return {
        "model_id": source_id,
        "model_name": name,
        "model_series": series,
        "model_type": first_value(item, ("model_type", "type")) or "llm",
        "model_config": {
            "api_model": api_model,
            "api_url": api_url,
            "api_base": api_url,
            "api_key": first_value(item, ("api_key",)) or first_value(cfg, ("api_key", "key")),
        },
        "max_model_len": int_value(item.get("max_model_len"), default=4096),
        "model_parameters": item.get("model_parameters"),
    }


def full_small_item(role_name: str, item: dict):
    cfg = item.get("model_config") or {}
    if not isinstance(cfg, dict):
        cfg = {}
    source_id = full_model_id(item, role_name)
    name = first_value(item, ("model_name", "name"))
    model_type_value = first_value(item, ("model_type", "type")) or role_name
    if not (name and model_type_value):
        raise RuntimeError(
            f"models.json small_models.{role_name} requires model_name and model_type"
        )
    kind = first_value(item, ("kind", "mode")) or ("adapter" if item.get("adapter") else "api")
    adapter_enabled = kind == "adapter" or bool(item.get("adapter"))
    result = {
        "model_id": source_id,
        "model_name": name,
        "model_type": model_type_value,
        "kind": kind,
        "adapter": adapter_enabled,
        "adapter_code": item.get("adapter_code"),
        "adapter_code_file": item.get("adapter_code_file"),
        "model_config": {
            "api_model": first_value(item, ("api_model", "model")) or first_value(
                cfg, ("api_model", "model", "model_name")
            ),
            "api_url": first_value(item, ("api_url", "api_base", "base_url", "url")) or first_value(
                cfg, ("api_url", "api_base", "base_url", "url")
            ),
            "api_key": first_value(item, ("api_key",)) or first_value(cfg, ("api_key", "key")),
        },
        "batch_size": int_value(item.get("batch_size"), cfg.get("batch_size"), default=100),
        "max_tokens": int_value(item.get("max_tokens"), item.get("max_model_len"), cfg.get("max_tokens")),
        "embedding_dim": int_value(item.get("embedding_dim"), item.get("dimension"), cfg.get("embedding_dim")),
    }
    if not result["adapter"] and not (result["model_config"]["api_model"] and result["model_config"]["api_url"]):
        raise RuntimeError(
            f"models.json small_models.{role_name} requires api_url and api_model for non-adapter models"
        )
    return result


def full_small_items():
    small_models = models_config.get("small_models") or {}
    if isinstance(small_models, dict):
        missing = [name for name in ("embedding", "reranker") if not isinstance(small_models.get(name), dict)]
        if missing:
            raise RuntimeError("models.json small_models requires embedding and reranker entries")
        items = []
        for role_name in ("embedding", "reranker"):
            role_config = small_models.get(role_name)
            if isinstance(role_config, dict):
                items.append((models_path, full_small_item(role_name, role_config)))
        for role_name, role_config in small_models.items():
            if role_name in ("embedding", "reranker"):
                continue
            if isinstance(role_config, dict):
                items.append((models_path, full_small_item(str(role_name), role_config)))
        return items
    if isinstance(small_models, list):
        return [
            (models_path, full_small_item(str(index), item))
            for index, item in enumerate(small_models)
            if isinstance(item, dict)
        ]
    return []


def role_env(role: dict, fallback: str):
    if isinstance(role, dict):
        configured = str(role.get("api_key_env") or "").strip()
        if configured:
            return configured
    return fallback


def role_api_key(role: dict):
    if not isinstance(role, dict):
        return ""
    cfg = role.get("model_config") or {}
    if not isinstance(cfg, dict):
        cfg = {}
    value = first_value(role, ("api_key", "key")) or first_value(cfg, ("api_key", "key"))
    return "" if looks_masked(value) else value


def env_secret(*names):
    for name in names:
        if not name:
            continue
        value = os.environ.get(name, "").strip()
        if value:
            return value
    return ""


def llm_role():
    role = model_roles.get("llm") or {}
    return role if isinstance(role, dict) else {}


def selected_llm_name():
    role = llm_role()
    return (
        os.environ.get("ANYBACKUP_LLM_NAME", "").strip()
        or str(role.get("model_name") or role.get("name") or "").strip()
    )


def llm_api_key_override():
    return env_secret("ANYBACKUP_LLM_API_KEY", role_env(llm_role(), ""))


def small_model_roles():
    roles = model_roles.get("small_models") or {}
    return roles if isinstance(roles, dict) else {}


def small_model_role_for(name: str, model_type_value: str):
    roles = small_model_roles()
    typed = roles.get(model_type_value)
    if isinstance(typed, dict):
        return typed
    for role in roles.values():
        if isinstance(role, dict) and str(role.get("model_name") or role.get("name") or "") == name:
            return role
    return {}


def selected_small_model_names():
    roles = small_model_roles()
    selected = {}
    defaults = {
        "embedding": os.environ.get("ANYBACKUP_EMBEDDING_MODEL_NAME", "").strip(),
        "reranker": os.environ.get("ANYBACKUP_RERANKER_MODEL_NAME", "").strip(),
    }
    for role_name in ("embedding", "reranker"):
        role = roles.get(role_name) or {}
        if not isinstance(role, dict):
            role = {}
        selected[role_name] = (
            defaults[role_name]
            or str(role.get("model_name") or role.get("name") or "").strip()
        )
    return {key: value for key, value in selected.items() if value}


def small_model_api_key_override(name: str, model_type_value: str):
    role = small_model_role_for(name, model_type_value)
    if model_type_value == "embedding":
        return env_secret("ANYBACKUP_EMBEDDING_API_KEY", role_env(role, "")) or role_api_key(role)
    if model_type_value == "reranker":
        return env_secret("ANYBACKUP_RERANKER_API_KEY", role_env(role, "")) or role_api_key(role)
    return env_secret(role_env(role, "")) or role_api_key(role)


def adapter_code_for(item, small_dir: Path, name: str, model_type_value: str):
    configured = first_value(item, ("adapter_code_file", "adapter_file"))
    candidates = []
    if configured:
        configured_path = Path(configured)
        if configured_path.is_absolute():
            candidates.append(configured_path)
        else:
            candidates.append(config_dir / configured_path)
            candidates.append(small_dir / configured_path)
    candidates.append(small_dir / "small-model-adapter.txt")
    for candidate in candidates:
        if candidate.exists():
            code = decode_text(candidate)
            if code.strip():
                return adapter_code_with_secret(code, name, model_type_value)
    code = item.get("adapter_code")
    if isinstance(code, str) and code.strip():
        return adapter_code_with_secret(code, name, model_type_value)
    return ""


def adapter_code_with_secret(code: str, name: str, model_type_value: str):
    secret = small_model_api_key_override(name, model_type_value)
    if secret:
        literal = json.dumps(secret)
        code = code.replace("__ANYBACKUP_RERANKER_API_KEY__", secret)
        code = re.sub(
            r'(DASHSCOPE_API_KEY\s*=\s*)["\'][^"\']*["\']',
            lambda match: match.group(1) + literal,
            code,
        )
        return code
    if "__ANYBACKUP_RERANKER_API_KEY__" in code:
        role = small_model_role_for(name, model_type_value)
        env_name = role_env(role, "ANYBACKUP_RERANKER_API_KEY")
        raise RuntimeError(f"Adapter small model {name} requires environment variable {env_name}")
    return code


def adapter_small_model_body(item, small_dir: Path, name: str, model_type_value: str):
    cfg = item.get("model_config") or item.get("config") or {}
    if not isinstance(cfg, dict):
        cfg = {}
    adapter_code = adapter_code_for(item, small_dir, name, model_type_value)
    if not (name and model_type_value and adapter_code):
        raise RuntimeError(f"Adapter small model {name or 'unknown'} has incomplete config")

    body = {
        "model_name": name,
        "model_type": model_type_value,
        "model_config": {},
        "adapter": True,
        "adapter_code": adapter_code,
        "batch_size": int_value(
            first_value(cfg, ("batch_size",)),
            first_value(item, ("batch_size",)),
            default=100,
        ),
    }
    max_tokens = int_value(
        first_value(cfg, ("max_tokens", "max_model_len")),
        first_value(item, ("max_tokens",)),
        default=None,
    )
    embedding_dim = int_value(
        first_value(cfg, ("embedding_dim", "dimension", "dim")),
        first_value(item, ("embedding_dim",)),
        default=None,
    )
    if max_tokens is not None:
        body["max_tokens"] = max_tokens
    if embedding_dim is not None:
        body["embedding_dim"] = embedding_dim
    return body


state = {
    "base_url": base_url,
    "business_domain": biz_domain,
    "models_config_file": str(models_path) if models_config else "",
    "model_roles": redact_secrets(model_roles),
    "llm": {},
    "small_model": {},
    "warnings": [],
}

llm_dir = config_dir / "llm"
llm_configs = []
api_key_by_host = {}
if isinstance(models_config.get("llm"), dict):
    llm_configs.append((models_path, full_llm_item(models_config["llm"])))
elif llm_dir.is_dir():
    for path in sorted(llm_dir.glob("*.json")):
        try:
            obj = read_json(path)
        except ValueError as exc:
            state["warnings"].append(str(exc))
            continue
        if isinstance(obj, dict) and obj.get("model_config") and model_id(obj) and model_name(obj):
            llm_configs.append((path, obj))

selected_llm = selected_llm_name()
if selected_llm:
    filtered_llm_configs = [(path, item) for path, item in llm_configs if model_name(item) == selected_llm]
    if not filtered_llm_configs:
        available = ", ".join(model_name(item) for _, item in llm_configs if model_name(item)) or "none"
        raise RuntimeError(f"Selected LLM {selected_llm} was not found in config. Available: {available}")
    llm_configs = filtered_llm_configs
elif len(llm_configs) > 1:
    available = ", ".join(model_name(item) for _, item in llm_configs if model_name(item))
    raise RuntimeError(
        "Multiple LLM configs are packaged. Set models.json llm.model_name, model-roles.json llm.model_name, "
        f"or ANYBACKUP_LLM_NAME to select exactly one. Available: {available}"
    )
if not llm_configs:
    raise RuntimeError("No LLM config found. Provide models.json llm or a selected llm/*.json config.")

for path, item in llm_configs:
    source_id = model_id(item)
    name = model_name(item)
    series = first_value(item, ("model_series", "series")) or "custom"
    cfg = item.get("model_config") or {}
    api_model = first_value(cfg, ("api_model", "model", "model_name"))
    api_base = first_value(cfg, ("api_url", "api_base", "base_url", "url"))
    api_key = first_value(cfg, ("api_key", "key"))
    override_key = llm_api_key_override()
    if override_key:
        api_key = override_key
    api_host = urlparse(api_base).netloc if api_base else ""
    if api_host and api_key and not looks_masked(api_key):
        api_key_by_host.setdefault(api_host, api_key)

    existing = list_llms_by_name(name)
    if existing:
        target = existing[0]
        print(f"Reuse existing LLM: {name}")
        if override_key:
            state["warnings"].append(
                f"LLM {name} already exists; KWeaver admin API does not support secret update in this installer path"
            )
    else:
        if not (name and api_model and api_base and api_key) or looks_masked(api_key):
            env_name = role_env(llm_role(), "ANYBACKUP_LLM_API_KEY")
            raise RuntimeError(
                f"LLM {name or path.name} cannot be created with incomplete or masked config. "
                f"Set {env_name} or pre-create a same-name LLM in KWeaver."
            )
        print(f"Create LLM: {name}")
        body = {
            "model_name": name,
            "model_series": series,
            "model_type": item.get("model_type") or "llm",
            "model_config": {
                "api_model": api_model,
                "api_url": api_base,
                "api_base": api_base,
                "api_key": api_key,
            },
            "max_model_len": int(item.get("max_model_len") or 4096),
        }
        if item.get("model_parameters") is not None:
            body["model_parameters"] = item.get("model_parameters")
        post_json("/api/mf-model-manager/v1/llm/add", body)
        matches = list_llms_by_name(name)
        if not matches:
            raise RuntimeError(f"Unable to resolve created LLM model id for {name}")
        target = matches[0]

    target_id = model_id(target)
    state["llm"][source_id] = {
        "source_id": source_id,
        "source_name": name,
        "target_id": target_id,
        "target_name": model_name(target) or name,
    }

if not skip_small_models:
    small_dir = config_dir / "small-model"
    small_configs = []
    if models_config.get("small_models"):
        small_configs = full_small_items()
    elif small_dir.is_dir():
        for path in sorted(small_dir.glob("*.json")):
            try:
                obj = read_json(path)
            except ValueError as exc:
                state["warnings"].append(f"Use lenient small-model parser for {path.name}: {exc}")
                small_configs.extend((path, item) for item in extract_small_models_lenient(path))
                continue
            if isinstance(obj, dict) and model_id(obj) and model_name(obj) and obj.get("model_type"):
                small_configs.append((path, obj))
            else:
                for item in extract_items(obj):
                    if isinstance(item, dict) and model_id(item) and model_name(item):
                        small_configs.append((path, item))

    selected_small = selected_small_model_names()
    if selected_small:
        selected_names = set(selected_small.values())
        filtered_small_configs = [
            (path, item) for path, item in small_configs if model_name(item) in selected_names
        ]
        found_names = {model_name(item) for _, item in filtered_small_configs}
        missing_roles = [
            f"{role}={name}" for role, name in selected_small.items() if name not in found_names
        ]
        if missing_roles:
            available = ", ".join(model_name(item) for _, item in small_configs if model_name(item)) or "none"
            raise RuntimeError(
                "Selected small-model config was not found: "
                + ", ".join(missing_roles)
                + f". Available: {available}"
            )
        small_configs = filtered_small_configs

    seen_small = set()
    for path, item in small_configs:
        source_id = model_id(item)
        if source_id in seen_small:
            continue
        seen_small.add(source_id)
        name = model_name(item)
        model_type_value = first_value(item, ("model_type", "type"))
        if item.get("adapter"):
            body = adapter_small_model_body(item, small_dir, name, model_type_value)
            existing = list_small_models_by_name(name)
            if existing:
                target = existing[0]
                target_id = model_id(target)
                print(f"Patch adapter small model: {name}")
            else:
                print(f"Create adapter small model placeholder: {name}")
                placeholder_body = {
                    "model_name": name,
                    "model_type": model_type_value,
                    "model_config": {
                        "api_url": "http://adapter-placeholder.local",
                        "api_model": name,
                        "api_key": "adapter-placeholder",
                    },
                    "adapter": False,
                    "batch_size": body["batch_size"],
                }
                if "max_tokens" in body:
                    placeholder_body["max_tokens"] = body["max_tokens"]
                if "embedding_dim" in body:
                    placeholder_body["embedding_dim"] = body["embedding_dim"]
                post_json("/api/mf-model-manager/v1/small-model/add", placeholder_body)

            matches = list_small_models_by_name(name)
            if not matches:
                raise RuntimeError(f"Unable to resolve adapter small model id for {name}")
            target = matches[0]
            patch_adapter_small_model_in_database(model_id(target), body)
            matches = list_small_models_by_name(name)
            if not matches:
                raise RuntimeError(f"Unable to resolve patched adapter small model id for {name}")
            target = matches[0]
            state["small_model"][source_id] = {
                "source_id": source_id,
                "source_name": name,
                "target_id": model_id(target),
                "target_name": model_name(target) or name,
            }
            continue
        cfg = item.get("model_config") or item.get("config") or {}
        if not isinstance(cfg, dict):
            cfg = {}
        api_model = first_value(cfg, ("api_model", "model", "model_name"))
        api_url = first_value(cfg, ("api_url", "api_base", "base_url", "url"))
        api_key = first_value(cfg, ("api_key", "key"))
        override_key = small_model_api_key_override(name, model_type_value)
        if override_key:
            api_key = override_key
        batch_size = first_value(cfg, ("batch_size",)) or first_value(item, ("batch_size",)) or "2048"
        max_tokens = first_value(cfg, ("max_tokens", "max_model_len")) or first_value(item, ("max_tokens",)) or "512"
        embedding_dim = first_value(cfg, ("embedding_dim", "dimension", "dim")) or first_value(item, ("embedding_dim",)) or "768"

        if not (name and model_type_value and api_model and api_url):
            raise RuntimeError(f"Small model {name or path.name} has incomplete config")
        if looks_masked(api_key):
            api_host = urlparse(api_url).netloc if api_url else ""
            fallback_key = api_key_by_host.get(api_host)
            if not fallback_key:
                raise RuntimeError(
                    f"Small model {name} has a masked api_key and no same-host LLM key fallback for {api_host}"
                )
            api_key = fallback_key
            state["warnings"].append(
                f"Small model {name} uses same-host LLM API key fallback for {api_host}"
            )

        existing = list_small_models_by_name(name)
        if existing:
            target = existing[0]
            if override_key:
                print(f"Update existing small model config: {name}")
                update_body = {
                    "model_id": model_id(target),
                    "model_name": name,
                    "model_type": model_type_value,
                    "change": True,
                    "model_config": {
                        "api_url": api_url,
                        "api_model": api_model,
                        "api_key": api_key,
                    },
                    "batch_size": int(batch_size),
                    "max_tokens": int(max_tokens),
                    "embedding_dim": int(embedding_dim),
                }
                post_json("/api/mf-model-manager/v1/small-model/edit", update_body)
                matches = list_small_models_by_name(name)
                if not matches:
                    raise RuntimeError(f"Unable to resolve updated small model id for {name}")
                target = matches[0]
            else:
                print(f"Reuse existing small model: {name}")
        else:
            print(f"Create small model: {name}")
            run_json(
                admin + [
                    "small-model",
                    "add",
                    "--name",
                    name,
                    "--type",
                    model_type_value,
                    "--api-url",
                    api_url,
                    "--api-model",
                    api_model,
                    "--api-key",
                    api_key,
                    "--batch-size",
                    str(batch_size),
                    "--max-tokens",
                    str(max_tokens),
                    "--embedding-dim",
                    str(embedding_dim),
                ]
            )
            matches = list_small_models_by_name(name)
            if not matches:
                raise RuntimeError(f"Unable to resolve created small model id for {name}")
            target = matches[0]

        state["small_model"][source_id] = {
            "source_id": source_id,
            "source_name": name,
            "target_id": model_id(target),
            "target_name": model_name(target) or name,
        }

state_file.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Model import state written: {state_file}")
PY
