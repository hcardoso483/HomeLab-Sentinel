#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MONITORING="${APP_ROOT}/core/monitoring/monitoring.py"
RESOLVER="${APP_ROOT}/core/resolver/resolver.sh"
HLS="${APP_ROOT}/installer/hls"

TMP_DIR="$(mktemp -d /tmp/hls-monitoring-provider-test.XXXXXX)"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

[[ -x "${MONITORING}" ]] ||
    fail "Monitoring Core missing or not executable: ${MONITORING}"
[[ -x "${RESOLVER}" ]] ||
    fail "Provider Resolver missing or not executable: ${RESOLVER}"
[[ -x "${HLS}" ]] ||
    fail "HLS CLI missing or not executable: ${HLS}"

echo "HomeLab Sentinel Monitoring provider regression test"
echo

EXPECTED_PROVIDER="$("${RESOLVER}" provider-id monitoring)" ||
    fail "Provider Resolver could not resolve monitoring provider"

[[ -n "${EXPECTED_PROVIDER}" ]] ||
    fail "Provider Resolver returned an empty monitoring provider"

pass "existing Provider Resolver returns a monitoring provider"

DIRECT_JSON="${TMP_DIR}/direct.json"
"${MONITORING}" provider --json >"${DIRECT_JSON}"

python3 - "${DIRECT_JSON}" "${EXPECTED_PROVIDER}" <<'PY'
import json
import sys

path, expected_provider = sys.argv[1:3]

with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

expected_keys = {
    "capability",
    "provider",
    "source",
    "status",
}

if set(data) != expected_keys:
    raise SystemExit(
        f"unexpected provider JSON contract: {sorted(data)}"
    )

if data["capability"] != "monitoring":
    raise SystemExit(
        f"unexpected capability: {data['capability']!r}"
    )

if data["provider"] != expected_provider:
    raise SystemExit(
        "Monitoring Core provider differs from Provider Resolver: "
        f"{data['provider']!r} != {expected_provider!r}"
    )

if not isinstance(data["source"], str) or not data["source"]:
    raise SystemExit("provider source is missing")

if data["status"] != "valid":
    raise SystemExit(
        f"unexpected provider status: {data['status']!r}"
    )
PY

pass "Monitoring Core delegates provider selection to Provider Resolver"
pass "provider JSON contract"

HLS_JSON="${TMP_DIR}/hls.json"
"${HLS}" monitoring provider --json >"${HLS_JSON}"

cmp -s "${DIRECT_JSON}" "${HLS_JSON}" ||
    fail "hls monitoring provider does not match Monitoring Core"

pass "hls monitoring provider routes to Monitoring Core"

HUMAN="${TMP_DIR}/human.txt"
"${MONITORING}" provider >"${HUMAN}"

grep -Fq "HomeLab Sentinel Monitoring Provider" "${HUMAN}" ||
    fail "human provider header missing"
grep -Fq "monitoring" "${HUMAN}" ||
    fail "human provider capability missing"
grep -Fq "${EXPECTED_PROVIDER}" "${HUMAN}" ||
    fail "human provider value missing"
grep -Fq "valid" "${HUMAN}" ||
    fail "human provider valid status missing"

pass "human Monitoring provider output"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Monitoring provider regression PASSED"
