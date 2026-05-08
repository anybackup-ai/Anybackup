#!/usr/bin/env bash
set -euo pipefail

python3 - "$@" <<'PY'
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from collections import OrderedDict
from pathlib import Path


def run_json(argv):
    result = subprocess.run(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise RuntimeError(
            "Command failed ({}): {}\n{}".format(
                result.returncode,
                " ".join(argv),
                result.stderr.strip(),
            )
        )
    return json.loads(result.stdout)


def parse_requirement_line(line):
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    line = line.split("#", 1)[0].split(";", 1)[0].strip()
    if not line or line.startswith(("-", "git+", "http://", "https://")):
        return None

    match = re.match(r"^([A-Za-z0-9_.-]+)\s*(===|==|~=|>=|<=|>|<|!=)\s*([A-Za-z0-9_.!+*-]+)", line)
    if not match:
        raise RuntimeError(
            "Unsupported requirement '{}'. Use an explicit package version such as name==1.2.3.".format(line)
        )

    name, operator, version = match.groups()
    return {
        "name": name,
        "version": version,
        "specifier": "{}{}".format(operator, version),
    }


def load_dependencies(skill_dirs):
    dependencies = OrderedDict()
    sources = []
    for skill_dir in skill_dirs:
        req = Path(skill_dir) / "requirements.txt"
        if not req.exists():
            continue
        for raw in req.read_text(encoding="utf-8").splitlines():
            item = parse_requirement_line(raw)
            if not item:
                continue
            dependencies[item["name"].lower()] = item
            sources.append({"skill_dir": str(skill_dir), "requirement": raw.strip()})
    return list(dependencies.values()), sources


def find_skill_dirs(args):
    skill_dirs = [Path(p) for p in args.skill_dir]
    if args.skills_root and not skill_dirs:
        root = Path(args.skills_root)
        if root.exists():
            skill_dirs = [p for p in sorted(root.iterdir()) if p.is_dir() and (p / "requirements.txt").exists()]
    return skill_dirs


def pod_session_id(pod):
    labels = pod.get("metadata", {}).get("labels", {})
    if labels.get("session_id"):
        return labels["session_id"]
    name = pod.get("metadata", {}).get("name", "")
    prefix = "sandbox-sandbox-"
    if name.startswith(prefix):
        return name[len(prefix):].replace("-", "_")
    return ""


def resolve_session_id(namespace, explicit_session_id):
    if explicit_session_id:
        return explicit_session_id

    pods = run_json([
        "kubectl",
        "get",
        "pods",
        "-n",
        namespace,
        "-l",
        "app=sandbox-executor",
        "-o",
        "json",
    ])
    candidates = []
    for pod in pods.get("items", []):
        if pod.get("status", {}).get("phase") != "Running":
            continue
        session_id = pod_session_id(pod)
        if session_id:
            candidates.append((pod.get("metadata", {}).get("name", ""), session_id))

    if not candidates:
        raise RuntimeError(
            "No running sandbox executor session was found in namespace '{}'. "
            "Create a sandbox session first or pass --session-id.".format(namespace)
        )
    candidates.sort()
    return candidates[0][1]


def resolve_control_plane_url(namespace, service_name, service_port, explicit_url):
    if explicit_url:
        return explicit_url.rstrip("/")

    svc = run_json(["kubectl", "get", "svc", "-n", namespace, service_name, "-o", "json"])
    cluster_ip = svc.get("spec", {}).get("clusterIP")
    if not cluster_ip or cluster_ip == "None":
        raise RuntimeError("Service {}/{} has no ClusterIP.".format(namespace, service_name))

    selected_port = service_port
    for port in svc.get("spec", {}).get("ports", []):
        if str(port.get("port")) == str(service_port):
            selected_port = port.get("port")
            break
    return "http://{}:{}".format(cluster_ip, selected_port).rstrip("/")


def install_dependencies(base_url, session_id, pypi_url, dependencies, timeout):
    payload = {
        "python_package_index_url": pypi_url,
        "dependencies": [
            {"name": dep["name"], "version": dep["version"]}
            for dep in dependencies
        ],
    }
    url = "{}/api/v1/sessions/{}/dependencies/install".format(base_url.rstrip("/"), session_id)
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            text = resp.read().decode("utf-8", errors="replace")
            try:
                body = json.loads(text) if text else {}
            except json.JSONDecodeError:
                body = {"raw": text}
            return {"status": resp.status, "body": body}
    except urllib.error.HTTPError as exc:
        text = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError("Dependency install API failed: HTTP {} {}".format(exc.code, text))


def main():
    parser = argparse.ArgumentParser(description="Install Python dependencies for imported KWeaver sandbox skills.")
    parser.add_argument("--namespace", default="kweaver")
    parser.add_argument("--service-name", default="sandbox-control-plane")
    parser.add_argument("--service-port", default="8000")
    parser.add_argument("--control-plane-url", default="")
    parser.add_argument("--session-id", default="")
    parser.add_argument("--skills-root", default="")
    parser.add_argument("--skill-dir", action="append", default=[])
    parser.add_argument("--pypi-url", default="https://pypi.tuna.tsinghua.edu.cn/simple")
    parser.add_argument("--state-file", default="")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()

    skill_dirs = find_skill_dirs(args)
    dependencies, sources = load_dependencies(skill_dirs)
    if not dependencies:
        print("[INFO] No Python skill dependencies found; nothing to install.")
        return 0

    session_id = resolve_session_id(args.namespace, args.session_id)
    base_url = resolve_control_plane_url(
        args.namespace,
        args.service_name,
        args.service_port,
        args.control_plane_url,
    )

    dep_summary = ", ".join("{}{}".format(dep["name"], dep["specifier"]) for dep in dependencies)
    print("[INFO] Installing sandbox dependencies for session {}: {}".format(session_id, dep_summary))
    response = install_dependencies(base_url, session_id, args.pypi_url, dependencies, args.timeout)
    print("[INFO] Sandbox dependency install request accepted by {}".format(base_url))

    if args.state_file:
        state_path = Path(args.state_file)
        state_path.parent.mkdir(parents=True, exist_ok=True)
        state_path.write_text(
            json.dumps(
                {
                    "session_id": session_id,
                    "control_plane_url": base_url,
                    "python_package_index_url": args.pypi_url,
                    "dependencies": dependencies,
                    "sources": sources,
                    "response": response,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
