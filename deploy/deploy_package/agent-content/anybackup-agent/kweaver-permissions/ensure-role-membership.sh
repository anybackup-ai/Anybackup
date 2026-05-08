#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ensure-role-membership.sh --roles ROLE[,ROLE...] [options]

Options:
  --roles NAMES          Required KWeaver platform roles for the current CLI user
  --config-path FILE     KWeaver config file. Default: /opt/v9-alpha-deploy/kweaver-config/config.yaml
  --namespace NS         KWeaver resource namespace. Default: resource

The script reads the current `kweaver auth whoami --json` identity and ensures
that user is a member of the required KWeaver platform roles. Tokens and
database passwords are never printed.
USAGE
}

ROLES_CSV=""
CONFIG_PATH="${KWEAVER_CONFIG_PATH:-/opt/v9-alpha-deploy/kweaver-config/config.yaml}"
NAMESPACE="${KWEAVER_RESOURCE_NAMESPACE:-resource}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --roles)
      ROLES_CSV="${2:-}"
      shift 2
      ;;
    --config-path)
      CONFIG_PATH="${2:-}"
      shift 2
      ;;
    --namespace)
      NAMESPACE="${2:-}"
      shift 2
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

if [[ -z "$ROLES_CSV" ]]; then
  usage >&2
  exit 2
fi

if ! command -v kweaver >/dev/null 2>&1; then
  echo "Required command is missing: kweaver" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Required command is missing: kubectl" >&2
  exit 1
fi

python3 - "$ROLES_CSV" "$CONFIG_PATH" "$NAMESPACE" <<'PY'
import json
import pathlib
import re
import subprocess
import sys
import time

roles_csv = sys.argv[1]
config_path = pathlib.Path(sys.argv[2])
namespace = sys.argv[3]


def parse_json_text(text: str):
    text = text.strip()
    if not text:
        raise RuntimeError("empty JSON output")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        starts = [pos for pos in (text.find("{"), text.find("[")) if pos >= 0]
        if not starts:
            raise
        return json.loads(text[min(starts):])


def run(args, *, input_text=None, description="command"):
    proc = subprocess.run(args, text=True, input=input_text, capture_output=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"{description} failed: {proc.stderr.strip()}")
    return proc.stdout


def unquote_yaml_scalar(value: str):
    value = value.strip()
    if not value:
        return ""
    if "#" in value and not value.startswith(("'", '"')):
        value = value.split("#", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def read_yaml_block_values(path: pathlib.Path, block_name: str):
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
    return "'" + str(value).replace("\\", "\\\\").replace("'", "''") + "'"


roles = [role.strip() for role in roles_csv.split(",") if role.strip()]
if not roles:
    raise RuntimeError("no role names were provided")

whoami = parse_json_text(run(["kweaver", "auth", "whoami", "--json"], description="read KWeaver identity"))
user_id = str(whoami.get("sub") or "").strip()
user_name = str(whoami.get("displayName") or whoami.get("preferred_username") or whoami.get("name") or user_id).strip()
if not user_id:
    raise RuntimeError("unable to resolve current KWeaver user id")

rds = read_yaml_block_values(config_path, "rds")
db_user = rds.get("user")
db_pass = rds.get("password")
if not (db_user and db_pass):
    raise RuntimeError("unable to resolve KWeaver MariaDB credentials from config")

pods = run(["kubectl", "get", "pods", "-n", namespace, "-o", "name"], description="discover MariaDB pod")
pod = ""
for line in pods.splitlines():
    candidate = line.strip().removeprefix("pod/")
    if "mariadb" in candidate:
        pod = candidate
        break
if not pod:
    raise RuntimeError(f"unable to discover MariaDB pod in namespace {namespace}")

now = int(time.time() * 1_000_000)
role_list = ",".join(sql_literal(role) for role in roles)
sql = f"""
USE anyshare;
SELECT f_name FROM t_role WHERE f_name IN ({role_list});
INSERT INTO t_role_member
    (f_role_id, f_member_id, f_member_type, f_member_name, f_created_time, f_modify_time)
SELECT r.f_id, {sql_literal(user_id)}, 1, {sql_literal(user_name)}, {now}, {now}
  FROM t_role r
 WHERE r.f_name IN ({role_list})
   AND NOT EXISTS (
       SELECT 1 FROM t_role_member m
        WHERE m.f_role_id = r.f_id
          AND m.f_member_id = {sql_literal(user_id)}
   );
SELECT r.f_name
  FROM t_role r
  JOIN t_role_member m ON m.f_role_id = r.f_id
 WHERE r.f_name IN ({role_list})
   AND m.f_member_id = {sql_literal(user_id)}
 ORDER BY r.f_name;
"""

output = run(
    [
        "kubectl",
        "exec",
        "-i",
        "-n",
        namespace,
        pod,
        "--",
        "env",
        f"MYSQL_PWD={db_pass}",
        "mariadb",
        "-u",
        db_user,
        "--batch",
        "--raw",
        "--skip-column-names",
    ],
    input_text=sql,
    description="ensure KWeaver role membership",
)

lines = [line.strip() for line in output.splitlines() if line.strip()]
existing_roles = set(lines[: len(roles)])
ensured_roles = set(lines[len(roles):])
missing_roles = sorted(set(roles) - existing_roles)
missing_membership = sorted(set(roles) - ensured_roles)
if missing_roles:
    raise RuntimeError(f"required KWeaver roles do not exist: {', '.join(missing_roles)}")
if missing_membership:
    raise RuntimeError(f"unable to grant KWeaver roles to {user_name}: {', '.join(missing_membership)}")

print(f"Ensured KWeaver role membership for {user_name}: {', '.join(roles)}")
PY
