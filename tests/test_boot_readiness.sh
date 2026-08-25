#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
WAIT="${APP_ROOT}/scripts/wait-core-api.sh"
CHECK="${APP_ROOT}/scripts/check-boot-ready.sh"

TMP_ROOT="$(mktemp -d /tmp/hls-boot-readiness-test.XXXXXX)"
DB="${TMP_ROOT}/inventory.db"
READY="${TMP_ROOT}/boot-ready"
PORT="$((19000 + RANDOM % 1000))"
SERVER_PID=""

cleanup() {
    if [[ -n "${SERVER_PID}" ]]; then
        kill "${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
    fi
    rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

echo "HomeLab Sentinel boot readiness regression test"
echo

python3 - "${DB}" <<'PY'
import sqlite3
import sys

db = sys.argv[1]
con = sqlite3.connect(db)
con.execute("CREATE TABLE entities (entity_id TEXT PRIMARY KEY)")
con.execute("PRAGMA user_version = 3")
con.execute("INSERT INTO entities VALUES ('dev-test')")
con.commit()
con.close()
PY

pass "deterministic Inventory fixture created"

python3 - "${PORT}" <<'PY' &
import http.server
import json
import sys

port = int(sys.argv[1])

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/api/v1/health":
            self.send_response(404)
            self.end_headers()
            return
        payload = json.dumps({"status": "ok"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        pass

http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY

SERVER_PID=$!

for _ in $(seq 1 20); do
    curl -fsS "http://127.0.0.1:${PORT}/api/v1/health" >/dev/null 2>&1 && break
    sleep 0.1
done

API_HEALTH_URL="http://127.0.0.1:${PORT}/api/v1/health" DATABASE="${DB}" BOOT_READY_FILE="${READY}" WAIT_TIMEOUT=10 WAIT_INTERVAL=0.1 DB_PROBE_TIMEOUT=2 REQUIRED_STABLE_PASSES=3     "${WAIT}"

[[ -f "${READY}" ]] || fail "boot readiness file was not created"
pass "boot readiness file created"

grep -Fxq "API_READY=1" "${READY}" || fail "API readiness flag missing"
grep -Fxq "INVENTORY_READY=1" "${READY}" || fail "Inventory readiness flag missing"
grep -Fxq "STABLE_PASSES=3" "${READY}" || fail "stable pass count missing"
pass "readiness records API, Inventory, and stability"

BOOT_READY_FILE="${READY}" "${CHECK}" >/dev/null
pass "current-boot readiness accepted"

cp "${READY}" "${READY}.wrong-boot"
sed -i 's/^BOOT_ID=.*/BOOT_ID=not-this-boot/' "${READY}.wrong-boot"

if BOOT_READY_FILE="${READY}.wrong-boot" "${CHECK}" >/dev/null 2>&1; then
    fail "stale boot readiness unexpectedly accepted"
fi
pass "different-boot readiness rejected"

BAD_READY="${TMP_ROOT}/bad-ready"

if API_HEALTH_URL="http://127.0.0.1:${PORT}/api/v1/health"    DATABASE="${TMP_ROOT}/missing.db"    BOOT_READY_FILE="${BAD_READY}"    WAIT_TIMEOUT=1    WAIT_INTERVAL=0.1    DB_PROBE_TIMEOUT=0.2    REQUIRED_STABLE_PASSES=2        "${WAIT}" >/dev/null 2>&1; then
    fail "missing Inventory unexpectedly produced readiness"
fi

[[ ! -e "${BAD_READY}" ]] ||
    fail "failed readiness attempt left a completion flag"

pass "Inventory failure prevents readiness publication"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel boot readiness regression PASSED"
