# AnyBackup Agent Integrated Deployment Notes

Last updated: 2026-05-07

This document captures what the current integrated deployment is trying to do, what has already been implemented in scripts, and what is still unfinished. The short operational rules live in `../AGENTS.md`; the live remaining-task list is still `../deploy_package/deploy_todo.md`.

## Canonical Repository

All future development happens in:

```text
E:\Code\Service\Anybackup
```

The old workspace below is not the canonical development source anymore:

```text
E:\Code\script\anybackup-agent-release
```

When moving to another computer, copy or archive `E:\Code\Service\Anybackup` as the single project root.

## Current Package Layout

Important paths:

| Path | Purpose |
| --- | --- |
| `deploy/deploy_package/install.sh` | Main integrated deployment entrypoint used on target hosts. |
| `deploy/deploy_package/uninstall.sh` | Cleanup script for package-owned resources except Kubernetes itself. |
| `deploy/deploy_package/ansible` | Ansible orchestration for K8s checks, KWeaver, Foundation, content, and services. |
| `deploy/deploy_package/agent-content` | Packaged Agent content installers, BKN assets, skills, model config, ContextLoader assets. |
| `deploy/deploy_package/helm-chart/anybackup-agent/charts` | Packaged Helm charts used by the installer. |
| `deploy/helm` | Canonical chart source inside the Anybackup repo. |
| `Agent/service` | Business service source directories used to build images. |
| `Agent/portal` | Web frontend source used to build `agent-web`. |
| `CLI/skill` | AnyBackup CLI skills imported into KWeaver. |
| `Agent/skills/ag-ui-response` | KWeaver skill with Python dependency installation requirements. |
| `Agent/knownledge` | Backup and recovery BKN source assets. |

## Main Deployment Flow

The current `install.sh --local` flow is staged as follows:

1. Prepare environment and run preflight checks.
2. Bootstrap or verify Kubernetes idempotently.
3. Run K8s, ingress, and network preflight.
4. Run `deploy-services` for platform services.
5. In the `full` profile, run `deploy-agent-content`.
6. In the `full` profile, run `app-services`.
7. Publish the external network entrypoint.
8. Verify the deployment.

Inside `deploy-services`, the current script order is:

1. Deploy V9 infrastructure: PostgreSQL, RabbitMQ, Redis, OpenSearch.
2. Install KWeaver Core from upstream source.
3. Install internal compatibility services needed by KWeaver 0.6.0.
4. Apply configured KWeaver image overrides.
5. Configure KWeaver CLI for the freshly installed local platform.
6. Install or verify Foundation according to deployment mode.
7. Install or verify FoundationClient.
8. Overlay `foundation-cli` into the KWeaver sandbox image.
9. Prepare internal runtime networking.

After `deploy-services` succeeds, the `full` profile must run `deploy-agent-content` before business services are released. The Agent content stage imports models, knowledge data, DataViews, BKNs, ContextLoader, skills, and Agents. The `app-services` stage then builds/imports business images from the Anybackup repository source and releases the five business services with Helm. Business image build defaults are derived from the full repository checkout: `anybackup_repo_root` defaults to `deploy/deploy_package/../..`, and `business_image_builds` must include `conversation-service`, `core-agent-service`, and `agent-web`. If this list is empty, the deployment should fail before Docker build with a clear source-root error rather than later during `agent-web` resolution.

Agent content can also be run separately with:

```bash
./install.sh --local --profile agent-content-only
```

That profile does not touch V9 infra or the five business service Helm releases.
It is the preferred resume path after a failure inside knowledge data,
DataView, BKN, ContextLoader, skill, or Agent import steps. Because packages may
be prepared from a Windows checkout, copied Agent shell scripts are normalized
to LF on the target before execution.

## Deployment Profiles

### full

The default end-to-end path. It installs or verifies Kubernetes, V9 infra, KWeaver Core, Foundation, FoundationClient, sandbox overlay, Agent content prerequisites, business images, business services, ingress, and verification.

### kweaver-core-only

Used when validating KWeaver Core installation behavior without releasing the full business stack.

### agent-content-only

Used after KWeaver and Foundation are already available. It imports or updates Agent content without redeploying V9 infra or business Helm releases.

## Business Domain Compatibility

KWeaver 0.6.0 may be deployed without `business-system-service` in the current ISF path. In that case, resource binding calls fail with DNS timeout and surface as HTTP 500 during BKN push or ContextLoader toolbox import.

The deployment reconciles this automatically:

- `bkn-backend`: set `BUSINESS_DOMAIN_ENABLED=false` when `business-system-service` is absent.
- `agent-operator-integration`: set `BUSINESS_DOMAIN_ENABLED=false` when `business-system-service` is absent, before ContextLoader import.
- `agent-factory`: set `BUSINESS_DOMAIN_ENABLED=false` when `business-system-service` is absent, before Agent create/publish.

If a later environment provides `business-system-service`, the same reconciliation should keep or restore `BUSINESS_DOMAIN_ENABLED=true`.

## BKN Default Small Model

ContextLoader and BKN data-query paths require BKN backend to allow default
small-model usage. KWeaver 0.6.0 currently ships `bkn-backend-cm` with
`server.defaultSmallModelEnabled: false`, which can surface as BKN query errors
or small-model failures after BKN content is deployed.

The deployment reconciles this automatically after KWeaver model configuration
and before BKN/DataView/ContextLoader import:

- Read ConfigMap `bkn-backend-cm` in the KWeaver namespace.
- Update only `bkn-backend-config.yaml` so `server.defaultSmallModelEnabled`
  is `true`.
- Preserve all other ConfigMap data.
- Restart `deployment/bkn-backend` with `kubectl rollout restart` and wait for
  rollout completion.

The behavior is controlled by `agent_content.bkn_small_model` in
`deploy_package/ansible/group_vars/all.yml`.

## Foundation Rules

Foundation is a traditional complete product. The deployment may invoke official scripts, but must not alter Foundation package contents.

Official install command template:

```bash
./install.sh --product=Enterprise --server-type=NONE --mgm-type=ControlNode --server-mode=All --self-ip=<foundation-self-ip> --clustertype=single
```

The real package URL is:

```text
https://ftp.anybackup.ai/FoundationServer-Linux_el7_x64-9.0.0.0-alpha1-20260430-release-zh_CN-3.tar.gz
```

By default the installer first searches `/opt/backupsoft/FoundationServer-Linux_el7_x64-9.0.0.0*.tar.gz`. If a matching FoundationServer package already exists there, it is reused. If no matching package exists, the installer downloads the package URL above into `/opt/backupsoft/<url-basename>`. Customers should not need to pass `--foundation-package-path` in the normal path. For validation, a predownloaded package may still be placed elsewhere and passed through `--foundation-package-path` as an escape hatch.

Deployment modes:

| Mode | Meaning |
| --- | --- |
| `integrated` | Foundation runs on the same host as K8s, KWeaver, and V9 services. |
| `separated` | Foundation runs on another host. The operator must provide Foundation access host or endpoint. |
| `external` | Foundation already exists. The installer consumes endpoints and credentials but does not install Foundation. |

`--foundation-access-host` is the host used by KWeaver DataViews, FoundationClient, and Core Agent Foundation endpoint defaults. In separated mode, it must point to the Foundation host, not the K8s host.

## FoundationClient Rules

FoundationClient is not `foundation-cli`. It is the backup client or runner side component.

Current intended install flow:

1. Detect the target architecture for the BasicRunner package directory under FoundationServer.
2. Take BasicRunner from:

```text
<FoundationServer>/data/softdownload/<arch>/Basic-<arch>-latest.tar.gz
```

3. Extract and run BasicRunner's official `install.sh`.
`ClientService/install.sh` in the BasicRunner package may be a shell script without a shebang. Automation must invoke it explicitly through `bash ./install.sh`; direct Ansible `command: ./install.sh` can fail with `Exec format error`.
4. Update:

```text
foundationcli/etc/ClientService/BasicRunner/all_runner_info.config
```

so the `MySQL` runner is known.

5. Install the MySQL runner through `client_cli`:

```bash
./client_cli install MySQL --path=<mysql-package-absolute-path>
```

The MySQL runner URL is intentionally fixed for the alpha version:

```text
https://ftp.anybackup.ai/MySQL-Linux_el7_x64-8.0.9.0-20251231-release-zh_CN-ABNormal-378.tar.gz
```

Do not require customers to pass `--foundation-client-package-path` in the normal path. The script should download or use the default cached path. The manual path is only a validation escape hatch.

## Foundation AK/SK Rules

Foundation AK/SK must be generated manually in the Foundation web console after Foundation is installed.

This means the one-click flow may have a human checkpoint:

1. Install or verify Foundation.
2. Stop before releasing Core Agent Service and business services if AK/SK is missing.
3. The user logs into Foundation and creates or copies AK/SK.
4. The same installer is rerun with credentials supplied through environment variables.

Preferred shell pattern:

```bash
export FOUNDATION_CLI_ENDPOINT='https://<foundation-host>:9600'
read -r -s FOUNDATION_CLI_AK
export FOUNDATION_CLI_AK
read -r -s FOUNDATION_CLI_SK
export FOUNDATION_CLI_SK
```

Avoid command-line flags for AK/SK in real runs because shell history and process listings can expose them.

Core Agent Service receives these values through Helm values and a Kubernetes Secret, then forwards them to Agent skill execution through `custom_querys.foundation`.

## Foundation MariaDB And Vega DataViews

Foundation MariaDB/Vega password is not AK/SK. It is used only when KWeaver DataViews are created for Foundation databases.

Alpha behavior:

- Prompt for the password only at the point of use, after Foundation exists.
- Hide the input.
- Default username is `sdba` because 108 did not have `v9agent2`.
- Preflight the credential before running the no-log DataView installer.
- Never write this password into code, docs, generated values, or logs.

108 update as of 2026-05-08:

- `HyperBackupMgmServiceDB` is now present in Foundation MariaDB.
- Keep using the real `HyperBackupMgmServiceDB.protect_object` source in recovery DataViews/BKN references.
- Do not guess-map it to another table.

## KWeaver Etrino Optional Services

KWeaver Core-only does not imply DataView connector readiness. Creating PostgreSQL or MariaDB DataViews through `kweaver ds connect ...` requires the KWeaver Etrino optional package.

For the full integrated path, the deployment calls KWeaver's official optional installer after KWeaver Core succeeds:

```text
<kweaver-core>/deploy/scripts/services/etrino.sh
```

The installer then verifies these KWeaver optional workloads before recovery Vega/DataView creation:

- `vega-calculate-coordinator`
- `vega-calculate-worker`
- `vega-metadata`
- `vega-datanode`
- `vega-namenode-master`

If the optional package is missing, KWeaver may return:

```text
Connector 'PostgreSQL' is not supported in the current installation. Please install the Etrino optional package to enable support for this connector.
```

The deployment also checks these workloads before the no-log recovery Vega task. `--agent-content-vega-skip-kweaver-data-views true` is only a temporary Core-only workaround; it skips KWeaver DataViews and is not a full integrated deployment closure.

## KWeaver Core Rules

KWeaver Core is installed from upstream `kweaver-core` release 0.6.0.

KWeaver Core success is atomic: the upstream official deploy command exit code is the success signal. Sandbox overlay, Agent content, Foundation, business services, and pod-count heuristics must not be folded into the Core success definition.

The flow still needs KWeaver runtime compatibility work around KWeaver 0.6.0 details, including internal compatibility services and image overrides.

Current explicit image override to keep:

```text
swr.cn-east-3.myhuaweicloud.com/kweaver-ai/dip/mf-model-api:0.6.0
```

## Sandbox Overlay

`foundation-cli` must be injected into the KWeaver sandbox image after KWeaver Core succeeds and before business services are released.

Current simple path:

- Use the current KWeaver `python-basic` sandbox image as the base.
- Copy Linux amd64 `bin/foundation-cli` into the image.
- Render the overlay Dockerfile with old Docker compatibility: do not use `COPY --chmod`; switch to `USER root`, then `COPY` and `RUN chmod 0755`.
- Rebuild with the same sandbox image tag when the pull policy allows local image reuse.
- Restart sandbox pods so new sessions use the overlaid image.

Do not change KWeaver database template rows for the simple same-tag replacement path unless product design changes.

## Agent Content Flow

Agent content deployment includes:

1. KWeaver CLI login and business domain setup.
2. KWeaver LLM and small-model configuration from `kweaver-llm-config`.
3. BKN backend `defaultSmallModelEnabled` reconciliation for ContextLoader and BKN query paths.
4. Backup knowledge data import.
5. KWeaver data source and DataView creation.
6. Backup BKN deployment.
7. Recovery Vega data import and DataView creation.
8. Recovery BKN deployment, including the Foundation `HyperBackupMgmServiceDB.protect_object` DataView binding.
9. ContextLoader toolbox import through the agent-operator-integration import API.
10. AnyBackup CLI skill import and publish.
11. `ag-ui-response` skill import plus Python dependency installation into a running sandbox session.
12. Agent JSON import, ID replacement, model ID replacement, tool ID replacement, create, and publish.

The model configuration step invokes `kweaver-admin`, while the earlier login step uses the regular `kweaver` CLI. The deployment task must bridge the current `kweaver` token into `KWEAVER_TOKEN` and `KWEAVER_ADMIN_TOKEN` inside the same process that runs the model installer. The token must not be printed, written to files, or shown in examples.

Before pushing BKN content, the deployment also reconciles the BKN backend business-domain binding mode. If `business-system-service` is present in the KWeaver namespace, `BUSINESS_DOMAIN_ENABLED` should remain `true`. If the service is absent in the current KWeaver 0.6.0 installation, the deploy flow sets `BUSINESS_DOMAIN_ENABLED=false`, waits for the `bkn-backend` rollout, and polls `kweaver bkn list` before calling `kweaver bkn push`.

The ContextLoader toolbox import currently relies on the KWeaver API rather than the CLI because the CLI path did not support it at the time of validation.

The same absent `business-system-service` compatibility applies to later Agent creation. Before invoking the Agent export installer, the deployment reconciles `agent-factory` with `BUSINESS_DOMAIN_ENABLED=false` when the service is absent, waits for rollout, and only then calls `kweaver agent create`.

## Skill Dependency Rule

Normal skill import and publish is not enough for skills with Python dependencies.

The special `ag-ui-response` skill must be packaged with `SKILL.md` at the first zip level and then have its dependencies installed into the sandbox runtime. Current default dependency source is Tsinghua PyPI mirror and may be overridden through deployment variables.

Current dependency:

```text
aio-pika>=9.5.0
```

## Business Services And Ingress

The five business-facing components are released from canonical charts under `deploy/helm`; `deploy/deploy_package/helm-chart/anybackup-agent` is legacy package output and must not be used as a chart source.

Important services:

- `api-gateway-service`
- `auth-service`
- `conversation-service`
- `core-agent-service`
- `agent-web`

`core-agent-service` is special because it receives Foundation endpoint and AK/SK through Helm values and Secret data.

External access should go through the web entrypoint only. Backend services should stay `ClusterIP` unless the product design explicitly changes.

## Current Implemented Items

The following are already represented in the current scripts or package assets:

1. Idempotent Kubernetes bootstrap or verification stage.
2. V9 infra Helm deployment.
3. KWeaver Core online install using upstream release 0.6.0.
4. KWeaver CLI login and platform verification.
5. Foundation install or verification modes.
6. FoundationClient BasicRunner plus MySQL runner install logic.
7. `foundation-cli` sandbox image overlay.
8. KWeaver image override support.
9. Business image build/import from the Anybackup repository source.
10. Helm release of the five services.
11. Ingress/network publication stage.
12. Agent content deployment profile.
13. Backup and recovery BKN package assets.
14. ContextLoader toolbox import.
15. AnyBackup CLI skills import and publish.
16. Special `ag-ui-response` skill and sandbox dependency installation path.
17. `uninstall.sh` for package-owned resources while keeping Kubernetes itself.

## Uninstall Rules

`deploy/uninstall.sh` delegates to `deploy/deploy_package/uninstall.sh`. The uninstall flow keeps Kubernetes itself, but removes package-owned namespaces, Helm releases, runtime paths, KWeaver CLI cache, and Foundation runtime directories.

Foundation cleanup must run the official `FoundationServer/uninstall.sh` when present, then remove the `FoundationServer` root directory. FoundationClient cleanup must run its uninstall script when present, stop/disable/remove `ABClientService.service`, reload systemd, then remove the `FoundationClient` root directory. This prevents stale extracted directories or install markers from making the next integrated install incorrectly skip Foundation or leave Foundation Web services unavailable. Downloaded FoundationServer and MySQL runner tarballs remain in place unless `--purge-packages` is used.
## Current Open Items

Keep `deploy/deploy_package/deploy_todo.md` as the live TODO list. The major open items are:

1. Reconfirm Foundation OpenSearch HTTP proxy and KWeaver Vega catalog creation in a clean integrated run.
2. Replace alpha `sdba` DataView access with a dedicated least-privilege account and managed Secret path.
3. Replace manual sensitive input with a production-grade secret mechanism such as Vault, KMS, Ansible Vault, SealedSecret, or ExternalSecret.
4. Productize image availability for Keycloak, Etrino, KWeaver optional services, and business images, especially for weak-network environments.
5. Remove adapter small-model compatibility workaround after the KWeaver backend API supports the required path cleanly.
6. Run final end-to-end Agent chat smoke test with real model credentials in a clean environment.
7. Repackage only from `E:\Code\Service\Anybackup` before moving to another machine.

## Packaging Rule

When preparing for another machine, archive the whole canonical repository root:

```text
E:\Code\Service\Anybackup
```

Do not package from `E:\Code\script\anybackup-agent-release`.

Exclude normal development noise such as `.git`, `__pycache__`, `*.pyc`, logs, and old generated tar packages unless the transfer explicitly needs them.

### Business Service Helm Release Safety

Application-required Kubernetes Secrets, especially `conversation-service-secrets`, must be rendered as normal Helm resources. They must not be Helm hooks. A pre-upgrade hook with `before-hook-creation` can delete the old Secret before the new revision is healthy; if the upgrade times out, Kubernetes keeps the old ReplicaSet running while the new Pod stays in `CreateContainerConfigError` because the Secret is absent.

Before releasing the five business services, the deploy role checks for Helm releases stuck in `pending-install`, `pending-upgrade`, or `pending-rollback`. If a deployed revision exists, it rolls back to that revision first and then continues the normal `helm upgrade --install` flow.
When copying charts to `/opt/v9-alpha-deploy/charts`, the deploy role removes the package-owned chart target directory first. This is required because Ansible `copy` does not delete files that disappeared from the source chart; stale templates such as an old `nginx-configmap.yaml` can otherwise remain in the remote chart and break future Helm renders.
`conversation-service` runs its migration Job as a Helm pre-install/pre-upgrade hook. Helm runs that hook before ordinary release resources, so the deploy role pre-creates the normal `conversation-service-secrets` resource from the same chart and values before invoking `helm upgrade --install`. The Secret remains a normal Helm-owned resource, not a hook, so a failed upgrade does not remove the Secret needed by existing Pods.
### Ansible Variable Access Safety

When a dictionary key is named like a Python mapping method, such as `items`, use bracket access in Jinja expressions: `some_dict['items']`. Dot access such as `some_dict.items` resolves to the method object and can make Ansible loops fail with `Invalid data passed to loop`.
### KWeaver CLI BKN Readiness Probe

Immediately after the upstream KWeaver Core install command exits, the platform login path can be usable while BKN routes still return transient `503 Service Temporarily Unavailable`. The deploy flow must treat the CLI BKN check as readiness polling, not a single-shot assertion. Configure `kweaver_cli_bkn_api_retries` and `kweaver_cli_bkn_api_delay_seconds` if a target environment needs a longer warm-up window.

The saved KWeaver CLI session must not be considered usable when `auth status` reports an expired token. A stale token can make `kweaver bkn list` fail with `HTTP 401 Unauthorized`; retrying BKN readiness will not fix that, so the deploy flow should re-login with the configured local admin credentials before polling BKN. If login attempts still leave the CLI in an expired-token state, fail before BKN polling and report the login problem directly.

Fresh KWeaver installs can briefly reject HTTP sign-in while the platform is still settling. The login tasks use `kweaver_cli_login_retries` and `kweaver_cli_login_delay_seconds` before falling back to the initial-password rotation path.
