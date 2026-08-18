#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

MODULE_ID="${1:-}"

if [[ -z "${MODULE_ID}" ]]; then
    die "Usage: $0 <module-id>"
fi

require_command docker

MODULE_DIR="$(require_module "${MODULE_ID}")"

log_info "Uninstalling module: ${MODULE_ID}"
log_info "Module directory: ${MODULE_DIR}"

validate_metadata "${MODULE_DIR}"

check_dependencies "${MODULE_DIR}"

if [[ ! -f "${MODULE_DIR}/compose.yml" ]]; then
    die "Module compose file not found: ${MODULE_DIR}/compose.yml"
fi

echo
log_warn "This will stop and remove the module containers."
log_info "Persistent Docker volumes will NOT be removed."

echo
read -r -p "Continue uninstalling ${MODULE_ID}? [y/N] " confirmation

case "${confirmation}" in
    y|Y|yes|YES|Yes)
        ;;
    *)
        echo
        log_info "Uninstallation cancelled."
        exit 0
        ;;
esac

echo
log_info "Stopping and removing module..."

docker compose \
    -f "${MODULE_DIR}/compose.yml" \
    down

echo
log_info "Module ${MODULE_ID} uninstalled."
echo "[DETAIL] Docker volumes were preserved."
