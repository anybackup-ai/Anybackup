#!/usr/bin/env bash

detect_local_ip() {
  local detected_ip=""

  if command -v hostname >/dev/null 2>&1; then
    detected_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi

  if [[ -z "${detected_ip}" ]] && command -v ip >/dev/null 2>&1; then
    detected_ip="$(
      ip route get 1 2>/dev/null \
        | awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }' \
        || true
    )"
  fi

  if [[ -z "${detected_ip}" ]]; then
    detected_ip="127.0.0.1"
  fi

  printf '%s\n' "${detected_ip}"
}

detect_python_interpreter() {
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return 0
  fi

  if command -v python >/dev/null 2>&1; then
    command -v python
    return 0
  fi

  printf '%s\n' "/usr/bin/python3"
}

ensure_ansible_playbook() {
  if command -v ansible-playbook >/dev/null 2>&1; then
    return 0
  fi

  cat >&2 <<'EOF'
ERROR: ansible-playbook was not found in PATH.
Install Ansible on the deployment controller first, or run this package on a Linux host where ansible-playbook is already available.
EOF
  return 1
}

create_local_inventory() {
  local inventory_path
  local detected_ip
  local python_interpreter
  local current_user
  local become_flag

  inventory_path="$(mktemp "${TMPDIR:-/tmp}/anybackup-ansible-local.XXXXXX.ini")"
  detected_ip="$(detect_local_ip)"
  python_interpreter="$(detect_python_interpreter)"
  current_user="$(id -un)"
  become_flag="false"

  if [[ "${current_user}" != "root" ]]; then
    become_flag="true"
  fi

  cat > "${inventory_path}" <<EOF
[v9_alpha]
localhost ansible_connection=local ansible_user=${current_user} ansible_become=${become_flag} ansible_python_interpreter=${python_interpreter} ansible_host=${detected_ip}
EOF

  printf '%s\n' "${inventory_path}"
}
