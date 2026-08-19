#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${APP_ROOT}/core/lib/common.sh"

DEFAULT_DATABASE="/srv/homelab-sentinel/sentinel/inventory.db"

DISCOVER="${APP_ROOT}/core/discovery/discover.sh"
STORE="${APP_ROOT}/core/inventory/store.py"
CORRELATE="${APP_ROOT}/core/inventory/correlate.py"
INVENTORY="${APP_ROOT}/core/inventory/inventory.py"

usage() {
    echo "Usage: ${0} [--database DATABASE] [scope-config]"
    echo
    echo "Run the HomeLab Sentinel discovery-to-inventory pipeline."
}

DATABASE="${DEFAULT_DATABASE}"
SCOPE_CONFIG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --database)
            [[ -n "${2:-}" ]] || die "Missing value for --database."
            DATABASE="$2"
            shift 2
            ;;
        --database=*)
            DATABASE="${1#*=}"
            shift
            ;;
        --*)
            die "Unknown option: $1"
            ;;
        *)
            [[ -z "${SCOPE_CONFIG}" ]] || die "Only one scope configuration may be specified."
            SCOPE_CONFIG="$1"
            shift
            ;;
    esac
done

for required_file in \
    "${DISCOVER}" \
    "${STORE}" \
    "${CORRELATE}" \
    "${INVENTORY}"
do
    [[ -x "${required_file}" ]] ||
        die "Required pipeline component not found or not executable: ${required_file}"
done

log_info "Starting discovery-to-inventory pipeline." >&2
log_info "Inventory database: ${DATABASE}" >&2

if [[ -n "${SCOPE_CONFIG}" ]]; then
    log_info "Discovery scope configuration: ${SCOPE_CONFIG}" >&2
    "${DISCOVER}" "${SCOPE_CONFIG}" |
        "${STORE}" --database "${DATABASE}"
else
    "${DISCOVER}" |
        "${STORE}" --database "${DATABASE}"
fi

"${CORRELATE}" --database "${DATABASE}"

log_info "Living Inventory follows." >&2
"${INVENTORY}" --database "${DATABASE}"
