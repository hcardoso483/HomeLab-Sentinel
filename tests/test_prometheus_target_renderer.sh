#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
RENDERER="${APP_ROOT}/compose/monitoring/prometheus/scripts/render-targets.py"
REGISTRY="${APP_ROOT}/registry/registry.sh"

TMP_ROOT="$(mktemp -d /tmp/hls-prometheus-target-renderer-test.XXXXXX)"
OUTPUT="${TMP_ROOT}/targets/reachability.json"

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

echo "HomeLab Sentinel Prometheus target renderer regression test"
echo
echo "Output : ${OUTPUT}"
echo

[[ -x "${RENDERER}" ]] ||
    fail "Prometheus target renderer missing or not executable"

ENTRYPOINT="$("${REGISTRY}" entrypoint prometheus monitoring-target-renderer)"

[[ "${ENTRYPOINT}" == "${RENDERER}" ]] ||
    fail "Registry returned unexpected target renderer: ${ENTRYPOINT}"

pass "Registry resolves provider-owned target renderer"

cat >"${TMP_ROOT}/targets.jsonl" <<'JSONL'
{"eligible":true,"endpoints":{"hostname":null,"ip_addresses":["192.0.2.20"]},"entity_id":"dev-render-b","entity_type":"device","schema_version":"1.0","state":"UNKNOWN"}
{"eligible":false,"endpoints":{"hostname":null,"ip_addresses":[]},"entity_id":"dev-render-skip","entity_type":"device","schema_version":"1.0","state":"UNKNOWN"}
{"eligible":true,"endpoints":{"hostname":"host-a.example","ip_addresses":[]},"entity_id":"dev-render-a","entity_type":"device","schema_version":"1.0","state":"UNKNOWN"}
JSONL

"${RENDERER}" \
    --output "${OUTPUT}" \
    <"${TMP_ROOT}/targets.jsonl"

[[ -f "${OUTPUT}" ]] ||
    fail "rendered file_sd target file was not created"

pass "provider runtime target file created"

python3 - "${OUTPUT}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    groups = json.load(handle)

assert len(groups) == 2

assert groups == [
    {
        "labels": {
            "hls_check_type": "reachability",
            "hls_entity_id": "dev-render-a",
            "hls_provider": "prometheus",
        },
        "targets": ["host-a.example"],
    },
    {
        "labels": {
            "hls_check_type": "reachability",
            "hls_entity_id": "dev-render-b",
            "hls_provider": "prometheus",
        },
        "targets": ["192.0.2.20"],
    },
]
PY

pass "eligible targets rendered deterministically"
pass "canonical entity_id preserved as provider label"
pass "ineligible target omitted"
pass "hostname fallback preserved"

BEFORE="$(sha256sum "${OUTPUT}")"

"${RENDERER}" \
    --output "${OUTPUT}" \
    <"${TMP_ROOT}/targets.jsonl"

AFTER="$(sha256sum "${OUTPUT}")"

[[ "${BEFORE}" == "${AFTER}" ]] ||
    fail "identical target input did not produce identical output"

pass "identical rendering is deterministic"

cat >"${TMP_ROOT}/duplicate.jsonl" <<'JSONL'
{"eligible":true,"endpoints":{"hostname":null,"ip_addresses":["192.0.2.20"]},"entity_id":"dev-duplicate","entity_type":"device","schema_version":"1.0","state":"UNKNOWN"}
{"eligible":true,"endpoints":{"hostname":null,"ip_addresses":["192.0.2.21"]},"entity_id":"dev-duplicate","entity_type":"device","schema_version":"1.0","state":"UNKNOWN"}
JSONL

if "${RENDERER}" \
    --output "${TMP_ROOT}/duplicate.json" \
    <"${TMP_ROOT}/duplicate.jsonl" \
    >/dev/null 2>&1; then
    fail "duplicate canonical entity_id unexpectedly rendered"
fi

pass "duplicate canonical entity_id rejected"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Prometheus target renderer regression PASSED"
