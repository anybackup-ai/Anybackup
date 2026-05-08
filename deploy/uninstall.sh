#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_UNINSTALL="${DEPLOY_DIR}/deploy_package/uninstall.sh"

if [[ ! -f "${PACKAGE_UNINSTALL}" ]]; then
  echo "ERROR: deploy package uninstall entrypoint not found: ${PACKAGE_UNINSTALL}" >&2
  echo "Run this script from a complete Anybackup repository checkout." >&2
  exit 1
fi

exec bash "${PACKAGE_UNINSTALL}" "$@"
