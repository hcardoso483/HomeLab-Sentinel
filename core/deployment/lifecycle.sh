#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RESOLVER="${APP_ROOT}/core/resolver/resolver.sh"
HEALTHCHECK="${APP_ROOT}/core/deployment/healthcheck.sh"
UPDATE="${APP_ROOT}/core/deployment/update.sh"
UNINSTALL="${APP_ROOT}/core/deployment/uninstall.sh"

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

usage() {
    cat <<EOF_USAGE
HomeLab Sentinel Lifecycle Orchestrator

Usage:
  lifecycle.sh healthcheck <capability>
  lifecycle.sh update <capability>
  lifecycle.sh uninstall <capability>
EOF_USAGE
}

require_file() {
    local file="$1"

    if [[ ! -f "${file}" ]]; then
        log_error "Required component not found: ${file}"
        exit 1
    fi
}

ACTION="${1:-}"
CAPABILITY="${2:-}"

if [[ -z "${ACTION}" || -z "${CAPABILITY}" ]]; then
    usage
    exit 1
fi

case "${ACTION}" in
    healthcheck|update|uninstall)
        ;;
    *)
        log_error "Unsupported lifecycle action: ${ACTION}"
        echo "[SUGGESTION] Supported actions:"
        echo "  healthcheck"
        echo "  update"
        echo "  uninstall"
        exit 1
        ;;
esac

require_file "${RESOLVER}"
require_file "${HEALTHCHECK}"
require_file "${UPDATE}"
require_file "${UNINSTALL}"

log_info "Resolving provider..."
echo
echo "Capability: ${CAPABILITY}"
echo

if ! RESOLUTION="$("${RESOLVER}" resolve "${CAPABILITY}")"; then
    echo
    log_error "Provider resolution failed."
    echo "[DETAIL] Capability: ${CAPABILITY}"
    exit 1
fi

printf '%s\n' "${RESOLUTION}"

PROVIDER="$(
    printf '%s\n' "${RESOLUTION}" |
        sed -n 's/^Selected provider: //p' |
        tail -n 1
)"

if [[ -z "${PROVIDER}" ]]; then
    log_error "Provider resolution did not return a provider."
    exit 1
fi

echo
log_info "Provider resolved: ${PROVIDER}"
echo "[DETAIL] Action: ${ACTION}"

echo

case "${ACTION}" in
    healthcheck)
        "${HEALTHCHECK}" "${PROVIDER}"
        ;;

    update)
        "${UPDATE}" "${PROVIDER}"
        ;;

    uninstall)
        "${UNINSTALL}" "${PROVIDER}"
        ;;
esac

echo
log_info "Lifecycle operation completed successfully."
echo "[DETAIL] Action: ${ACTION}"
echo "[DETAIL] Capability: ${CAPABILITY}"
echo "[DETAIL] Provider: ${PROVIDER}"
