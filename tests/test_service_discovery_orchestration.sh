#!/usr/bin/env bash

set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCHESTRATOR="${APP_ROOT}/core/service_discovery/orchestrate.py"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo
echo "HomeLab Sentinel Service Discovery orchestration regression"
echo

[[ -f "${ORCHESTRATOR}" ]] \
    || fail "Service Discovery orchestrator missing: ${ORCHESTRATOR}"

[[ -x "${ORCHESTRATOR}" ]] \
    || fail "Service Discovery orchestrator is not executable"

grep -q '"provider-id"' "${ORCHESTRATOR}" \
    || fail "orchestrator does not use generic provider resolution"

grep -q '"service-discovery"' "${ORCHESTRATOR}" \
    || fail "orchestrator does not resolve the service-discovery capability"

grep -q 'ENTRYPOINT_ROLE = "service-discovery"' "${ORCHESTRATOR}" \
    || fail "orchestrator does not use the canonical service-discovery entrypoint role"

if grep -qi 'nmap' "${ORCHESTRATOR}"; then
    fail "Service Discovery orchestrator contains provider-specific Nmap knowledge"
fi

grep -q '"--entity-id"' "${ORCHESTRATOR}" \
    || fail "orchestrator does not pass canonical entity_id to provider"

grep -q '"--address"' "${ORCHESTRATOR}" \
    || fail "orchestrator does not pass canonical address to provider"

pass "Service Discovery capability is resolved generically"
pass "Service Discovery entrypoint role is provider-neutral"
pass "canonical entity_id is passed through provider boundary"
pass "canonical address is passed through provider boundary"
pass "Service Discovery Core contains no Nmap-specific execution knowledge"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery orchestration regression PASSED"
