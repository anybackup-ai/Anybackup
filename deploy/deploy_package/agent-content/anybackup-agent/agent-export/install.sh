#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  install.sh --export-file FILE --work-dir DIR [options]

Options:
  --model-map FILE      Model id mapping emitted by model-config/install.sh
  --base-url URL        KWeaver platform URL. Passed to kweaver as --base-url
  --biz-domain BD       Business domain. Default: bd_public
  --insecure            Disable TLS verification for the kweaver CLI process
  --publish             Publish agents whose export status is published. Default
  --no-publish          Create/update agents but do not publish

The script imports an agent_export_*.json file idempotently by agent key.
Existing agents are updated; missing agents are created with the original key.
USAGE
}

EXPORT_FILE=""
MODEL_MAP=""
BASE_URL="${KWEAVER_BASE_URL:-}"
BIZ_DOMAIN="${KWEAVER_BUSINESS_DOMAIN:-bd_public}"
WORK_DIR=""
PUBLISH=1
INSECURE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --export-file)
      EXPORT_FILE="${2:-}"
      shift 2
      ;;
    --model-map)
      MODEL_MAP="${2:-}"
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
    --work-dir)
      WORK_DIR="${2:-}"
      shift 2
      ;;
    --insecure)
      INSECURE=1
      shift
      ;;
    --publish)
      PUBLISH=1
      shift
      ;;
    --no-publish)
      PUBLISH=0
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

if [[ -z "$EXPORT_FILE" || -z "$WORK_DIR" ]]; then
  usage >&2
  exit 2
fi

if [[ ! -f "$EXPORT_FILE" ]]; then
  echo "Agent export file does not exist: $EXPORT_FILE" >&2
  exit 1
fi

if ! command -v kweaver >/dev/null 2>&1; then
  echo "Required command is missing: kweaver" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"

python3 - "$EXPORT_FILE" "$MODEL_MAP" "$BASE_URL" "$BIZ_DOMAIN" "$WORK_DIR" "$PUBLISH" "$INSECURE" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

export_file = Path(sys.argv[1])
model_map_file = Path(sys.argv[2]) if sys.argv[2] else None
base_url = sys.argv[3]
biz_domain = sys.argv[4]
work_dir = Path(sys.argv[5])
publish_enabled = sys.argv[6] == "1"
insecure = sys.argv[7] == "1"


def read_json(path: Path):
    raw = path.read_bytes()
    encodings = ("utf-8-sig", "utf-16", "utf-16-le", "gb18030")
    last_error = None
    for enc in encodings:
        try:
            return json.loads(raw.decode(enc))
        except Exception as exc:  # noqa: BLE001
            last_error = exc
    raise ValueError(f"Unable to parse JSON file {path}: {last_error}") from last_error


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
    for path in (
        ("data", "items"),
        ("data", "records"),
        ("data", "list"),
        ("items",),
        ("records",),
        ("entries",),
        ("data",),
    ):
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
    if isinstance(obj, dict):
        for key in keys:
            value = obj.get(key)
            if value is not None and value != "":
                return str(value)
    return ""


def object_id(obj):
    return first_value(obj, ("id", "agent_id", "agentId"))


def object_key(obj):
    return first_value(obj, ("key", "agent_key", "agentKey"))


def load_agent_config(agent):
    cfg = agent.get("config")
    if isinstance(cfg, str):
        return json.loads(cfg)
    if isinstance(cfg, dict):
        return cfg
    raise ValueError(f"Agent {agent.get('name') or agent.get('id')} has no usable config")


export = read_json(export_file)
agents = export.get("agents") if isinstance(export, dict) else None
if not isinstance(agents, list) or not agents:
    raise ValueError(f"Agent export does not contain a non-empty agents array: {export_file}")

model_map = {"llm": {}}
if model_map_file and model_map_file.exists():
    model_map = read_json(model_map_file)

llm_by_id = model_map.get("llm") or {}
llm_by_name = {
    item.get("source_name"): item
    for item in llm_by_id.values()
    if isinstance(item, dict) and item.get("source_name")
}

# Known toolbox/tool aliases from exported 0.6.x environments. The toolbox ADP
# import is deterministic for the current target environment, but historical
# exports may contain ids from another KWeaver instance.
toolbox_aliases = {
    "408b5319-eefc-445e-9b15-7d332f0706ee": "e521d454-4a0b-4dc9-8a28-d0986de1cef9",
    "f182d75a-7fd2-421a-a8e0-7064d75e39af": "1a98d9e8-cfa6-4150-9c54-2ad8445d31a5",
}

tool_aliases = {
    "139e027f-af32-4d5c-9d8b-4fa48b185d96": "5467284c-f25a-4665-8f05-a320dd6e1ec3",
    "4b66ad66-4277-4d68-b847-c302c94265c9": "f46fa5df-f371-447f-8451-2d2f34cc78e9",
    "636c77ee-70ad-46a3-b68b-78b0ed2eb7c8": "00929c5f-3375-4ddc-9fb0-c48a24707f39",
    "a666b98e-9278-401f-b4e5-e491bcaed3f8": "8542b7c2-f82a-4c1e-ab8c-83e2e73ccfdf",
    "b06c7316-9359-4aff-a425-4db8f43f2837": "3c78c9da-0bd5-48b4-b23b-960972d4d2af",
    "cf6753b9-fba2-4c66-9cbe-27659087882b": "05275bb1-46e2-4727-9c6f-97d9ea0af94b",
    "fcfaee61-7055-4847-bb45-60e5e22b02b0": "2fd071fa-a696-4fee-91e1-5b2dc190e88b",
    "fe3f1f26-ff56-4f62-a5c7-a68d1e8ac2d7": "52b35175-cee3-41ea-91c0-1d70e8371f9c",
    "51382ef3-b35b-44a6-8a53-c670cbf53f10": "598b4027-47a8-47d4-ae77-e1efb08478f9",
}


def rewrite_llm_refs(obj):
    if isinstance(obj, list):
        for item in obj:
            rewrite_llm_refs(item)
        return
    if not isinstance(obj, dict):
        return

    llm_cfg = obj.get("llm_config")
    if isinstance(llm_cfg, dict):
        source_id = str(llm_cfg.get("id") or "")
        source_name = str(llm_cfg.get("name") or "")
        mapped = llm_by_id.get(source_id) or llm_by_name.get(source_name)
        if not mapped and len(llm_by_id) == 1:
            mapped = next(iter(llm_by_id.values()))
        if mapped:
            llm_cfg["id"] = mapped.get("target_id") or source_id
            llm_cfg["name"] = mapped.get("target_name") or source_name

    for value in obj.values():
        rewrite_llm_refs(value)


def rewrite_tool_refs(obj):
    if isinstance(obj, list):
        for item in obj:
            rewrite_tool_refs(item)
        return
    if not isinstance(obj, dict):
        return

    tool_box_id = str(obj.get("tool_box_id") or "")
    tool_id = str(obj.get("tool_id") or "")
    if tool_box_id in toolbox_aliases:
        obj["tool_box_id"] = toolbox_aliases[tool_box_id]
    if tool_id in tool_aliases:
        obj["tool_id"] = tool_aliases[tool_id]

    for value in obj.values():
        rewrite_tool_refs(value)


agents_by_key = {}
configs_by_key = {}
for agent in agents:
    key = str(agent.get("key") or "")
    if not key:
        raise ValueError(f"Agent is missing key: {agent.get('name') or agent.get('id')}")
    agents_by_key[key] = agent
    configs_by_key[key] = load_agent_config(agent)


def dependencies_for(key):
    cfg = configs_by_key[key]
    skills = cfg.get("skills") if isinstance(cfg, dict) else None
    refs = []
    if isinstance(skills, dict):
        for child in skills.get("agents") or []:
            if isinstance(child, dict):
                child_key = str(child.get("agent_key") or "")
                if child_key and child_key in agents_by_key:
                    refs.append(child_key)
    return refs


order = []
visiting = set()
visited = set()


def visit(key):
    if key in visited:
        return
    if key in visiting:
        raise ValueError(f"Cyclic agent dependency detected at key {key}")
    visiting.add(key)
    for dep in dependencies_for(key):
        visit(dep)
    visiting.remove(key)
    visited.add(key)
    order.append(key)


for key in agents_by_key:
    visit(key)

env = os.environ.copy()
env["KWEAVER_BUSINESS_DOMAIN"] = biz_domain
if insecure:
    env["KWEAVER_TLS_INSECURE"] = "1"
    env["NODE_TLS_REJECT_UNAUTHORIZED"] = "0"

def kweaver_supports_base_url():
    proc = subprocess.run(["kweaver", "--help"], text=True, capture_output=True, check=False, env=env)
    return "--base-url" in (proc.stdout or "") or "--base-url" in (proc.stderr or "")


kweaver_base = ["kweaver"]
if base_url and kweaver_supports_base_url():
    kweaver_base.extend(["--base-url", base_url])
elif base_url:
    print("kweaver CLI does not support --base-url; using the current logged-in platform")


def run(args, *, check=True):
    proc = subprocess.run(args, text=True, capture_output=True, check=False, env=env)
    if check and proc.returncode != 0:
        raise RuntimeError(
            f"Command failed ({proc.returncode}): {' '.join(args)}\n"
            f"stdout={proc.stdout.strip()}\nstderr={proc.stderr.strip()}"
        )
    return proc


def get_by_key(key):
    proc = run(kweaver_base + ["agent", "get-by-key", key, "-bd", biz_domain], check=False)
    if proc.returncode != 0:
        return None
    obj = parse_json_text(proc.stdout)
    if isinstance(obj, dict):
        return obj
    items = extract_items(obj)
    return items[0] if items else None


work_dir.mkdir(parents=True, exist_ok=True)
configs_dir = work_dir / "configs"
configs_dir.mkdir(parents=True, exist_ok=True)

state = {
    "business_domain": biz_domain,
    "base_url": base_url,
    "source_export": str(export_file),
    "agents": {},
    "warnings": [],
}

for key in order:
    agent = agents_by_key[key]
    cfg = configs_by_key[key]
    rewrite_llm_refs(cfg)
    rewrite_tool_refs(cfg)

    name = str(agent.get("name") or cfg.get("name") or key)
    profile = str(agent.get("profile") or cfg.get("profile") or "")
    product_key = str(agent.get("product_key") or "dip")
    status = str(agent.get("status") or "")
    source_id = str(agent.get("id") or "")

    cfg_file = configs_dir / f"{key}.json"
    cfg_file.write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")

    existing = get_by_key(key)
    if existing:
        target_id = object_id(existing)
        if not target_id:
            raise RuntimeError(f"Unable to resolve existing agent id for key {key}")
        print(f"Update Agent: {name} ({key})")
        run(kweaver_base + ["agent", "update", target_id, "--name", name, "--profile", profile, "--config-path", str(cfg_file)])
        action = "updated"
    else:
        print(f"Create Agent: {name} ({key})")
        run(
            kweaver_base
            + [
                "agent",
                "create",
                "--name",
                name,
                "--profile",
                profile,
                "--product-key",
                product_key,
                "--key",
                key,
                "--config",
                str(cfg_file),
                "-bd",
                biz_domain,
            ]
        )
        created = get_by_key(key)
        target_id = object_id(created) if created else ""
        if not target_id:
            raise RuntimeError(f"Unable to resolve created agent id for key {key}")
        action = "created"

    if publish_enabled and status.lower() == "published":
        print(f"Publish Agent: {name} ({key})")
        run(kweaver_base + ["agent", "publish", target_id, "-bd", biz_domain])

    state["agents"][key] = {
        "source_id": source_id,
        "source_key": key,
        "source_name": name,
        "target_id": target_id,
        "target_key": key,
        "action": action,
        "published": publish_enabled and status.lower() == "published",
    }

state_file = work_dir / "agent-export-state.json"
state_file.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Agent export state written: {state_file}")
PY
