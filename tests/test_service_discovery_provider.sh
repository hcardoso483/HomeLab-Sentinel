#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RESOLVER="${APP_ROOT}/core/resolver/resolver.sh"

pass() {
    echo "[PASS] $*"
}

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

echo
echo "HomeLab Sentinel Service Discovery provider regression test"
echo

[[ -x "${RESOLVER}" ]] ||
    fail "Provider Resolver missing or not executable: ${RESOLVER}"

DISCOVERY_PROVIDER="$("${RESOLVER}" provider-id discovery)" ||
    fail "existing discovery capability no longer resolves"

[[ "${DISCOVERY_PROVIDER}" == "nmap" ]] ||
    fail "existing discovery capability should resolve to nmap"

pass "existing discovery capability remains resolved to nmap"

SERVICE_PROVIDER="$("${RESOLVER}" provider-id service-discovery)" ||
    fail "service-discovery capability does not resolve"

[[ "${SERVICE_PROVIDER}" == "nmap" ]] ||
    fail "service-discovery capability should resolve to nmap"

pass "service-discovery capability resolves to nmap"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery provider regression PASSED"
