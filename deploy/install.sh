#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "${ROOT_DIR}/ansible" ]]; then
  DEPLOY_ASSET_DIR="${ROOT_DIR}"
elif [[ -d "${ROOT_DIR}/deploy_package/ansible" ]]; then
  DEPLOY_ASSET_DIR="${ROOT_DIR}/deploy_package"
else
  DEPLOY_ASSET_DIR="${ROOT_DIR}"
fi
ANSIBLE_DIR="${DEPLOY_ASSET_DIR}/ansible"
COMMON_LIB="${DEPLOY_ASSET_DIR}/scripts/lib/ansible-common.sh"
LOCAL_KWEAVER_CORE_INSTALL="${DEPLOY_ASSET_DIR}/scripts/install-kweaver-core-only-local.sh"
DEPLOYMENT_PROFILE="full"
INVENTORY_PATH="${ANSIBLE_DIR}/inventory.ini"
LOCAL_MODE="false"
TEMP_INVENTORY_PATH=""
FOUNDATION_SELF_IP="${FOUNDATION_SELF_IP:-}"
FOUNDATION_ENABLED="${FOUNDATION_ENABLED:-}"
FOUNDATION_MODE="${FOUNDATION_MODE:-}"
FOUNDATION_PACKAGE_PATH="${FOUNDATION_PACKAGE_PATH:-}"
FOUNDATION_INSTALL_ROOT="${FOUNDATION_INSTALL_ROOT:-}"
KWEAVER_CLI_BASE_URL="${KWEAVER_CLI_BASE_URL:-}"
KWEAVER_CLI_USERNAME="${KWEAVER_CLI_USERNAME:-}"
KWEAVER_CLI_INITIAL_PASSWORD="${KWEAVER_CLI_INITIAL_PASSWORD:-}"
KWEAVER_CLI_PASSWORD="${KWEAVER_CLI_PASSWORD:-}"
KWEAVER_CLI_NEW_PASSWORD="${KWEAVER_CLI_NEW_PASSWORD:-}"
AGENT_CONTENT_KWEAVER_BASE_URL="${AGENT_CONTENT_KWEAVER_BASE_URL:-}"
AGENT_CONTENT_KWEAVER_USERNAME="${AGENT_CONTENT_KWEAVER_USERNAME:-}"
AGENT_CONTENT_KWEAVER_PASSWORD="${AGENT_CONTENT_KWEAVER_PASSWORD:-}"
AGENT_CONTENT_SKIP_LOGIN="${AGENT_CONTENT_SKIP_LOGIN:-}"
AGENT_CONTENT_FOUNDATION_CLI_SKILLS_PUBLISH="${AGENT_CONTENT_FOUNDATION_CLI_SKILLS_PUBLISH:-}"
AGENT_CONTENT_FOUNDATION_CLI_SKILLS_ENSURE_PUBLISH_SCHEMA="${AGENT_CONTENT_FOUNDATION_CLI_SKILLS_ENSURE_PUBLISH_SCHEMA:-}"

source "${COMMON_LIB}"

cleanup_temp_inventory() {
  if [[ -n "${TEMP_INVENTORY_PATH}" && -f "${TEMP_INVENTORY_PATH}" ]]; then
    rm -f "${TEMP_INVENTORY_PATH}"
  fi
}

trap cleanup_temp_inventory EXIT

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [--profile full|kweaver-core-only|agent-content-only] [--foundation-self-ip IP] [--inventory /path/to/inventory.ini]
  ./install.sh [--profile full|kweaver-core-only|agent-content-only] [--foundation-self-ip IP] --local

Foundation options:
  --foundation-self-ip IP       Foundation installer --self-ip value.
  --skip-foundation             Skip Foundation install/verify in this run.
  --foundation-mode MODE        integrated | separated | external.
  --foundation-package-path PATH
                                Remote Foundation tar.gz path, default /backupsoft/Linux_el7_x64-latest.tar.gz.
  --foundation-install-root PATH
                                Remote extracted AnyBackupServer path, default /backupsoft/AnyBackupServer.

KWeaver CLI options:
  --kweaver-cli-base-url URL    KWeaver platform URL for post-core configuration.
  --kweaver-cli-username USER
  --kweaver-cli-initial-password PASSWORD
                                Initial password used only when the account
                                must rotate its password on first login.
  --kweaver-cli-password PASSWORD
  --kweaver-cli-new-password PASSWORD
                                New password for KWeaver accounts that must
                                rotate the initial password on first login.

Agent content options:
  --agent-content-kweaver-base-url URL
  --agent-content-kweaver-username USER
  --agent-content-kweaver-password PASSWORD
  --agent-content-skip-login true|false
  --agent-content-foundation-cli-skills-publish true|false
                                Publish imported/reused AnyBackup CLI skills.
  --agent-content-foundation-cli-skills-ensure-publish-schema true|false
                                Create missing KWeaver skill publish tables before publishing.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --profile requires a value" >&2
        usage
        exit 1
      fi
      DEPLOYMENT_PROFILE="$1"
      ;;
    --inventory)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --inventory requires a value" >&2
        usage
        exit 1
      fi
      INVENTORY_PATH="$1"
      ;;
    --local)
      LOCAL_MODE="true"
      ;;
    --foundation-self-ip)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-self-ip requires a value" >&2
        usage
        exit 1
      fi
      FOUNDATION_SELF_IP="$1"
      ;;
    --skip-foundation)
      FOUNDATION_ENABLED="false"
      ;;
    --foundation-mode)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-mode requires a value" >&2
        usage
        exit 1
      fi
      FOUNDATION_MODE="$1"
      ;;
    --foundation-package-path)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-package-path requires a value" >&2
        usage
        exit 1
      fi
      FOUNDATION_PACKAGE_PATH="$1"
      ;;
    --foundation-install-root)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-install-root requires a value" >&2
        usage
        exit 1
      fi
      FOUNDATION_INSTALL_ROOT="$1"
      ;;
    --kweaver-cli-base-url)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --kweaver-cli-base-url requires a value" >&2
        usage
        exit 1
      fi
      KWEAVER_CLI_BASE_URL="$1"
      ;;
    --kweaver-cli-username)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --kweaver-cli-username requires a value" >&2
        usage
        exit 1
      fi
      KWEAVER_CLI_USERNAME="$1"
      ;;
    --kweaver-cli-password)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --kweaver-cli-password requires a value" >&2
        usage
        exit 1
      fi
      KWEAVER_CLI_PASSWORD="$1"
      ;;
    --kweaver-cli-initial-password)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --kweaver-cli-initial-password requires a value" >&2
        usage
        exit 1
      fi
      KWEAVER_CLI_INITIAL_PASSWORD="$1"
      ;;
    --kweaver-cli-new-password)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --kweaver-cli-new-password requires a value" >&2
        usage
        exit 1
      fi
      KWEAVER_CLI_NEW_PASSWORD="$1"
      ;;
    --agent-content-kweaver-base-url)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-kweaver-base-url requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_KWEAVER_BASE_URL="$1"
      ;;
    --agent-content-kweaver-username)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-kweaver-username requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_KWEAVER_USERNAME="$1"
      ;;
    --agent-content-kweaver-password)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-kweaver-password requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_KWEAVER_PASSWORD="$1"
      ;;
    --agent-content-skip-login)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-skip-login requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_SKIP_LOGIN="$1"
      ;;
    --agent-content-foundation-cli-skills-publish)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-foundation-cli-skills-publish requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_FOUNDATION_CLI_SKILLS_PUBLISH="$1"
      ;;
    --agent-content-foundation-cli-skills-ensure-publish-schema)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-foundation-cli-skills-ensure-publish-schema requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_FOUNDATION_CLI_SKILLS_ENSURE_PUBLISH_SCHEMA="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

case "${DEPLOYMENT_PROFILE}" in
  full|kweaver-core-only|agent-content-only)
    ;;
  *)
    echo "ERROR: unsupported profile: ${DEPLOYMENT_PROFILE}" >&2
    usage
    exit 1
    ;;
esac

if [[ "${LOCAL_MODE}" == "true" && "${INVENTORY_PATH}" != "${ANSIBLE_DIR}/inventory.ini" ]]; then
  echo "ERROR: --local cannot be combined with --inventory" >&2
  usage
  exit 1
fi

if [[ "${LOCAL_MODE}" == "true" && "${DEPLOYMENT_PROFILE}" == "kweaver-core-only" ]]; then
  exec "${LOCAL_KWEAVER_CORE_INSTALL}"
fi

ensure_ansible_playbook

if [[ "${LOCAL_MODE}" == "true" ]]; then
  TEMP_INVENTORY_PATH="$(create_local_inventory)"
  INVENTORY_PATH="${TEMP_INVENTORY_PATH}"
fi

run_stage() {
  local tag="$1"
  local extra_vars=()
  if [[ -n "${FOUNDATION_SELF_IP}" ]]; then
    extra_vars+=(-e "foundation_self_ip=${FOUNDATION_SELF_IP}")
  fi
  if [[ -n "${FOUNDATION_ENABLED}" ]]; then
    extra_vars+=(-e "foundation_enabled=${FOUNDATION_ENABLED}")
  fi
  if [[ -n "${FOUNDATION_MODE}" ]]; then
    extra_vars+=(-e "foundation_mode=${FOUNDATION_MODE}")
  fi
  if [[ -n "${FOUNDATION_PACKAGE_PATH}" ]]; then
    extra_vars+=(-e "foundation_package_path=${FOUNDATION_PACKAGE_PATH}")
  fi
  if [[ -n "${FOUNDATION_INSTALL_ROOT}" ]]; then
    extra_vars+=(-e "foundation_install_root=${FOUNDATION_INSTALL_ROOT}")
  fi
  if [[ -n "${KWEAVER_CLI_BASE_URL}" ]]; then
    extra_vars+=(-e "kweaver_cli_base_url=${KWEAVER_CLI_BASE_URL}")
  fi
  if [[ -n "${KWEAVER_CLI_USERNAME}" ]]; then
    extra_vars+=(-e "kweaver_cli_username=${KWEAVER_CLI_USERNAME}")
  fi
  if [[ -n "${KWEAVER_CLI_INITIAL_PASSWORD}" ]]; then
    extra_vars+=(-e "kweaver_cli_initial_password=${KWEAVER_CLI_INITIAL_PASSWORD}")
  fi
  if [[ -n "${KWEAVER_CLI_PASSWORD}" ]]; then
    extra_vars+=(-e "kweaver_cli_password=${KWEAVER_CLI_PASSWORD}")
  fi
  if [[ -n "${KWEAVER_CLI_NEW_PASSWORD}" ]]; then
    extra_vars+=(-e "kweaver_cli_new_password=${KWEAVER_CLI_NEW_PASSWORD}")
  fi
  if [[ -n "${AGENT_CONTENT_KWEAVER_BASE_URL}" ]]; then
    extra_vars+=(-e "agent_content_kweaver_base_url=${AGENT_CONTENT_KWEAVER_BASE_URL}")
  fi
  if [[ -n "${AGENT_CONTENT_KWEAVER_USERNAME}" ]]; then
    extra_vars+=(-e "agent_content_kweaver_username=${AGENT_CONTENT_KWEAVER_USERNAME}")
  fi
  if [[ -n "${AGENT_CONTENT_KWEAVER_PASSWORD}" ]]; then
    extra_vars+=(-e "agent_content_kweaver_password=${AGENT_CONTENT_KWEAVER_PASSWORD}")
  fi
  if [[ -n "${AGENT_CONTENT_SKIP_LOGIN}" ]]; then
    extra_vars+=(-e "agent_content_skip_login=${AGENT_CONTENT_SKIP_LOGIN}")
  elif [[ -n "${AGENT_CONTENT_KWEAVER_BASE_URL}" && -n "${AGENT_CONTENT_KWEAVER_USERNAME}" && -n "${AGENT_CONTENT_KWEAVER_PASSWORD}" ]]; then
    extra_vars+=(-e "agent_content_skip_login=false")
  fi
  if [[ -n "${AGENT_CONTENT_FOUNDATION_CLI_SKILLS_PUBLISH}" ]]; then
    extra_vars+=(-e "agent_content_foundation_cli_skills_publish=${AGENT_CONTENT_FOUNDATION_CLI_SKILLS_PUBLISH}")
  fi
  if [[ -n "${AGENT_CONTENT_FOUNDATION_CLI_SKILLS_ENSURE_PUBLISH_SCHEMA}" ]]; then
    extra_vars+=(-e "agent_content_foundation_cli_skills_ensure_publish_schema=${AGENT_CONTENT_FOUNDATION_CLI_SKILLS_ENSURE_PUBLISH_SCHEMA}")
  fi

  ansible-playbook \
    -i "${INVENTORY_PATH}" \
    "${ANSIBLE_DIR}/site.yml" \
    -e "deployment_profile=${DEPLOYMENT_PROFILE}" \
    "${extra_vars[@]}" \
    --tags "${tag}"
}

echo "=== 1. Ensure Kubernetes base cluster ==="
run_stage k8s-cluster

echo "=== 2. Prepare environment ==="
run_stage prepare

if [[ "${DEPLOYMENT_PROFILE}" == "agent-content-only" ]]; then
  echo "=== 3. Deploy AnyBackup Agent content only ==="
  run_stage deploy-agent-content
  echo "=== Agent content flow finished ==="
  echo "Note: profile = ${DEPLOYMENT_PROFILE}"
  echo "Note: inventory = ${INVENTORY_PATH}"
  echo "Note: v9_infra and the 5 business service Helm releases were not touched."
  exit 0
fi

echo "=== 3. K8s / Ingress / network preflight ==="
run_stage network-preflight

if [[ "${DEPLOYMENT_PROFILE}" == "kweaver-core-only" ]]; then
  echo "=== 4. Deploy KWeaver Core online ==="
else
  echo "=== 4. Deploy KWeaver Core, V9 infra, Agent content, and business services ==="
fi
run_stage deploy-services

echo "=== 5. Publish network entrypoint ==="
run_stage publish-network

echo "=== 6. Verify deployment ==="
run_stage verify

echo "=== Install flow finished ==="
echo "Note: profile = ${DEPLOYMENT_PROFILE}"
echo "Note: inventory = ${INVENTORY_PATH}"
echo "Note: KWeaver Core is cloned from https://github.com/kweaver-ai/kweaver-core.git and installed from release 0.6.0."
echo "Note: v9_infra PostgreSQL / RabbitMQ / Redis / OpenSearch are still deployed for business services."
