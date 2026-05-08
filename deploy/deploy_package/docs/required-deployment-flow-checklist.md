# AnyBackup Agent end-to-end deployment checklist

This checklist is the required acceptance path for the integrated deployment script.
Do not declare a deployment successful unless every enabled item below either completed
successfully or was explicitly disabled by configuration for the current run.

## Required order and gates

1. Kubernetes and base middleware
   - If Kubernetes already exists and is healthy, reuse it.
   - If Kubernetes is absent, bootstrap it before this package continues.
   - The package exposes this as `k8s_cluster_bootstrap_command`; when it is
     empty and no cluster exists, the run must fail instead of silently skipping.
   - Verify the four V9 middleware components: PostgreSQL, RabbitMQ, Redis, and OpenSearch.
   - Verify there is only one V9 middleware set. Do not leave both `v9-infra-*` and legacy `v9-*` workloads running.

2. KWeaver Core
   - Clone `https://github.com/kweaver-ai/kweaver-core.git`.
   - Check out `release/0.6.0`.
   - Run the official atomic command from the upstream `deploy` directory.
   - KWeaver Core success is determined by that command's exit code.

3. KWeaver runtime compatibility
   - Inject `bin/foundation-cli` into the KWeaver sandbox image before Agent content and business services.
   - Use the same-tag sandbox image replacement only when the live sandbox image pull policy is not `Always`.
   - Verify the rebuilt sandbox image contains `/usr/local/bin/foundation-cli`.
   - Apply the temporary `mf-model-api` image override:
     `swr.cn-east-3.myhuaweicloud.com/kweaver-ai/dip/mf-model-api:0.6.0`.
   - Verify the `kweaver/mf-model-api` Deployment is rolled out with that exact image.

4. Foundation
   - Supported modes: `integrated`, `separated`, and `external`.
   - Integrated mode installs Foundation on the same host and requires an explicit `foundation.self_ip`.
   - Separated mode requires the operator to provide the Foundation host IP/access endpoints explicitly.
   - External mode does not install Foundation; it only consumes existing Foundation endpoints.
   - Distinguish install IP from access endpoint:
     `foundation.self_ip` is passed to the official installer, while
     `foundation.endpoint` is the Core Agent/Foundation CLI endpoint.
   - Default endpoint resolution is
     `https://<foundation.access_host|foundation.self_ip>:9600`; override it
     with `--foundation-endpoint`, `foundation_endpoint`, or
     `FOUNDATION_CLI_ENDPOINT` when the public/access address differs.
   - After Foundation is installed, obtain AK/SK from the Foundation web
     console and inject them through hidden prompts or `FOUNDATION_CLI_AK` /
     `FOUNDATION_CLI_SK`; do not provide AK/SK before Foundation exists.
   - Automation may copy, extract, call the official installer, and verify. It must not modify the Foundation product package.
   - Alpha default: install FoundationClient on the same host as FoundationServer.
     FoundationClient is separate from the sandbox `foundation-cli` binary.
   - Install the FoundationClient MySQL runner before releasing business
     services. The current runner package source is
     `https://ftp.anybackup.ai/MySQL-Linux_el7_x64-8.0.9.0-20251231-release-zh_CN-ABNormal-378.tar.gz`.

5. Knowledge data import
   - Import backup rule knowledge into PostgreSQL.
   - Import recovery experience knowledge into PostgreSQL.
   - Verify expected tables and minimum rows before BKN deployment.

6. KWeaver data connections
   - Create/discover the backup rule Vega catalog.
   - Create/discover the recovery experience Vega catalog.
   - Foundation OpenSearch must be exposed to KWeaver through the internal HTTP proxy because the KWeaver connector cannot consume Foundation HTTPS directly.
   - Foundation MariaDB and knowledge PostgreSQL connection values must come from controlled secrets, not hard-coded plaintext.
   - The full integrated path must create KWeaver datasource/dataview objects by default, including `HyperBackupMgmServiceDB.protect_object`.
   - For KWeaver Core-only installs without the Etrino optional package, explicitly set `agent_content_vega_skip_kweaver_data_views=true`. In that mode, Vega catalogs are still created, but KWeaver datasource/dataview creation is skipped because the PostgreSQL connector is unavailable.

7. BKN deployment
   - Deploy backup and recovery BKNs after data connections are present.
   - The BKN IDs and data connection IDs must match the target environment's generated IDs.
   - Use `bkn push` through KWeaver tooling or the deploy orchestrator.

8. ContextLoader
   - Import the ContextLoader toolbox package that matches the installed KWeaver version.
   - Import both packaged ADP files when present:
     `context_loader_toolset.adp` and `execution_factory_tools.adp`.
   - Verify the imported toolbox is exportable through KWeaver's impex API.

9. AnyBackup CLI skills
   - Import and publish all seven skills: `client`, `job`, `mysql`, `policy`, `protect`, `storage`, and `timepoint`.
   - Each uploaded zip must have `SKILL.md` at the zip root.
   - Registration alone is not enough. The script must publish each skill.

10. Model configuration
    - Configure LLMs and small models before importing Agents.
    - API keys and database passwords must come from encrypted or controlled secret injection.
    - Do not commit real API keys, database passwords, or platform tokens.

11. Agent deployment
    - Import Agent JSON from `kweaver-agent-config`.
    - Rewrite `tool_id` and `tool_box_id` from the ContextLoader import result.
    - Rewrite LLM IDs/names from the target model mapping.
    - Publish Agents when `agent_content.publish_agents=true`.

12. Business services and ingress
    - Bring up the five services in namespace `anybackup-ai`:
      `api_gateway_service`, `auth_service`, `conversation_service`, `core_agent_service`, and `web_service`.
    - All five business services must stay `ClusterIP`.
    - The only external entry is Ingress/NodePort to `agent-web`.
    - Do not expose backend services as NodePort and do not expose `/api` directly to `api-gateway-service`.

The `full` install profile must run the Agent content stage before final verification.
The verifier checks Agent content state artifacts, so it must not run directly after
business service release unless Agent content has already been imported in the same run.

## Current scripted verification

The final `verify` stage now checks:

- V9 middleware StatefulSets are rolled out.
- KWeaver running pods are Ready.
- Configured KWeaver image overrides, including `mf-model-api`, are applied.
- The sandbox overlay image contains `foundation-cli` when overlay was applied.
- Business service Kubernetes Services are `ClusterIP`.
- Public Ingress `v9-web` targets `agent-web` only.
- KWeaver CLI can still access the BKN API.
- Agent content state artifacts exist for enabled model, BKN, skill, and Agent import steps.
- The cluster smoke script still runs after these deployment-specific gates.

## 2026-05-08 note: recovery Vega and Etrino

On the 108 integrated validation path, `kweaver ds connect postgresql ...` returned:

```text
Connector 'PostgreSQL' is not supported in the current installation. Please install the Etrino optional package to enable support for this connector.
```

This is not a Foundation connection failure. In that run, Foundation MariaDB authentication was valid, recovery PostgreSQL data import had completed, and Vega catalogs had already been created. The failure happened when KWeaver tried to create datasource/dataview objects.

Full integrated installs must install or verify the KWeaver Etrino optional package before DataView creation. The deployment uses KWeaver's official installer:

```text
<kweaver-core>/deploy/scripts/services/etrino.sh
```

The required ready workloads are:

- `vega-calculate-coordinator`
- `vega-calculate-worker`
- `vega-metadata`
- `vega-datanode`
- `vega-namenode-master`

The script verifies these workloads after the official installer and checks them again before the no-log recovery Vega task so the operator sees a clear prerequisite error instead of a censored Ansible failure. `agent_content_vega_skip_kweaver_data_views=true` remains only a temporary Core-only workaround; it skips KWeaver DataViews and is not a full integrated deployment closure.
