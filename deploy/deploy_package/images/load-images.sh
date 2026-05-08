#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_tar() {
  local tar_file="$1"
  if [[ -f "${tar_file}" ]]; then
    echo "[load-images] loading ${tar_file}"
    docker load -i "${tar_file}"
  fi
}

echo "[load-images] scanning offline image tar files under ${SCRIPT_DIR}"

shopt -s nullglob
for tar_file in "${SCRIPT_DIR}"/*.tar; do
  load_tar "${tar_file}"
done

for tar_file in "${SCRIPT_DIR}/kweaver-core"/*.tar; do
  load_tar "${tar_file}"
done
shopt -u nullglob

echo "[load-images] finished. If no .tar files were present, this step is a no-op."
