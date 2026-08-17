#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RESOLVER="${APP_ROOT}/core/resolver/resolver.sh"
ACQUISITION="${APP_ROOT}/core/acquisition/acquisition.sh"
INSTALLER="${APP_ROOT}/core/deployment/install.sh"

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

usage() {
    cat <<EOF_USAGE
HomeLab Sentinel Deployment Orchestrator

Usage:
  deploy.sh <capability>
EOF_USAGE
}

require_file() {
    local file="$1"

    if [[ ! -f "${file}" ]]; then
        log_error "Required component not found: ${file}"
        exit 1
    fi
}

if [[ -z "${1:-}" ]]; then
    usage
    exit 1
fi

CAPABILITY="${1}"

require_file "${RESOLVER}"
require_file "${ACQUISITION}"
require_file "${INSTALLER}"

log_info "Starting deployment..."
echo
echo "Capability: ${CAPABILITY}"
echo

log_info "Resolving provider..."

if ! RESOLUTION="$("${RESOLVER}" resolve "${CAPABILITY}")"; then
    echo
    log_error "Provider resolution failed."
    echo "[DETAIL] Capability: ${CAPABILITY}"
    echo "[SUGGESTION] Resolve the provider before deployment."
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

echo
log_info "Acquiring provider..."

"${ACQUISITION}" acquire "${CAPABILITY}" "${PROVIDER}"

echo
log_info "Deploying provider..."

"${INSTALLER}" "${PROVIDER}"

echo
log_info "Deployment completed successfully."
echo "[DETAIL] Capability: ${CAPABILITY}"
echo "[DETAIL] Provider: ${PROVIDER}"
