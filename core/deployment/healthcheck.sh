#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

MODULE_ID="${1:-}"

if [[ -z "${MODULE_ID}" ]]; then
    die "Usage: $0 <module-id>"
fi

MODULE_DIR="$(require_module "${MODULE_ID}")"

log_info "Checking module: ${MODULE_ID}"
log_info "Module directory: ${MODULE_DIR}"

validate_metadata "${MODULE_DIR}"

run_healthcheck "${MODULE_DIR}"

log_info "Module ${MODULE_ID} is healthy."
