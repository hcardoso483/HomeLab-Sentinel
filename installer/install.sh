#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SYSTEMD_SOURCE="${SCRIPT_DIR}/systemd"
SYSTEMD_TARGET="/etc/systemd/system"

API_UNIT="homelab-sentinel-api.service"
VERIFY_UNIT="homelab-sentinel-verify.service"

API_HEALTH_URL="http://127.0.0.1:8000/api/v1/health"

log_info() {
    echo "[INFO] $*"
}

log_pass() {
    echo "[PASS] $*"
}

die() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "Platform installation must be run as root."
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || \
        die "Required command not found: $1"
}

require_file() {
    [[ -f "$1" ]] || die "Required file not found: $1"
}

install_unit() {
    local unit="$1"

    log_info "Installing systemd unit: ${unit}"
    install -m 0644 \
        "${SYSTEMD_SOURCE}/${unit}" \
        "${SYSTEMD_TARGET}/${unit}"
}

wait_for_api() {
    local attempt

    log_info "Waiting for Core API..."

    for attempt in {1..10}; do
        if curl --fail --silent \
            --max-time 5 "${API_HEALTH_URL}" >/dev/null 2>&1; then
            log_pass "Core API healthcheck passed."
            return 0
        fi

        sleep 2
    done

    die "Core API did not become healthy."
}

echo "HomeLab Sentinel Platform Bootstrap"
echo

require_root

require_command systemctl
require_command install
require_command python3
require_command curl

require_file "${APP_ROOT}/api/server.py"
require_file "${APP_ROOT}/scripts/verify-sentinel.sh"
require_file "${SYSTEMD_SOURCE}/${API_UNIT}"
require_file "${SYSTEMD_SOURCE}/${VERIFY_UNIT}"

log_pass "Platform prerequisites validated."

install_unit "${API_UNIT}"
install_unit "${VERIFY_UNIT}"

log_info "Reloading systemd..."
systemctl daemon-reload

log_info "Enabling Core API..."
systemctl enable "${API_UNIT}"

log_info "Starting Core API..."
systemctl restart "${API_UNIT}"

wait_for_api

log_info "Enabling post-boot verification..."
systemctl enable "${VERIFY_UNIT}"

log_info "Running HomeLab Sentinel verification..."
"${APP_ROOT}/scripts/verify-sentinel.sh"

echo
log_pass "HomeLab Sentinel platform bootstrap completed successfully."
