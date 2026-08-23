#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SYSTEMD_SOURCE="${SCRIPT_DIR}/systemd"
SYSTEMD_TARGET="/etc/systemd/system"
SYSUSERS_SOURCE="${SCRIPT_DIR}/sysusers.d/homelab-sentinel.conf"
SYSUSERS_TARGET="/etc/sysusers.d/homelab-sentinel.conf"

API_UNIT="homelab-sentinel-api.service"
VERIFY_UNIT="homelab-sentinel-verify.service"
DISCOVERY_UNIT="homelab-sentinel-discovery.service"

DEPENDENCY_MANAGER="${SCRIPT_DIR}/dependencies.py"
INVENTORY_MANAGER="${SCRIPT_DIR}/inventory.py"
HLS_SOURCE="${SCRIPT_DIR}/hls"
HLS_TARGET="/usr/local/bin/hls"
API_HEALTH_URL="http://127.0.0.1:8000/api/v1/health"
SERVICE_USER="homelab-sentinel"
SERVICE_GROUP="homelab-sentinel"
SENTINEL_STATE_DIR="/srv/homelab-sentinel/sentinel"
INVENTORY_DATABASE="${SENTINEL_STATE_DIR}/inventory.db"

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

reconcile_sentinel_state_ownership() {
    require_file "${INVENTORY_DATABASE}"

    [[ -d "${SENTINEL_STATE_DIR}" ]] || \
        die "Sentinel state directory not found: ${SENTINEL_STATE_DIR}"

    log_info "Reconciling Sentinel state ownership..."

    chown "${SERVICE_USER}:${SERVICE_GROUP}" \
        "${SENTINEL_STATE_DIR}" \
        "${INVENTORY_DATABASE}"

    log_pass "Sentinel state ownership ready: ${SERVICE_USER}:${SERVICE_GROUP}"
}

echo "HomeLab Sentinel Platform Bootstrap"
echo

require_root

require_file "${DEPENDENCY_MANAGER}"
require_file "${INVENTORY_MANAGER}"
require_file "${SYSUSERS_SOURCE}"
require_file "${HLS_SOURCE}"

log_info "Checking mandatory Sentinel dependencies..."
"${DEPENDENCY_MANAGER}" --recover

log_info "Preparing Sentinel inventory state..."
"${INVENTORY_MANAGER}"

require_command systemd-sysusers
require_command install
require_command systemctl
require_command python3
require_command curl
require_command chown

log_info "Preparing sysusers configuration directory..."
install -d -m 0755 "$(dirname "${SYSUSERS_TARGET}")"

log_info "Installing HomeLab Sentinel service identity declaration..."
install -m 0644 "${SYSUSERS_SOURCE}" "${SYSUSERS_TARGET}"

log_info "Ensuring HomeLab Sentinel service identity exists..."
systemd-sysusers "${SYSUSERS_TARGET}"

reconcile_sentinel_state_ownership

require_file "${APP_ROOT}/api/server.py"
require_file "${APP_ROOT}/scripts/verify-sentinel.sh"
require_file "${SYSTEMD_SOURCE}/${API_UNIT}"
require_file "${SYSTEMD_SOURCE}/${VERIFY_UNIT}"
require_file "${SYSTEMD_SOURCE}/${DISCOVERY_UNIT}"

log_pass "Platform prerequisites validated."

log_info "Installing HomeLab Sentinel CLI..."
install -m 0755 "${HLS_SOURCE}" "${HLS_TARGET}"
log_pass "HomeLab Sentinel CLI installed: ${HLS_TARGET}"

install_unit "${API_UNIT}"
install_unit "${VERIFY_UNIT}"
install_unit "${DISCOVERY_UNIT}"

log_info "Reloading systemd..."
systemctl daemon-reload

log_info "Enabling Core API..."
systemctl enable "${API_UNIT}"

log_info "Starting Core API..."
systemctl restart "${API_UNIT}"

wait_for_api

log_info "Running initial managed discovery..."

systemctl start "${DISCOVERY_UNIT}"

log_info "Enabling post-boot verification..."
systemctl enable "${VERIFY_UNIT}"

log_info "Running HomeLab Sentinel verification..."
"${APP_ROOT}/scripts/verify-sentinel.sh"

echo
log_pass "HomeLab Sentinel platform bootstrap completed successfully."
