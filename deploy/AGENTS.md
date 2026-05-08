# AnyBackup Agent Deployment Guide Index

This `deploy` directory is the canonical home for AnyBackup Agent integrated deployment work.
Historical absolute paths in older notes may differ by machine; prefer repository-relative paths from this directory.
Do not continue deployment development in `E:\Code\script\anybackup-agent-release`; that directory was only a temporary release workspace.

## Progressive Reading

Use progressive disclosure when handing this project to another AI or engineer:

1. Start here for project background, source boundaries, and non-negotiable constraints.
2. Read `doc/integrated-deployment-flow.md` for the complete end-to-end action flow.
3. Read `doc/anybackup-agent-deployment.md` for implementation notes and historical decisions.
4. Read `doc/kweaver-model-config.md` before changing LLM or small-model deployment behavior.
5. Read `deploy_package/deploy_todo.md` for only the gaps that are still open.
6. Read `deploy_package/ansible/group_vars/all.yml` for live defaults and feature flags.
7. Read the Ansible entry roles only when changing behavior:
   - `deploy_package/ansible/roles/deploy-services/tasks/main.yml`
   - `deploy_package/ansible/roles/deploy-agent-content/tasks/main.yml`
   - `deploy_package/ansible/roles/internal`

## Source Boundaries

The runnable package lives in `deploy_package`.

Canonical source inputs are:

- Helm charts: `helm`
- Service source code: `../Agent/service` and `../Agent/portal`
- AnyBackup CLI skills: `../CLI/skill`
- KWeaver runtime skills: `../Agent/skills`
- Backup and recovery BKN assets: `../Agent/knownledge`

`deploy/helm` is the only chart source for V9 infra and the five business services.
Do not reintroduce or edit `deploy/deploy_package/helm-chart/anybackup-agent` as a development source.
Runtime artifacts, image tarballs, old packages, and one-off transfer files belong under `deploy/tmp/`.

## Deployment Guardrails

1. Keep deployment changes under `deploy/` unless the deploy side cannot solve the issue.
2. KWeaver Core success is determined by the upstream official install command exit code.
3. Foundation is a complete product. Automation may copy, extract, install, uninstall, and verify it, but must not modify Foundation package contents or installer scripts.
4. Never hard-code passwords, AK/SK, API keys, KWeaver tokens, database credentials, generated values, command examples, or logs.
5. Foundation AK/SK is obtained manually from the Foundation web console and injected only through hidden input, environment variables, or Kubernetes Secrets.
6. Foundation MariaDB/Vega password is separate from Foundation AK/SK and is only used for DataView creation.
7. `foundation-cli` sandbox injection happens after KWeaver Core succeeds and before business services are released. Keep the generated Dockerfile compatible with older Docker engines; do not use BuildKit-only syntax such as `COPY --chmod`.
8. The temporary `mf-model-api` image override stays explicit until the upstream alpha compatibility issue is retired.
9. The only external application entrypoint is `agent-web`; backend services remain `ClusterIP`.
10. Business service runtime Secrets must be normal Helm resources, not Helm hooks.
11. Foundation uninstall must also remove extracted FoundationServer/FoundationClient roots and the FoundationClient systemd unit so a later reinstall is clean.
12. BKN backend must enable default small-model usage before BKN/ContextLoader validation; details live in `doc/anybackup-agent-deployment.md`.
13. In KWeaver installs without `business-system-service`, deployment must reconcile `bkn-backend`, `agent-operator-integration`, and `agent-factory` before their BKN/ContextLoader/Agent steps.
14. KWeaver model deployment is configured through `deploy_package/kweaver-llm-config/models.json`; it binds exactly one LLM role and two small-model roles (`embedding`, `reranker`). API keys are supplied through environment variables or equivalent secret injection, never through packaged JSON or adapter code.

## Verification

After deployment-script changes, run from the repository root:

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
python -m unittest discover -s deploy\deploy_package\tests -v
git diff --check -- deploy
```

Before handing a package to another machine, package from the canonical AnyBackup repository checkout, not from an old release workspace.
