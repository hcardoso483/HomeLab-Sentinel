#!/usr/bin/env bash
set -Eeuo pipefail

API_HEALTH_URL="${API_HEALTH_URL:-http://127.0.0.1:8000/api/v1/health}"
DATABASE="${DATABASE:-/srv/homelab-sentinel/sentinel/inventory.db}"
BOOT_READY_FILE="${BOOT_READY_FILE:-/run/homelab-sentinel/boot-ready}"

WAIT_TIMEOUT="${WAIT_TIMEOUT:-90}"
WAIT_INTERVAL="${WAIT_INTERVAL:-1}"
DB_PROBE_TIMEOUT="${DB_PROBE_TIMEOUT:-5}"
REQUIRED_STABLE_PASSES="${REQUIRED_STABLE_PASSES:-3}"

rm -f "${BOOT_READY_FILE}" "${BOOT_READY_FILE}.tmp"

boot_id="$(cat /proc/sys/kernel/random/boot_id)"
deadline=$((SECONDS + WAIT_TIMEOUT))
stable_passes=0

probe_inventory() {
    timeout "${DB_PROBE_TIMEOUT}" python3 - "${DATABASE}" <<'PY'
import sqlite3
import sys

database = sys.argv[1]

try:
    connection = sqlite3.connect(
        f"file:{database}?mode=ro",
        uri=True,
        timeout=2.0,
    )
    try:
        connection.execute("PRAGMA query_only = ON")
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        connection.execute("SELECT COUNT(*) FROM entities").fetchone()
    finally:
        connection.close()
except (OSError, sqlite3.Error):
    raise SystemExit(1)

if version < 1:
    raise SystemExit(1)
PY
}

echo "[INFO] Waiting for HomeLab Sentinel platform readiness..."
echo "[INFO] Required stable passes: ${REQUIRED_STABLE_PASSES}"

while (( SECONDS < deadline )); do
    response=""
    api_ready=false
    inventory_ready=false

    if response="$(curl --fail --silent --max-time 2 "${API_HEALTH_URL}" 2>/dev/null)" &&
       python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    raise SystemExit(1)

raise SystemExit(0 if payload.get("status") == "ok" else 1)
' <<< "${response}"; then
        api_ready=true
    fi

    if [[ "${api_ready}" == "true" ]] && probe_inventory; then
        inventory_ready=true
    fi

    if [[ "${api_ready}" == "true" && "${inventory_ready}" == "true" ]]; then
        stable_passes=$((stable_passes + 1))
        echo "[INFO] Platform readiness pass ${stable_passes}/${REQUIRED_STABLE_PASSES}"
    else
        if (( stable_passes > 0 )); then
            echo "[INFO] Platform readiness stability reset."
        fi
        stable_passes=0
    fi

    if (( stable_passes >= REQUIRED_STABLE_PASSES )); then
        mkdir -p "$(dirname "${BOOT_READY_FILE}")"
        tmp_file="${BOOT_READY_FILE}.tmp"

        {
            echo "BOOT_ID=${boot_id}"
            echo "API_READY=1"
            echo "INVENTORY_READY=1"
            echo "STABLE_PASSES=${stable_passes}"
            echo "READY_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
            echo "API_URL=${API_HEALTH_URL}"
            echo "DATABASE=${DATABASE}"
        } > "${tmp_file}"

        mv "${tmp_file}" "${BOOT_READY_FILE}"

        echo "[PASS] Core API readiness confirmed."
        echo "[PASS] Inventory readiness confirmed."
        echo "[PASS] Platform readiness recorded: ${BOOT_READY_FILE}"
        exit 0
    fi

    sleep "${WAIT_INTERVAL}"
done

echo "[FAIL] Platform did not become stably ready within ${WAIT_TIMEOUT} seconds." >&2
exit 1
