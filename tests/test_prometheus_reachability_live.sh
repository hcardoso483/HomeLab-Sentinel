#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
PROM_ROOT="${APP_ROOT}/compose/monitoring/prometheus"
REGISTRY="${APP_ROOT}/registry/registry.sh"

PROMETHEUS_URL="http://127.0.0.1:9090"
TARGET_FILE="/srv/homelab-sentinel/prometheus/targets/reachability.json"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo "HomeLab Sentinel Prometheus live reachability integration"
echo

RECONCILER="$(
    "${REGISTRY}" \
        entrypoint \
        prometheus \
        monitoring-target-reconciler
)"

[[ -x "${RECONCILER}" ]] ||
    fail "Prometheus target reconciler unavailable"

echo "=== TARGET RECONCILIATION ==="

"${RECONCILER}"

[[ -r "${TARGET_FILE}" ]] ||
    fail "Prometheus runtime target state is not host-readable"

EXPECTED="$(
    python3 - "${TARGET_FILE}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    groups = json.load(handle)

print(len(groups))
PY
)"

[[ "${EXPECTED}" -gt 0 ]] ||
    fail "No live Prometheus reachability targets were rendered"

pass "live Monitoring targets reconciled: ${EXPECTED}"

echo
echo "=== PROMETHEUS READINESS ==="

curl -fsS "${PROMETHEUS_URL}/-/ready" >/dev/null ||
    fail "Prometheus is not ready"

pass "Prometheus ready"

CONTAINER="$(
    docker compose \
        -f "${PROM_ROOT}/compose.yml" \
        ps -q prometheus
)"

[[ -n "${CONTAINER}" ]] ||
    fail "Prometheus container is not running"

docker exec "${CONTAINER}" \
    test -r /etc/prometheus/hls-targets/reachability.json ||
    fail "Prometheus cannot read reconciled target state"

pass "Prometheus can read reconciled target state"

echo
echo "=== FILE-SD DISCOVERY ==="

TMP_ROOT="$(mktemp -d /tmp/hls-prometheus-reachability-live.XXXXXX)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

TARGETS_JSON="${TMP_ROOT}/targets.json"
PROBES_JSON="${TMP_ROOT}/probes.json"

LOADED=0

for _ in $(seq 1 10); do
    curl -fsS \
        "${PROMETHEUS_URL}/api/v1/targets?state=active" \
        -o "${TARGETS_JSON}" ||
        fail "Unable to query Prometheus active targets"

    LOADED="$(
        python3 - "${TARGETS_JSON}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

targets = [
    target
    for target in payload["data"]["activeTargets"]
    if target.get("labels", {}).get("hls_check_type") == "reachability"
]

print(len(targets))
PY
    )"

    [[ "${LOADED}" -eq "${EXPECTED}" ]] && break
    sleep 5
done

[[ "${LOADED}" -eq "${EXPECTED}" ]] ||
    fail "Prometheus loaded ${LOADED}/${EXPECTED} reachability targets"

pass "Prometheus loaded all ${LOADED} reachability targets"

python3 - "${TARGETS_JSON}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

targets = [
    target
    for target in payload["data"]["activeTargets"]
    if target.get("labels", {}).get("hls_check_type") == "reachability"
]

for target in targets:
    labels = target.get("labels", {})

    assert labels.get("hls_entity_id"), (
        "reachability target missing hls_entity_id"
    )

    assert labels.get("hls_provider") == "prometheus", (
        "reachability target missing canonical provider label"
    )
PY

pass "Sentinel identity labels preserved through file-SD"

echo
echo "=== PROBE EVIDENCE ==="

PROBE_COUNT=0

for _ in $(seq 1 10); do
    curl -fsS \
        --get \
        --data-urlencode \
        'query=probe_success{hls_check_type="reachability"}' \
        "${PROMETHEUS_URL}/api/v1/query" \
        -o "${PROBES_JSON}" ||
        fail "Unable to query Prometheus probe evidence"

    PROBE_COUNT="$(
        python3 - "${PROBES_JSON}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

print(len(payload["data"]["result"]))
PY
    )"

    [[ "${PROBE_COUNT}" -eq "${EXPECTED}" ]] && break
    sleep 5
done

[[ "${PROBE_COUNT}" -eq "${EXPECTED}" ]] ||
    fail "Prometheus exposes ${PROBE_COUNT}/${EXPECTED} probe_success series"

python3 - "${PROBES_JSON}" "${EXPECTED}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

expected = int(sys.argv[2])
series = payload["data"]["result"]

assert len(series) == expected

entity_ids = set()

for item in series:
    metric = item["metric"]
    value = item["value"][1]

    entity_id = metric.get("hls_entity_id")
    assert entity_id, "probe_success series missing hls_entity_id"
    assert entity_id not in entity_ids, (
        f"duplicate probe_success entity identity: {entity_id}"
    )

    entity_ids.add(entity_id)

    assert value in {"0", "1"}, (
        f"invalid probe_success value for {entity_id}: {value}"
    )

reachable = sum(item["value"][1] == "1" for item in series)
unreachable = len(series) - reachable

print(f"Probe series : {len(series)}")
print(f"Reachable    : {reachable}")
print(f"Unreachable  : {unreachable}")
PY

pass "every reconciled target exposes canonical probe evidence"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Prometheus live reachability integration PASSED"
