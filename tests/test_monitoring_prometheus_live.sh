#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
ADAPTER="${APP_ROOT}/compose/monitoring/prometheus/scripts/observe.py"
VALIDATOR_DIR="${APP_ROOT}/core/monitoring"

TMP_ROOT="$(mktemp -d /tmp/hls-prometheus-live-test.XXXXXX)"
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

[[ -x "${ADAPTER}" ]] ||
    fail "Prometheus Monitoring adapter missing or not executable: ${ADAPTER}"

echo "HomeLab Sentinel Prometheus live adapter regression test"
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
                    "__name__": "up",
                    "instance": "localhost:9090",
                    "job": "prometheus",
                },
                "value": [1787648311.832, "1"],
            },
            {
                "metric": {
                    "__name__": "up",
                    "instance": "192.0.2.20:9100",
                    "job": "sentinel",
                },
                "value": [1787648311.832, "0"],
            },
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

        query = urllib.parse.parse_qs(parsed.query).get("query", [""])[0]
        if query != "up":
            self.send_response(400)
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
    fail "deterministic Prometheus HTTP fixture server did not start"

PORT="$(cat "${TMP_ROOT}/port")"
BASE_URL="http://127.0.0.1:${PORT}"

pass "deterministic Prometheus HTTP fixture server started"

"${ADAPTER}" \
    --entity-id "dev-live-fixture" \
    --target "localhost:9090" \
    --live \
    --prometheus-url "${BASE_URL}" \
    --instance "localhost:9090" \
    --job "prometheus" \
    --checked-at "2026-08-25T10:15:00Z" \
    >"${TMP_ROOT}/success.out"

PYTHONPATH="${VALIDATOR_DIR}" \
python3 - "${TMP_ROOT}/success.out" <<'PY'
import json
import sys

from validate_observation import validate_observation

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    record = json.load(handle)

validate_observation(record)

assert record["entity_id"] == "dev-live-fixture"
assert record["provider"] == "prometheus"
assert record["check_type"] == "reachability"
assert record["target"] == "localhost:9090"
assert record["checked_at"] == "2026-08-25T10:15:00Z"
assert record["status"] == "success"
assert record["latency_ms"] is None
PY

pass "live HTTP query -> canonical success observation"

"${ADAPTER}" \
    --entity-id "dev-live-fixture" \
    --target "192.0.2.20:9100" \
    --live \
    --prometheus-url "${BASE_URL}" \
    --instance "192.0.2.20:9100" \
    --job "sentinel" \
    --checked-at "2026-08-25T10:15:00Z" \
    >"${TMP_ROOT}/failed.out"

python3 - "${TMP_ROOT}/failed.out" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    record = json.load(handle)

assert record["status"] == "failed"
PY

pass "live HTTP query selects requested instance/job"

"${ADAPTER}" \
    --entity-id "dev-live-fixture" \
    --target "192.0.2.99:9100" \
    --live \
    --prometheus-url "${BASE_URL}" \
    --instance "192.0.2.99:9100" \
    --job "sentinel" \
    --checked-at "2026-08-25T10:15:00Z" \
    >"${TMP_ROOT}/unknown.out"

python3 - "${TMP_ROOT}/unknown.out" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    record = json.load(handle)

assert record["status"] == "unknown"
PY

pass "missing requested live result -> canonical unknown observation"

"${ADAPTER}" \
    --entity-id "dev-live-fixture" \
    --target "ambiguous" \
    --live \
    --prometheus-url "${BASE_URL}" \
    --checked-at "2026-08-25T10:15:00Z" \
    >"${TMP_ROOT}/ambiguous.out"

python3 - "${TMP_ROOT}/ambiguous.out" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    record = json.load(handle)

assert record["status"] == "unknown"
PY

pass "ambiguous live vector -> canonical unknown observation"

if "${ADAPTER}" \
    --entity-id "dev-live-fixture" \
    --target "unreachable" \
    --live \
    --prometheus-url "http://127.0.0.1:1" \
    --timeout 0.2 \
    --checked-at "2026-08-25T10:15:00Z" \
    >"${TMP_ROOT}/unreachable.out" 2>"${TMP_ROOT}/unreachable.err"; then
    fail "unreachable Prometheus endpoint unexpectedly succeeded"
fi

grep -q "Prometheus live query failed" "${TMP_ROOT}/unreachable.err" ||
    fail "unreachable Prometheus endpoint did not report provider query failure"

pass "unreachable Prometheus endpoint fails without inventing observation"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Prometheus live adapter regression PASSED"
