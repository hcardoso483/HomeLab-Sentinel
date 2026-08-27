#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"

RECONCILER="${APP_ROOT}/compose/monitoring/prometheus/scripts/reconcile-targets.sh"
RENDERER="${APP_ROOT}/compose/monitoring/prometheus/scripts/render-targets.py"
REGISTRY="${APP_ROOT}/registry/registry.sh"

TMP_ROOT="$(mktemp -d /tmp/hls-prometheus-target-reconcile-test.XXXXXX)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

DATABASE="${TMP_ROOT}/inventory.db"
OUTPUT="${TMP_ROOT}/targets/reachability.json"
MONITORING_CORE="${TMP_ROOT}/monitoring-core.sh"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo "HomeLab Sentinel Prometheus target reconciliation regression"

[[ -x "${RECONCILER}" ]] ||
    fail "Prometheus target reconciler missing or not executable"

[[ -x "${RENDERER}" ]] ||
    fail "Prometheus target renderer missing or not executable"

touch "${DATABASE}"

cat > "${MONITORING_CORE}" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail

cat <<'JSONL'
{"eligible":true,"endpoints":{"hostname":null,"ip_addresses":["192.0.2.20"]},"entity_id":"dev-live-b","entity_type":"device","schema_version":"1.0","state":"UNKNOWN"}
{"eligible":false,"endpoints":{"hostname":null,"ip_addresses":[]},"entity_id":"dev-live-skip","entity_type":"device","schema_version":"1.0","state":"UNKNOWN"}
{"eligible":true,"endpoints":{"hostname":"live-a.example","ip_addresses":[]},"entity_id":"dev-live-a","entity_type":"device","schema_version":"1.0","state":"UNKNOWN"}
JSONL
MOCK

chmod +x "${MONITORING_CORE}"

ENTRYPOINT="$(
    "${REGISTRY}" \
        entrypoint \
        prometheus \
        monitoring-target-reconciler
)"

[[ "${ENTRYPOINT}" == "${RECONCILER}" ]] ||
    fail "Registry returned unexpected target reconciler: ${ENTRYPOINT}"

pass "Registry resolves provider-owned target reconciler"

echo
echo "=== RECONCILIATION ==="

OUTPUT_TEXT="$(
    APP_ROOT="${APP_ROOT}" \
    DATABASE="${DATABASE}" \
    OUTPUT="${OUTPUT}" \
    MONITORING_CORE="${MONITORING_CORE}" \
    RENDERER="${RENDERER}" \
    "${RECONCILER}"
)"

printf '%s\n' "${OUTPUT_TEXT}"

[[ -f "${OUTPUT}" ]] ||
    fail "reconciled Prometheus target state was not created"

pass "Prometheus runtime target state created"

python3 - "${OUTPUT}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    groups = json.load(handle)

assert groups == [
    {
        "labels": {
            "hls_check_type": "reachability",
            "hls_entity_id": "dev-live-a",
            "hls_provider": "prometheus",
        },
        "targets": ["live-a.example"],
    },
    {
        "labels": {
            "hls_check_type": "reachability",
            "hls_entity_id": "dev-live-b",
            "hls_provider": "prometheus",
        },
        "targets": ["192.0.2.20"],
    },
]
PY

pass "canonical Monitoring targets reconciled deterministically"
pass "ineligible canonical target omitted"
pass "canonical entity identity preserved"

grep -Fq "Canonical targets : 3" <<<"${OUTPUT_TEXT}" ||
    fail "canonical target count missing"

grep -Fq "Rendered targets  : 2" <<<"${OUTPUT_TEXT}" ||
    fail "rendered target count missing"

pass "reconciliation summary reports canonical and rendered counts"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Prometheus target reconciliation regression PASSED"
