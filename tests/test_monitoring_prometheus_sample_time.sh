#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
ADAPTER="${APP_ROOT}/compose/monitoring/prometheus/scripts/observe.py"
STORE="${APP_ROOT}/core/monitoring/store.py"

TMP_ROOT="$(mktemp -d /tmp/hls-prometheus-sample-time.XXXXXX)"
SERVER_PID=""

cleanup() {
    if [[ -n "${SERVER_PID}" ]]; then
        kill "${SERVER_PID}" >/dev/null 2>&1 || true
        wait "${SERVER_PID}" >/dev/null 2>&1 || true
    fi
    rm -rf "${TMP_ROOT}"
}

trap cleanup EXIT

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo "HomeLab Sentinel Prometheus sample-time regression"
echo

cat >"${TMP_ROOT}/server.py" <<'PY'
#!/usr/bin/env python3

import json
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

port_file = sys.argv[1]

payload = {
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": {
                    "__name__": "probe_success",
                    "hls_check_type": "reachability",
                    "hls_entity_id": "dev-sample-time",
                    "hls_provider": "prometheus",
                    "instance": "192.0.2.50",
                    "job": "hls-reachability",
                },
                "value": [1787852001.137, "0"],
            }
        ],
    },
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path != "/api/v1/query":
            self.send_response(404)
            self.end_headers()
            return

        body = json.dumps(payload).encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return


server = HTTPServer(("127.0.0.1", 0), Handler)

with open(port_file, "w", encoding="utf-8") as handle:
    handle.write(str(server.server_address[1]))

server.serve_forever()
PY

python3 "${TMP_ROOT}/server.py" "${TMP_ROOT}/port" &
SERVER_PID=$!

for _ in $(seq 1 50); do
    [[ -s "${TMP_ROOT}/port" ]] && break
    sleep 0.05
done

[[ -s "${TMP_ROOT}/port" ]] ||
    fail "deterministic Prometheus fixture server did not start"

PORT="$(cat "${TMP_ROOT}/port")"
BASE_URL="http://127.0.0.1:${PORT}"

pass "deterministic Prometheus fixture server started"

"${ADAPTER}" \
    --entity-id "dev-sample-time" \
    --target "192.0.2.50" \
    --prometheus-url "${BASE_URL}" \
    >"${TMP_ROOT}/first.json"

sleep 1

"${ADAPTER}" \
    --entity-id "dev-sample-time" \
    --target "192.0.2.50" \
    --prometheus-url "${BASE_URL}" \
    >"${TMP_ROOT}/second.json"

python3 - "${TMP_ROOT}/first.json" "${TMP_ROOT}/second.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    first = json.load(handle)

with open(sys.argv[2], encoding="utf-8") as handle:
    second = json.load(handle)

assert first == second

assert first["checked_at"] == "2026-08-27T17:33:21.137000Z"
assert first["status"] == "failed"
PY

pass "repeated live query preserves identical Prometheus sample timestamp"
pass "same provider sample produces identical canonical observation"

echo
echo "=== STORE IDEMPOTENCE ==="

python3 - "${TMP_ROOT}/inventory.db" <<'PY'
import sqlite3
import sys

db = sys.argv[1]

con = sqlite3.connect(db)

try:
    con.executescript("""
        PRAGMA user_version = 3;

        CREATE TABLE entities (
            entity_id TEXT PRIMARY KEY
        );

        CREATE TABLE monitoring_observations (
            monitoring_observation_id TEXT PRIMARY KEY,
            entity_id TEXT NOT NULL,
            schema_version TEXT NOT NULL,
            provider TEXT NOT NULL,
            check_type TEXT NOT NULL,
            target TEXT NOT NULL,
            checked_at TEXT NOT NULL,
            received_at TEXT NOT NULL,
            status TEXT NOT NULL,
            latency_ms REAL,
            payload_json TEXT NOT NULL,
            payload_hash TEXT NOT NULL UNIQUE
        );

        INSERT INTO entities(entity_id)
        VALUES ('dev-sample-time');
    """)
    con.commit()
finally:
    con.close()
PY

cat "${TMP_ROOT}/first.json" \
    "${TMP_ROOT}/second.json" \
    | "${STORE}" \
        --database "${TMP_ROOT}/inventory.db" \
        >"${TMP_ROOT}/store.out" \
        2>"${TMP_ROOT}/store.err"

python3 - "${TMP_ROOT}/inventory.db" <<'PY'
import sqlite3
import sys

con = sqlite3.connect(sys.argv[1])

try:
    count = con.execute(
        "SELECT COUNT(*) FROM monitoring_observations"
    ).fetchone()[0]

    assert count == 1
finally:
    con.close()
PY

pass "same Prometheus sample is persisted only once"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Prometheus sample-time regression PASSED"
