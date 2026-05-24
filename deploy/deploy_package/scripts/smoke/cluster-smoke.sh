#!/usr/bin/env bash
set -euo pipefail

: "${V9_NAMESPACE:?V9_NAMESPACE is required}"
: "${V9_INFRA_NAMESPACE:?V9_INFRA_NAMESPACE is required}"
: "${KWEAVER_NAMESPACE:?KWEAVER_NAMESPACE is required}"

ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-600s}"
CORE_AGENT_DEPLOYMENT="${CORE_AGENT_DEPLOYMENT:-core-agent-service}"
BUSINESS_DEPLOYMENTS="${BUSINESS_DEPLOYMENTS:-}"
SANDBOX_IMAGE="${SANDBOX_IMAGE:-}"
CORE_AGENT_MQ_READY_PATTERN="${CORE_AGENT_MQ_READY_PATTERN:-}"
CORE_AGENT_LOG_TAIL="${CORE_AGENT_LOG_TAIL:-200}"
POSTGRES_SERVICE="${POSTGRES_SERVICE:-v9-infra-postgres}"
RABBITMQ_SERVICE="${RABBITMQ_SERVICE:-v9-infra-rabbitmq}"
REDIS_SERVICE="${REDIS_SERVICE:-v9-infra-redis}"
OPENSEARCH_SERVICE="${OPENSEARCH_SERVICE:-v9-infra-opensearch}"
KWEAVER_RUNTIME_SERVICE="${KWEAVER_RUNTIME_SERVICE:-}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-}"
PUBLIC_WEB_SERVICE="${PUBLIC_WEB_SERVICE:-}"
PUBLIC_INGRESS_NAME="${PUBLIC_INGRESS_NAME:-}"

rollout() {
  local kind="$1"
  local name="$2"
  local ns="$3"
  kubectl rollout status "${kind}/${name}" -n "${ns}" --timeout="${ROLLOUT_TIMEOUT}"
}

echo "[smoke] waiting for V9 infra"
rollout statefulset v9-infra-postgres "${V9_INFRA_NAMESPACE}"
rollout statefulset v9-infra-rabbitmq "${V9_INFRA_NAMESPACE}"
rollout statefulset v9-infra-redis "${V9_INFRA_NAMESPACE}"
rollout statefulset v9-infra-opensearch "${V9_INFRA_NAMESPACE}"

echo "[smoke] waiting for core agent"
rollout deployment "${CORE_AGENT_DEPLOYMENT}" "${V9_NAMESPACE}"

for dep in ${BUSINESS_DEPLOYMENTS}; do
  echo "[smoke] waiting for ${dep}"
  rollout deployment "${dep}" "${V9_NAMESPACE}"
done

echo "[smoke] checking KWeaver pods"
kweaver_pods="$(kubectl get pods -n "${KWEAVER_NAMESPACE}" --field-selector=status.phase=Running -o jsonpath='{range .items[*]}pod/{.metadata.name} {end}')"
if [[ -n "${kweaver_pods}" ]]; then
  kubectl wait -n "${KWEAVER_NAMESPACE}" --for=condition=Ready ${kweaver_pods} --timeout="${ROLLOUT_TIMEOUT}" >/dev/null
fi

echo "[smoke] checking service endpoints"
kubectl get svc -n "${V9_INFRA_NAMESPACE}" "${POSTGRES_SERVICE}" >/dev/null
kubectl get svc -n "${V9_INFRA_NAMESPACE}" "${RABBITMQ_SERVICE}" >/dev/null
kubectl get svc -n "${V9_INFRA_NAMESPACE}" "${REDIS_SERVICE}" >/dev/null
kubectl get svc -n "${V9_INFRA_NAMESPACE}" "${OPENSEARCH_SERVICE}" >/dev/null
kubectl get svc -n "${V9_NAMESPACE}" "${CORE_AGENT_DEPLOYMENT}" >/dev/null

if [[ -n "${KWEAVER_RUNTIME_SERVICE}" ]]; then
  echo "[smoke] checking KWeaver runtime alias service"
  kubectl get svc -n "${V9_NAMESPACE}" "${KWEAVER_RUNTIME_SERVICE}" >/dev/null
else
  echo "[smoke] KWEAVER_RUNTIME_SERVICE not set; skipped alias service assertion"
fi

if [[ -n "${PUBLIC_WEB_SERVICE}" ]]; then
  echo "[smoke] checking public web ingress resources"
  kubectl get svc -n "${V9_NAMESPACE}" "${PUBLIC_WEB_SERVICE}" >/dev/null
  if [[ -n "${PUBLIC_INGRESS_NAME}" ]]; then
    kubectl get ingress -n "${V9_NAMESPACE}" "${PUBLIC_INGRESS_NAME}" >/dev/null
  fi
  if [[ -n "${PUBLIC_BASE_URL}" ]]; then
    if command -v curl >/dev/null 2>&1; then
      curl -fsS --max-time 10 "${PUBLIC_BASE_URL}" >/dev/null
    else
      echo "[smoke] curl not found; skipped HTTP probe for ${PUBLIC_BASE_URL}"
    fi
  fi
else
  echo "[smoke] PUBLIC_WEB_SERVICE not set; skipped public ingress assertion"
fi

if [[ -n "${SANDBOX_IMAGE}" ]]; then
  echo "[smoke] checking sandbox image contains foundation-cli"
  docker run --rm --entrypoint /bin/sh "${SANDBOX_IMAGE}" -c 'command -v foundation-cli >/dev/null'
fi

if [[ -n "${CORE_AGENT_MQ_READY_PATTERN}" ]]; then
  echo "[smoke] checking core agent logs for MQ ready pattern"
  pod_name="$(kubectl get pods -n "${V9_NAMESPACE}" -l "app.kubernetes.io/name=${CORE_AGENT_DEPLOYMENT}" -o jsonpath='{.items[0].metadata.name}')"
  kubectl logs -n "${V9_NAMESPACE}" "${pod_name}" --tail="${CORE_AGENT_LOG_TAIL}" | grep -E "${CORE_AGENT_MQ_READY_PATTERN}" >/dev/null
else
  echo "[smoke] CORE_AGENT_MQ_READY_PATTERN not set; skipped app-specific MQ log assertion"
fi

echo "[smoke] completed successfully"
