#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RELEASE_NAME="core-agent-service"
NAMESPACE="anybackup-ai"
IMAGE="core-agent-service:local"
IMAGE_REPOSITORY=""
IMAGE_TAG=""
DATABASE_URL="postgresql+psycopg://postgres:V9_KILL_POLICY@postgres.middleware:5432/kweaver"
RABBITMQ_URL="amqp://admin:Ks4unnn%2FOkdxJGDCECc6vxdAMGs%3D@rabbitmq.middleware.svc.cluster.local:5672/"
RABBITMQ_EXCHANGE="conversation.agent.events"
RABBITMQ_EXCHANGE_TYPE="topic"
RABBITMQ_QUEUE="core_agent.minimal.relay.v1"
KWEAVER_BASE_URL="https://115.190.186.186/"
KWEAVER_DECISION_AGENT_ID="01KPYRHRAPNBZNG3HHZZN9V0B1"
KWEAVER_BUSINESS_DOMAIN="bd_public"
KWEAVER_TLS_INSECURE="true"
KWEAVER_PROBE_ON_STARTUP="true"
KWEAVER_USERNAME="admin"
KWEAVER_PASSWORD="eisoo.com123"
KWEAVER_TOKEN=""
SECRETS_CREATE="true"
SECRETS_NAME="core-agent-service-secrets"
KWEAVER_HOST_PATH=""
KWEAVER_MOUNT_PATH="/root/.kweaver"
ENV_FILE_ENABLED="false"
ENV_FILE_MOUNT_PATH="/app/.env"

usage() {
  cat <<'EOF'
用法：
  bash scripts/deploy.sh [参数]

必填参数：
  --image                       完整镜像地址，必须包含标签，例如 registry.example.com/core-agent-service:107
  --kweaver-base-url            KWeaver 基础地址
  --kweaver-decision-agent-id   KWeaver Decision Agent 标识

可选参数：
  --release-name                Helm release 名称，默认：core-agent-service
  --namespace                   Kubernetes 命名空间，默认：core-agent
  --database-url                PostgreSQL 连接串，默认：postgresql+asyncpg://conversation:conversation@postgres.middleware:5432/conversation
  --rabbitmq-url                RabbitMQ 连接串，默认：amqp://guest:guest@rabbitmq.middleware:5672/
  --rabbitmq-exchange           RabbitMQ exchange，默认：conversation.agent.events
  --rabbitmq-exchange-type      RabbitMQ exchange type，默认：topic
  --rabbitmq-queue              RabbitMQ queue，默认：core_agent.minimal.relay.v1
  --kweaver-username            KWeaver 用户名，可选
  --kweaver-password            KWeaver 密码，可选
  --kweaver-business-domain     KWeaver business domain，可选，默认：bd_public
  --kweaver-tls-insecure        是否跳过 KWeaver TLS 校验，可选值：true/false，默认：true
  --kweaver-probe-on-startup    是否启动时探测 Decision Agent，可选值：true/false，默认：true
  --kweaver-token               KWeaver token，可选
  --secrets-create              是否由 chart 创建 Secret，可选值：true/false，默认：false
  --secrets-name                复用现有 Secret 时的 Secret 名称，默认：core-agent-service-secrets
  --kweaver-host-path           节点本地 ~/.kweaver 实际绝对路径；传入后自动启用 hostPath 挂载
  --kweaver-mount-path          容器内挂载路径，默认：/root/.kweaver
  --env-file-enabled            是否启用 .env 兜底挂载，可选值：true/false，默认：false
  --env-file-mount-path         容器内 .env 文件挂载路径，默认：/app/.env
  -h, --help                    显示帮助

说明：
  1. 当前 Chart 默认以 MQ worker 形态部署，不对外暴露 Service/Ingress。
  2. KWeaver 鉴权优先使用用户名密码，其次 token，最后才回退 ~/.kweaver 挂载。
  3. 若传入 --kweaver-host-path，则脚本会自动设置 kweaverHostMount.enabled=true。
  4. 如果已经提供用户名密码，就不再需要挂载 /root/.kweaver。
  5. 本脚本只执行 helm upgrade --install，不做 kubectl/集群探测。

示例：
  bash scripts/deploy.sh \
    --image registry.example.com/core-agent-service:107 \
    --kweaver-base-url 'https://kweaver.example.com' \
    --kweaver-decision-agent-id 'decision-agent-id' \
    --kweaver-username 'service_account' \
    --kweaver-password '***'
EOF
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "${value}" ]]; then
    echo "参数 ${option} 缺少取值。" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-name)
      require_value "$1" "${2:-}"
      RELEASE_NAME="$2"
      shift 2
      ;;
    --namespace)
      require_value "$1" "${2:-}"
      NAMESPACE="$2"
      shift 2
      ;;
    --image)
      require_value "$1" "${2:-}"
      IMAGE="$2"
      shift 2
      ;;
    --database-url)
      require_value "$1" "${2:-}"
      DATABASE_URL="$2"
      shift 2
      ;;
    --rabbitmq-url)
      require_value "$1" "${2:-}"
      RABBITMQ_URL="$2"
      shift 2
      ;;
    --rabbitmq-exchange)
      require_value "$1" "${2:-}"
      RABBITMQ_EXCHANGE="$2"
      shift 2
      ;;
    --rabbitmq-exchange-type)
      require_value "$1" "${2:-}"
      RABBITMQ_EXCHANGE_TYPE="$2"
      shift 2
      ;;
    --rabbitmq-queue)
      require_value "$1" "${2:-}"
      RABBITMQ_QUEUE="$2"
      shift 2
      ;;
    --kweaver-base-url)
      require_value "$1" "${2:-}"
      KWEAVER_BASE_URL="$2"
      shift 2
      ;;
    --kweaver-decision-agent-id)
      require_value "$1" "${2:-}"
      KWEAVER_DECISION_AGENT_ID="$2"
      shift 2
      ;;
    --kweaver-business-domain)
      require_value "$1" "${2:-}"
      KWEAVER_BUSINESS_DOMAIN="$2"
      shift 2
      ;;
    --kweaver-tls-insecure)
      require_value "$1" "${2:-}"
      KWEAVER_TLS_INSECURE="$2"
      shift 2
      ;;
    --kweaver-probe-on-startup)
      require_value "$1" "${2:-}"
      KWEAVER_PROBE_ON_STARTUP="$2"
      shift 2
      ;;
    --kweaver-username)
      require_value "$1" "${2:-}"
      KWEAVER_USERNAME="$2"
      shift 2
      ;;
    --kweaver-password)
      require_value "$1" "${2:-}"
      KWEAVER_PASSWORD="$2"
      shift 2
      ;;
    --kweaver-token)
      require_value "$1" "${2:-}"
      KWEAVER_TOKEN="$2"
      shift 2
      ;;
    --secrets-create)
      require_value "$1" "${2:-}"
      SECRETS_CREATE="$2"
      shift 2
      ;;
    --secrets-name)
      require_value "$1" "${2:-}"
      SECRETS_NAME="$2"
      shift 2
      ;;
    --kweaver-host-path)
      require_value "$1" "${2:-}"
      KWEAVER_HOST_PATH="$2"
      shift 2
      ;;
    --kweaver-mount-path)
      require_value "$1" "${2:-}"
      KWEAVER_MOUNT_PATH="$2"
      shift 2
      ;;
    --env-file-enabled)
      require_value "$1" "${2:-}"
      ENV_FILE_ENABLED="$2"
      shift 2
      ;;
    --env-file-mount-path)
      require_value "$1" "${2:-}"
      ENV_FILE_MOUNT_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数：$1" >&2
      echo "使用 --help 查看完整用法。" >&2
      exit 1
      ;;
  esac
done

if [[ -n "${IMAGE}" ]]; then
  if [[ "${IMAGE}" == *@* ]]; then
    echo "--image 当前仅支持带标签的镜像地址，不支持 digest 形式。" >&2
    exit 1
  fi

  LAST_SEGMENT="${IMAGE##*/}"
  if [[ "${LAST_SEGMENT}" != *:* ]]; then
    echo "--image 必须包含标签，例如 registry.example.com/core-agent-service:107" >&2
    exit 1
  fi

  IMAGE_REPOSITORY="${IMAGE%:*}"
  IMAGE_TAG="${IMAGE##*:}"
fi

for required in IMAGE_REPOSITORY IMAGE_TAG KWEAVER_BASE_URL KWEAVER_DECISION_AGENT_ID; do
  if [[ -z "${!required}" ]]; then
    echo "缺少必填参数：${required}" >&2
    echo "使用 --help 查看完整用法。" >&2
    exit 1
  fi
done

if ! command -v helm >/dev/null 2>&1; then
  echo "未找到 helm 命令，请先安装 Helm。" >&2
  exit 1
fi

if [[ "${ENV_FILE_ENABLED}" != "true" && "${ENV_FILE_ENABLED}" != "false" ]]; then
  echo "--env-file-enabled 只能取 true 或 false。" >&2
  exit 1
fi

if [[ "${SECRETS_CREATE}" != "true" && "${SECRETS_CREATE}" != "false" ]]; then
  echo "--secrets-create 只能取 true 或 false。" >&2
  exit 1
fi

if [[ "${KWEAVER_TLS_INSECURE}" != "true" && "${KWEAVER_TLS_INSECURE}" != "false" ]]; then
  echo "--kweaver-tls-insecure 只能取 true 或 false。" >&2
  exit 1
fi

if [[ "${KWEAVER_PROBE_ON_STARTUP}" != "true" && "${KWEAVER_PROBE_ON_STARTUP}" != "false" ]]; then
  echo "--kweaver-probe-on-startup 只能取 true 或 false。" >&2
  exit 1
fi

if [[ -n "${KWEAVER_USERNAME}" && -z "${KWEAVER_PASSWORD}" ]]; then
  echo "提供 --kweaver-username 时必须同时提供 --kweaver-password。" >&2
  exit 1
fi

if [[ -n "${KWEAVER_PASSWORD}" && -z "${KWEAVER_USERNAME}" ]]; then
  echo "提供 --kweaver-password 时必须同时提供 --kweaver-username。" >&2
  exit 1
fi

if [[ -n "${KWEAVER_USERNAME}" ]]; then
  KWEAVER_HOST_PATH=""
fi

HELM_ARGS=(
  upgrade --install "${RELEASE_NAME}" "${CHART_DIR}"
  --namespace "${NAMESPACE}"
  --create-namespace
  --set-string "image.repository=${IMAGE_REPOSITORY}"
  --set-string "image.tag=${IMAGE_TAG}"
  --set "secrets.create=${SECRETS_CREATE}"
  --set-string "secrets.name=${SECRETS_NAME}"
  --set-string "secrets.databaseUrl=${DATABASE_URL}"
  --set-string "secrets.rabbitmqUrl=${RABBITMQ_URL}"
  --set-string "config.rabbitmqExchange=${RABBITMQ_EXCHANGE}"
  --set-string "config.rabbitmqExchangeType=${RABBITMQ_EXCHANGE_TYPE}"
  --set-string "config.rabbitmqQueue=${RABBITMQ_QUEUE}"
  --set-string "config.kweaverBaseUrl=${KWEAVER_BASE_URL}"
  --set-string "config.kweaverDecisionAgentId=${KWEAVER_DECISION_AGENT_ID}"
  --set-string "config.kweaverBusinessDomain=${KWEAVER_BUSINESS_DOMAIN}"
  --set-string "config.kweaverTlsInsecure=${KWEAVER_TLS_INSECURE}"
  --set-string "config.kweaverProbeOnStartup=${KWEAVER_PROBE_ON_STARTUP}"
  --set "service.enabled=false"
  --set "ingress.enabled=false"
  --set "envFile.enabled=${ENV_FILE_ENABLED}"
  --set-string "envFile.mountPath=${ENV_FILE_MOUNT_PATH}"
)

if [[ -n "${KWEAVER_USERNAME}" ]]; then
  HELM_ARGS+=(--set-string "secrets.kweaverUsername=${KWEAVER_USERNAME}")
fi

if [[ -n "${KWEAVER_PASSWORD}" ]]; then
  HELM_ARGS+=(--set-string "secrets.kweaverPassword=${KWEAVER_PASSWORD}")
fi

if [[ -n "${KWEAVER_TOKEN}" ]]; then
  HELM_ARGS+=(--set-string "secrets.kweaverToken=${KWEAVER_TOKEN}")
fi

if [[ -n "${KWEAVER_HOST_PATH}" ]]; then
  HELM_ARGS+=(
    --set "kweaverHostMount.enabled=true"
    --set-string "kweaverHostMount.hostPath=${KWEAVER_HOST_PATH}"
    --set-string "kweaverHostMount.mountPath=${KWEAVER_MOUNT_PATH}"
  )
else
  HELM_ARGS+=(--set "kweaverHostMount.enabled=false")
fi

echo "开始部署 core_agent_service..."
echo "release: ${RELEASE_NAME}"
echo "namespace: ${NAMESPACE}"
echo "chart: ${CHART_DIR}"
echo "image: ${IMAGE_REPOSITORY}:${IMAGE_TAG}"
echo "databaseUrl: ${DATABASE_URL}"
echo "rabbitmqUrl: ${RABBITMQ_URL}"
if [[ -n "${KWEAVER_USERNAME}" ]]; then
  echo "kweaverAuthMode: username_password"
else
  echo "kweaverAuthMode: token_or_config"
fi
echo "service.enabled: false"
echo "ingress.enabled: false"
echo "envFile.enabled: ${ENV_FILE_ENABLED}"
if [[ -n "${KWEAVER_HOST_PATH}" ]]; then
  echo "kweaverHostMount.enabled: true"
  echo "kweaverHostMount.hostPath: ${KWEAVER_HOST_PATH}"
  echo "kweaverHostMount.mountPath: ${KWEAVER_MOUNT_PATH}"
else
  echo "kweaverHostMount.enabled: false"
fi

helm "${HELM_ARGS[@]}"

echo "Helm 部署命令执行完成。"
