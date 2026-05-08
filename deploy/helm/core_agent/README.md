# core_agent_service_chart

## 仓库说明

这是 `core_agent_service` 的 Helm 部署仓库，用于承载当前服务的 Kubernetes Chart 内容。
当前 Chart 按“MQ worker”形态设计，默认不对外暴露 Service 或 Ingress。

## Chart 目录结构

本仓库根目录就是 Chart 根目录，直接包含以下内容：

- `Chart.yaml`
- `values.yaml`
- `templates/`

不再保留 `deploy/helm/core-agent-service` 这类嵌套层级。

## values 覆盖项

部署时可通过 `values.yaml` 或安装命令中的覆盖参数，调整以下配置：

- 镜像参数
- Secret 参数
- KWeaver 参数
- `.env` 兜底挂载参数
- 节点本地 `~/.kweaver` 挂载参数

## 关键说明

- 当前服务通过 RabbitMQ 与外部系统交互，默认不需要 Service 和 Ingress。
- PostgreSQL、RabbitMQ 和 KWeaver 凭据通过 `secrets` 配置和 `secretKeyRef` 注入。
- KWeaver 鉴权优先使用用户名密码，其次使用显式 token，最后才回退节点本地 `~/.kweaver` 挂载。
- 如已配置用户名密码，则不再需要挂载 `/root/.kweaver`。
- 如需挂载节点本地 `~/.kweaver`，请在 values 中使用绝对路径配置 `kweaverHostMount.hostPath`。
- `kweaverHostMount.enabled` 默认关闭，只有在需要复用节点本地 ConfigAuth 登录态时才开启。

## 当前状态

当前仓库已完成 Helm Chart 迁移与 MQ worker 形态收敛，但尚未进行 Kubernetes 联调验证。

## 部署脚本

仓库提供 Bash 部署脚本：

- `scripts/deploy.sh`

可通过以下命令查看帮助：

```bash
bash scripts/deploy.sh --help
```

脚本入口约定：

- 通过 `--image` 传完整镜像地址，例如 `registry.example.com/core-agent-service:107`
- `--database-url` 默认值为 `postgresql+asyncpg://conversation:conversation@postgres.middleware:5432/conversation`
- `--rabbitmq-url` 默认值为 `amqp://guest:guest@rabbitmq.middleware:5672/`
- 如需显式用户名密码鉴权，可额外传入 `--kweaver-username` 与 `--kweaver-password`
- `--kweaver-tls-insecure` 默认值为 `true`
- `--kweaver-probe-on-startup` 默认值为 `true`
