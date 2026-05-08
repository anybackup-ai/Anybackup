#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SKILLS_ROOT="$SCRIPT_DIR/skills"

usage() {
  cat <<'EOF'
Usage:
  ./install.sh --base-url <url> [options]

Options:
  --base-url <url>      KWeaver service base URL.
  --biz-domain <value>  Business domain ID (default: bd_public).
  --skills-root <dir>   Directory containing skill directories.
  --skill-dir <dir>     Skill directory to import. Can be repeated.
  --state-file <path>   Write imported skill id mapping to this JSON file.
  --source <value>      KWeaver skill source value (default: custom).
  --publish             Set imported/reused skills to published.
  --no-publish          Do not change skill publish status.
  --kweaver-config <p>  KWeaver deploy config used for publish schema checks.
  --resource-namespace <ns>
                        KWeaver resource namespace (default: resource).
  --kweaver-namespace <ns>
                        KWeaver application namespace (default: kweaver).
  --skip-publish-schema-check
                        Do not create missing KWeaver skill publish tables.
  --skip-auth-policy-check
                        Do not create missing KWeaver skill authorization policy.
  --skip-oss-storage-check
                        Do not create missing KWeaver OSS Gateway default storage.
  --insecure            Tell KWeaver CLI to skip TLS verification where supported.
  -h, --help            Show this help.

Environment variables:
  KWEAVER_BASE_URL
  KWEAVER_BUSINESS_DOMAIN
  ANYBACKUP_SKILLS_ROOT
  ANYBACKUP_SKILL_DIRS       Comma-separated skill directories.
  ANYBACKUP_SKILLS_STATE_FILE
  ANYBACKUP_SKILLS_SOURCE    Default: custom.
  ANYBACKUP_SKILLS_PUBLISH   1 or 0. Default: 1.
  ANYBACKUP_SKILLS_ENSURE_PUBLISH_SCHEMA
                             1 or 0. Default: 1.
  ANYBACKUP_SKILLS_ENSURE_AUTH_POLICY
                             1 or 0. Default: 1.
  ANYBACKUP_SKILLS_ENSURE_OSS_STORAGE
                             1 or 0. Default: 1.
  KWEAVER_CONFIG_PATH        Default: /opt/v9-alpha-deploy/kweaver-config/config.yaml.
  KWEAVER_RESOURCE_NAMESPACE Default: resource.
  KWEAVER_NAMESPACE          Default: kweaver.
  KWEAVER_INSECURE           1 or 0.
EOF
}

error() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || error "Required command not found: $1"
}

KWEAVER_BASE_URL="${KWEAVER_BASE_URL:-}"
KWEAVER_BUSINESS_DOMAIN="${KWEAVER_BUSINESS_DOMAIN:-bd_public}"
SKILLS_ROOT="${ANYBACKUP_SKILLS_ROOT:-$DEFAULT_SKILLS_ROOT}"
SKILL_DIRS=()
if [[ -n "${ANYBACKUP_SKILL_DIRS:-}" ]]; then
  IFS=',' read -r -a SKILL_DIRS <<< "$ANYBACKUP_SKILL_DIRS"
fi
STATE_FILE="${ANYBACKUP_SKILLS_STATE_FILE:-}"
SKILL_SOURCE="${ANYBACKUP_SKILLS_SOURCE:-custom}"
PUBLISH="${ANYBACKUP_SKILLS_PUBLISH:-1}"
ENSURE_PUBLISH_SCHEMA="${ANYBACKUP_SKILLS_ENSURE_PUBLISH_SCHEMA:-1}"
ENSURE_AUTH_POLICY="${ANYBACKUP_SKILLS_ENSURE_AUTH_POLICY:-1}"
ENSURE_OSS_STORAGE="${ANYBACKUP_SKILLS_ENSURE_OSS_STORAGE:-1}"
KWEAVER_CONFIG_PATH="${KWEAVER_CONFIG_PATH:-/opt/v9-alpha-deploy/kweaver-config/config.yaml}"
KWEAVER_RESOURCE_NAMESPACE="${KWEAVER_RESOURCE_NAMESPACE:-resource}"
KWEAVER_NAMESPACE="${KWEAVER_NAMESPACE:-kweaver}"
KWEAVER_INSECURE="${KWEAVER_INSECURE:-0}"

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
    --skills-root)
      SKILLS_ROOT="${2:-}"
      shift 2
      ;;
    --skill-dir)
      SKILL_DIRS+=("${2:-}")
      shift 2
      ;;
    --state-file)
      STATE_FILE="${2:-}"
      shift 2
      ;;
    --source)
      SKILL_SOURCE="${2:-}"
      shift 2
      ;;
    --publish)
      PUBLISH="1"
      shift
      ;;
    --no-publish)
      PUBLISH="0"
      shift
      ;;
    --kweaver-config)
      KWEAVER_CONFIG_PATH="${2:-}"
      shift 2
      ;;
    --resource-namespace)
      KWEAVER_RESOURCE_NAMESPACE="${2:-}"
      shift 2
      ;;
    --kweaver-namespace)
      KWEAVER_NAMESPACE="${2:-}"
      shift 2
      ;;
    --skip-publish-schema-check)
      ENSURE_PUBLISH_SCHEMA="0"
      shift
      ;;
    --skip-auth-policy-check)
      ENSURE_AUTH_POLICY="0"
      shift
      ;;
    --skip-oss-storage-check)
      ENSURE_OSS_STORAGE="0"
      shift
      ;;
    --insecure)
      KWEAVER_INSECURE="1"
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

require_command python3
require_command kweaver

[[ -n "$KWEAVER_BASE_URL" ]] || error "--base-url or KWEAVER_BASE_URL is required."
[[ -n "$KWEAVER_BUSINESS_DOMAIN" ]] || error "--biz-domain or KWEAVER_BUSINESS_DOMAIN is required."

if [[ ${#SKILL_DIRS[@]} -eq 0 ]]; then
  [[ -d "$SKILLS_ROOT" ]] || error "Skills root not found: $SKILLS_ROOT"
  while IFS= read -r dir; do
    SKILL_DIRS+=("$dir")
  done < <(find "$SKILLS_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
fi

[[ ${#SKILL_DIRS[@]} -gt 0 ]] || error "No skill directories found."
for dir in "${SKILL_DIRS[@]}"; do
  [[ -d "$dir" ]] || error "Skill directory not found: $dir"
  [[ -f "$dir/SKILL.md" ]] || error "Missing SKILL.md in skill directory: $dir"
done

python3 - "$KWEAVER_BASE_URL" "$KWEAVER_BUSINESS_DOMAIN" "$STATE_FILE" "$SKILL_SOURCE" "$PUBLISH" "$KWEAVER_INSECURE" "$ENSURE_PUBLISH_SCHEMA" "$ENSURE_AUTH_POLICY" "$ENSURE_OSS_STORAGE" "$KWEAVER_CONFIG_PATH" "$KWEAVER_RESOURCE_NAMESPACE" "$KWEAVER_NAMESPACE" "${SKILL_DIRS[@]}" <<'PY'
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

(
    base_url,
    biz_domain,
    state_file,
    source,
    publish_flag,
    insecure_flag,
    ensure_publish_schema_flag,
    ensure_auth_policy_flag,
    ensure_oss_storage_flag,
    kweaver_config_path,
    resource_namespace,
    kweaver_namespace,
    *skill_dirs,
) = sys.argv[1:]
publish = publish_flag == "1"
insecure = insecure_flag == "1"
ensure_publish_schema = ensure_publish_schema_flag == "1"
ensure_auth_policy = ensure_auth_policy_flag == "1"
ensure_oss_storage = ensure_oss_storage_flag == "1"

env = os.environ.copy()
env["KWEAVER_BASE_URL"] = base_url
env["KWEAVER_BUSINESS_DOMAIN"] = biz_domain
if insecure:
    env["KWEAVER_TLS_INSECURE"] = "1"
    env["NODE_TLS_REJECT_UNAUTHORIZED"] = "0"

help_proc = subprocess.run(
    ["kweaver", "--help"],
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    env=env,
)
supports_base_url = "--base-url" in (help_proc.stdout + help_proc.stderr)

AUTH_OPERATION_CHECK_PATH = "/api/authorization/v1/operation-check"
AUTH_POLICY_PATH = "/api/authorization/v1/policy"
AUTH_RESOURCE_TYPE_PATH_PREFIX = "/api/authorization/v1/resource_type"
AUTH_SKILL_OPERATIONS = (
    "create",
    "modify",
    "delete",
    "view",
    "publish",
    "unpublish",
    "authorize",
    "public_access",
    "execute",
)


def log(message: str) -> None:
    print(f"[INFO] {message}", flush=True)


def run_kweaver(args, check=True):
    cmd = ["kweaver"]
    if supports_base_url:
        cmd.extend(["--base-url", base_url])
    cmd.extend(args)
    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    if check and proc.returncode != 0:
        raise RuntimeError(
            "KWeaver CLI failed: "
            + " ".join(cmd)
            + f"\nrc={proc.returncode}\nstdout={proc.stdout}\nstderr={proc.stderr}"
        )
    return proc


def run_kweaver_auth(args, check=True):
    # Auth subcommands in the 0.6.x CLI use saved sessions only when no
    # transient base-url override is present. Keep this path separate from
    # API calls, which still use --base-url.
    cmd = ["kweaver"]
    cmd.extend(args)
    auth_env = env.copy()
    auth_env.pop("KWEAVER_BASE_URL", None)
    auth_env.pop("KWEAVER_BUSINESS_DOMAIN", None)
    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=auth_env)
    if check and proc.returncode != 0:
        raise RuntimeError(
            "KWeaver auth CLI failed: "
            + " ".join(cmd)
            + f"\nrc={proc.returncode}\nstdout={proc.stdout}\nstderr={proc.stderr}"
        )
    return proc


def run_cmd(args, *, check=True, input_text=None, safe_name="command"):
    proc = subprocess.run(
        args,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    if check and proc.returncode != 0:
        raise RuntimeError(
            f"{safe_name} failed"
            + f"\nrc={proc.returncode}\nstdout={proc.stdout}\nstderr={proc.stderr}"
        )
    return proc


def first_value(item: dict, keys) -> str:
    for key in keys:
        value = item.get(key)
        if value:
            return str(value)
    return ""


def parse_accessor_from_text(text: str) -> dict:
    payload = parse_json_payload(text)
    candidates = []
    if isinstance(payload, dict):
        candidates.append(payload)
        for key in ("data", "user", "account", "profile"):
            value = payload.get(key)
            if isinstance(value, dict):
                candidates.append(value)
    for item in candidates:
        user_id = first_value(item, ("id", "user_id", "userId", "account_id", "accountId", "sub"))
        user_name = first_value(item, ("name", "username", "user_name", "account", "account_name", "preferred_username"))
        if user_id:
            return {"id": str(user_id), "type": "user", "name": str(user_name or user_id)}

    patterns = (
        r"User:\s*(?P<name>.*?)\s*\((?P<id>[0-9A-Za-z_-]{8,})\)",
        r"User ID:\s*(?P<id>[0-9A-Za-z_-]{8,})",
        r"User:\s*(?P<id>[0-9A-Za-z_-]{8,})",
        r"sub:\s*(?P<id>[0-9A-Za-z_-]{8,})",
    )
    user_id = None
    user_name = None
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match and match.groupdict().get("id"):
            user_id = match.group("id").strip()
            if match.groupdict().get("name"):
                user_name = match.group("name").strip()
            break
    if not user_name:
        match = re.search(r"(?:Username|Name|User name):\s*(?P<name>[^\r\n]+)", text, re.IGNORECASE)
        if match:
            user_name = match.group("name").strip()
    if user_id:
        return {"id": user_id, "type": "user", "name": user_name or user_id}
    return {}


def current_kweaver_accessor() -> dict:
    for args in (["auth", "whoami"], ["auth", "status"]):
        proc = run_kweaver_auth(args, check=False)
        if proc.returncode != 0:
            continue
        accessor = parse_accessor_from_text(proc.stdout + "\n" + proc.stderr)
        if accessor.get("id"):
            return accessor
    raise RuntimeError(
        "Unable to resolve current KWeaver user id. "
        "Run `kweaver auth status` on the target host and confirm the login is usable."
    )


def kubectl_json(args, *, safe_name: str):
    proc = run_cmd(["kubectl", *args], safe_name=safe_name)
    return json.loads(proc.stdout)


def get_service(namespace: str, service_names, *, name_contains=(), safe_name: str):
    for name in service_names:
        proc = run_cmd(
            ["kubectl", "get", "svc", "-n", namespace, name, "-o", "json"],
            check=False,
            safe_name=f"kubectl get svc/{name}",
        )
        if proc.returncode == 0:
            return json.loads(proc.stdout)

    payload = kubectl_json(["get", "svc", "-n", namespace, "-o", "json"], safe_name=safe_name)
    candidates = []
    for item in payload.get("items", []):
        name = item.get("metadata", {}).get("name", "")
        if any(token in name for token in name_contains):
            candidates.append(item)
    candidates.sort(key=lambda item: item.get("metadata", {}).get("name", ""))
    if candidates:
        return candidates[0]
    return None


def service_port(service: dict, *, preferred_names=(), preferred_ports=()) -> int:
    ports = service.get("spec", {}).get("ports") or []
    if not ports:
        name = service.get("metadata", {}).get("name", "")
        raise RuntimeError(f"Service {name} has no ports")
    for candidate in ports:
        if str(candidate.get("name", "")).lower() in preferred_names:
            port = candidate.get("port")
            if port:
                return int(port)
    for candidate in ports:
        port = candidate.get("port")
        if port in preferred_ports:
            return int(port)
    port = ports[0].get("port")
    if not port:
        name = service.get("metadata", {}).get("name", "")
        raise RuntimeError(f"Service {name} has no usable port")
    return int(port)


def discover_authorization_base_url(namespace: str) -> str:
    service_names = ("authorization-private", "authorization", "authorization-public")
    services = []
    for name in service_names:
        proc = run_cmd(
            ["kubectl", "get", "svc", "-n", namespace, name, "-o", "json"],
            check=False,
            safe_name=f"kubectl get svc/{name}",
        )
        if proc.returncode == 0:
            services.append(json.loads(proc.stdout))
            break
    if not services:
        payload = kubectl_json(["get", "svc", "-n", namespace, "-o", "json"], safe_name="kubectl get authorization services")
        for item in payload.get("items", []):
            name = item.get("metadata", {}).get("name", "")
            if "authorization" in name:
                services.append(item)
        services.sort(key=lambda item: item.get("metadata", {}).get("name", ""))
    if not services:
        raise RuntimeError(f"Unable to find authorization service in namespace {namespace}")

    service = services[0]
    name = service.get("metadata", {}).get("name", "")
    spec = service.get("spec", {})
    cluster_ip = spec.get("clusterIP")
    if not cluster_ip or cluster_ip == "None":
        raise RuntimeError(f"Authorization service {namespace}/{name} has no usable ClusterIP")
    ports = spec.get("ports") or []
    if not ports:
        raise RuntimeError(f"Authorization service {namespace}/{name} has no ports")
    port = None
    for candidate in ports:
        if str(candidate.get("name", "")).lower() in ("http", "private", "tcp"):
            port = candidate.get("port")
            break
    if port is None:
        port = ports[0].get("port")
    if not port:
        raise RuntimeError(f"Authorization service {namespace}/{name} has no usable port")
    return f"http://{cluster_ip}:{port}"


def post_json(url: str, payload, *, expected_statuses=(200,)):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            if resp.status not in expected_statuses:
                raise RuntimeError(f"HTTP {resp.status} from {url}: {body}")
            return resp.status, body
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} from {url}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Unable to call {url}: {exc}") from exc


def get_json(url: str, *, expected_statuses=(200,)):
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            if resp.status not in expected_statuses:
                raise RuntimeError(f"HTTP {resp.status} from {url}: {body}")
            return resp.status, body
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} from {url}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Unable to call {url}: {exc}") from exc


def put_json(url: str, payload, *, expected_statuses=(200, 201, 204)):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="PUT",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            if resp.status not in expected_statuses:
                raise RuntimeError(f"HTTP {resp.status} from {url}: {body}")
            return resp.status, body
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} from {url}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Unable to call {url}: {exc}") from exc


def ensure_authorization_resource_type(auth_base_url: str, resource_type: str) -> None:
    def operation_name(op: str) -> str:
        return {
            "create": "Create",
            "modify": "Modify",
            "delete": "Delete",
            "view": "View",
            "publish": "Publish",
            "unpublish": "Unpublish",
            "authorize": "Authorize",
            "public_access": "Public Access",
            "execute": "Execute",
        }.get(op, op)

    payload = {
        "name": "Skill",
        "description": "Execution Factory Skill",
        "instance_url": "",
        "data_struct": "string",
        "operation": [
            {
                "id": op,
                "name": [
                    {"language": "zh-cn", "value": operation_name(op)},
                    {"language": "en-us", "value": operation_name(op)},
                    {"language": "zh-tw", "value": operation_name(op)},
                ],
                "description": "",
                "scope": ["type", "instance"],
            }
            for op in AUTH_SKILL_OPERATIONS
        ],
        "hidden": False,
    }
    put_json(f"{auth_base_url}{AUTH_RESOURCE_TYPE_PATH_PREFIX}/{resource_type}", payload)


def authorization_operation_check(auth_base_url: str, accessor: dict, resource_type: str, operation: str) -> bool:
    payload = {
        "accessor": accessor,
        "resource": {"id": "*", "type": resource_type, "name": "*"},
        "operation": [operation],
        "method": "GET",
    }
    _, body = post_json(f"{auth_base_url}{AUTH_OPERATION_CHECK_PATH}", payload, expected_statuses=(200,))
    result = json.loads(body or "{}")
    return bool(result.get("result"))


def create_authorization_policy(auth_base_url: str, accessor: dict, resource_type: str) -> None:
    payload = [
        {
            "accessor": accessor,
            "resource": {"id": "*", "type": resource_type, "name": "*"},
            "operation": {
                "allow": [{"id": op, "name": op} for op in AUTH_SKILL_OPERATIONS],
                "deny": [],
            },
        }
    ]
    post_json(f"{auth_base_url}{AUTH_POLICY_PATH}", payload, expected_statuses=(204,))


def ensure_execution_factory_auth_policy() -> bool:
    if not ensure_auth_policy:
        return False

    accessor = current_kweaver_accessor()
    auth_base_url = discover_authorization_base_url(kweaver_namespace)
    ensure_authorization_resource_type(auth_base_url, "skill")
    required_ops = ("create", "publish")
    missing_before = [
        op
        for op in required_ops
        if not authorization_operation_check(auth_base_url, accessor, "skill", op)
    ]
    if not missing_before:
        log(f"KWeaver skill authorization policy already usable for {accessor['name']} ({accessor['id']})")
        return False

    create_authorization_policy(auth_base_url, accessor, "skill")
    missing_after = [
        op
        for op in required_ops
        if not authorization_operation_check(auth_base_url, accessor, "skill", op)
    ]
    if missing_after:
        raise RuntimeError(
            "KWeaver skill authorization policy bootstrap did not take effect. "
            f"Missing operations for {accessor['id']}: {', '.join(missing_after)}"
        )
    log(f"Ensured KWeaver skill authorization policy for {accessor['name']} ({accessor['id']})")
    return True


def discover_oss_gateway_base_url(namespace: str) -> str:
    service = get_service(
        namespace,
        ("oss-gateway-backend",),
        name_contains=("oss-gateway",),
        safe_name="kubectl get oss-gateway-backend services",
    )
    if not service:
        raise RuntimeError(f"Unable to find oss-gateway-backend service in namespace {namespace}")
    name = service.get("metadata", {}).get("name", "")
    cluster_ip = service.get("spec", {}).get("clusterIP")
    if not cluster_ip or cluster_ip == "None":
        raise RuntimeError(f"oss-gateway-backend service {namespace}/{name} has no usable ClusterIP")
    port = service_port(service, preferred_names=("http", "tcp"), preferred_ports=(8080,))
    return f"http://{cluster_ip}:{port}"


def service_pods(namespace: str, service: dict) -> list:
    selector = service.get("spec", {}).get("selector") or {}
    if not selector:
        return []
    label_selector = ",".join(f"{key}={value}" for key, value in sorted(selector.items()))
    payload = kubectl_json(
        ["get", "pods", "-n", namespace, "-l", label_selector, "-o", "json"],
        safe_name=f"kubectl get pods for service {service.get('metadata', {}).get('name', '')}",
    )
    pods = []
    for item in payload.get("items", []):
        status = item.get("status", {})
        conditions = status.get("conditions", [])
        ready = any(
            condition.get("type") == "Ready" and condition.get("status") == "True"
            for condition in conditions
        )
        phase = status.get("phase") == "Running"
        name = item.get("metadata", {}).get("name", "")
        pods.append((phase and ready, name, item))
    pods.sort(reverse=True, key=lambda item: (item[0], item[1]))
    return [item for _, _, item in pods]


def secret_value(namespace: str, secret_name: str, secret_key: str) -> str:
    payload = kubectl_json(
        ["get", "secret", "-n", namespace, secret_name, "-o", "json"],
        safe_name=f"kubectl get secret/{secret_name}",
    )
    encoded = (payload.get("data") or {}).get(secret_key)
    if not encoded:
        raise RuntimeError(f"Secret {namespace}/{secret_name} does not contain key {secret_key}")
    return base64.b64decode(encoded).decode("utf-8")


def env_item_value(namespace: str, item: dict) -> str:
    if "value" in item:
        return str(item.get("value") or "")
    secret_ref = (
        item.get("valueFrom", {})
        .get("secretKeyRef", {})
    )
    if secret_ref.get("name") and secret_ref.get("key"):
        return secret_value(namespace, secret_ref["name"], secret_ref["key"])
    return ""


def pod_env_map(namespace: str, pod: dict) -> dict:
    values = {}
    for container in pod.get("spec", {}).get("containers", []):
        for item in container.get("env", []) or []:
            name = item.get("name")
            if name and name not in values:
                values[name] = env_item_value(namespace, item)
    return values


def discover_minio_config(namespace: str) -> dict:
    service = get_service(
        namespace,
        ("minio",),
        name_contains=("minio",),
        safe_name="kubectl get MinIO services",
    )
    if not service:
        raise RuntimeError(f"Unable to find MinIO service in namespace {namespace}")
    service_name = service.get("metadata", {}).get("name", "")
    port = service_port(service, preferred_names=("api", "minio", "http"), preferred_ports=(9000,))
    pods = service_pods(namespace, service)
    if not pods:
        raise RuntimeError(f"Unable to find a ready MinIO pod for service {namespace}/{service_name}")
    env_values = pod_env_map(namespace, pods[0])
    access_key = env_values.get("MINIO_ROOT_USER") or env_values.get("MINIO_ACCESS_KEY")
    secret_key = env_values.get("MINIO_ROOT_PASSWORD") or env_values.get("MINIO_SECRET_KEY")
    if not access_key or not secret_key:
        raise RuntimeError(f"Unable to resolve MinIO credentials from pod env for service {namespace}/{service_name}")
    buckets = env_values.get("MINIO_DEFAULT_BUCKETS") or "sandbox-workspace"
    bucket = next((part.strip() for part in buckets.split(",") if part.strip()), "sandbox-workspace")
    endpoint = f"http://{service_name}.{namespace}.svc.cluster.local:{port}"
    return {
        "endpoint": endpoint,
        "bucket": bucket,
        "access_key": access_key,
        "secret_key": secret_key,
        "pod": pods[0].get("metadata", {}).get("name", ""),
    }


def ensure_minio_bucket(namespace: str, minio: dict) -> None:
    pod = minio.get("pod")
    if not pod:
        raise RuntimeError("Unable to ensure MinIO bucket because no MinIO pod was resolved")
    script = f"""
set -eu
ACCESS_KEY=$(cat <<'ANYBACKUP_MINIO_ACCESS_KEY'
{minio["access_key"]}
ANYBACKUP_MINIO_ACCESS_KEY
)
SECRET_KEY=$(cat <<'ANYBACKUP_MINIO_SECRET_KEY'
{minio["secret_key"]}
ANYBACKUP_MINIO_SECRET_KEY
)
BUCKET=$(cat <<'ANYBACKUP_MINIO_BUCKET'
{minio["bucket"]}
ANYBACKUP_MINIO_BUCKET
)
ENDPOINT=$(cat <<'ANYBACKUP_MINIO_ENDPOINT'
{minio["endpoint"]}
ANYBACKUP_MINIO_ENDPOINT
)
export MC_CONFIG_DIR="/tmp/anybackup-mc-$$"
command -v mc >/dev/null 2>&1
mc alias set anybackup "$ENDPOINT" "$ACCESS_KEY" "$SECRET_KEY" >/dev/null
if mc ls "anybackup/$BUCKET" >/dev/null 2>&1; then
    exit 0
fi
mc mb -p "anybackup/$BUCKET" >/dev/null
"""
    run_cmd(
        ["kubectl", "exec", "-i", "-n", namespace, pod, "--", "sh", "-s"],
        input_text=script,
        safe_name="ensure MinIO bucket for KWeaver OSSGateway default storage",
    )


def default_oss_gateway_storages(oss_base_url: str) -> list:
    _, body = get_json(f"{oss_base_url}/api/v1/storages?enabled=true&is_default=true")
    payload = json.loads(body or "{}")
    return [item for item in list_items(payload) if isinstance(item, dict)]


def ensure_oss_gateway_default_storage() -> bool:
    if not ensure_oss_storage:
        return False

    oss_base_url = discover_oss_gateway_base_url(kweaver_namespace)
    existing = default_oss_gateway_storages(oss_base_url)
    minio = discover_minio_config(kweaver_namespace)
    ensure_minio_bucket(kweaver_namespace, minio)
    if existing:
        log("OSSGateway default storage already exists and MinIO bucket is ready")
        return False

    payload = {
        "storage_name": "kweaver-minio-default",
        "vendor_type": "ECEPH",
        "endpoint": minio["endpoint"],
        "internal_endpoint": minio["endpoint"],
        "bucket_name": minio["bucket"],
        "access_key_id": minio["access_key"],
        "access_key_secret": minio["secret_key"],
        "is_default": True,
    }
    post_json(f"{oss_base_url}/api/v1/storages", payload, expected_statuses=(200, 201, 204))
    after = default_oss_gateway_storages(oss_base_url)
    if not after:
        raise RuntimeError("OSSGateway default storage creation returned success but no default storage is visible")
    log(f"Ensured OSSGateway default storage backed by MinIO bucket {minio['bucket']}")
    return True


def parse_json_payload(text: str):
    text = text.strip()
    if not text:
        return None
    decoder = json.JSONDecoder()
    starts = [idx for idx in (text.find("{"), text.find("[")) if idx >= 0]
    if not starts:
        return None
    start = min(starts)
    payload, _ = decoder.raw_decode(text[start:])
    return payload


def list_items(payload):
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for path in (
            ("data", "items"),
            ("data", "records"),
            ("data", "list"),
            ("items",),
            ("records",),
            ("entries",),
            ("data",),
        ):
            cur = payload
            for part in path:
                if not isinstance(cur, dict) or part not in cur:
                    cur = None
                    break
                cur = cur[part]
            if isinstance(cur, list):
                return cur
    return []


def item_id(item: dict) -> str:
    for key in ("id", "skill_id", "skillId"):
        value = item.get(key)
        if value:
            return str(value)
    return ""


def item_name(item: dict) -> str:
    for key in ("name", "skill_name", "skillName"):
        value = item.get(key)
        if value:
            return str(value)
    return ""


def item_status(item: dict) -> str:
    for key in ("status", "skill_status", "skillStatus"):
        value = item.get(key)
        if value:
            return str(value)
    return ""


def skill_name(skill_dir: Path) -> str:
    text = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
    match = re.search(r"(?m)^name:\s*(.+?)\s*$", text)
    if not match:
        raise RuntimeError(f"Unable to read skill name from {skill_dir / 'SKILL.md'}")
    return match.group(1).strip().strip('"').strip("'")


def zip_skill_dir(skill_dir: Path, output_dir: Path) -> Path:
    zip_path = output_dir / f"{skill_dir.name}.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(skill_dir.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(skill_dir).as_posix())
    return zip_path


def find_skill_by_name(name: str):
    proc = run_kweaver(["skill", "list", "--name", name, "-bd", biz_domain])
    payload = parse_json_payload(proc.stdout)
    for item in list_items(payload):
        if isinstance(item, dict) and item_name(item) == name and item_id(item):
            return item
    return None


def resolve_registered_skill(name: str, stdout: str) -> dict:
    payload = parse_json_payload(stdout)
    candidates = []
    if isinstance(payload, dict):
        candidates.append(payload)
        for key in ("data", "item", "skill"):
            value = payload.get(key)
            if isinstance(value, dict):
                candidates.append(value)
    for item in candidates:
        sid = item_id(item)
        if sid:
            return item
    item = find_skill_by_name(name)
    if item:
        return item
    raise RuntimeError(f"Unable to resolve imported skill id for {name}")


def yaml_value(value: str) -> str:
    value = value.strip()
    if " #" in value:
        value = value.split(" #", 1)[0].rstrip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def read_rds_config(path: str) -> dict:
    config = Path(path)
    if not config.exists():
        raise RuntimeError(f"KWeaver config file not found: {path}")

    lines = config.read_text(encoding="utf-8").splitlines()
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped != "rds:":
            continue

        base_indent = len(line) - len(line.lstrip())
        block = {}
        for child in lines[idx + 1 :]:
            child_stripped = child.strip()
            if not child_stripped or child_stripped.startswith("#"):
                continue
            indent = len(child) - len(child.lstrip())
            if indent <= base_indent:
                break
            if ":" not in child_stripped:
                continue
            key, value = child_stripped.split(":", 1)
            block[key.strip()] = yaml_value(value)

        if all(block.get(key) for key in ("user", "password", "database")):
            return block

    raise RuntimeError(f"Unable to resolve rds.user/password/database from {path}")


def discover_mariadb_pod(namespace: str) -> str:
    proc = run_cmd(
        ["kubectl", "get", "pods", "-n", namespace, "-o", "json"],
        safe_name="kubectl get mariadb pods",
    )
    payload = json.loads(proc.stdout)
    candidates = []
    for item in payload.get("items", []):
        metadata = item.get("metadata", {})
        status = item.get("status", {})
        name = metadata.get("name", "")
        if "mariadb" not in name:
            continue
        phase = status.get("phase", "")
        ready = False
        for condition in status.get("conditions", []):
            if condition.get("type") == "Ready" and condition.get("status") == "True":
                ready = True
                break
        candidates.append((phase == "Running" and ready, name))
    candidates.sort(reverse=True)
    if candidates:
        return candidates[0][1]
    raise RuntimeError(f"Unable to find a MariaDB pod in namespace {namespace}")


def ensure_skill_publish_schema() -> bool:
    if not publish or not ensure_publish_schema:
        return False

    rds = read_rds_config(kweaver_config_path)
    pod = discover_mariadb_pod(resource_namespace)
    sql = r"""
CREATE TABLE IF NOT EXISTS `t_skill_release` (
    `f_id` bigint AUTO_INCREMENT NOT NULL,
    `f_skill_id` varchar(40) NOT NULL DEFAULT '',
    `f_name` varchar(255) NOT NULL DEFAULT '',
    `f_description` longtext DEFAULT NULL,
    `f_skill_content` longtext DEFAULT NULL,
    `f_version` varchar(40) NOT NULL DEFAULT '',
    `f_status` varchar(40) NOT NULL DEFAULT 'published',
    `f_source` varchar(50) NOT NULL DEFAULT '',
    `f_extend_info` longtext DEFAULT NULL,
    `f_dependencies` longtext DEFAULT NULL,
    `f_file_manifest` longtext DEFAULT NULL,
    `f_create_user` varchar(50) NOT NULL DEFAULT '',
    `f_create_time` bigint(20) NOT NULL DEFAULT 0,
    `f_update_user` varchar(50) NOT NULL DEFAULT '',
    `f_update_time` bigint(20) NOT NULL DEFAULT 0,
    `f_release_desc` varchar(255) NOT NULL DEFAULT '',
    `f_release_user` varchar(50) NOT NULL DEFAULT '',
    `f_release_time` bigint(20) NOT NULL DEFAULT 0,
    `f_delete_user` varchar(50) NOT NULL DEFAULT '',
    `f_delete_time` bigint(20) NOT NULL DEFAULT 0,
    `f_category` varchar(50) DEFAULT '',
    `f_is_deleted` boolean DEFAULT 0,
    `f_creation_type` varchar(20) NOT NULL DEFAULT 'custom',
    `f_config_source` varchar(40) NOT NULL DEFAULT '',
    `f_component_id` varchar(40) NOT NULL DEFAULT '',
    PRIMARY KEY (`f_id`),
    UNIQUE KEY `uk_skill_release` (`f_skill_id`, `f_version`) USING BTREE,
    KEY `idx_skill_id_create_time` (`f_skill_id`, `f_create_time`) USING BTREE,
    KEY `idx_status_update_time` (`f_status`, `f_update_time`) USING BTREE,
    KEY `idx_category_update_time` (`f_category`, `f_update_time`) USING BTREE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = 'Skill release table compatibility';

CREATE TABLE IF NOT EXISTS `t_skill_release_history` (
    `f_id` bigint AUTO_INCREMENT NOT NULL,
    `f_skill_id` varchar(40) NOT NULL DEFAULT '',
    `f_skill_release` longtext DEFAULT NULL,
    `f_version` varchar(40) NOT NULL DEFAULT '',
    `f_skill_version` varchar(40) NOT NULL DEFAULT '',
    `f_release_desc` varchar(255) NOT NULL DEFAULT '',
    `f_create_user` varchar(50) NOT NULL DEFAULT '',
    `f_create_time` bigint(20) NOT NULL DEFAULT 0,
    `f_update_user` varchar(50) NOT NULL DEFAULT '',
    `f_update_time` bigint(20) NOT NULL DEFAULT 0,
    `f_release_user` varchar(50) NOT NULL DEFAULT '',
    `f_release_time` bigint(20) NOT NULL DEFAULT 0,
    `f_metadata_version` varchar(40) NOT NULL DEFAULT '',
    `f_metadata_type` varchar(40) NOT NULL DEFAULT '',
    PRIMARY KEY (`f_id`),
    UNIQUE KEY `uk_skill_release_history` (`f_skill_id`, `f_version`) USING BTREE,
    KEY `idx_skill_id_create_time` (`f_skill_id`, `f_create_time`) USING BTREE,
    KEY `idx_skill_id_metadata_version` (`f_skill_id`, `f_metadata_version`) USING BTREE
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = 'Skill release history table compatibility';
"""
    run_cmd(
        [
            "kubectl",
            "exec",
            "-i",
            "-n",
            resource_namespace,
            pod,
            "--",
            "env",
            f"MYSQL_PWD={rds['password']}",
            "mariadb",
            f"-u{rds['user']}",
            "-D",
            rds["database"],
        ],
        input_text=sql,
        safe_name="ensure KWeaver skill publish schema",
    )
    log(f"Ensured KWeaver skill publish schema in {resource_namespace}/{pod}")
    return True


def publish_skill(skill_id: str, status: str) -> str:
    if not publish:
        return "skipped"
    if status == "published":
        return "already_published"
    proc = run_kweaver(["skill", "set-status", skill_id, "published", "-bd", biz_domain], check=False)
    if proc.returncode == 0:
        return "published"
    fallback = run_kweaver(["skill", "status", skill_id, "published", "-bd", biz_domain], check=False)
    if fallback.returncode == 0:
        return "published"
    raise RuntimeError(
        f"Failed to publish skill {skill_id}\n"
        f"set-status stdout={proc.stdout}\nset-status stderr={proc.stderr}\n"
        f"status stdout={fallback.stdout}\nstatus stderr={fallback.stderr}"
    )


state = {
    "base_url": base_url,
    "business_domain": biz_domain,
    "auth_policy_checked": False,
    "oss_storage_checked": False,
    "publish_schema_checked": False,
    "skills": {},
}

state["auth_policy_checked"] = ensure_execution_factory_auth_policy()
state["oss_storage_checked"] = ensure_oss_gateway_default_storage()
state["publish_schema_checked"] = ensure_skill_publish_schema()

for raw_dir in skill_dirs:
    skill_dir = Path(raw_dir).resolve()
    name = skill_name(skill_dir)
    existing = find_skill_by_name(name)
    action = "reused"
    if existing:
        skill = existing
        log(f"Reuse existing skill: {name} ({item_id(skill)})")
    else:
        log(f"Register skill: {name} from {skill_dir}")
        with tempfile.TemporaryDirectory(prefix="anybackup-skill-") as tmpdir:
            zip_path = zip_skill_dir(skill_dir, Path(tmpdir))
            proc = run_kweaver(
                [arg for arg in [
                    "skill",
                    "register",
                    "--zip-file",
                    str(zip_path),
                    *(["--source", source] if source else []),
                    "-bd",
                    biz_domain,
                ] if arg]
            )
        skill = resolve_registered_skill(name, proc.stdout)
        action = "registered"
        log(f"Registered skill: {name} ({item_id(skill)})")
    sid = item_id(skill)
    publish_result = publish_skill(sid, item_status(skill))
    if publish_result == "published":
        log(f"Published skill: {name} ({sid})")
    elif publish_result == "already_published":
        log(f"Skill already published: {name} ({sid})")
    state["skills"][name] = {
        "id": sid,
        "source_dir": str(skill_dir),
        "action": action,
        "published": publish_result in ("published", "already_published"),
        "publish_action": publish_result,
    }

if state_file:
    path = Path(state_file)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    log(f"Wrote skill state: {path}")

print(json.dumps(state, ensure_ascii=False, indent=2))
PY
