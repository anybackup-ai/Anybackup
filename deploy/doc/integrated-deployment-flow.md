# AnyBackup Agent 完整一体化部署流程

本文沉淀 AnyBackup Agent 当前目标的一体化部署动作。`deploy/AGENTS.md` 只保留项目索引、背景和硬约束；本文件保留完整操作顺序、关键信息和验收边界。

## 总体原则

完整流程不是“部署 KWeaver 后导 BKN/Agent”。目标路径是：先准备 K8s 和基础组件，再部署 KWeaver、Foundation、FoundationClient、Etrino/Vega 可选能力和 sandbox，然后建立数据连接/DataView，再导入 BKN、ContextLoader、skills、Agent，最后构建并发布 5 个业务服务和唯一 web 入口，并在 AK/SK、数据库密码、模型凭证这些点上保持人工安全断点或 Secret 化。

敏感信息禁止写入代码、文档、values、命令示例或日志，包括密码、AK/SK、API key、KWeaver token、数据库凭证和模型凭证。

## 0. 部署前准备

- 校验部署包完整性，必须从当前 AnyBackup 仓库信源打包。
- 确认 `deploy/helm` 是唯一 Helm chart 信源。
- 清理或忽略 `deploy/tmp` 临时文件。
- 准备镜像、FoundationServer 包、FoundationClient MySQL runner 包的下载或缓存策略。
- 确认所有敏感信息只走隐藏输入、环境变量、Secret、Vault/KMS/SealedSecret/ExternalSecret/Ansible Vault 等受控方案。

## 1. 部署或校验 K8s 基础环境

- 如果目标机器已有可用 K8s，则跳过初始化。
- 如果没有可用 K8s，则初始化 K8s、container runtime、CNI、StorageClass 和 Ingress Controller。
- 校验 `kubectl get nodes`、CoreDNS、`ingress-nginx`、`local-path-storage` 等基础组件。

## 2. 部署 V9 四大基础组件

- PostgreSQL。
- RabbitMQ。
- Redis。
- OpenSearch。
- 保持幂等：已安装且健康则跳过，不健康才修复或失败提示。

## 3. 部署 KWeaver Core

- 在线拉取 `kweaver-core`。
- checkout 对应版本，例如 `release/0.6.0`。
- 调用 KWeaver 官方部署命令。
- KWeaver Core 是否成功只看官方命令退出码，不把 sandbox、Agent、业务服务混进 Core 成功判定。
- 配置 KWeaver CLI，完成登录、密码轮换、token 校验和 BKN API readiness polling。

## 4. 安装 KWeaver 可选能力

- 安装或校验 Etrino / Vega calculate optional services。
- 这是创建 PostgreSQL / MariaDB DataView 的前置条件。
- 等待 `vega-calculate-coordinator`、worker、metadata 等组件 ready。
- 弱网环境要考虑镜像预拉取，Etrino 镜像可能很大。

## 5. 替换临时 KWeaver 镜像

- 确认或替换 `mf-model-api` 镜像为：

```text
swr.cn-east-3.myhuaweicloud.com/kweaver-ai/dip/mf-model-api:0.6.0
```

- 这是当前 alpha 兼容要求，后续 upstream 修复后再移除。

## 6. 部署 FoundationServer

支持三种模式：

| 模式 | 说明 |
| --- | --- |
| `integrated` | Foundation 和 K8s/KWeaver/V9 在同一台机器。 |
| `separated` | Foundation 单独机器，用户必须指定 Foundation IP/endpoint。 |
| `external` | Foundation 已存在，只消费 endpoint 和凭证。 |

- `integrated` 模式需要用户指定 `foundation-self-ip`。
- 正常路径不要求用户手动指定 Foundation 包路径。
- 脚本先匹配本地包：

```text
/opt/backupsoft/FoundationServer-Linux_el7_x64-9.0.0.0*.tar.gz
```

- 不存在才下载默认包：

```text
https://ftp.anybackup.ai/FoundationServer-Linux_el7_x64-9.0.0.0-alpha1-20260430-release-zh_CN-3.tar.gz
```

- 只调用 Foundation 官方安装脚本，不修改 Foundation 包内容。

## 7. 部署 FoundationClient

- FoundationClient 不是 `foundation-cli`，它是备份客户端/runner。
- 默认和 FoundationServer 安装在同一台机器。
- 从 FoundationServer 内置目录取 BasicRunner：

```text
<FoundationServer>/data/softdownload/<arch>/Basic-<arch>-latest.tar.gz
```

- 解压后执行 BasicRunner 官方 `install.sh`。
- 修改 runner 配置，加入 MySQL。
- 下载或复用 MySQL runner 包：

```text
https://ftp.anybackup.ai/MySQL-Linux_el7_x64-8.0.9.0-20251231-release-zh_CN-ABNormal-378.tar.gz
```

- 在 `foundationcli/etc/ClientService` 下执行：

```bash
./client_cli install MySQL --path=<mysql包绝对路径>
```

## 8. Foundation AK/SK 人工断点

- Foundation 装好后，用户登录 Foundation 前端获取 AK/SK。
- AK/SK 不是 KWeaver 自动生成，也不是 Core Agent Service 下发。
- 部署可以在这里暂停。
- 用户输入 AK/SK 后继续发布 Core Agent Service 和业务服务。
- AK/SK 只允许走隐藏输入、环境变量或 Secret，不写进命令历史和文件。

## 9. 注入 foundation-cli 到 KWeaver sandbox

- 发生在 KWeaver Core 成功之后、业务服务发布之前。
- 把 Linux amd64 `foundation-cli` 注入 KWeaver 当前 python-basic sandbox 镜像。
- 使用兼容旧 Docker 的 Dockerfile，不能用 `COPY --chmod`。
- 同 tag rebuild/import，然后重启 sandbox pod。
- 这一步不是 KWeaver Core 成功判定的一部分。

## 10. 部署模型配置

- 配置大模型 LLM。
- 配置普通小模型。
- adapter 小模型当前仍是 alpha 兼容路径，不能跳过；后续等 KWeaver 后端 API 正式支持后清理 workaround。
- 模型配置脚本会调用 `kweaver-admin` 查询和创建模型；部署编排必须在调用前复用已登录的 `kweaver` CLI token，并只通过进程环境传递给 `KWEAVER_TOKEN` / `KWEAVER_ADMIN_TOKEN`。
- 模型 API key 不能明文入库或入文档，后续应走 Secret/Vault/KMS。

## 11. 导入知识库数据

- 导入备份推荐相关知识库数据。
- 导入恢复规则/恢复经验相关知识库数据。
- 这一步通常涉及 PostgreSQL 建库、导表和初始化数据。

## 12. 建立 KWeaver 数据连接和 DataView

Foundation OpenSearch：

- KWeaver 不支持直接接 Foundation HTTPS OpenSearch。
- 需要用 Nginx/代理把 KWeaver HTTP 请求转到 Foundation OpenSearch HTTPS。
- 然后在 KWeaver Vega 中创建 catalog/discover。
- Foundation OpenSearch 密码必须通过隐藏输入、受控环境变量或 Secret 注入。默认流程应像 AK/SK 一样暂停并隐藏输入；也可以使用受控环境变量 `AGENT_CONTENT_FOUNDATION_OPENSEARCH_PASSWORD`。不能写进命令示例、values 或日志。

Foundation MariaDB：

- alpha 默认用户为 `sdba`。
- 密码部署时隐藏输入。
- 生产不能长期用高权限账号，需要专用只读账号和 Secret 方案。

知识库 PostgreSQL：

- 创建 KWeaver datasource。
- discover schema/table。

注意：DataView ID 和数据连接 ID 都是环境相关的，不能硬编码到 BKN 或 Agent 配置里。

## 13. 部署 BKN

- Backup BKN。
- Recovery BKN。
- BKN 中引用的数据视图必须和第 12 步生成的逻辑对象对应。
- 禁止重新引入固定 DataView UUID。
- 调用 `kweaver bkn push` 或现有 BKN installer 上传。
- `HyperBackupMgmServiceDB` 当前已经存在，恢复相关 DataView/BKN 应继续使用真实的 `HyperBackupMgmServiceDB.protect_object` 逻辑对象，不做猜测映射。
- 当前 KWeaver 0.6.0 环境中如果缺少 `business-system-service`，BKN backend 业务域绑定会失败；部署脚本需要自动把 `bkn-backend` 的 `BUSINESS_DOMAIN_ENABLED` 切为 `false`、等待 rollout，并重新轮询 BKN API。若后续环境提供 `business-system-service`，应保持或恢复为 `true`。

## 14. 部署 ContextLoader

- 使用和当前 KWeaver 版本对应的 ContextLoader 工具包。
- 当前 CLI 不完整支持，所以通过 KWeaver API 导入 `.adp` toolbox。
- 导入后记录生成的 `toolbox_id` 和 `tool_id`。
- 后续 Agent JSON 里的 tool id / toolbox id 要替换成这一步生成的 ID。

## 15. 导入并发布 KWeaver skills

导入 AnyBackup CLI skills：

- `client`
- `job`
- `mysql`
- `policy`
- `protect`
- `storage`
- `timepoint`

要求：

- 每个 skill 上传前都要压缩。
- zip 第一层必须就是 skill 目录结构。
- 导入后还要发布，不是只 register。
- 还要导入特殊 skill：`ag-ui-response`。
- `ag-ui-response` 有 Python 依赖，导入/发布后必须通过 sandbox dependency API 安装 `requirements.txt` 里的依赖。
- 当前依赖为：

```text
aio-pika>=9.5.0
```

## 16. 部署 Agent

- 读取标准 Agent export JSON。
- 替换 ContextLoader 生成的 `tool_id` 和 `tool_box_id`。
- 替换 skill ID。
- 替换 LLM id、模型名称、小模型 id。
- 替换 BKN、DataView、数据连接相关引用。
- 调用 KWeaver CLI/API 创建 Agent。
- 发布 Agent。
- 使用 KWeaver CLI 的 Agent 能力做基础查询和必要 smoke。

## 17. 构建并导入业务服务镜像

- 从 AnyBackup 仓库源码构建，不从历史 images 目录拿。
- 至少包括：
  - `conversation-service`
  - `core-agent-service`
  - `agent-web`
- 第三方服务镜像包括 Keycloak/Traefik 等，要明确预拉取或导入策略。
- 弱网环境要提前处理大镜像。

## 18. 部署 5 个业务服务

服务清单：

- `api-gateway-service`
- `auth-service`
- `core-agent-service`
- `conversation-service`
- `agent-web`

`core-agent-service` 特殊要求：

- 需要注入 Foundation endpoint。
- 需要注入 Foundation AK/SK。
- Agent 调用 Foundation CLI 时依赖它透传 `custom_querys.foundation`。

`conversation-service` 的 Secret 必须是普通 Helm resource，不能是 hook，否则失败升级会导致 Secret 丢失。

## 19. 部署 Ingress / 对外入口

- web 是唯一对外入口。
- 后端服务保持 `ClusterIP`。
- 不开放后端 NodePort。
- 不直接暴露 `/api` 到后端服务。
- 最终外部访问链路应是：

```text
Browser -> Ingress/Traefik -> agent-web -> api-gateway/auth/conversation
```

## 20. 部署后校验

Kubernetes / Helm：

- `kubectl get po -A` 所有关键 pod ready。
- `helm list -A` release 状态为 deployed。

KWeaver CLI：

- `auth status`。
- `bkn list`。
- `agent list`。

Foundation：

- Foundation Web 可访问。
- FoundationClient service 正常。
- MySQL runner 已安装。

KWeaver DataView：

- Foundation OpenSearch catalog 存在。
- Foundation MariaDB DataView 存在。
- 知识库 PostgreSQL DataView 存在。

BKN：

- Backup BKN push 成功。
- Recovery BKN push 成功，HyperBackup 相关 DataView/BKN 引用指向当前 Foundation 中的真实对象。

Skills：

- AnyBackup CLI skills 已导入并发布。
- `ag-ui-response` 已导入并安装 Python 依赖。

Agent：

- Agent 已创建并发布。
- tool/toolbox/model ID 已替换。
- 用真实模型凭证跑一次 Agent chat smoke。

## 21. 卸载 / 重装闭环

- `uninstall.sh` 保留 K8s。
- 清理 Helm releases、namespace、KWeaver、业务服务和 runtime 目录。
- Foundation 卸载不能只跑官方 uninstall。
- 还要清理：
  - `/opt/backupsoft/FoundationServer`
  - `/opt/backupsoft/FoundationClient`
  - `ABClientService.service`

## Additional Gate: BKN default small model

After KWeaver model configuration and before BKN/DataView/ContextLoader import,
the integrated deployment must reconcile `bkn-backend-cm` in the KWeaver
namespace:

- Set `server.defaultSmallModelEnabled: true` in `bkn-backend-config.yaml`.
- Preserve all other ConfigMap data.
- Restart `deployment/bkn-backend` and wait for rollout completion.

This replaces the old manual path of editing the ConfigMap and deleting the
`bkn-backend` pod by hand. The implementation details live in
`doc/anybackup-agent-deployment.md`.

## Additional Gate: KWeaver business-system compatibility

In the current KWeaver 0.6.0 ISF path, `business-system-service` may be absent.
When it is absent, KWeaver resource binding calls can fail with HTTP 500 during
BKN push, ContextLoader toolbox import, or Agent create. The deployment must
reconcile these platform components before the corresponding content step:

- `bkn-backend`
- `agent-operator-integration`
- `agent-factory`

For each component, set `BUSINESS_DOMAIN_ENABLED=false` when
`business-system-service` is absent, then wait for rollout completion. Restore
or keep `true` when a later environment provides `business-system-service`.
- 包文件默认保留，除非显式 `--purge-packages`。
- 目标是卸载后能直接重新跑一体化部署脚本。
