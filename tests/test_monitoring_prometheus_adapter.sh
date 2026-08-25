#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
ADAPTER="${APP_ROOT}/compose/monitoring/prometheus/scripts/observe.py"
VALIDATOR_DIR="${APP_ROOT}/core/monitoring"

TMP_ROOT="$(mktemp -d /tmp/hls-prometheus-adapter-test.XXXXXX)"

cleanup() {
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

echo "HomeLab Sentinel Prometheus Monitoring adapter regression test"
echo

cat >"${TMP_ROOT}/up.json" <<'JSON'
{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": [
      {
        "metric": {
          "__name__": "up",
          "instance": "192.0.2.10:9100",
          "job": "sentinel"
        },
        "value": [1787644800, "1"]
      }
    ]
  }
}
JSON

cat >"${TMP_ROOT}/down.json" <<'JSON'
{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": [
      {
        "metric": {
          "__name__": "up",
          "instance": "192.0.2.11:9100",
          "job": "sentinel"
        },
        "value": [1787644800, "0"]
      }
    ]
  }
}
JSON

cat >"${TMP_ROOT}/missing.json" <<'JSON'
{
  "status": "success",
  "data": {
    "resultType": "vector",
    "result": []
  }
}
JSON

cat >"${TMP_ROOT}/error.json" <<'JSON'
{
  "status": "error",
  "errorType": "timeout",
  "error": "fixture timeout"
}
JSON

run_case() {
    local fixture="$1"
    local expected="$2"
    local output="$3"

    "${ADAPTER}" \
        --entity-id "dev-prometheus-fixture" \
        --target "192.0.2.10" \
        --fixture "${fixture}" \
        --checked-at "2026-08-25T10:00:00Z" \
        >"${output}"

    PYTHONPATH="${VALIDATOR_DIR}" \
    python3 - "${output}" "${expected}" <<'PY'
import json
import sys

from validate_observation import validate_observation

path = sys.argv[1]
expected = sys.argv[2]

with open(path, "r", encoding="utf-8") as handle:
    record = json.load(handle)

validate_observation(record)

assert record["schema_version"] == "1.0"
assert record["entity_id"] == "dev-prometheus-fixture"
assert record["provider"] == "prometheus"
assert record["check_type"] == "reachability"
assert record["target"] == "192.0.2.10"
assert record["checked_at"] == "2026-08-25T10:00:00Z"
assert record["status"] == expected
assert record["latency_ms"] is None
PY
}

run_case "${TMP_ROOT}/up.json" "success" "${TMP_ROOT}/up.out"
pass "Prometheus up=1 -> canonical success observation"

run_case "${TMP_ROOT}/down.json" "failed" "${TMP_ROOT}/down.out"
pass "Prometheus up=0 -> canonical failed observation"

run_case "${TMP_ROOT}/missing.json" "unknown" "${TMP_ROOT}/missing.out"
pass "missing Prometheus result -> canonical unknown observation"

run_case "${TMP_ROOT}/error.json" "unknown" "${TMP_ROOT}/error.out"
pass "Prometheus API error -> canonical unknown observation"

python3 - "${TMP_ROOT}/up.out" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    record = json.load(handle)

for forbidden in ("HEALTHY", "DEGRADED", "DOWN"):
    if record.get("status") == forbidden:
        raise SystemExit("provider adapter derived Core health state")
PY
pass "provider adapter does not derive Monitoring Core health"

if grep -qE 'sqlite3|monitoring_observations|INSERT INTO' "${ADAPTER}"; then
    fail "provider adapter contains persistence coupling"
fi
pass "provider adapter has no persistence coupling"

if grep -qE 'HEALTHY|DEGRADED|DOWN' "${ADAPTER}"; then
    fail "provider adapter contains Monitoring Core health states"
fi
pass "provider adapter has no health-evaluator coupling"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Prometheus Monitoring adapter regression PASSED"
