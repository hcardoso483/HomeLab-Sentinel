#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

RETRY_WRAPPER="${APP_ROOT}/scripts/with-inventory-retry.sh"
LOCK_WRAPPER="${APP_ROOT}/scripts/with-inventory-lock.sh"

SERVICES=(
    "homelab-sentinel-discovery.service"
    "homelab-sentinel-monitoring.service"
    "homelab-sentinel-verify.service"
)

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

[[ -x "${RETRY_WRAPPER}" ]] ||
    fail "Inventory retry wrapper is not executable"

[[ -x "${LOCK_WRAPPER}" ]] ||
    fail "Inventory lock wrapper is not executable"

grep -Fq 'LOCK_WRAPPER="${APP_ROOT}/scripts/with-inventory-lock.sh"' "${RETRY_WRAPPER}" ||
    fail "Inventory retry wrapper does not delegate to the canonical lock wrapper"

pass "Inventory retry wrapper delegates to canonical inventory lock"

echo

for service_name in "${SERVICES[@]}"; do
    service_path="${APP_ROOT}/installer/systemd/${service_name}"

    [[ -f "${service_path}" ]] ||
        fail "Missing systemd unit: ${service_name}"

    grep -Fxq "ConditionPathExists=/opt/homelab-sentinel/app/scripts/with-inventory-retry.sh" "${service_path}" ||
        fail "${service_name} does not require the inventory retry wrapper"

    exec_start="$(grep -E '^ExecStart=' "${service_path}" || true)"

    [[ -n "${exec_start}" ]] ||
        fail "${service_name} has no ExecStart"

    [[ "${exec_start}" == *"/scripts/with-inventory-retry.sh "* ]] ||
        fail "${service_name} does not use the inventory retry wrapper"

    [[ "${exec_start}" != *"/scripts/with-inventory-lock.sh "* ]] ||
        fail "${service_name} bypasses retry policy and invokes the lock wrapper directly"

    pass "${service_name} uses bounded inventory contention retry"
done

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel systemd inventory retry integration regression PASSED"
