#!/usr/bin/env bash
set -Eeuo pipefail

API_HEALTH_URL="${API_HEALTH_URL:-http://127.0.0.1:8000/api/v1/health}"
BOOT_READY_FILE="${BOOT_READY_FILE:-/run/homelab-sentinel/boot-ready}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-30}"
WAIT_INTERVAL="${WAIT_INTERVAL:-1}"

rm -f "${BOOT_READY_FILE}" "${BOOT_READY_FILE}.tmp"

boot_id="$(cat /proc/sys/kernel/random/boot_id)"
deadline=$((SECONDS + WAIT_TIMEOUT))

echo "[INFO] Waiting for HomeLab Sentinel Core API readiness..."

while (( SECONDS < deadline )); do
    response=""

    if response="$(curl --fail --silent --max-time 2 "${API_HEALTH_URL}" 2>/dev/null)" &&
       grep -Fq '"status":"ok"' <<< "${response}"; then

        mkdir -p "$(dirname "${BOOT_READY_FILE}")"

        tmp_file="${BOOT_READY_FILE}.tmp"

        {
            echo "BOOT_ID=${boot_id}"
            echo "API_READY=1"
            echo "READY_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
            echo "API_URL=${API_HEALTH_URL}"
        } > "${tmp_file}"

        mv "${tmp_file}" "${BOOT_READY_FILE}"

        echo "[PASS] Core API readiness confirmed."
        echo "[PASS] Boot readiness recorded: ${BOOT_READY_FILE}"
        exit 0
    fi

    sleep "${WAIT_INTERVAL}"
done

echo "[FAIL] Core API did not become ready within ${WAIT_TIMEOUT} seconds." >&2
exit 1
