#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

DB_ENGINE="${VEGA_DB_ENGINE:-postgresql}"
DB_HOST="${VEGA_DB_HOST:-}"
DB_PORT="${VEGA_DB_PORT:-}"
DB_NAME="${VEGA_DB_NAME:-ExperienceBKNDB}"
DB_USER="${VEGA_DB_USER:-}"
DB_PASSWORD="${VEGA_DB_PASSWORD:-}"
DB_SCHEMA="${VEGA_DB_SCHEMA:-public}"
POSTGRES_IMPORT_MODE="${POSTGRES_IMPORT_MODE:-auto}"
K8S_NAMESPACE="${K8S_NAMESPACE:-v9-system}"
POSTGRES_POD="${POSTGRES_POD:-v9-infra-postgres-0}"
POSTGRES_USERNAME="${POSTGRES_USERNAME:-}"
FOUNDATION_VEGA_ENABLED="${FOUNDATION_VEGA_ENABLED:-1}"
FOUNDATION_DB_ENGINE="${FOUNDATION_DB_ENGINE:-mariadb}"
FOUNDATION_DB_HOST="${FOUNDATION_DB_HOST:-}"
FOUNDATION_DB_PORT="${FOUNDATION_DB_PORT:-9602}"
FOUNDATION_DB_USER="${FOUNDATION_DB_USER:-${FOUNDATION_DB_USERNAME:-}}"
FOUNDATION_DB_PASSWORD="${FOUNDATION_DB_PASSWORD:-}"
FOUNDATION_DB_SCHEMA="${FOUNDATION_DB_SCHEMA:-}"
KWEAVER_BUSINESS_DOMAIN="${KWEAVER_BUSINESS_DOMAIN:-${VEGA_BUSINESS_DOMAIN:-bd_public}}"
VEGA_EXPERIENCE_CATALOG_NAME="${VEGA_EXPERIENCE_CATALOG_NAME:-${VEGA_CATALOG_NAME:-恢复经验知识网络数据连接}}"
VEGA_COMMON_CATALOG_NAME="${VEGA_COMMON_CATALOG_NAME:-CommonServiceDB-client}"
VEGA_COMMON_DB_NAME="${VEGA_COMMON_DB_NAME:-CommonServiceDB}"
VEGA_COMMON_DB_SCHEMA="${VEGA_COMMON_DB_SCHEMA:-public}"
VEGA_MULTI_STORAGE_CATALOG_NAME="${VEGA_MULTI_STORAGE_CATALOG_NAME:-MultiStorageSvcMgmServiceDB-storageservice}"
VEGA_MULTI_STORAGE_DB_NAME="${VEGA_MULTI_STORAGE_DB_NAME:-MultiStorageSvcMgmServiceDB}"
VEGA_MULTI_STORAGE_DB_SCHEMA="${VEGA_MULTI_STORAGE_DB_SCHEMA:-public}"
VEGA_STORAGE_RES_CATALOG_NAME="${VEGA_STORAGE_RES_CATALOG_NAME:-StorageResMgmServiceDB-poolv8}"
VEGA_STORAGE_RES_DB_NAME="${VEGA_STORAGE_RES_DB_NAME:-StorageResMgmServiceDB}"
VEGA_STORAGE_RES_DB_SCHEMA="${VEGA_STORAGE_RES_DB_SCHEMA:-public}"
VEGA_HYPER_BACKUP_CATALOG_NAME="${VEGA_HYPER_BACKUP_CATALOG_NAME:-HyperBackupMgmServiceDB-protectobject}"
VEGA_HYPER_BACKUP_DB_NAME="${VEGA_HYPER_BACKUP_DB_NAME:-HyperBackupMgmServiceDB}"
VEGA_HYPER_BACKUP_DB_SCHEMA="${VEGA_HYPER_BACKUP_DB_SCHEMA:-public}"
VEGA_HYPER_JOB_CATALOG_NAME="${VEGA_HYPER_JOB_CATALOG_NAME:-HyperJobWorkerServiceDB-job}"
VEGA_HYPER_JOB_DB_NAME="${VEGA_HYPER_JOB_DB_NAME:-HyperJobWorkerServiceDB}"
VEGA_HYPER_JOB_DB_SCHEMA="${VEGA_HYPER_JOB_DB_SCHEMA:-public}"
KWEAVER_EXPERIENCE_DATASOURCE_NAME="${KWEAVER_EXPERIENCE_DATASOURCE_NAME:-$VEGA_EXPERIENCE_CATALOG_NAME}"
KWEAVER_COMMON_DATASOURCE_NAME="${KWEAVER_COMMON_DATASOURCE_NAME:-CommonServiceDB}"
KWEAVER_MULTI_STORAGE_DATASOURCE_NAME="${KWEAVER_MULTI_STORAGE_DATASOURCE_NAME:-MultiStorageSvcMgmServiceDB}"
KWEAVER_STORAGE_RES_DATASOURCE_NAME="${KWEAVER_STORAGE_RES_DATASOURCE_NAME:-StorageResMgmServiceDB}"
KWEAVER_HYPER_BACKUP_DATASOURCE_NAME="${KWEAVER_HYPER_BACKUP_DATASOURCE_NAME:-HyperBackupMgmServiceDB}"
KWEAVER_HYPER_JOB_DATASOURCE_NAME="${KWEAVER_HYPER_JOB_DATASOURCE_NAME:-HyperJobWorkerServiceDB}"
SKIP_VEGA_CATALOG="${VEGA_SKIP_CATALOG:-0}"
SKIP_KWEAVER_DATA_VIEWS="${KWEAVER_SKIP_DATA_VIEWS:-${VEGA_SKIP_DATA_VIEWS:-0}}"

TMP_DIR=""
MYSQL_DEFAULTS_FILE=""

usage() {
  cat <<'EOF'
Usage:
  ./install.sh <host> <port> <username> <password> [--engine postgresql|mysql|mariadb]
  ./install.sh <host> <port> <database> <username> <password> [--engine postgresql|mysql|mariadb]
  ./install.sh --host <host> --port <port> --username <username> --password <password> [--database ExperienceBKNDB] [--engine postgresql|mysql|mariadb]

Options:
  --engine <value>      Database engine. Supported: postgresql, mysql, mariadb. Default: postgresql.
  --host <value>        Database host or host:port.
  --port <value>        Database port. Default: 5432 for postgresql, 3306 for mysql/mariadb.
  --database <value>    Database name to create and initialize. Default: ExperienceBKNDB.
  --schema <value>      PostgreSQL schema used by the Vega catalog. Default: public.
  --username <value>    Database user.
  --password <value>    Database password.
  --biz-domain <value>  KWeaver business domain for Vega catalog creation. Default: bd_public.
  --import-mode <value> PostgreSQL import mode: auto, local, or kubectl. Default: auto.
  --namespace <value>   Kubernetes namespace of the PostgreSQL pod when import-mode=kubectl.
  --pod <value>         PostgreSQL pod name when import-mode=kubectl.
  --postgres-username <value>
                      PostgreSQL username used inside the pod. Default: --username.
  --skip-vega-catalog   Skip creating the Vega data connection.
  -h, --help            Show this help.

Environment variables:
  VEGA_DB_ENGINE
  VEGA_DB_HOST
  VEGA_DB_PORT
  VEGA_DB_NAME
  VEGA_DB_USER
  VEGA_DB_PASSWORD
  VEGA_DB_SCHEMA
  POSTGRES_IMPORT_MODE
  K8S_NAMESPACE
  POSTGRES_POD
  POSTGRES_USERNAME
  FOUNDATION_VEGA_ENABLED
  FOUNDATION_DB_ENGINE
  FOUNDATION_DB_HOST
  FOUNDATION_DB_PORT
  FOUNDATION_DB_USER
  FOUNDATION_DB_PASSWORD
  FOUNDATION_DB_SCHEMA
  VEGA_EXPERIENCE_CATALOG_NAME
  VEGA_COMMON_CATALOG_NAME
  VEGA_COMMON_DB_NAME
  VEGA_COMMON_DB_SCHEMA
  VEGA_MULTI_STORAGE_CATALOG_NAME
  VEGA_MULTI_STORAGE_DB_NAME
  VEGA_MULTI_STORAGE_DB_SCHEMA
  VEGA_STORAGE_RES_CATALOG_NAME
  VEGA_STORAGE_RES_DB_NAME
  VEGA_STORAGE_RES_DB_SCHEMA
  VEGA_HYPER_BACKUP_CATALOG_NAME
  VEGA_HYPER_BACKUP_DB_NAME
  VEGA_HYPER_BACKUP_DB_SCHEMA
  VEGA_HYPER_JOB_CATALOG_NAME
  VEGA_HYPER_JOB_DB_NAME
  VEGA_HYPER_JOB_DB_SCHEMA
  VEGA_BUSINESS_DOMAIN
  KWEAVER_BUSINESS_DOMAIN
  VEGA_SKIP_CATALOG
  KWEAVER_SKIP_DATA_VIEWS or VEGA_SKIP_DATA_VIEWS
                      Skip KWeaver datasource/dataview creation. Keep this enabled
                      for KWeaver Core-only installs that do not include Etrino.

Notes:
  1. The installer creates the target database if the account has permission.
  2. It creates five recovery experience tables and imports CSV data from ./data.
  3. It creates or updates two Vega PostgreSQL data connections:
     - 恢复经验知识网络数据连接 -> ExperienceBKNDB
     - CommonServiceDB-client -> CommonServiceDB
     - MultiStorageSvcMgmServiceDB-storageservice -> MultiStorageSvcMgmServiceDB
     - StorageResMgmServiceDB-poolv8 -> StorageResMgmServiceDB
     - HyperBackupMgmServiceDB-protectobject -> HyperBackupMgmServiceDB
     - HyperJobWorkerServiceDB-job -> HyperJobWorkerServiceDB
  4. The Vega connections use JDBC and schema public by default.
  5. Re-running the installer truncates only these five target tables before importing.
  6. Vega catalog creation requires the kweaver CLI to be installed and authenticated.
EOF
}

log() {
  printf '[INFO] %s\n' "$*"
}

error() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || error "Required command not found: $1"
}

require_data_file() {
  local file="$DATA_DIR/$1"
  [[ -f "$file" ]] || error "Required data file not found: $file"
}

validate_database_name() {
  [[ "$DB_NAME" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || error "Database name must match ^[A-Za-z_][A-Za-z0-9_]*$"
}

validate_port() {
  [[ "$DB_PORT" =~ ^[0-9]+$ ]] || error "Database port must be numeric"
}

parse_host_port() {
  if [[ -z "$DB_PORT" && "$DB_HOST" == *:* && "$DB_HOST" != *"]"* ]]; then
    DB_PORT="${DB_HOST##*:}"
    DB_HOST="${DB_HOST%:*}"
  fi
}

default_port() {
  if [[ -n "$DB_PORT" ]]; then
    return 0
  fi

  case "$DB_ENGINE" in
    postgresql)
      DB_PORT="5432"
      ;;
    mysql|mariadb)
      DB_PORT="3306"
      ;;
  esac
}

normalize_engine() {
  case "$DB_ENGINE" in
    postgres|postgresql|pg)
      DB_ENGINE="postgresql"
      ;;
    mysql)
      DB_ENGINE="mysql"
      ;;
    mariadb)
      DB_ENGINE="mariadb"
      ;;
    *)
      error "Unsupported engine: $DB_ENGINE"
      ;;
  esac
}

normalize_foundation_engine() {
  case "$FOUNDATION_DB_ENGINE" in
    postgres|postgresql|pg)
      FOUNDATION_DB_ENGINE="postgresql"
      ;;
    mysql)
      FOUNDATION_DB_ENGINE="mysql"
      ;;
    mariadb)
      FOUNDATION_DB_ENGINE="mariadb"
      ;;
    *)
      error "Unsupported Foundation database engine: $FOUNDATION_DB_ENGINE"
      ;;
  esac
}

foundation_vega_enabled() {
  case "${FOUNDATION_VEGA_ENABLED,,}" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

parse_args() {
  local positional=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --engine)
        [[ $# -ge 2 ]] || error "--engine requires a value"
        DB_ENGINE="$2"
        shift 2
        ;;
      --host)
        [[ $# -ge 2 ]] || error "--host requires a value"
        DB_HOST="$2"
        shift 2
        ;;
      --port)
        [[ $# -ge 2 ]] || error "--port requires a value"
        DB_PORT="$2"
        shift 2
        ;;
      --database|--db-name)
        [[ $# -ge 2 ]] || error "$1 requires a value"
        DB_NAME="$2"
        shift 2
        ;;
      --schema)
        [[ $# -ge 2 ]] || error "--schema requires a value"
        DB_SCHEMA="$2"
        shift 2
        ;;
      --username|--user)
        [[ $# -ge 2 ]] || error "$1 requires a value"
        DB_USER="$2"
        shift 2
        ;;
      --password)
        [[ $# -ge 2 ]] || error "--password requires a value"
        DB_PASSWORD="$2"
        shift 2
        ;;
      --biz-domain)
        [[ $# -ge 2 ]] || error "--biz-domain requires a value"
        KWEAVER_BUSINESS_DOMAIN="$2"
        shift 2
        ;;
      --import-mode)
        [[ $# -ge 2 ]] || error "--import-mode requires a value"
        POSTGRES_IMPORT_MODE="$2"
        shift 2
        ;;
      --namespace)
        [[ $# -ge 2 ]] || error "--namespace requires a value"
        K8S_NAMESPACE="$2"
        shift 2
        ;;
      --pod)
        [[ $# -ge 2 ]] || error "--pod requires a value"
        POSTGRES_POD="$2"
        shift 2
        ;;
      --postgres-username)
        [[ $# -ge 2 ]] || error "--postgres-username requires a value"
        POSTGRES_USERNAME="$2"
        shift 2
        ;;
      --skip-vega-catalog)
        SKIP_VEGA_CATALOG="1"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do
          positional+=("$1")
          shift
        done
        ;;
      -*)
        error "Unknown option: $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#positional[@]} -gt 0 ]]; then
    [[ ${#positional[@]} -eq 3 || ${#positional[@]} -eq 4 || ${#positional[@]} -ge 5 ]] || error "Positional mode requires: <host> <port> <username> <password> or <host> <port> <database> <username> <password>"
    DB_HOST="${positional[0]}"
    if [[ ${#positional[@]} -eq 3 ]]; then
      DB_USER="${positional[1]}"
      DB_PASSWORD="${positional[2]}"
    elif [[ "${positional[1]}" =~ ^[0-9]+$ ]]; then
      DB_PORT="${positional[1]}"
      if [[ ${#positional[@]} -eq 4 ]]; then
        DB_USER="${positional[2]}"
        DB_PASSWORD="${positional[3]}"
      else
        DB_NAME="${positional[2]}"
        DB_USER="${positional[3]}"
        DB_PASSWORD="${positional[4]}"
      fi
      if [[ ${#positional[@]} -ge 6 ]]; then
        DB_ENGINE="${positional[5]}"
      fi
    else
      DB_NAME="${positional[1]}"
      DB_USER="${positional[2]}"
      DB_PASSWORD="${positional[3]}"
      if [[ ${#positional[@]} -ge 5 ]]; then
        DB_ENGINE="${positional[4]}"
      fi
    fi
  fi
}

assert_inputs() {
  [[ -n "$DB_HOST" ]] || error "Missing database host"
  [[ -n "$DB_NAME" ]] || error "Missing database name"
  [[ -n "$DB_USER" ]] || error "Missing database username"
  [[ -n "$DB_PASSWORD" ]] || error "Missing database password"
  [[ -d "$DATA_DIR" ]] || error "Data directory not found: $DATA_DIR"

  require_data_file "availability_checkpoint_template.csv"
  require_data_file "fault_pattern.csv"
  require_data_file "recovery_capability.csv"
  require_data_file "recovery_strategy_template.csv"
  require_data_file "risk_rule.csv"

  validate_database_name
  parse_host_port
  normalize_engine
  normalize_foundation_engine
  default_port
  validate_port
  POSTGRES_USERNAME="${POSTGRES_USERNAME:-$DB_USER}"

  if foundation_vega_enabled; then
    [[ -n "$FOUNDATION_DB_HOST" ]] || error "Missing Foundation database host for Vega catalog creation"
    [[ -n "$FOUNDATION_DB_PORT" ]] || error "Missing Foundation database port for Vega catalog creation"
    [[ -n "$FOUNDATION_DB_USER" ]] || error "Missing Foundation database username for Vega catalog creation"
    [[ -n "$FOUNDATION_DB_PASSWORD" ]] || error "Missing Foundation database password for Vega catalog creation"
    [[ "$FOUNDATION_DB_PORT" =~ ^[0-9]+$ ]] || error "Foundation database port must be numeric"
  fi
}

run_psql() {
  local database="$1"
  shift

  if [[ -n "$DB_PORT" ]]; then
    PGPASSWORD="$DB_PASSWORD" PGCLIENTENCODING=UTF8 PGPORT="$DB_PORT" psql -h "$DB_HOST" -U "$DB_USER" -d "$database" -v ON_ERROR_STOP=1 "$@"
  else
    PGPASSWORD="$DB_PASSWORD" PGCLIENTENCODING=UTF8 psql -h "$DB_HOST" -U "$DB_USER" -d "$database" -v ON_ERROR_STOP=1 "$@"
  fi
}

create_postgresql_database() {
  if run_psql "$DB_NAME" -qAt -c "SELECT 1;" >/dev/null 2>&1; then
    log "PostgreSQL database already exists: $DB_NAME"
    return 0
  fi

  log "Creating PostgreSQL database: $DB_NAME"
  run_psql postgres -v db_name="$DB_NAME" -c 'CREATE DATABASE :"db_name";'
}

create_postgresql_schema() {
  log "Creating PostgreSQL tables"
  run_psql "$DB_NAME" <<'SQL'
CREATE TABLE IF NOT EXISTS "availability_checkpoint_template" (
  "checkpointTemplateId" TEXT PRIMARY KEY,
  "name" TEXT,
  "appType" TEXT,
  "checkpointType" TEXT,
  "targetScope" TEXT,
  "verificationMethod" TEXT,
  "successCriteria" TEXT,
  "faultPatternId" TEXT,
  "strategyTemplateId" TEXT,
  "enabled" BOOLEAN
);

CREATE TABLE IF NOT EXISTS "fault_pattern" (
  "patternId" TEXT PRIMARY KEY,
  "name" TEXT,
  "appType" TEXT,
  "faultCategory" TEXT,
  "affectedGranularity" TEXT,
  "symptomKeywords" TEXT,
  "intentKeywords" TEXT,
  "requiredClarification" TEXT,
  "disposalHint" TEXT,
  "severityBaseline" TEXT,
  "enabled" BOOLEAN
);

CREATE TABLE IF NOT EXISTS "recovery_capability" (
  "capabilityId" TEXT PRIMARY KEY,
  "name" TEXT,
  "vendor" TEXT,
  "appType" TEXT,
  "supportedGranularity" TEXT,
  "supportedTechnique" TEXT,
  "supportedMode" TEXT,
  "supportsOriginalRestore" BOOLEAN,
  "supportsRemoteRestore" BOOLEAN,
  "supportsPointInTimeRestore" BOOLEAN,
  "supportsLogRestore" BOOLEAN,
  "tableRecoveryMode" TEXT,
  "capabilitySummary" TEXT,
  "enabled" BOOLEAN
);

CREATE TABLE IF NOT EXISTS "recovery_strategy_template" (
  "strategyTemplateId" TEXT PRIMARY KEY,
  "name" TEXT,
  "vendor" TEXT,
  "appType" TEXT,
  "faultPatternId" TEXT,
  "recoveryGranularity" TEXT,
  "destinationType" TEXT,
  "recoveryMethod" TEXT,
  "requiresRecovery" BOOLEAN,
  "strategySummary" TEXT,
  "riskBaseline" TEXT,
  "approvalRequired" BOOLEAN,
  "enabled" BOOLEAN
);

CREATE TABLE IF NOT EXISTS "risk_rule" (
  "riskRuleId" TEXT PRIMARY KEY,
  "name" TEXT,
  "appType" TEXT,
  "strategyTemplateId" TEXT,
  "triggerCondition" TEXT,
  "riskLevel" TEXT,
  "approvalRequired" BOOLEAN,
  "mitigationAdvice" TEXT,
  "enabled" BOOLEAN
);
SQL
}

escape_sql_literal() {
  local value="$1"
  printf "%s" "${value//\'/\'\'}"
}

postgresql_copy_csv() {
  local table="$1"
  local columns="$2"
  local file
  file="$(escape_sql_literal "$DATA_DIR/$3")"

  log "Importing $3 into $table"
  run_psql "$DB_NAME" <<SQL
TRUNCATE TABLE "$table";
\\copy "$table" ($columns) FROM '$file' WITH (FORMAT csv, HEADER true);
SQL
}

install_postgresql_local() {
  require_command psql
  create_postgresql_database
  create_postgresql_schema

  postgresql_copy_csv "availability_checkpoint_template" '"checkpointTemplateId", "name", "appType", "checkpointType", "targetScope", "verificationMethod", "successCriteria", "faultPatternId", "strategyTemplateId", "enabled"' "availability_checkpoint_template.csv"
  postgresql_copy_csv "fault_pattern" '"patternId", "name", "appType", "faultCategory", "affectedGranularity", "symptomKeywords", "intentKeywords", "requiredClarification", "disposalHint", "severityBaseline", "enabled"' "fault_pattern.csv"
  postgresql_copy_csv "recovery_capability" '"capabilityId", "name", "vendor", "appType", "supportedGranularity", "supportedTechnique", "supportedMode", "supportsOriginalRestore", "supportsRemoteRestore", "supportsPointInTimeRestore", "supportsLogRestore", "tableRecoveryMode", "capabilitySummary", "enabled"' "recovery_capability.csv"
  postgresql_copy_csv "recovery_strategy_template" '"strategyTemplateId", "name", "vendor", "appType", "faultPatternId", "recoveryGranularity", "destinationType", "recoveryMethod", "requiresRecovery", "strategySummary", "riskBaseline", "approvalRequired", "enabled"' "recovery_strategy_template.csv"
  postgresql_copy_csv "risk_rule" '"riskRuleId", "name", "appType", "strategyTemplateId", "triggerCondition", "riskLevel", "approvalRequired", "mitigationAdvice", "enabled"' "risk_rule.csv"
}

psql_postgres_kubectl() {
  kubectl exec -i -n "$K8S_NAMESPACE" "$POSTGRES_POD" -- \
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USERNAME" -d postgres "$@"
}

psql_target_kubectl() {
  kubectl exec -i -n "$K8S_NAMESPACE" "$POSTGRES_POD" -- \
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USERNAME" -d "$DB_NAME" "$@"
}

create_postgresql_database_kubectl() {
  local db_exists
  db_exists="$(psql_postgres_kubectl -Atc "select 1 from pg_database where datname = '$DB_NAME';")"
  if [[ "$db_exists" == "1" ]]; then
    log "PostgreSQL database already exists: $DB_NAME"
    return 0
  fi

  log "Creating PostgreSQL database through pod: $DB_NAME"
  kubectl exec -n "$K8S_NAMESPACE" "$POSTGRES_POD" -- \
    createdb -U "$POSTGRES_USERNAME" "$DB_NAME"
}

create_postgresql_schema_kubectl() {
  log "Creating PostgreSQL tables through pod"
  psql_target_kubectl <<'SQL'
CREATE TABLE IF NOT EXISTS "availability_checkpoint_template" (
  "checkpointTemplateId" TEXT PRIMARY KEY,
  "name" TEXT,
  "appType" TEXT,
  "checkpointType" TEXT,
  "targetScope" TEXT,
  "verificationMethod" TEXT,
  "successCriteria" TEXT,
  "faultPatternId" TEXT,
  "strategyTemplateId" TEXT,
  "enabled" BOOLEAN
);

CREATE TABLE IF NOT EXISTS "fault_pattern" (
  "patternId" TEXT PRIMARY KEY,
  "name" TEXT,
  "appType" TEXT,
  "faultCategory" TEXT,
  "affectedGranularity" TEXT,
  "symptomKeywords" TEXT,
  "intentKeywords" TEXT,
  "requiredClarification" TEXT,
  "disposalHint" TEXT,
  "severityBaseline" TEXT,
  "enabled" BOOLEAN
);

CREATE TABLE IF NOT EXISTS "recovery_capability" (
  "capabilityId" TEXT PRIMARY KEY,
  "name" TEXT,
  "vendor" TEXT,
  "appType" TEXT,
  "supportedGranularity" TEXT,
  "supportedTechnique" TEXT,
  "supportedMode" TEXT,
  "supportsOriginalRestore" BOOLEAN,
  "supportsRemoteRestore" BOOLEAN,
  "supportsPointInTimeRestore" BOOLEAN,
  "supportsLogRestore" BOOLEAN,
  "tableRecoveryMode" TEXT,
  "capabilitySummary" TEXT,
  "enabled" BOOLEAN
);

CREATE TABLE IF NOT EXISTS "recovery_strategy_template" (
  "strategyTemplateId" TEXT PRIMARY KEY,
  "name" TEXT,
  "vendor" TEXT,
  "appType" TEXT,
  "faultPatternId" TEXT,
  "recoveryGranularity" TEXT,
  "destinationType" TEXT,
  "recoveryMethod" TEXT,
  "requiresRecovery" BOOLEAN,
  "strategySummary" TEXT,
  "riskBaseline" TEXT,
  "approvalRequired" BOOLEAN,
  "enabled" BOOLEAN
);

CREATE TABLE IF NOT EXISTS "risk_rule" (
  "riskRuleId" TEXT PRIMARY KEY,
  "name" TEXT,
  "appType" TEXT,
  "strategyTemplateId" TEXT,
  "triggerCondition" TEXT,
  "riskLevel" TEXT,
  "approvalRequired" BOOLEAN,
  "mitigationAdvice" TEXT,
  "enabled" BOOLEAN
);
SQL
}

postgresql_copy_csv_kubectl() {
  local table="$1"
  local columns="$2"
  local csv_name="$3"
  local file="$DATA_DIR/$csv_name"

  log "Importing $csv_name into $table through pod"
  psql_target_kubectl -c "TRUNCATE TABLE \"$table\";"
  kubectl exec -i -n "$K8S_NAMESPACE" "$POSTGRES_POD" -- \
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USERNAME" -d "$DB_NAME" \
    -c "\\copy \"$table\" ($columns) FROM STDIN WITH (FORMAT csv, HEADER true);" <"$file"
}

install_postgresql_kubectl() {
  require_command kubectl
  kubectl get pod -n "$K8S_NAMESPACE" "$POSTGRES_POD" >/dev/null
  create_postgresql_database_kubectl
  create_postgresql_schema_kubectl

  postgresql_copy_csv_kubectl "availability_checkpoint_template" '"checkpointTemplateId", "name", "appType", "checkpointType", "targetScope", "verificationMethod", "successCriteria", "faultPatternId", "strategyTemplateId", "enabled"' "availability_checkpoint_template.csv"
  postgresql_copy_csv_kubectl "fault_pattern" '"patternId", "name", "appType", "faultCategory", "affectedGranularity", "symptomKeywords", "intentKeywords", "requiredClarification", "disposalHint", "severityBaseline", "enabled"' "fault_pattern.csv"
  postgresql_copy_csv_kubectl "recovery_capability" '"capabilityId", "name", "vendor", "appType", "supportedGranularity", "supportedTechnique", "supportedMode", "supportsOriginalRestore", "supportsRemoteRestore", "supportsPointInTimeRestore", "supportsLogRestore", "tableRecoveryMode", "capabilitySummary", "enabled"' "recovery_capability.csv"
  postgresql_copy_csv_kubectl "recovery_strategy_template" '"strategyTemplateId", "name", "vendor", "appType", "faultPatternId", "recoveryGranularity", "destinationType", "recoveryMethod", "requiresRecovery", "strategySummary", "riskBaseline", "approvalRequired", "enabled"' "recovery_strategy_template.csv"
  postgresql_copy_csv_kubectl "risk_rule" '"riskRuleId", "name", "appType", "strategyTemplateId", "triggerCondition", "riskLevel", "approvalRequired", "mitigationAdvice", "enabled"' "risk_rule.csv"
}

install_postgresql() {
  case "$POSTGRES_IMPORT_MODE" in
    local)
      install_postgresql_local
      ;;
    kubectl)
      install_postgresql_kubectl
      ;;
    auto)
      if command -v psql >/dev/null 2>&1; then
        install_postgresql_local
      else
        install_postgresql_kubectl
      fi
      ;;
    *)
      error "Unsupported PostgreSQL import mode: $POSTGRES_IMPORT_MODE"
      ;;
  esac
}

prepare_mysql_defaults_file() {
  TMP_DIR="$(mktemp -d)"
  MYSQL_DEFAULTS_FILE="$TMP_DIR/mysql.cnf"

  {
    printf '[client]\n'
    printf 'host=%s\n' "$DB_HOST"
    if [[ -n "$DB_PORT" ]]; then
      printf 'port=%s\n' "$DB_PORT"
    fi
    printf 'user=%s\n' "$DB_USER"
    printf 'password=%s\n' "$DB_PASSWORD"
    printf 'local-infile=1\n'
    printf 'default-character-set=utf8mb4\n'
  } >"$MYSQL_DEFAULTS_FILE"
  chmod 600 "$MYSQL_DEFAULTS_FILE"
}

prepare_mysql_csv_files() {
  require_command sed
  for file in "$DATA_DIR"/*.csv; do
    sed 's/\r$//' "$file" >"$TMP_DIR/$(basename "$file")"
  done
}

mysql_exec() {
  mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" --local-infile=1 "$@"
}

mysql_exec_db() {
  mysql_exec "$DB_NAME" "$@"
}

create_mysql_database() {
  log "Creating MySQL/MariaDB database if needed: $DB_NAME"
  mysql_exec -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
}

create_mysql_schema() {
  log "Creating MySQL/MariaDB tables"
  mysql_exec_db <<'SQL'
CREATE TABLE IF NOT EXISTS `availability_checkpoint_template` (
  `checkpointTemplateId` VARCHAR(255) PRIMARY KEY,
  `name` TEXT,
  `appType` TEXT,
  `checkpointType` TEXT,
  `targetScope` TEXT,
  `verificationMethod` TEXT,
  `successCriteria` TEXT,
  `faultPatternId` TEXT,
  `strategyTemplateId` TEXT,
  `enabled` BOOLEAN
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `fault_pattern` (
  `patternId` VARCHAR(255) PRIMARY KEY,
  `name` TEXT,
  `appType` TEXT,
  `faultCategory` TEXT,
  `affectedGranularity` TEXT,
  `symptomKeywords` TEXT,
  `intentKeywords` TEXT,
  `requiredClarification` TEXT,
  `disposalHint` TEXT,
  `severityBaseline` TEXT,
  `enabled` BOOLEAN
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `recovery_capability` (
  `capabilityId` VARCHAR(255) PRIMARY KEY,
  `name` TEXT,
  `vendor` TEXT,
  `appType` TEXT,
  `supportedGranularity` TEXT,
  `supportedTechnique` TEXT,
  `supportedMode` TEXT,
  `supportsOriginalRestore` BOOLEAN,
  `supportsRemoteRestore` BOOLEAN,
  `supportsPointInTimeRestore` BOOLEAN,
  `supportsLogRestore` BOOLEAN,
  `tableRecoveryMode` TEXT,
  `capabilitySummary` TEXT,
  `enabled` BOOLEAN
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `recovery_strategy_template` (
  `strategyTemplateId` VARCHAR(255) PRIMARY KEY,
  `name` TEXT,
  `vendor` TEXT,
  `appType` TEXT,
  `faultPatternId` TEXT,
  `recoveryGranularity` TEXT,
  `destinationType` TEXT,
  `recoveryMethod` TEXT,
  `requiresRecovery` BOOLEAN,
  `strategySummary` TEXT,
  `riskBaseline` TEXT,
  `approvalRequired` BOOLEAN,
  `enabled` BOOLEAN
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `risk_rule` (
  `riskRuleId` VARCHAR(255) PRIMARY KEY,
  `name` TEXT,
  `appType` TEXT,
  `strategyTemplateId` TEXT,
  `triggerCondition` TEXT,
  `riskLevel` TEXT,
  `approvalRequired` BOOLEAN,
  `mitigationAdvice` TEXT,
  `enabled` BOOLEAN
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SQL
}

escape_mysql_literal() {
  local value="$1"
  value="${value//\\/\\\\}"
  printf "%s" "${value//\'/\\\'}"
}

mysql_load_csv() {
  local table="$1"
  local columns="$2"
  local file
  local set_clause="${4:-}"
  file="$(escape_mysql_literal "$TMP_DIR/$3")"

  log "Importing $3 into $table"
  local sql="TRUNCATE TABLE \`$table\`; LOAD DATA LOCAL INFILE '$file' INTO TABLE \`$table\` CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' ENCLOSED BY '\"' LINES TERMINATED BY '\n' IGNORE 1 LINES ($columns)"
  if [[ -n "$set_clause" ]]; then
    sql="$sql SET $set_clause"
  fi
  mysql_exec_db -e "$sql;"
}

install_mysql() {
  require_command mysql
  prepare_mysql_defaults_file
  prepare_mysql_csv_files
  create_mysql_database
  create_mysql_schema

  mysql_load_csv "availability_checkpoint_template" '`checkpointTemplateId`, `name`, `appType`, `checkpointType`, `targetScope`, `verificationMethod`, `successCriteria`, `faultPatternId`, `strategyTemplateId`, @enabled' "availability_checkpoint_template.csv" '`enabled` = (LOWER(@enabled) = "true")'
  mysql_load_csv "fault_pattern" '`patternId`, `name`, `appType`, `faultCategory`, `affectedGranularity`, `symptomKeywords`, `intentKeywords`, `requiredClarification`, `disposalHint`, `severityBaseline`, @enabled' "fault_pattern.csv" '`enabled` = (LOWER(@enabled) = "true")'
  mysql_load_csv "recovery_capability" '`capabilityId`, `name`, `vendor`, `appType`, `supportedGranularity`, `supportedTechnique`, `supportedMode`, @supportsOriginalRestore, @supportsRemoteRestore, @supportsPointInTimeRestore, @supportsLogRestore, `tableRecoveryMode`, `capabilitySummary`, @enabled' "recovery_capability.csv" '`supportsOriginalRestore` = (LOWER(@supportsOriginalRestore) = "true"), `supportsRemoteRestore` = (LOWER(@supportsRemoteRestore) = "true"), `supportsPointInTimeRestore` = (LOWER(@supportsPointInTimeRestore) = "true"), `supportsLogRestore` = (LOWER(@supportsLogRestore) = "true"), `enabled` = (LOWER(@enabled) = "true")'
  mysql_load_csv "recovery_strategy_template" '`strategyTemplateId`, `name`, `vendor`, `appType`, `faultPatternId`, `recoveryGranularity`, `destinationType`, `recoveryMethod`, @requiresRecovery, `strategySummary`, `riskBaseline`, @approvalRequired, @enabled' "recovery_strategy_template.csv" '`requiresRecovery` = (LOWER(@requiresRecovery) = "true"), `approvalRequired` = (LOWER(@approvalRequired) = "true"), `enabled` = (LOWER(@enabled) = "true")'
  mysql_load_csv "risk_rule" '`riskRuleId`, `name`, `appType`, `strategyTemplateId`, `triggerCondition`, `riskLevel`, @approvalRequired, `mitigationAdvice`, @enabled' "risk_rule.csv" '`approvalRequired` = (LOWER(@approvalRequired) = "true"), `enabled` = (LOWER(@enabled) = "true")'
}

build_vega_connector_config() {
  local connector_engine="$1"
  local connector_host="$2"
  local connector_port="$3"
  local connector_database="$4"
  local connector_schema="$5"
  local connector_user="$6"
  local connector_password="$7"

  require_command python3

  VEGA_DB_ENGINE="$connector_engine" \
  VEGA_DB_HOST="$connector_host" \
  VEGA_DB_PORT="$connector_port" \
  VEGA_DB_NAME="$connector_database" \
  VEGA_DB_SCHEMA="$connector_schema" \
  VEGA_DB_USER="$connector_user" \
  VEGA_DB_PASSWORD="$connector_password" \
  python3 <<'PY'
import json
import os

engine = os.environ["VEGA_DB_ENGINE"]
host = os.environ["VEGA_DB_HOST"]
port = int(os.environ["VEGA_DB_PORT"])
database = os.environ["VEGA_DB_NAME"]
schema = os.environ["VEGA_DB_SCHEMA"]

config = {
    "host": host,
    "port": port,
    "username": os.environ["VEGA_DB_USER"],
    "password": os.environ["VEGA_DB_PASSWORD"],
    "databases": [database],
    "database": database,
    "database_name": database,
    "connect_protocol": "jdbc",
}

if engine == "postgresql":
    config["databases"] = [database]
    if schema:
        config["schema"] = schema
        config["schema_name"] = schema
    config["jdbc_url"] = f"jdbc:postgresql://{host}:{port}/{database}"
elif engine == "mysql":
    config["jdbc_url"] = f"jdbc:mysql://{host}:{port}/{database}"
elif engine == "mariadb":
    config["jdbc_url"] = f"jdbc:mariadb://{host}:{port}/{database}"
else:
    raise SystemExit(f"unsupported connector engine: {engine}")

print(json.dumps(config, ensure_ascii=False, separators=(",", ":")))
PY
}

find_vega_catalog_ids_by_name() {
  local catalog_name="$1"

  require_command python3

  local output
  output="$(kweaver vega catalog list --limit 100 -bd "$KWEAVER_BUSINESS_DOMAIN" --pretty)"

  VEGA_CATALOG_LIST_JSON="$output" \
  VEGA_CATALOG_NAME="$catalog_name" \
  python3 <<'PY'
import json
import os

text = os.environ.get("VEGA_CATALOG_LIST_JSON", "").strip()
target_name = os.environ["VEGA_CATALOG_NAME"]
if not text:
    raise SystemExit(0)

data = json.loads(text)
if isinstance(data, list):
    entries = data
elif isinstance(data, dict):
    entries = (
        data.get("entries")
        or data.get("data")
        or data.get("items")
        or data.get("catalogs")
        or []
    )
else:
    entries = []

for item in entries:
    if not isinstance(item, dict):
        continue
    if item.get("name") != target_name:
        continue
    catalog_id = item.get("id") or item.get("catalog_id")
    if catalog_id:
        print(catalog_id)
PY
}

extract_vega_catalog_id() {
  require_command python3

  VEGA_CATALOG_JSON="$1" python3 <<'PY'
import json
import os

text = os.environ.get("VEGA_CATALOG_JSON", "").strip()
if not text:
    raise SystemExit(1)

try:
    data = json.loads(text)
except json.JSONDecodeError:
    raise SystemExit(1)

def find_catalog_id(node):
    if isinstance(node, dict):
        for key in ("id", "catalog_id"):
            value = node.get(key)
            if value not in (None, ""):
                return value
        for value in node.values():
            found = find_catalog_id(value)
            if found not in (None, ""):
                return found
    elif isinstance(node, list):
        for item in node:
            found = find_catalog_id(item)
            if found not in (None, ""):
                return found
    return None

catalog_id = find_catalog_id(data)
if catalog_id in (None, ""):
    raise SystemExit(1)

print(catalog_id)
PY
}

scan_vega_data_connection() {
  local catalog_id="$1"
  local catalog_name="$2"
  [[ -n "$catalog_id" ]] || error "Vega catalog ID is required before scanning"

  log "Scanning Vega data connection: $catalog_name ($catalog_id)"
  kweaver vega catalog discover "$catalog_id" --wait -bd "$KWEAVER_BUSINESS_DOMAIN" --pretty
}

create_or_update_vega_data_connection() {
  local catalog_name="$1"
  local connector_type="$2"
  local connector_host="$3"
  local connector_port="$4"
  local connector_database="$5"
  local connector_schema="$6"
  local connector_user="$7"
  local connector_password="$8"
  local description="${9:-Recovery experience knowledge network data connection}"

  local connector_config
  connector_config="$(build_vega_connector_config "$connector_type" "$connector_host" "$connector_port" "$connector_database" "$connector_schema" "$connector_user" "$connector_password")"

  local existing_ids
  existing_ids="$(find_vega_catalog_ids_by_name "$catalog_name")"

  local existing_id
  existing_id="$(printf '%s\n' "$existing_ids" | sed -n '1p')"

  if [[ -n "$existing_id" ]]; then
    log "Updating existing Vega data connection: $catalog_name ($existing_id)"
    local update_output
    update_output="$(kweaver vega catalog update "$existing_id" \
      --name "$catalog_name" \
      --connector-type "$connector_type" \
      --connector-config "$connector_config" \
      --description "$description" \
      -bd "$KWEAVER_BUSINESS_DOMAIN" \
      --pretty)"
    printf '%s\n' "$update_output"
    scan_vega_data_connection "$existing_id" "$catalog_name"
    return 0
  fi

  log "Creating Vega data connection: $catalog_name"
  local create_output
  create_output="$(kweaver vega catalog create \
    --name "$catalog_name" \
    --connector-type "$connector_type" \
    --connector-config "$connector_config" \
    --description "$description" \
    -bd "$KWEAVER_BUSINESS_DOMAIN" \
    --pretty)"
  printf '%s\n' "$create_output"

  local created_id
  created_id="$(extract_vega_catalog_id "$create_output" || true)"
  if [[ -z "$created_id" ]]; then
    created_id="$(find_vega_catalog_ids_by_name "$catalog_name" | sed -n '1p')"
  fi
  if [[ -z "$created_id" ]]; then
    error "Vega data connection was created, but its catalog ID could not be resolved for scanning."
  fi

  scan_vega_data_connection "$created_id" "$catalog_name"
}

create_vega_data_connections() {
  if [[ "$SKIP_VEGA_CATALOG" == "1" || "$SKIP_VEGA_CATALOG" == "true" ]]; then
    log "Skipping Vega data connection creation."
    return 0
  fi

  require_command kweaver

  create_or_update_vega_data_connection "$VEGA_EXPERIENCE_CATALOG_NAME" "$DB_ENGINE" "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_SCHEMA" "$DB_USER" "$DB_PASSWORD"

  if ! foundation_vega_enabled; then
    log "Skipping Foundation Vega data connection creation."
    return 0
  fi

  create_or_update_vega_data_connection "$VEGA_COMMON_CATALOG_NAME" "$FOUNDATION_DB_ENGINE" "$FOUNDATION_DB_HOST" "$FOUNDATION_DB_PORT" "$VEGA_COMMON_DB_NAME" "$FOUNDATION_DB_SCHEMA" "$FOUNDATION_DB_USER" "$FOUNDATION_DB_PASSWORD" "Foundation CommonServiceDB data connection"
  create_or_update_vega_data_connection "$VEGA_MULTI_STORAGE_CATALOG_NAME" "$FOUNDATION_DB_ENGINE" "$FOUNDATION_DB_HOST" "$FOUNDATION_DB_PORT" "$VEGA_MULTI_STORAGE_DB_NAME" "$FOUNDATION_DB_SCHEMA" "$FOUNDATION_DB_USER" "$FOUNDATION_DB_PASSWORD" "Foundation MultiStorageSvcMgmServiceDB data connection"
  create_or_update_vega_data_connection "$VEGA_STORAGE_RES_CATALOG_NAME" "$FOUNDATION_DB_ENGINE" "$FOUNDATION_DB_HOST" "$FOUNDATION_DB_PORT" "$VEGA_STORAGE_RES_DB_NAME" "$FOUNDATION_DB_SCHEMA" "$FOUNDATION_DB_USER" "$FOUNDATION_DB_PASSWORD" "Foundation StorageResMgmServiceDB data connection"
  create_or_update_vega_data_connection "$VEGA_HYPER_BACKUP_CATALOG_NAME" "$FOUNDATION_DB_ENGINE" "$FOUNDATION_DB_HOST" "$FOUNDATION_DB_PORT" "$VEGA_HYPER_BACKUP_DB_NAME" "$FOUNDATION_DB_SCHEMA" "$FOUNDATION_DB_USER" "$FOUNDATION_DB_PASSWORD" "Foundation HyperBackupMgmServiceDB data connection"
  create_or_update_vega_data_connection "$VEGA_HYPER_JOB_CATALOG_NAME" "$FOUNDATION_DB_ENGINE" "$FOUNDATION_DB_HOST" "$FOUNDATION_DB_PORT" "$VEGA_HYPER_JOB_DB_NAME" "$FOUNDATION_DB_SCHEMA" "$FOUNDATION_DB_USER" "$FOUNDATION_DB_PASSWORD" "Foundation HyperJobWorkerServiceDB data connection"
}

create_kweaver_data_views() {
  if [[ "$SKIP_KWEAVER_DATA_VIEWS" == "1" || "$SKIP_KWEAVER_DATA_VIEWS" == "true" ]]; then
    log "Skipping KWeaver data view creation."
    return 0
  fi

  require_command kweaver
  require_command python3

  local dataview_tool="$PACKAGE_ROOT/common/kweaver_dataviews.py"
  [[ -f "$dataview_tool" ]] || error "KWeaver data view helper not found: $dataview_tool"

  log "Creating KWeaver data views for recovery experience tables."
  python3 "$dataview_tool" \
    --biz-domain "$KWEAVER_BUSINESS_DOMAIN" \
    --datasource-name "$KWEAVER_EXPERIENCE_DATASOURCE_NAME" \
    --engine "$DB_ENGINE" \
    --host "$DB_HOST" \
    --port "$DB_PORT" \
    --database "$DB_NAME" \
    --schema "$DB_SCHEMA" \
    --username "$DB_USER" \
    --password "$DB_PASSWORD" \
    --view "availability_checkpoint_template=ExperienceBKNDB.public.availability_checkpoint_template" \
    --view "fault_pattern=ExperienceBKNDB.public.fault_pattern" \
    --view "recovery_capability=ExperienceBKNDB.public.recovery_capability" \
    --view "recovery_strategy_template=ExperienceBKNDB.public.recovery_strategy_template" \
    --view "risk_rule=ExperienceBKNDB.public.risk_rule"

  if ! foundation_vega_enabled; then
    log "Skipping Foundation KWeaver data view creation."
    return 0
  fi

  log "Creating KWeaver data views for Foundation tables."
  python3 "$dataview_tool" \
    --biz-domain "$KWEAVER_BUSINESS_DOMAIN" \
    --datasource-name "$KWEAVER_COMMON_DATASOURCE_NAME" \
    --engine "$FOUNDATION_DB_ENGINE" \
    --host "$FOUNDATION_DB_HOST" \
    --port "$FOUNDATION_DB_PORT" \
    --database "$VEGA_COMMON_DB_NAME" \
    --schema "$FOUNDATION_DB_SCHEMA" \
    --username "$FOUNDATION_DB_USER" \
    --password "$FOUNDATION_DB_PASSWORD" \
    --view "client=CommonServiceDB.client"

  python3 "$dataview_tool" \
    --biz-domain "$KWEAVER_BUSINESS_DOMAIN" \
    --datasource-name "$KWEAVER_MULTI_STORAGE_DATASOURCE_NAME" \
    --engine "$FOUNDATION_DB_ENGINE" \
    --host "$FOUNDATION_DB_HOST" \
    --port "$FOUNDATION_DB_PORT" \
    --database "$VEGA_MULTI_STORAGE_DB_NAME" \
    --schema "$FOUNDATION_DB_SCHEMA" \
    --username "$FOUNDATION_DB_USER" \
    --password "$FOUNDATION_DB_PASSWORD" \
    --view "console_storage_svc=MultiStorageSvcMgmServiceDB.console_storage_svc"

  python3 "$dataview_tool" \
    --biz-domain "$KWEAVER_BUSINESS_DOMAIN" \
    --datasource-name "$KWEAVER_STORAGE_RES_DATASOURCE_NAME" \
    --engine "$FOUNDATION_DB_ENGINE" \
    --host "$FOUNDATION_DB_HOST" \
    --port "$FOUNDATION_DB_PORT" \
    --database "$VEGA_STORAGE_RES_DB_NAME" \
    --schema "$FOUNDATION_DB_SCHEMA" \
    --username "$FOUNDATION_DB_USER" \
    --password "$FOUNDATION_DB_PASSWORD" \
    --view "pool_v8=StorageResMgmServiceDB.pool_v8"

  python3 "$dataview_tool" \
    --biz-domain "$KWEAVER_BUSINESS_DOMAIN" \
    --datasource-name "$KWEAVER_HYPER_BACKUP_DATASOURCE_NAME" \
    --engine "$FOUNDATION_DB_ENGINE" \
    --host "$FOUNDATION_DB_HOST" \
    --port "$FOUNDATION_DB_PORT" \
    --database "$VEGA_HYPER_BACKUP_DB_NAME" \
    --schema "$FOUNDATION_DB_SCHEMA" \
    --username "$FOUNDATION_DB_USER" \
    --password "$FOUNDATION_DB_PASSWORD" \
    --view "protect_object=HyperBackupMgmServiceDB.protect_object"

  python3 "$dataview_tool" \
    --biz-domain "$KWEAVER_BUSINESS_DOMAIN" \
    --datasource-name "$KWEAVER_HYPER_JOB_DATASOURCE_NAME" \
    --engine "$FOUNDATION_DB_ENGINE" \
    --host "$FOUNDATION_DB_HOST" \
    --port "$FOUNDATION_DB_PORT" \
    --database "$VEGA_HYPER_JOB_DB_NAME" \
    --schema "$FOUNDATION_DB_SCHEMA" \
    --username "$FOUNDATION_DB_USER" \
    --password "$FOUNDATION_DB_PASSWORD" \
    --view "job=HyperJobWorkerServiceDB.job"
}

main() {
  parse_args "$@"
  assert_inputs

  log "Installing Vega recovery experience data"
  log "Engine: $DB_ENGINE"
  log "Host: $DB_HOST"
  log "Port: $DB_PORT"
  log "Database: $DB_NAME"

  case "$DB_ENGINE" in
    postgresql)
      install_postgresql
      ;;
    mysql|mariadb)
      install_mysql
      ;;
  esac

  create_vega_data_connections
  create_kweaver_data_views

  log "Vega data install completed."
}

main "$@"
