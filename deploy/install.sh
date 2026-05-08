#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_INSTALL="${DEPLOY_DIR}/deploy_package/install.sh"

if [[ ! -f "${PACKAGE_INSTALL}" ]]; then
  echo "ERROR: deploy package entrypoint not found: ${PACKAGE_INSTALL}" >&2
  echo "Run this script from a complete Anybackup repository checkout." >&2
  exit 1
fi

exec bash "${PACKAGE_INSTALL}" "$@"