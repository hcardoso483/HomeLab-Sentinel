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

log_info "Installing module: ${MODULE_ID}"
log_info "Module directory: ${MODULE_DIR}"

validate_metadata "${MODULE_DIR}"

check_dependencies "${MODULE_DIR}"

if [[ ! -f "${MODULE_DIR}/compose.yml" ]]; then
    die "Module compose file not found: ${MODULE_DIR}/compose.yml"
fi

log_info "Starting module..."

docker compose \
    -f "${MODULE_DIR}/compose.yml" \
    up -d

run_healthcheck "${MODULE_DIR}"

log_info "Module ${MODULE_ID} installed and healthy."
