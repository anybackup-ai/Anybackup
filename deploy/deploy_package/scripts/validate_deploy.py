#!/usr/bin/env python
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]


@dataclass
class CheckResult:
    status: str
    name: str
    detail: str


class Validator:
    def __init__(self, mode: str) -> None:
        self.mode = mode
        self.results: list[CheckResult] = []
        self.tool_cache: dict[str, str | None] = {}

    def add(self, status: str, name: str, detail: str) -> None:
        self.results.append(CheckResult(status=status, name=name, detail=detail))

    def pass_(self, name: str, detail: str) -> None:
        self.add("PASS", name, detail)

    def fail(self, name: str, detail: str) -> None:
        self.add("FAIL", name, detail)

    def warn(self, name: str, detail: str) -> None:
        self.add("WARN", name, detail)

    def skip(self, name: str, detail: str) -> None:
        self.add("SKIP", name, detail)

    def has_failures(self) -> bool:
        return any(result.status == "FAIL" for result in self.results)

    def is_release_mode(self) -> bool:
        return self.mode == "release"

    def tool(self, name: str) -> str | None:
        if name not in self.tool_cache:
            self.tool_cache[name] = shutil.which(name)
        return self.tool_cache[name]

    def run(
        self,
        name: str,
        command: list[str],
        success_detail: str,
        fail_detail: str,
        required: bool = True,
        cwd: Path | None = None,
    ) -> subprocess.CompletedProcess[str] | None:
        try:
            completed = subprocess.run(
                command,
                cwd=str(cwd or REPO_ROOT),
                text=True,
                capture_output=True,
                check=False,
            )
        except FileNotFoundError:
            message = f"missing executable: {command[0]}"
            if required:
                self.fail(name, message)
            else:
                self.skip(name, message)
            return None

        if completed.returncode == 0:
            self.pass_(name, success_detail)
        else:
            detail = fail_detail
            stderr = (completed.stderr or completed.stdout).strip()
            if stderr:
                detail = f"{detail}: {trim(stderr)}"
            if required:
                self.fail(name, detail)
            else:
                self.warn(name, detail)
        return completed

    def print_summary(self) -> None:
        for result in self.results:
            print(f"[{result.status}] {result.name}: {result.detail}")

        counts = {status: 0 for status in ("PASS", "WARN", "SKIP", "FAIL")}
        for result in self.results:
            counts[result.status] += 1

        print()
        print(
            "Summary: "
            f"{counts['PASS']} pass, "
            f"{counts['WARN']} warn, "
            f"{counts['SKIP']} skip, "
            f"{counts['FAIL']} fail"
        )


def trim(text: str, limit: int = 240) -> str:
    single_line = " ".join(text.split())
    if len(single_line) <= limit:
        return single_line
    return single_line[: limit - 3] + "..."


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def check_required_files(validator: Validator) -> None:
    required_paths = [
        Path("install.sh"),
        Path("README.md"),
        Path("ansible/site.yml"),
        Path("ansible/inventory.ini"),
        Path("ansible/group_vars/all.yml"),
        Path("ansible/group_vars/secrets.yml.example"),
        Path("ansible/roles/internal/verify/tasks/main.yml"),
        Path("ansible/roles/internal/foundation_install/tasks/main.yml"),
        Path("ansible/roles/internal/kweaver_online_install/tasks/main.yml"),
        Path("ansible/roles/internal/cleanup_core_validation/tasks/main.yml"),
        Path("ansible/roles/internal/verify_core_only/tasks/main.yml"),
        Path("../helm/v9-infra/Chart.yaml"),
        Path("../helm/v9-infra/Chart.yaml"),
        Path("../helm/core_agent/Chart.yaml"),
        Path("../helm/conversation/Chart.yaml"),
        Path("images/load-images.sh"),
        Path("init-scripts/inject-cli-to-sandbox.sh"),
        Path("scripts/cleanup-kweaver-core-validation.sh"),
        Path("scripts/cleanup-kweaver-core-validation-local.sh"),
        Path("scripts/install-kweaver-core-only-local.sh"),
        Path("scripts/build-foundation-cli.ps1"),
        Path("scripts/verify-sandbox-overlay-local.sh"),
        Path("scripts/lib/ansible-common.sh"),
        Path("scripts/lib/kweaver-core-local-common.sh"),
        Path("docs/操作文档/cluster-smoke.sh"),
    ]

    missing = [str(path) for path in required_paths if not (REPO_ROOT / path).exists()]
    if missing:
        validator.fail("required-files", "missing files: " + ", ".join(missing))
    else:
        validator.pass_("required-files", "all deployment entry files are present")


def check_install_script_references(validator: Validator) -> None:
    install_path = REPO_ROOT / "install.sh"
    text = read_text(install_path)
    required_snippets = [
        '--profile',
        'kweaver-core-only',
        'deployment_profile=',
        'install-kweaver-core-only-local.sh',
        'run_stage prepare',
        'run_stage network-preflight',
        'run_stage deploy-services',
        'run_stage publish-network',
        'run_stage verify',
    ]
    forbidden_snippets = [
        'images/load-images.sh',
        'init-scripts/init-kweaver.sh',
        'foundation/install-foundation.sh',
        'init-scripts/generate-aksk.sh',
    ]

    problems: list[str] = []
    for snippet in required_snippets:
        if snippet not in text:
            problems.append(f"install.sh is missing {snippet}")
    for snippet in forbidden_snippets:
        if snippet in text:
            problems.append(f"install.sh still references legacy step {snippet}")

    if problems:
        validator.fail("install-script-references", "; ".join(problems))
    else:
        validator.pass_(
            "install-script-references",
            "install.sh points at the online KWeaver Core deployment flow and exposes a local bash path for core-only validation",
        )


def check_inventory(validator: Validator) -> None:
    inventory_path = REPO_ROOT / "ansible/inventory.ini"
    text = read_text(inventory_path)

    if "192.0.2." in text or "example" in text.lower():
        message = "inventory still contains example host values"
        if validator.is_release_mode():
            validator.fail("inventory", message)
        else:
            validator.warn("inventory", message)
    else:
        validator.pass_("inventory", "inventory is not using the bundled example host")


def check_secrets_file(validator: Validator) -> None:
    secrets_path = REPO_ROOT / "ansible/group_vars/secrets.yml"
    if secrets_path.exists():
        validator.pass_("secrets-file", "ansible/group_vars/secrets.yml is present")
        return

    detail = "ansible/group_vars/secrets.yml is missing; only the example file exists"
    if validator.is_release_mode():
        validator.fail("secrets-file", detail)
    else:
        validator.warn("secrets-file", detail)


def check_foundation_cli_binary(validator: Validator) -> None:
    foundation_cli = REPO_ROOT / "bin/foundation-cli"
    if not foundation_cli.exists():
        validator.fail("foundation-cli-binary", "bin/foundation-cli is missing")
        return

    data = foundation_cli.read_bytes()[:4096]
    is_placeholder = b"placeholder detected" in data
    is_too_small = foundation_cli.stat().st_size < 1024 * 1024
    if is_placeholder or is_too_small:
        detail = (
            "bin/foundation-cli is not the Linux release binary; run "
            "PowerShell -ExecutionPolicy Bypass -File scripts/build-foundation-cli.ps1 "
            "from the release workspace before packaging"
        )
        if validator.is_release_mode():
            validator.fail("foundation-cli-binary", detail)
        else:
            validator.warn("foundation-cli-binary", detail)
        return

    validator.pass_(
        "foundation-cli-binary",
        f"bin/foundation-cli exists and is {foundation_cli.stat().st_size} bytes",
    )


def check_kweaver_online_defaults(validator: Validator) -> None:
    ansible_vars = read_text(REPO_ROOT / "ansible/group_vars/all.yml")
    deploy_services = read_text(REPO_ROOT / "ansible/roles/deploy-services/tasks/main.yml")
    online_tasks = read_text(REPO_ROOT / "ansible/roles/internal/kweaver_online_install/tasks/main.yml")
    sandbox_overlay_tasks = read_text(REPO_ROOT / "ansible/roles/internal/sandbox_overlay/tasks/main.yml")
    local_installer = read_text(REPO_ROOT / "scripts/install-kweaver-core-only-local.sh")

    required_snippets = [
        "kweaver_online:",
        "https://github.com/kweaver-ai/kweaver-core.git",
        'git_ref: "release/0.6.0"',
        "kweaver-online-install-state",
        "internal/kweaver_online_install",
        "sandbox_overlay_enabled | default(true) | bool",
        "./deploy.sh",
        "kweaver-core",
        "install_kweaver_core",
        "internal/sandbox_overlay",
        "sandbox_overlay_dry_run",
        "imagePullPolicy",
    ]
    forbidden_snippets = [
        "internal/kweaver_offline_preflight",
        "internal/proton_base",
        "internal/kweaver_platform",
        "internal/kweaver_offline_install",
        "install_proton_base",
        "deploy_kweaver_platform",
        "kweaver_should_skip_install",
        "kweaver_online.helm_hook_timeout",
        "containerd_image_aliases",
        "deploy', 'install', 'core",
    ]

    combined = "\n".join([ansible_vars, deploy_services, online_tasks, sandbox_overlay_tasks, local_installer])
    problems = [f"missing {snippet}" for snippet in required_snippets if snippet not in combined]
    problems.extend(
        f"default flow still references {snippet}"
        for snippet in forbidden_snippets
        if snippet in combined
    )

    if problems:
        validator.fail("kweaver-online-defaults", "; ".join(problems))
    else:
        validator.pass_(
            "kweaver-online-defaults",
            "default flow runs the official KWeaver Core deploy.sh command atomically and no longer invokes proton-cli roles",
        )


def check_offline_assets(validator: Validator) -> None:
    business_tars = list((REPO_ROOT / "images").glob("*.tar"))

    if business_tars:
        validator.pass_(
            "packaged-business-images",
            f"found {len(business_tars)} business image tar(s)",
        )
        return

    validator.warn("packaged-business-images", "no business image tar archives were found under images/")


def check_placeholder_scripts(validator: Validator) -> None:
    target_paths = [
        Path("foundation/install-foundation.sh"),
        Path("init-scripts/init-kweaver.sh"),
        Path("init-scripts/generate-aksk.sh"),
    ]
    markers = [
        "placeholder",
        "not implemented",
        "manual or external",
        "no sdk automation is bundled",
        "add the real",
    ]

    hits: list[str] = []
    for relative_path in target_paths:
        text = read_text(REPO_ROOT / relative_path).lower()
        if any(marker in text for marker in markers):
            hits.append(str(relative_path))

    if not hits:
        validator.pass_("placeholder-scripts", "no obvious placeholder deployment scripts detected")
        return

    install_script = read_text(REPO_ROOT / "install.sh")
    still_referenced = [path for path in hits if Path(path).as_posix() in install_script]

    if still_referenced:
        detail = "legacy placeholder steps are still referenced by install.sh: " + ", ".join(still_referenced)
        if validator.is_release_mode():
            validator.fail("placeholder-scripts", detail)
        else:
            validator.warn("placeholder-scripts", detail)
        return

    validator.pass_(
        "placeholder-scripts",
        "placeholder helper scripts remain in the package, but the default installer no longer references them",
    )


def check_tooling(validator: Validator) -> None:
    required_tools = ["python", "helm", "git"]
    optional_tools = ["ansible-playbook", "kubectl", "docker", "bash"]

    for tool_name in required_tools:
        path = validator.tool(tool_name)
        if path:
            validator.pass_(f"tool:{tool_name}", path)
        else:
            validator.fail(f"tool:{tool_name}", f"{tool_name} is not available in PATH")

    for tool_name in optional_tools:
        path = validator.tool(tool_name)
        if path:
            validator.pass_(f"tool:{tool_name}", path)
        else:
            validator.skip(
                f"tool:{tool_name}",
                f"{tool_name} is not available; related runtime checks will be skipped",
            )


def helm_checks(validator: Validator) -> None:
    if not validator.tool("helm"):
        return

    charts = [
        Path("../helm/v9-infra"),
        Path("../helm/core_agent"),
        Path("../helm/conversation"),
        Path("../helm/web"),
    ]

    for chart in charts:
        chart_name = chart.as_posix()
        validator.run(
            name=f"helm-lint:{chart_name}",
            command=["helm", "lint", str(chart)],
            success_detail=f"helm lint passed for {chart_name}",
            fail_detail=f"helm lint failed for {chart_name}",
        )

        completed = validator.run(
            name=f"helm-template:{chart_name}",
            command=["helm", "template", f"smoke-{chart.name}", str(chart)],
            success_detail=f"helm template passed for {chart_name}",
            fail_detail=f"helm template failed for {chart_name}",
        )

        if completed is None or completed.returncode != 0:
            continue

        output = completed.stdout
        if chart_name.endswith("v9-infra"):
            required_tokens = ["v9-postgres", "v9-rabbitmq", "v9-redis", "v9-opensearch"]
            missing = [token for token in required_tokens if token not in output]
            if missing:
                validator.fail(
                    "helm-template:v9-infra-components",
                    "v9-infra output missing " + ", ".join(missing),
                )
            else:
                validator.pass_(
                    "helm-template:v9-infra-components",
                    "render includes postgres, rabbitmq, redis, and opensearch resources",
                )

        if chart_name.endswith("core-agent-service"):
            required_envs = ["POSTGRES_URL", "RABBITMQ_URL", "REDIS_URL", "OPENSEARCH_URL"]
            missing_envs = [env for env in required_envs if env not in output]
            if missing_envs:
                validator.fail(
                    "helm-template:core-agent-envs",
                    "core-agent render missing envs " + ", ".join(missing_envs),
                )
            else:
                validator.pass_(
                    "helm-template:core-agent-envs",
                    "core-agent render includes all runtime connection env vars",
                )


def ansible_checks(validator: Validator) -> None:
    if not validator.tool("ansible-playbook"):
        validator.skip(
            "ansible-syntax",
            "ansible-playbook is missing; syntax check not executed on this machine",
        )
        return

    validator.run(
        name="ansible-syntax",
        command=[
            "ansible-playbook",
            "-i",
            str(REPO_ROOT / "ansible/inventory.ini"),
            "--syntax-check",
            str(REPO_ROOT / "ansible/site.yml"),
        ],
        success_detail="ansible-playbook syntax check passed",
        fail_detail="ansible-playbook syntax check failed",
    )


def smoke_path_check(validator: Validator) -> None:
    verify_tasks = read_text(REPO_ROOT / "ansible/roles/internal/verify/tasks/main.yml")
    smoke_path = "docs/操作文档/cluster-smoke.sh"
    if smoke_path in verify_tasks and (REPO_ROOT / smoke_path).exists():
        validator.pass_("smoke-script-path", "verify role points at an existing smoke script")
    else:
        validator.fail("smoke-script-path", "verify role smoke script path is missing or stale")


def runtime_deep_checks_notice(validator: Validator) -> None:
    missing = [tool for tool in ("kubectl", "docker", "bash") if not validator.tool(tool)]
    if missing:
        validator.warn(
            "runtime-deep-checks",
            "cannot execute full local deployment/runtime validation without "
            + ", ".join(missing),
        )
    else:
        validator.pass_(
            "runtime-deep-checks",
            "kubectl, docker, and bash are available for deeper runtime checks",
        )


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate deployment scripts and deployment-related charts/ansible assets."
    )
    parser.add_argument(
        "--mode",
        choices=("regression", "release"),
        default="regression",
        help="regression validates code changes locally; release also fails on placeholder delivery gaps",
    )
    return parser.parse_args(list(argv))


def main(argv: Iterable[str]) -> int:
    args = parse_args(argv)
    validator = Validator(mode=args.mode)

    check_required_files(validator)
    check_install_script_references(validator)
    check_inventory(validator)
    check_secrets_file(validator)
    check_foundation_cli_binary(validator)
    check_kweaver_online_defaults(validator)
    check_offline_assets(validator)
    check_placeholder_scripts(validator)
    check_tooling(validator)
    smoke_path_check(validator)
    helm_checks(validator)
    ansible_checks(validator)
    runtime_deep_checks_notice(validator)

    print(f"Validation mode: {args.mode}")
    print(f"Repository root: {REPO_ROOT}")
    print()
    validator.print_summary()
    return 1 if validator.has_failures() else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
