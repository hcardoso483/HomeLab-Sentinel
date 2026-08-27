#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
ADAPTER="${APP_ROOT}/compose/monitoring/prometheus/scripts/observe.py"
VALIDATOR_DIR="${APP_ROOT}/core/monitoring"

TMP_ROOT="$(mktemp -d /tmp/hls-prometheus-reachability-adapter.XXXXXX)"
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

echo "HomeLab Sentinel Prometheus reachability adapter regression"
echo

cat >"${TMP_ROOT}/server.py" <<'PY'
#!/usr/bin/env python3

import json
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

port_file = sys.argv[1]

EXPECTED_QUERY = (
    'probe_success{'
    'hls_check_type="reachability",'
    'hls_provider="prometheus",'
    'hls_entity_id="dev-reachability-fixture",'
    'job="hls-reachability"'
    '}'
)

payload = {
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": {
                    "__name__": "probe_success",
                    "hls_check_type": "reachability",
                    "hls_entity_id": "dev-reachability-fixture",
                    "hls_provider": "prometheus",
                    "instance": "192.0.2.20",
                    "job": "hls-reachability",
                },
                "value": [1787852001.137, "1"],
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

        query = urllib.parse.parse_qs(
            parsed.query
        ).get("query", [""])[0]

        if query != EXPECTED_QUERY:
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
    fail "deterministic Prometheus fixture server did not start"

PORT="$(cat "${TMP_ROOT}/port")"
BASE_URL="http://127.0.0.1:${PORT}"

pass "deterministic Prometheus fixture server started"

"${ADAPTER}" \
    --entity-id "dev-reachability-fixture" \
    --target "192.0.2.20" \
    --prometheus-url "${BASE_URL}" \
    --checked-at "2026-08-27T17:35:00Z" \
    >"${TMP_ROOT}/observation.json"

PYTHONPATH="${VALIDATOR_DIR}" \
python3 - "${TMP_ROOT}/observation.json" <<'PY'
import json
import sys

from validate_observation import validate_observation

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    record = json.load(handle)

validate_observation(record)

assert record == {
    "check_type": "reachability",
    "checked_at": "2026-08-27T17:35:00Z",
    "entity_id": "dev-reachability-fixture",
    "latency_ms": None,
    "provider": "prometheus",
    "schema_version": "1.0",
    "status": "success",
    "target": "192.0.2.20",
}
PY

pass "default provider query selects canonical probe_success evidence"
pass "probe_success=1 translates to canonical success observation"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Prometheus reachability adapter regression PASSED"
