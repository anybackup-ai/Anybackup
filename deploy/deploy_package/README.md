# AnyBackup Agent V9 Release Package

Sandbox overlay note: the full deploy now injects the Linux amd64
`bin/foundation-cli` into the current KWeaver `python-basic` sandbox image after
KWeaver Core succeeds and before the 5 business services are released. Build the
binary from `E:\Code\Service\foundation_cli` with
`PowerShell -ExecutionPolicy Bypass -File scripts\build-foundation-cli.ps1`
before packaging. Details:
`docs/操作文档/sandbox-overlay-current-behavior.md`.

这个发布包默认执行一体化部署。KWeaver Core 已改为在线部署：脚本会从 `https://github.com/kweaver-ai/kweaver-core.git` 获取源码，切换到 `release/0.6.0`，进入 `deploy` 目录后只安装 KWeaver Core。默认流程不再使用 `proton-cli`、Proton 离线包或 KWeaver Core 离线应用包。

## 默认部署流程

```bash
./install.sh
```

执行顺序：

1. `prepare`
2. `network-preflight`
3. `deploy-services`
4. `publish-network`
5. `verify`

`deploy-services` 内部编排：

1. 部署业务侧基础组件 `v9_infra`
   - PostgreSQL
   - RabbitMQ
   - Redis
   - OpenSearch
2. 在线部署 KWeaver Core
   - `git clone https://github.com/kweaver-ai/kweaver-core.git`
   - checkout `release/0.6.0`
   - 进入 `deploy` 目录
   - 执行 `./deploy.sh kweaver-core install`
3. KWeaver Core 成功后执行运行时补齐动作
   - 注入 `bin/foundation-cli` 到 KWeaver sandbox 镜像
   - 幂等确认或替换 `mf-model-api` 临时镜像
   - 安装或校验 Foundation
   - 导入 Agent 内容：知识库数据、Vega 数据连接、BKN、ContextLoader、AnyBackup CLI skills、模型配置、Agent JSON
4. 完整模式下部署 `anybackup-ai` 命名空间下的 5 个业务服务
   - `agent-web`
   - `api-gateway-service`
   - `auth-service`
   - `conversation-service`
   - `core-agent-service`
5. 发布唯一公网入口并验收

## 关键约束

- KWeaver 侧只安装 KWeaver Core，不安装其他 KWeaver 产品线。
- KWeaver Core 阶段只认 `./deploy.sh kweaver-core install` 的退出码：`0` 表示成功，非 `0` 表示失败。
- 109 alpha/demo 环境中，KWeaver admin 首次改密后统一使用 `V9_KILL_POLICY`；后续 `agent-content-only` 重跑时用它作为 `--kweaver-cli-password`。
- 公网入口只允许访问 `agent-web`。
- 除 `ingress-nginx-controller` 使用 `NodePort 30080/30443` 外，业务服务全部保持 `ClusterIP`。
- 不为 `api-gateway-service`、`auth-service`、`conversation-service`、`core-agent-service` 开 `NodePort`。
- 不创建 `/api -> api-gateway-service` 的公网 Ingress 直连规则。
- `internal/sandbox_overlay` 在完整部署中默认开启，位于 KWeaver Core 成功之后、5 个业务服务发布之前；它不参与 KWeaver Core 成功判定。
- AnyBackup CLI skills 不只是注册，还必须发布；脚本默认使用 `kweaver skill set-status <skill-id> published`，并在 KWeaver 0.6.0 缺少 skill 发布表时先补齐兼容表。顶层 `install.sh` 可通过 `--agent-content-foundation-cli-skills-publish` 和 `--agent-content-foundation-cli-skills-ensure-publish-schema` 控制这两个动作。

公网入口固定为：

```text
外部用户 -> http://<node-ip>:30080 -> ingress-nginx -> agent-web
```

## 关键目录

- `ansible/`
  - 一体化部署主流程
- `ansible/roles/internal/kweaver_online_install/`
  - KWeaver Core 在线部署角色
- `helm-chart/`
  - 业务 Helm Chart
- `images/`
  - 业务服务镜像 tar
- `scripts/`
  - 本地验证和清理脚本
- `docs/操作文档/deployment-guide.md`
  - 详细部署说明

## 说明

- `v9_infra` 和 KWeaver 自身依赖是两套不同用途的资源平面，不要混淆或互相替代。
- `v9-infra-*` StatefulSet 是业务侧中间件的正式实例；如果现场残留旧的 `v9-postgres`、`v9-rabbitmq`、`v9-redis` Deployment，应删除残留并让同名 Service selector 指向 `v9-infra-*`。
- 完整业务部署必须看到 `anybackup-ai` 中 5 个业务服务全部 Running。
- 详细步骤见 [deployment-guide.md](docs/操作文档/deployment-guide.md)。

## Required deployment gates

The acceptance checklist for the current end-to-end flow lives in
`docs/required-deployment-flow-checklist.md`. A deployment is not successful
until every enabled gate in that checklist is verified: K8s/base middleware,
KWeaver Core, sandbox `foundation-cli`, temporary `mf-model-api`, Foundation,
knowledge data, data connections, BKN, ContextLoader, AnyBackup CLI skills,
models, Agents, and the five business services with `agent-web` as the only
external ingress target.

The full integrated path creates KWeaver DataViews by default, including the
Foundation `HyperBackupMgmServiceDB.protect_object` view used by recovery BKN.
For KWeaver Core-only environments that do not include Etrino/PostgreSQL
datasource support, explicitly pass
`./install.sh --agent-content-vega-skip-kweaver-data-views true`.

## Foundation endpoint and client defaults

For the alpha integrated path, FoundationServer and FoundationClient default to
the same host. `foundation.self_ip` is the IP passed to the official Foundation
installer; `foundation.endpoint` is the endpoint consumed by Core Agent Service
and `foundation-cli`, defaulting to
`https://<foundation.access_host|foundation.self_ip>:9600`.

Use `--foundation-access-host` or `--foundation-endpoint` when separated or
external Foundation access differs from the install IP. After Foundation is
installed, obtain AK/SK from the Foundation web console and provide them through
hidden prompts or `FOUNDATION_CLI_AK` / `FOUNDATION_CLI_SK` before the five
business services are released.

## Uninstall

`uninstall.sh` sits next to `install.sh` and removes package-owned runtime
artifacts while keeping Kubernetes itself. Always preview first:

```bash
bash ./uninstall.sh --dry-run
bash ./uninstall.sh --yes
```

Foundation is first removed through its official installer root:
`/opt/backupsoft/FoundationServer/uninstall.sh` by default. After the official
uninstall returns, the script also removes the `FoundationServer` root directory
so stale install markers cannot make the next run skip a real install.
FoundationClient follows the same rule: run its uninstall script when present,
stop/disable/remove `ABClientService.service`, then remove the
`FoundationClient` root. Override paths with
`--foundation-install-root <path>` and `--foundation-client-install-root <path>`
when they differ. Downloaded package tarballs are kept unless
`--purge-packages` is specified.
