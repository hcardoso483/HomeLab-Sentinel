#!/usr/bin/env bash
set -Eeuo pipefail

BOOT_READY_FILE="${BOOT_READY_FILE:-/run/homelab-sentinel/boot-ready}"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

[[ -f "${BOOT_READY_FILE}" ]] ||
    fail "Boot readiness file missing: ${BOOT_READY_FILE}"

current_boot_id="$(cat /proc/sys/kernel/random/boot_id)"

boot_id="$(awk -F= '$1 == "BOOT_ID" {print substr($0, index($0, "=") + 1)}' "${BOOT_READY_FILE}")"
api_ready="$(awk -F= '$1 == "API_READY" {print substr($0, index($0, "=") + 1)}' "${BOOT_READY_FILE}")"
inventory_ready="$(awk -F= '$1 == "INVENTORY_READY" {print substr($0, index($0, "=") + 1)}' "${BOOT_READY_FILE}")"

[[ "${boot_id}" == "${current_boot_id}" ]] ||
    fail "Boot readiness belongs to a different boot"

[[ "${api_ready}" == "1" ]] ||
    fail "Boot readiness does not confirm Core API readiness"

[[ "${inventory_ready}" == "1" ]] ||
    fail "Boot readiness does not confirm Inventory readiness"

echo "[PASS] Current-boot platform readiness confirmed."
