---
name: kweaver-core-offline-deploy
description: Use when executing or verifying the AnyBackup Agent release deployment flow with KWeaver Core, Foundation, sandbox, V9 infra, and business services.
---

# AnyBackup Agent Deploy

The historical offline KWeaver flow using `proton-cli`, Proton offline packages, and KWeaver Core offline application packages is retired from the default release flow.

## Current Default Flow

1. Run package preflight checks.
2. Install or verify Kubernetes. If a usable Kubernetes cluster already exists, do not reinstall it.
3. Deploy or verify the 4 V9 infrastructure components in `v9-system`: PostgreSQL, RabbitMQ, Redis, and OpenSearch. The operation must be idempotent and must not create duplicate `v9-*` and `v9-infra-*` stacks.
4. Clone `https://github.com/kweaver-ai/kweaver-core.git`.
5. Check out `release/0.6.0`.
6. Enter the upstream `deploy` directory.
7. Install KWeaver Core only:
   - prefer `./deploy install core` when the repository provides `deploy`
   - otherwise run `./deploy.sh kweaver-core install`
8. Inject `foundation-cli` into the KWeaver sandbox image before Agent content and business services are released.
9. Apply the temporary KWeaver image override for `mf-model-api` when configured. The current alpha target image is `swr.cn-east-3.myhuaweicloud.com/kweaver-ai/dip/mf-model-api:0.6.0`; if the deployment already uses that image, skip.
10. Install or verify Foundation, according to the configured deployment mode.
11. Deploy AnyBackup Agent content: import knowledge data, create KWeaver Vega data connections, push BKNs, import ContextLoader toolboxes, import AnyBackup CLI skills, configure LLM/small-model entries, and create/publish KWeaver Agents.
12. Prepare internal KWeaver runtime networking.
13. Build/import or pull the 5 business service images.
14. Release the 5 business services into `anybackup-ai`: `api_gateway_service`, `auth_service`, `conversation_service`, `core_agent_service`, and `web_service`.
15. Publish ingress so external traffic reaches `agent-web` only.
16. Verify the final cluster state and run an Agent smoke test.

KWeaver Core success is atomic: the official install command exit code is the success signal. Do not patch upstream deploy scripts, create ad hoc image aliases, or reinterpret the result with extra pod waits.

## Foundation Rules

Foundation is a complete traditional software product. Automation may copy, extract, install, and verify it, but must not modify the Foundation package contents or installer scripts.

Official install command template:

```bash
./install.sh --product=Enterprise --server-type=NONE --mgm-type=ControlNode --server-mode=All --self-ip=<foundation-self-ip> --clustertype=single
```

`foundation.self_ip` is a required explicit input. Do not hard-code it. On cloud hosts, use the Foundation host's private/internal IP unless the product documentation says otherwise.

Deployment modes:

- `integrated`: Foundation runs on the same host as K8s/KWeaver/V9 services. Alpha 109 uses `self_ip=192.168.40.109`.
- `separated`: Foundation runs on a different host. Run the installer on that host and feed its access addresses into KWeaver data connections and business service configuration.
- `external`: Foundation already exists. Do not install; only verify and consume its endpoints, database, OpenSearch, and credentials.

Endpoint handling:

- `foundation.self_ip` is the IP passed to the Foundation official installer.
- `foundation.access_host` is the address KWeaver and business services should use to reach Foundation. In integrated mode it defaults to `foundation.self_ip`; in separated/external mode the operator should set it explicitly.
- `foundation.endpoint` is the Foundation CLI/API endpoint consumed by Core Agent Service. It defaults to `https://<foundation.access_host|foundation.self_ip>:9600`, and can be overridden with `--foundation-endpoint`, `foundation_endpoint`, or `FOUNDATION_CLI_ENDPOINT`.
- Core Agent Service must receive `FOUNDATION_ENDPOINT`, `FOUNDATION_AK`, and `FOUNDATION_SK` through Helm values/Kubernetes Secret before the five business services are released.
- AK/SK cannot be known before Foundation is installed. In the alpha flow, install/verify Foundation first, then pause or prompt for AK/SK obtained from the Foundation web console, then continue idempotently.

FoundationClient:

- FoundationClient is the backup client/runner runtime, not the `foundation-cli` binary injected into the KWeaver sandbox image.
- In the alpha release, install FoundationClient on the same host as FoundationServer by default.
- Install FoundationClient after Foundation succeeds and before sandbox overlay/business service release.
- The FoundationServer package should provide `FoundationClient-Linux_el7_x64-latest.tar.gz` under `FoundationServer/data/softdownload/Linux_el7_x64/`.
- Install the MySQL runner package with `client_cli install MySQL --path=<mysql-package-absolute-path>`. The current package source is `https://ftp.anybackup.ai/MySQL-Linux_el7_x64-8.0.9.0-20251231-release-zh_CN-ABNormal-378.tar.gz`.

Idempotence:

- Not installed: run the official installer.
- Installed and healthy: skip.
- Installed but key settings differ, including `self_ip`: fail and require operator confirmation.

## Sandbox Rules

Run sandbox overlay after KWeaver Core succeeds and before releasing the 5 business services.

- Inject Linux amd64 `bin/foundation-cli` into the current KWeaver `python-basic` sandbox/sandbox-executor image.
- Prefer the simple same-tag replacement only when the sandbox image pull policy is not `Always`.
- Do not update KWeaver database template rows for the simple replacement path.
- Sandbox overlay is not part of KWeaver Core success.

## Agent Content Rules

Agent content deployment runs after KWeaver Core, sandbox image injection, the `mf-model-api` temporary image override, and Foundation verification, but before the 5 business services are released.

- Import backup and recovery knowledge data before creating Vega data connections.
- Create Foundation OpenSearch access through the V9 infra HTTP proxy; do not modify Foundation OpenSearch.
- Create Foundation MariaDB and knowledge PostgreSQL Vega catalogs before BKN push.
- BKN data view IDs must resolve to the target environment's Vega data views; prefer logical names over environment-specific UUIDs.
- Import ContextLoader toolboxes from KWeaver-version-matched `.adp` packages before creating Agents.
- Import AnyBackup CLI skills before creating Agents that reference Foundation CLI capabilities. Current required skills are `foundation-cli-client`, `foundation-cli-job`, `foundation-cli-mysql`, `foundation-cli-policy`, `foundation-cli-protect`, `foundation-cli-storage`, `foundation-cli-timepoint`, and `ag-ui-response`.
- Register those skills with `kweaver skill register --zip-file <skill.zip> --source custom`; the zip root must contain `SKILL.md` directly.
- Publish every imported/reused AnyBackup CLI skill with `kweaver skill set-status <skill-id> published`. On KWeaver 0.6.0, if the runtime image requires `t_skill_release` and `t_skill_release_history` but the upstream migration did not create them, the integrated installer must first create the missing compatibility tables through KWeaver MariaDB, then use the KWeaver CLI publish command. Do not mark a skill deployment complete while it is still `unpublish`.
- For skills with Python dependencies, importing and publishing the skill is not enough. After skill import, install dependencies from each skill's `requirements.txt` into a running KWeaver sandbox session through `POST /api/v1/sessions/<session_id>/dependencies/install` on `sandbox-control-plane`. The current `ag-ui-response` skill requires `aio-pika>=9.5.0`; use an explicit PyPI mirror URL, defaulting to `https://pypi.tuna.tsinghua.edu.cn/simple`, and fail clearly if no running sandbox session can be resolved.
- On KWeaver 0.6.0 alpha, the default `admin` login can be valid while still lacking Execution Factory `skill/*` create/publish permission. Before `kweaver skill register`, the integrated installer may call the private `authorization` service in the KWeaver namespace, first ensure the `skill` resource type exists through `PUT /api/authorization/v1/resource_type/skill`, and then create an idempotent wildcard `skill` policy for the current logged-in user. Read the current user from the saved `kweaver auth whoami/status` session without adding `--base-url`, because auth subcommands with a transient base URL require `KWEAVER_TOKEN`. This is an alpha compatibility bootstrap, not a replacement for the normal permission model.
- On KWeaver 0.6.0 alpha, `kweaver skill register` uploads the zip through Execution Factory and requires an OSS Gateway default storage. If `oss-gateway-backend` returns `OSSGatewayDefaultStorageNotFound`, the integrated installer should idempotently create a default storage backed by the in-cluster MinIO service before registering skills. Also ensure the target MinIO bucket exists; otherwise upload can fail with `OSSGatewayFailed` / `The specified bucket does not exist`. Do not log MinIO credentials.
- Configure both LLM and small-model entries before Agent import. Do not skip `adapter=true` rerank models. On KWeaver 0.6.0, the public adapter small-model API has conflicting validation; the current compatibility path is API placeholder creation followed by a targeted `t_small_model` update through KWeaver MariaDB, without printing credentials or adapter code.
- Replace Agent `tool_id`, `tool_box_id`, skill IDs, LLM IDs, and model names with target-environment values before create/publish.

## Secret Rules

Never hard-code real database, OpenSearch, model, or platform passwords in repository files, public docs, examples, logs, or command transcripts.

- Use encrypted secret storage for deploy-time values, such as Ansible Vault or an approved encrypted secret file.
- Keep example files on placeholders such as `CHANGE_ME`.
- Mark Ansible tasks that pass secrets with `no_log: true`.
- Temporary remote files containing secrets must be mode `0600` and removed or overwritten when no longer needed.

## Ingress Rules

External ingress exposes `agent-web` only.

- Keep `agent-web`, `api-gateway-service`, `auth-service`, `conversation-service`, and `core-agent-service` as `ClusterIP`.
- Do not create NodePort services for business backends.
- Do not expose direct `/api` ingress to `api-gateway-service`.

## Idempotence Rules

- Not installed: install.
- Same version and healthy: skip by default.
- Same version and unhealthy: replay the online install.
- Different version: fail unless `kweaver_online.allow_upgrade=true`.

`kweaver_online.force_reinstall=true` forces a replay even when the same version is already healthy.
