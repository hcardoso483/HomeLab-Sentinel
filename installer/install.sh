#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SYSTEMD_SOURCE="${SCRIPT_DIR}/systemd"
SYSTEMD_TARGET="/etc/systemd/system"
SYSUSERS_SOURCE="${SCRIPT_DIR}/sysusers.d/homelab-sentinel.conf"
SYSUSERS_TARGET="/etc/sysusers.d/homelab-sentinel.conf"

API_UNIT="homelab-sentinel-api.service"
HOMEPAGE_API_SERVICE="homelab-sentinel-homepage-api.service"
HOMEPAGE_API_SOCKET="homelab-sentinel-homepage-api.socket"
VERIFY_UNIT="homelab-sentinel-verify.service"
VERIFY_TIMER="homelab-sentinel-verify.timer"
DISCOVERY_UNIT="homelab-sentinel-discovery.service"
DISCOVERY_TIMER="homelab-sentinel-discovery.timer"

DEPENDENCY_MANAGER="${SCRIPT_DIR}/dependencies.py"
INVENTORY_MANAGER="${SCRIPT_DIR}/inventory.py"
DISCOVERY_SCHEDULE_HELPER="${APP_ROOT}/core/discovery/schedule.py"
DISCOVERY_CONFIG="${APP_ROOT}/config/sentinel/discovery.yml"
HLS_SOURCE="${SCRIPT_DIR}/hls"
HLS_TARGET="/usr/local/bin/hls"
API_HEALTH_URL="http://127.0.0.1:8000/api/v1/health"
SERVICE_USER="homelab-sentinel"
SERVICE_GROUP="homelab-sentinel"
SENTINEL_STATE_DIR="/srv/homelab-sentinel/sentinel"
INVENTORY_DATABASE="${SENTINEL_STATE_DIR}/inventory.db"
IDENTITY_DATABASE="${SENTINEL_STATE_DIR}/identity.db"
RUNTIME_STATE_DIR="${SENTINEL_STATE_DIR}/runtime"

HOMEPAGE_NETWORK_NAME="homelab-network"
HOMEPAGE_NETWORK_SUBNET="172.18.0.0/16"
HOMEPAGE_NETWORK_GATEWAY="172.18.0.1"

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

    if [[ -d "${RUNTIME_STATE_DIR}" ]]; then
        chown "${SERVICE_USER}:${SERVICE_GROUP}"             "${RUNTIME_STATE_DIR}"
    fi

    if [[ -f "${IDENTITY_DATABASE}" ]]; then
        chown "${SERVICE_USER}:${SERVICE_GROUP}"             "${IDENTITY_DATABASE}"
    fi

    log_pass "Sentinel state ownership ready: ${SERVICE_USER}:${SERVICE_GROUP}"
}


reconcile_homepage_network() {
    local actual_subnet
    local actual_gateway

    log_info "Reconciling Homepage Docker network..."

    if ! docker network inspect "${HOMEPAGE_NETWORK_NAME}" \
        >/dev/null 2>&1; then
        log_info "Creating Homepage Docker network: ${HOMEPAGE_NETWORK_NAME}"

        docker network create \
            --driver bridge \
            --subnet "${HOMEPAGE_NETWORK_SUBNET}" \
            --gateway "${HOMEPAGE_NETWORK_GATEWAY}" \
            "${HOMEPAGE_NETWORK_NAME}" \
            >/dev/null ||
            die "Unable to create Homepage Docker network."

        log_pass "Homepage Docker network created."
    fi

    actual_subnet="$(
        docker network inspect "${HOMEPAGE_NETWORK_NAME}" \
            --format '{{(index .IPAM.Config 0).Subnet}}'
    )" || die "Unable to inspect Homepage Docker network subnet."

    actual_gateway="$(
        docker network inspect "${HOMEPAGE_NETWORK_NAME}" \
            --format '{{(index .IPAM.Config 0).Gateway}}'
    )" || die "Unable to inspect Homepage Docker network gateway."

    if [[ "${actual_subnet}" != "${HOMEPAGE_NETWORK_SUBNET}" ]]; then
        die "Homepage Docker network subnet mismatch: expected ${HOMEPAGE_NETWORK_SUBNET}, found ${actual_subnet}"
    fi

    if [[ "${actual_gateway}" != "${HOMEPAGE_NETWORK_GATEWAY}" ]]; then
        die "Homepage Docker network gateway mismatch: expected ${HOMEPAGE_NETWORK_GATEWAY}, found ${actual_gateway}"
    fi

    log_pass "Homepage Docker network ready: ${HOMEPAGE_NETWORK_SUBNET} gateway ${HOMEPAGE_NETWORK_GATEWAY}"
}


reconcile_discovery_schedule() {
    local interval
    local dropin_dir
    local dropin_file
    local temporary_file

    interval="$(
        "${DISCOVERY_SCHEDULE_HELPER}" interval \
            --config "${DISCOVERY_CONFIG}"
    )" || die "Unable to resolve Discovery scheduling policy."

    dropin_dir="${SYSTEMD_TARGET}/${DISCOVERY_TIMER}.d"
    dropin_file="${dropin_dir}/schedule.conf"

    log_info "Reconciling Discovery schedule: ${interval} minutes"

    install -d -m 0755 "${dropin_dir}"

    temporary_file="$(
        mktemp "${dropin_dir}/.schedule.conf.XXXXXX"
    )"

    "${DISCOVERY_SCHEDULE_HELPER}" dropin \
        --config "${DISCOVERY_CONFIG}" > "${temporary_file}" ||
        die "Unable to render Discovery schedule drop-in."

    chmod 0644 "${temporary_file}"
    mv -f "${temporary_file}" "${dropin_file}"

    log_pass "Discovery schedule ready: ${interval} minutes"
}


echo "HomeLab Sentinel Platform Bootstrap"
echo

require_root

require_file "${DEPENDENCY_MANAGER}"
require_file "${INVENTORY_MANAGER}"
require_file "${DISCOVERY_SCHEDULE_HELPER}"
require_file "${DISCOVERY_CONFIG}"
require_file "${SYSUSERS_SOURCE}"
require_file "${HLS_SOURCE}"

log_info "Checking mandatory Sentinel dependencies..."
"${DEPENDENCY_MANAGER}" --recover

log_info "Validating Discovery scheduling policy..."
"${DISCOVERY_SCHEDULE_HELPER}" validate \
    --config "${DISCOVERY_CONFIG}" ||
    die "Discovery scheduling policy validation failed."

log_info "Preparing Sentinel inventory state..."
"${INVENTORY_MANAGER}"

require_command systemd-sysusers
require_command install
require_command systemctl
require_command python3
require_command curl
require_command chown
require_command docker

reconcile_homepage_network

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
require_file "${SYSTEMD_SOURCE}/${HOMEPAGE_API_SERVICE}"
require_file "${SYSTEMD_SOURCE}/${HOMEPAGE_API_SOCKET}"
require_file "${SYSTEMD_SOURCE}/${VERIFY_UNIT}"
require_file "${SYSTEMD_SOURCE}/${VERIFY_TIMER}"
require_file "${SYSTEMD_SOURCE}/${DISCOVERY_UNIT}"
require_file "${SYSTEMD_SOURCE}/${DISCOVERY_TIMER}"

log_pass "Platform prerequisites validated."

log_info "Installing HomeLab Sentinel CLI..."
install -m 0755 "${HLS_SOURCE}" "${HLS_TARGET}"
log_pass "HomeLab Sentinel CLI installed: ${HLS_TARGET}"

install_unit "${API_UNIT}"
install_unit "${HOMEPAGE_API_SERVICE}"
install_unit "${HOMEPAGE_API_SOCKET}"
install_unit "${VERIFY_UNIT}"
install_unit "${VERIFY_TIMER}"
install_unit "${DISCOVERY_UNIT}"
install_unit "${DISCOVERY_TIMER}"

reconcile_discovery_schedule

log_info "Reloading systemd..."
systemctl daemon-reload

log_info "Enabling Core API..."
systemctl enable "${API_UNIT}"

log_info "Starting Core API..."
systemctl restart "${API_UNIT}"

wait_for_api

log_info "Enabling Homepage API bridge socket..."
systemctl enable --now "${HOMEPAGE_API_SOCKET}"

log_info "Enabling Discovery scheduler..."

systemctl enable --now "${DISCOVERY_TIMER}"

log_info "Running initial managed discovery..."

systemctl start "${DISCOVERY_UNIT}"

log_info "Enabling delayed post-boot verification..."
systemctl disable "${VERIFY_UNIT}" >/dev/null 2>&1 || true
systemctl enable --now "${VERIFY_TIMER}"

log_info "Running HomeLab Sentinel verification..."
"${APP_ROOT}/scripts/verify-sentinel.sh"

echo
log_pass "HomeLab Sentinel platform bootstrap completed successfully."
