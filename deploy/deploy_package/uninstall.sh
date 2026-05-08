#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=true
YES=false
WAIT_TIMEOUT_SECONDS=600
HELM_TIMEOUT=10m
SKIP_K8S_RESOURCES=false
SKIP_FOUNDATION=false
SKIP_FOUNDATION_CLIENT=false
PURGE_PACKAGES=false

FOUNDATION_INSTALL_ROOT="${FOUNDATION_INSTALL_ROOT:-/opt/backupsoft/FoundationServer}"
FOUNDATION_CLIENT_INSTALL_ROOT="${FOUNDATION_CLIENT_INSTALL_ROOT:-/opt/backupsoft/FoundationClient}"
FOUNDATION_PACKAGE_PATH="${FOUNDATION_PACKAGE_PATH:-}"
FOUNDATION_CLIENT_MYSQL_PACKAGE_PATH="${FOUNDATION_CLIENT_MYSQL_PACKAGE_PATH:-/opt/backupsoft/MySQL-Linux_el7_x64-8.0.9.0-20251231-release-zh_CN-ABNormal-378.tar.gz}"

APP_NAMESPACES=(
  anybackup-ai
  kweaver
  resource
  v9-system
  ingress-nginx
  middleware
)

KEEP_K8S_NAMESPACES=(
  kube-system
  kube-public
  kube-node-lease
  kube-flannel
  local-path-storage
)

INGRESS_CLASSES=(
  class-443
  traefik
  nginx
)

REMOTE_PATHS=(
  /opt/v9-alpha-deploy
  /opt/v9-sources
  /root/.kweaver
  /root/.kweaver-admin
)

usage() {
  cat <<'EOF'
Usage:
  ./uninstall.sh --dry-run
  ./uninstall.sh --yes

Purpose:
  Remove AnyBackup Agent / KWeaver / V9 / Foundation runtime artifacts while
  keeping Kubernetes itself installed.

This script removes or uninstalls:
  - Helm releases and Kubernetes resources in package-owned namespaces:
    anybackup-ai, kweaver, resource, v9-system, ingress-nginx, middleware
  - Package-owned IngressClass residue: class-443, traefik, nginx
  - PersistentVolumes whose claimRef points to package-owned namespaces
  - KWeaver/V9 working directories: /opt/v9-alpha-deploy, /opt/v9-sources
  - root KWeaver CLI cached login state: /root/.kweaver, /root/.kweaver-admin
  - Foundation through its official ./uninstall.sh, then its FoundationServer root
  - FoundationClient through its uninstall script when present, then its root

This script intentionally keeps:
  - Kubernetes itself and system namespaces:
    kube-system, kube-public, kube-node-lease, kube-flannel, local-path-storage
  - Container runtime services
  - This release package directory
  - Downloaded install packages, unless --purge-packages is specified

Options:
  --dry-run                         Print actions without deleting anything. Default.
  --yes                             Execute destructive uninstall.
  --skip-k8s-resources              Do not touch Kubernetes resources.
  --skip-foundation                 Do not run Foundation official uninstall or remove FoundationServer root.
  --skip-foundation-client          Do not uninstall/remove FoundationClient.
  --foundation-install-root PATH    FoundationServer root. Default /opt/backupsoft/FoundationServer.
  --foundation-client-install-root PATH
                                    FoundationClient root. Default /opt/backupsoft/FoundationClient.
  --foundation-package-path PATH    Optional package path removed only with --purge-packages.
  --foundation-client-mysql-package-path PATH
                                    Optional MySQL runner package path removed only with --purge-packages.
  --purge-packages                  Also remove explicitly known downloaded tar.gz packages.
  --wait-timeout SECONDS            Namespace/PV wait timeout. Default 600.
  -h, --help                        Show this help.
EOF
}

log() {
  printf '[uninstall] %s\n' "$*"
}

shell_quote() {
  printf '%q' "$1"
}

run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '[dry-run]'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  else
    "$@"
  fi
}

run_shell() {
  local script="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '[dry-run] bash -lc %q\n' "${script}"
  else
    bash -lc "${script}"
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_root_for_destructive_run() {
  if [[ "${DRY_RUN}" == "false" && "$(id -u)" != "0" ]]; then
    echo "ERROR: destructive uninstall requires root" >&2
    exit 1
  fi
}

assert_safe_remove_path() {
  local path="$1"
  if [[ -z "${path}" || "${path}" != /* ]]; then
    echo "ERROR: refusing to remove non-absolute path: ${path}" >&2
    exit 1
  fi
  case "${path}" in
    /|/opt|/root|/home|/usr|/var|/etc|/bin|/sbin|/lib|/lib64)
      echo "ERROR: refusing to remove broad system path: ${path}" >&2
      exit 1
      ;;
  esac
}

safe_remove_path() {
  local path="$1"
  assert_safe_remove_path "${path}"
  if [[ "${path}" == "${ROOT_DIR}" ]]; then
    echo "ERROR: refusing to remove current release package directory: ${path}" >&2
    exit 1
  fi
  if [[ "${DRY_RUN}" == "false" && ! -e "${path}" ]]; then
    log "Skip absent path ${path}"
    return 0
  fi
  log "Remove path ${path}"
  run rm -rf --one-file-system "${path}"
}

remove_systemd_unit() {
  local unit="$1"
  log "Stop and remove systemd unit ${unit} if present"
  run systemctl stop "${unit}" || true
  run systemctl disable "${unit}" || true
  run systemctl reset-failed "${unit}" || true
  run rm -f "/etc/systemd/system/${unit}"
  run rm -f "/usr/lib/systemd/system/${unit}"
  run rm -f "/etc/systemd/system/multi-user.target.wants/${unit}"
  run systemctl daemon-reload || true
}

delete_helm_releases() {
  local ns="$1"
  kubectl get namespace "${ns}" >/dev/null 2>&1 || return 0

  local releases
  releases="$(helm list -n "${ns}" -q 2>/dev/null || true)"
  [[ -n "${releases}" ]] || return 0

  while IFS= read -r release; do
    [[ -n "${release}" ]] || continue
    log "Uninstall Helm release ${release} in ${ns}"
    run helm uninstall "${release}" -n "${ns}" --wait --timeout "${HELM_TIMEOUT}"
  done <<< "${releases}"
}

wait_for_namespace_absent() {
  local ns="$1"
  local elapsed=0
  while kubectl get namespace "${ns}" >/dev/null 2>&1; do
    if (( elapsed >= WAIT_TIMEOUT_SECONDS )); then
      echo "ERROR: namespace still exists after waiting: ${ns}" >&2
      return 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

force_clear_namespace_finalizers() {
  local ns="$1"
  kubectl get namespace "${ns}" >/dev/null 2>&1 || return 0

  log "Clearing finalizers for resources in namespace ${ns} if needed"
  run_shell "kubectl api-resources --verbs=list --namespaced -o name \
    | while read -r resource; do \
        kubectl get \"\${resource}\" -n $(shell_quote "${ns}") -o name 2>/dev/null \
          | while read -r item; do \
              kubectl patch \"\${item}\" -n $(shell_quote "${ns}") --type=merge -p '{\"metadata\":{\"finalizers\":[]}}' >/dev/null 2>&1 || true; \
            done; \
      done"
}

collect_pvs_for_app_namespaces() {
  local ns_regex
  ns_regex="$(IFS='|'; echo "${APP_NAMESPACES[*]}")"
  kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.claimRef.namespace}{"\n"}{end}' 2>/dev/null \
    | awk -F '\t' -v re="^(${ns_regex})$" '$2 ~ re {print $1}' \
    | sort -u
}

wait_for_pv_absent() {
  local pv="$1"
  local elapsed=0
  while kubectl get pv "${pv}" >/dev/null 2>&1; do
    if (( elapsed >= WAIT_TIMEOUT_SECONDS )); then
      echo "ERROR: persistent volume still exists after waiting: ${pv}" >&2
      return 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
}

cleanup_k8s_resources() {
  if [[ "${SKIP_K8S_RESOURCES}" == "true" ]]; then
    log "Skip Kubernetes resource cleanup by request."
    return 0
  fi
  if ! have_cmd kubectl || ! have_cmd helm; then
    log "kubectl or helm not found; skip Kubernetes resource cleanup."
    return 0
  fi

  log "Keeping Kubernetes system namespaces: ${KEEP_K8S_NAMESPACES[*]}"
  log "Cleaning package-owned namespaces: ${APP_NAMESPACES[*]}"

  local pvs_before=()
  mapfile -t pvs_before < <(collect_pvs_for_app_namespaces || true)

  for ns in "${APP_NAMESPACES[@]}"; do
    delete_helm_releases "${ns}"
  done

  for ns in "${APP_NAMESPACES[@]}"; do
    if kubectl get namespace "${ns}" >/dev/null 2>&1 || [[ "${DRY_RUN}" == "true" ]]; then
      log "Delete namespace ${ns}"
      run kubectl delete namespace "${ns}" --ignore-not-found=true
    fi
  done

  if [[ "${DRY_RUN}" == "false" ]]; then
    for ns in "${APP_NAMESPACES[@]}"; do
      if ! wait_for_namespace_absent "${ns}"; then
        force_clear_namespace_finalizers "${ns}"
        wait_for_namespace_absent "${ns}"
      fi
    done
  fi

  for ingress_class in "${INGRESS_CLASSES[@]}"; do
    log "Delete ingress class ${ingress_class}"
    run kubectl delete ingressclass "${ingress_class}" --ignore-not-found=true
  done

  local pvs_after=()
  if [[ "${DRY_RUN}" == "true" ]]; then
    pvs_after=("${pvs_before[@]}")
  else
    mapfile -t pvs_after < <(collect_pvs_for_app_namespaces || true)
  fi

  local pvs=("${pvs_before[@]}" "${pvs_after[@]}")
  if (( ${#pvs[@]} > 0 )); then
    mapfile -t pvs < <(printf '%s\n' "${pvs[@]}" | awk 'NF' | sort -u)
  fi

  for pv in "${pvs[@]}"; do
    [[ -n "${pv}" ]] || continue
    if [[ "${DRY_RUN}" == "false" ]] && ! kubectl get pv "${pv}" >/dev/null 2>&1; then
      log "Skip PV ${pv}; already absent"
      continue
    fi
    log "Clear claimRef and delete PV ${pv}"
    if [[ "${DRY_RUN}" == "true" ]]; then
      run kubectl patch pv "${pv}" --type=merge --patch '{"spec":{"claimRef":null}}'
    else
      kubectl patch pv "${pv}" --type=merge --patch '{"spec":{"claimRef":null}}' >/dev/null 2>&1 || true
    fi
    run kubectl delete pv "${pv}" --ignore-not-found=true
  done

  if [[ "${DRY_RUN}" == "false" ]]; then
    for pv in "${pvs[@]}"; do
      [[ -n "${pv}" ]] || continue
      wait_for_pv_absent "${pv}"
    done
  fi
}

uninstall_foundation() {
  if [[ "${SKIP_FOUNDATION}" == "true" ]]; then
    log "Skip Foundation official uninstall and FoundationServer root removal by request."
    return 0
  fi

  local uninstall_script="${FOUNDATION_INSTALL_ROOT}/uninstall.sh"
  if [[ -f "${uninstall_script}" ]]; then
    log "Run Foundation official uninstall from ${FOUNDATION_INSTALL_ROOT}"
    run_shell "cd $(shell_quote "${FOUNDATION_INSTALL_ROOT}") && ./uninstall.sh" \
      || log "Foundation official uninstall failed; continue removing FoundationServer root."
  else
    log "Foundation uninstall script not found at ${uninstall_script}; remove root directly if present."
  fi

  safe_remove_path "${FOUNDATION_INSTALL_ROOT}"
}

uninstall_foundation_client() {
  if [[ "${SKIP_FOUNDATION_CLIENT}" == "true" ]]; then
    log "Skip FoundationClient uninstall by request."
    return 0
  fi

  local candidates=(
    "${FOUNDATION_CLIENT_INSTALL_ROOT}/uninstall.sh"
    "${FOUNDATION_CLIENT_INSTALL_ROOT}/ClientService/uninstall.sh"
    "${FOUNDATION_CLIENT_INSTALL_ROOT}/etc/ClientService/uninstall.sh"
  )

  local ran_uninstall=false
  for script in "${candidates[@]}"; do
    if [[ -f "${script}" ]]; then
      log "Run FoundationClient uninstall script ${script}"
      run_shell "cd $(shell_quote "$(dirname "${script}")") && ./$(basename "${script}")" \
        || log "FoundationClient uninstall script failed; continue removing service and root."
      ran_uninstall=true
      break
    fi
  done

  if [[ "${ran_uninstall}" == "false" ]]; then
    log "No FoundationClient uninstall script found under ${FOUNDATION_CLIENT_INSTALL_ROOT}; remove service and root directly if present."
  fi

  remove_systemd_unit ABClientService.service
  safe_remove_path "${FOUNDATION_CLIENT_INSTALL_ROOT}"
}

remove_runtime_paths() {
  for path in "${REMOTE_PATHS[@]}"; do
    safe_remove_path "${path}"
  done

  run_shell "rm -f /tmp/anybackup-ansible-local.*.ini /tmp/anybackup-syntax-check.log 2>/dev/null || true"
}

purge_packages() {
  if [[ "${PURGE_PACKAGES}" != "true" ]]; then
    log "Keep downloaded packages. Use --purge-packages to remove known package tarballs."
    return 0
  fi

  if [[ -n "${FOUNDATION_PACKAGE_PATH}" ]]; then
    safe_remove_path "${FOUNDATION_PACKAGE_PATH}"
  fi
  safe_remove_path "${FOUNDATION_CLIENT_MYSQL_PACKAGE_PATH}"
}

print_snapshot() {
  log "Post-uninstall snapshot:"
  if have_cmd kubectl; then
    run_shell "kubectl get pod -A 2>/dev/null | grep -E 'anybackup-ai|kweaver|resource|v9-system|ingress-nginx|middleware' || true"
  fi
  if have_cmd helm; then
    run_shell "helm list -A -a 2>/dev/null | grep -E 'anybackup-ai|kweaver|resource|v9-system|ingress-nginx|middleware|failed|pending' || true"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      ;;
    --yes)
      DRY_RUN=false
      YES=true
      ;;
    --skip-k8s-resources)
      SKIP_K8S_RESOURCES=true
      ;;
    --skip-foundation)
      SKIP_FOUNDATION=true
      ;;
    --skip-foundation-client)
      SKIP_FOUNDATION_CLIENT=true
      ;;
    --foundation-install-root)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --foundation-install-root requires a value" >&2; exit 1; }
      FOUNDATION_INSTALL_ROOT="$1"
      ;;
    --foundation-client-install-root)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --foundation-client-install-root requires a value" >&2; exit 1; }
      FOUNDATION_CLIENT_INSTALL_ROOT="$1"
      ;;
    --foundation-package-path)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --foundation-package-path requires a value" >&2; exit 1; }
      FOUNDATION_PACKAGE_PATH="$1"
      ;;
    --foundation-client-mysql-package-path)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --foundation-client-mysql-package-path requires a value" >&2; exit 1; }
      FOUNDATION_CLIENT_MYSQL_PACKAGE_PATH="$1"
      ;;
    --purge-packages)
      PURGE_PACKAGES=true
      ;;
    --wait-timeout)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --wait-timeout requires a value" >&2; exit 1; }
      WAIT_TIMEOUT_SECONDS="$1"
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

if [[ "${DRY_RUN}" == "false" && "${YES}" != "true" ]]; then
  echo "ERROR: destructive uninstall requires --yes" >&2
  exit 1
fi

require_root_for_destructive_run

if [[ "${DRY_RUN}" == "true" ]]; then
  log "DRY RUN only. Re-run with --yes to execute uninstall."
else
  log "Executing destructive uninstall. Kubernetes itself will be kept."
fi

cleanup_k8s_resources
uninstall_foundation
uninstall_foundation_client
remove_runtime_paths
purge_packages
print_snapshot

log "Uninstall flow finished."
