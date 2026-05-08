#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${ROOT_DIR}/ansible"
COMMON_LIB="${ROOT_DIR}/scripts/lib/ansible-common.sh"
LOCAL_KWEAVER_CORE_INSTALL="${ROOT_DIR}/scripts/install-kweaver-core-only-local.sh"
DEPLOYMENT_PROFILE="full"
INVENTORY_PATH="${ANSIBLE_DIR}/inventory.ini"
LOCAL_MODE="false"
TEMP_INVENTORY_PATH=""
FOUNDATION_SELF_IP="${FOUNDATION_SELF_IP:-}"
FOUNDATION_ENABLED="${FOUNDATION_ENABLED:-}"
FOUNDATION_MODE="${FOUNDATION_MODE:-}"
FOUNDATION_ACCESS_HOST="${FOUNDATION_ACCESS_HOST:-}"
FOUNDATION_ENDPOINT="${FOUNDATION_ENDPOINT:-}"
FOUNDATION_PACKAGE_PATH="${FOUNDATION_PACKAGE_PATH:-}"
FOUNDATION_PACKAGE_URL="${FOUNDATION_PACKAGE_URL:-}"
FOUNDATION_WORK_DIR="${FOUNDATION_WORK_DIR:-}"
FOUNDATION_INSTALL_ROOT="${FOUNDATION_INSTALL_ROOT:-}"
CORE_AGENT_FOUNDATION_ENDPOINT="${CORE_AGENT_FOUNDATION_ENDPOINT:-${FOUNDATION_CLI_ENDPOINT:-}}"
CORE_AGENT_FOUNDATION_AK="${CORE_AGENT_FOUNDATION_AK:-${FOUNDATION_CLI_AK:-}}"
CORE_AGENT_FOUNDATION_SK="${CORE_AGENT_FOUNDATION_SK:-${FOUNDATION_CLI_SK:-}}"
FOUNDATION_CLIENT_ENABLED="${FOUNDATION_CLIENT_ENABLED:-}"
FOUNDATION_CLIENT_PACKAGE_URL="${FOUNDATION_CLIENT_PACKAGE_URL:-}"
FOUNDATION_CLIENT_PACKAGE_PATH="${FOUNDATION_CLIENT_PACKAGE_PATH:-}"
FOUNDATION_CLIENT_INSTALL_ROOT="${FOUNDATION_CLIENT_INSTALL_ROOT:-}"
FOUNDATION_CLIENT_FORCE_REINSTALL="${FOUNDATION_CLIENT_FORCE_REINSTALL:-}"
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
AGENT_CONTENT_VEGA_SKIP_KWEAVER_DATA_VIEWS="${AGENT_CONTENT_VEGA_SKIP_KWEAVER_DATA_VIEWS:-}"
AGENT_CONTENT_FOUNDATION_VEGA_HOST="${AGENT_CONTENT_FOUNDATION_VEGA_HOST:-}"
AGENT_CONTENT_FOUNDATION_VEGA_PORT="${AGENT_CONTENT_FOUNDATION_VEGA_PORT:-}"
AGENT_CONTENT_FOUNDATION_VEGA_USERNAME="${AGENT_CONTENT_FOUNDATION_VEGA_USERNAME:-}"
AGENT_CONTENT_FOUNDATION_VEGA_PASSWORD="${AGENT_CONTENT_FOUNDATION_VEGA_PASSWORD:-}"
AGENT_CONTENT_DEPLOY_SKILL_DEPENDENCIES="${AGENT_CONTENT_DEPLOY_SKILL_DEPENDENCIES:-}"
AGENT_CONTENT_SKILL_DEPENDENCIES_SESSION_ID="${AGENT_CONTENT_SKILL_DEPENDENCIES_SESSION_ID:-}"
AGENT_CONTENT_SKILL_DEPENDENCIES_PYTHON_PACKAGE_INDEX_URL="${AGENT_CONTENT_SKILL_DEPENDENCIES_PYTHON_PACKAGE_INDEX_URL:-}"

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
  --enable-foundation           Install or verify Foundation in this run.
  --skip-foundation             Skip Foundation install/verify in this run.
  --foundation-mode MODE        integrated | separated | external.
  --foundation-access-host HOST
                                Foundation host used by KWeaver data views,
                                FoundationClient, and business service endpoint
                                defaults. In separated mode this is the
                                Foundation host address, not the K8s host.
  --foundation-endpoint URL     Foundation CLI endpoint for Core Agent Service.
                                Default https://<foundation-access-host>:9600.
  --foundation-package-path PATH
                                Remote Foundation tar.gz path, default /backupsoft/Linux_el7_x64-latest.tar.gz.
  --foundation-package-url URL  Download URL used when package path is missing on the target host.
  --foundation-work-dir PATH    Remote Foundation work/extract directory, default is inferred from the package path.
  --foundation-install-root PATH
                                Remote extracted FoundationServer path, default /backupsoft/FoundationServer.
  --foundation-cli-endpoint URL Foundation control-plane endpoint passed to Core Agent.
  --foundation-cli-ak AK        Foundation access key passed to Core Agent.
  --foundation-cli-sk SK        Foundation secret key passed to Core Agent.
                                Prefer environment variables FOUNDATION_CLI_ENDPOINT,
                                FOUNDATION_CLI_AK, and FOUNDATION_CLI_SK so secrets
                                do not land in shell history.
  --skip-foundation-client      Skip FoundationClient install/verify in this run.
  --foundation-client-package-url URL
                                MySQL FoundationClient runner package URL.
  --foundation-client-package-path PATH
                                Remote MySQL FoundationClient runner tar.gz path.
  --foundation-client-install-root PATH
                                Remote extracted FoundationClient root,
                                default <foundation-work-dir>/FoundationClient.
  --foundation-client-force-reinstall true|false
                                Re-extract and reinstall FoundationClient BasicRunner.

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
  --agent-content-deploy-skill-dependencies true|false
                                Install Python dependencies for sandbox skills.
  --agent-content-skill-dependencies-session-id SESSION_ID
                                Use a specific running sandbox session for dependency install.
                                By default, auto-detect a running sandbox executor pod.
  --agent-content-skill-dependencies-python-package-index-url URL
                                PyPI index URL for sandbox dependency install.
                                Default https://pypi.tuna.tsinghua.edu.cn/simple.
  --agent-content-vega-skip-kweaver-data-views true|false
                                Skip KWeaver datasource/dataview creation for recovery Vega.
                                Default false. Set true only for KWeaver Core-only
                                environments without Etrino/PostgreSQL datasource support.
  --agent-content-foundation-vega-host HOST
                                Foundation MariaDB host used for KWeaver DataViews.
  --agent-content-foundation-vega-port PORT
                                Foundation MariaDB port used for KWeaver DataViews.
  --agent-content-foundation-vega-username USER
                                Foundation MariaDB user used for KWeaver DataViews.
  AGENT_CONTENT_FOUNDATION_VEGA_PASSWORD
                                Environment variable for Foundation MariaDB password.
                                Prefer `read -s` or Ansible Vault; do not hardcode it.
  AGENT_CONTENT_FOUNDATION_OPENSEARCH_PASSWORD
                                Environment variable for Foundation OpenSearch password
                                used when creating the KWeaver Vega catalog.
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
    --enable-foundation)
      FOUNDATION_ENABLED="true"
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
    --foundation-access-host)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-access-host requires a value" >&2
        usage
        exit 1
      fi
      FOUNDATION_ACCESS_HOST="$1"
      ;;
    --foundation-endpoint)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-endpoint requires a value" >&2
        usage
        exit 1
      fi
      FOUNDATION_ENDPOINT="$1"
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
    --foundation-package-url)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-package-url requires a value" >&2
        usage
        exit 1
      fi
      FOUNDATION_PACKAGE_URL="$1"
      ;;
    --foundation-work-dir)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-work-dir requires a value" >&2
        usage
        exit 1
      fi
      FOUNDATION_WORK_DIR="$1"
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
    --foundation-cli-endpoint)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-cli-endpoint requires a value" >&2
        usage
        exit 1
      fi
      CORE_AGENT_FOUNDATION_ENDPOINT="$1"
      ;;
    --foundation-cli-ak)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-cli-ak requires a value" >&2
        usage
        exit 1
      fi
      CORE_AGENT_FOUNDATION_AK="$1"
      ;;
    --foundation-cli-sk)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-cli-sk requires a value" >&2
        usage
        exit 1
      fi
      CORE_AGENT_FOUNDATION_SK="$1"
      ;;
    --skip-foundation-client)
      FOUNDATION_CLIENT_ENABLED="false"
      ;;
    --foundation-client-package-url)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-client-package-url requires a value" >&2
        usage
        exit 1
      fi
      FOUNDATION_CLIENT_PACKAGE_URL="$1"
      ;;
    --foundation-client-package-path)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-client-package-path requires a value" >&2
        usage
        exit 1
      fi
      FOUNDATION_CLIENT_PACKAGE_PATH="$1"
      ;;
    --foundation-client-install-root)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-client-install-root requires a value" >&2
        usage
        exit 1
      fi
      FOUNDATION_CLIENT_INSTALL_ROOT="$1"
      ;;
    --foundation-client-force-reinstall)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --foundation-client-force-reinstall requires a value" >&2
        usage
        exit 1
      fi
      FOUNDATION_CLIENT_FORCE_REINSTALL="$1"
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
    --agent-content-deploy-skill-dependencies)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-deploy-skill-dependencies requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_DEPLOY_SKILL_DEPENDENCIES="$1"
      ;;
    --agent-content-skill-dependencies-session-id)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-skill-dependencies-session-id requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_SKILL_DEPENDENCIES_SESSION_ID="$1"
      ;;
    --agent-content-skill-dependencies-python-package-index-url)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-skill-dependencies-python-package-index-url requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_SKILL_DEPENDENCIES_PYTHON_PACKAGE_INDEX_URL="$1"
      ;;
    --agent-content-vega-skip-kweaver-data-views)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-vega-skip-kweaver-data-views requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_VEGA_SKIP_KWEAVER_DATA_VIEWS="$1"
      ;;
    --agent-content-foundation-vega-host)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-foundation-vega-host requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_FOUNDATION_VEGA_HOST="$1"
      ;;
    --agent-content-foundation-vega-port)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-foundation-vega-port requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_FOUNDATION_VEGA_PORT="$1"
      if [[ ! "${AGENT_CONTENT_FOUNDATION_VEGA_PORT}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --agent-content-foundation-vega-port must be numeric" >&2
        usage
        exit 1
      fi
      ;;
    --agent-content-foundation-vega-username)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --agent-content-foundation-vega-username requires a value" >&2
        usage
        exit 1
      fi
      AGENT_CONTENT_FOUNDATION_VEGA_USERNAME="$1"
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

foundation_cli_arg_count=0
for foundation_cli_value in "${CORE_AGENT_FOUNDATION_ENDPOINT}" "${CORE_AGENT_FOUNDATION_AK}" "${CORE_AGENT_FOUNDATION_SK}"; do
  if [[ -n "${foundation_cli_value}" ]]; then
    foundation_cli_arg_count=$((foundation_cli_arg_count + 1))
  fi
done
if [[ "${foundation_cli_arg_count}" -ne 0 && "${foundation_cli_arg_count}" -ne 3 ]]; then
  echo "ERROR: Foundation CLI credentials must be supplied as a complete endpoint/AK/SK set." >&2
  echo "Use FOUNDATION_CLI_ENDPOINT/FOUNDATION_CLI_AK/FOUNDATION_CLI_SK or all three --foundation-cli-* options." >&2
  usage
  exit 1
fi
if [[ -n "${CORE_AGENT_FOUNDATION_ENDPOINT}" ]]; then
  export FOUNDATION_CLI_ENDPOINT="${CORE_AGENT_FOUNDATION_ENDPOINT}"
  export FOUNDATION_CLI_AK="${CORE_AGENT_FOUNDATION_AK}"
  export FOUNDATION_CLI_SK="${CORE_AGENT_FOUNDATION_SK}"
fi

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
  if [[ -n "${FOUNDATION_ACCESS_HOST}" ]]; then
    extra_vars+=(-e "foundation_access_host=${FOUNDATION_ACCESS_HOST}")
  fi
  if [[ -n "${FOUNDATION_ENDPOINT}" ]]; then
    extra_vars+=(-e "foundation_endpoint=${FOUNDATION_ENDPOINT}")
  fi
  if [[ -n "${FOUNDATION_PACKAGE_PATH}" ]]; then
    extra_vars+=(-e "foundation_package_path=${FOUNDATION_PACKAGE_PATH}")
  fi
  if [[ -n "${FOUNDATION_PACKAGE_URL}" ]]; then
    extra_vars+=(-e "foundation_package_url=${FOUNDATION_PACKAGE_URL}")
  fi
  if [[ -n "${FOUNDATION_WORK_DIR}" ]]; then
    extra_vars+=(-e "foundation_work_dir=${FOUNDATION_WORK_DIR}")
  fi
  if [[ -n "${FOUNDATION_INSTALL_ROOT}" ]]; then
    extra_vars+=(-e "foundation_install_root=${FOUNDATION_INSTALL_ROOT}")
  fi
  if [[ -n "${FOUNDATION_CLIENT_ENABLED}" ]]; then
    extra_vars+=(-e "foundation_client_enabled=${FOUNDATION_CLIENT_ENABLED}")
  fi
  if [[ -n "${FOUNDATION_CLIENT_PACKAGE_URL}" ]]; then
    extra_vars+=(-e "foundation_client_package_url=${FOUNDATION_CLIENT_PACKAGE_URL}")
  fi
  if [[ -n "${FOUNDATION_CLIENT_PACKAGE_PATH}" ]]; then
    extra_vars+=(-e "foundation_client_package_path=${FOUNDATION_CLIENT_PACKAGE_PATH}")
  fi
  if [[ -n "${FOUNDATION_CLIENT_INSTALL_ROOT}" ]]; then
    extra_vars+=(-e "foundation_client_install_root=${FOUNDATION_CLIENT_INSTALL_ROOT}")
  fi
  if [[ -n "${FOUNDATION_CLIENT_FORCE_REINSTALL}" ]]; then
    extra_vars+=(-e "foundation_client_force_reinstall=${FOUNDATION_CLIENT_FORCE_REINSTALL}")
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
  if [[ -n "${AGENT_CONTENT_DEPLOY_SKILL_DEPENDENCIES}" ]]; then
    extra_vars+=(-e "agent_content_deploy_skill_dependencies=${AGENT_CONTENT_DEPLOY_SKILL_DEPENDENCIES}")
  fi
  if [[ -n "${AGENT_CONTENT_SKILL_DEPENDENCIES_SESSION_ID}" ]]; then
    extra_vars+=(-e "agent_content_skill_dependencies_session_id=${AGENT_CONTENT_SKILL_DEPENDENCIES_SESSION_ID}")
  fi
  if [[ -n "${AGENT_CONTENT_SKILL_DEPENDENCIES_PYTHON_PACKAGE_INDEX_URL}" ]]; then
    extra_vars+=(-e "agent_content_skill_dependencies_python_package_index_url=${AGENT_CONTENT_SKILL_DEPENDENCIES_PYTHON_PACKAGE_INDEX_URL}")
  fi
  if [[ -n "${AGENT_CONTENT_VEGA_SKIP_KWEAVER_DATA_VIEWS}" ]]; then
    extra_vars+=(-e "agent_content_vega_skip_kweaver_data_views=${AGENT_CONTENT_VEGA_SKIP_KWEAVER_DATA_VIEWS}")
  fi
  if [[ -n "${AGENT_CONTENT_FOUNDATION_VEGA_HOST}" ]]; then
    extra_vars+=(-e "agent_content_foundation_vega_host=${AGENT_CONTENT_FOUNDATION_VEGA_HOST}")
  fi
  if [[ -n "${AGENT_CONTENT_FOUNDATION_VEGA_PORT}" ]]; then
    extra_vars+=(-e "agent_content_foundation_vega_port=${AGENT_CONTENT_FOUNDATION_VEGA_PORT}")
  fi
  if [[ -n "${AGENT_CONTENT_FOUNDATION_VEGA_USERNAME}" ]]; then
    extra_vars+=(-e "agent_content_foundation_vega_username=${AGENT_CONTENT_FOUNDATION_VEGA_USERNAME}")
  fi
  if [[ -n "${AGENT_CONTENT_FOUNDATION_VEGA_PASSWORD}" ]]; then
    extra_vars+=(-e "agent_content_foundation_vega_password=${AGENT_CONTENT_FOUNDATION_VEGA_PASSWORD}")
  fi

  ansible-playbook \
    -i "${INVENTORY_PATH}" \
    "${ANSIBLE_DIR}/site.yml" \
    -e "deployment_profile=${DEPLOYMENT_PROFILE}" \
    "${extra_vars[@]}" \
    --tags "${tag}"
}

echo "=== 1. Prepare environment ==="
run_stage prepare

if [[ "${DEPLOYMENT_PROFILE}" == "agent-content-only" ]]; then
  echo "=== 2. Deploy AnyBackup Agent content only ==="
  run_stage deploy-agent-content
  echo "=== Agent content flow finished ==="
  echo "Note: profile = ${DEPLOYMENT_PROFILE}"
  echo "Note: inventory = ${INVENTORY_PATH}"
  echo "Note: v9_infra and the 5 business service Helm releases were not touched."
  exit 0
fi

echo "=== 2. Kubernetes cluster bootstrap / idempotent check ==="
run_stage k8s-cluster

echo "=== 3. K8s / Ingress / network preflight ==="
run_stage network-preflight

if [[ "${DEPLOYMENT_PROFILE}" == "kweaver-core-only" ]]; then
  echo "=== 4. Deploy v9_infra + Ingress + KWeaver Core online ==="
else
  echo "=== 4. Deploy platform services ==="
fi
run_stage deploy-services

if [[ "${DEPLOYMENT_PROFILE}" == "full" ]]; then
  echo "=== 5. Deploy AnyBackup Agent content ==="
  run_stage deploy-agent-content

  echo "=== 6. Build, import, and release business services ==="
  run_stage app-services
fi

echo "=== 7. Publish network entrypoint ==="
run_stage publish-network

echo "=== 8. Verify deployment ==="
run_stage verify

echo "=== Install flow finished ==="
echo "Note: profile = ${DEPLOYMENT_PROFILE}"
echo "Note: inventory = ${INVENTORY_PATH}"
echo "Note: KWeaver Core is cloned from https://github.com/kweaver-ai/kweaver-core.git and installed from release 0.6.0."
echo "Note: v9_infra PostgreSQL / RabbitMQ / Redis / OpenSearch are still deployed for business services."
