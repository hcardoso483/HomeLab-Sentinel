#!/usr/bin/env bash

set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="${APP_ROOT}/core/resolver/resolver.sh"
REGISTRY="${APP_ROOT}/registry/registry.sh"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo
echo "HomeLab Sentinel Service Discovery provider-entrypoint regression"
echo

[[ -x "${RESOLVER}" ]] || fail "provider resolver missing"
[[ -x "${REGISTRY}" ]] || fail "provider registry missing"

PROVIDER="$("${RESOLVER}" provider-id service-discovery)" \
    || fail "Service Discovery provider resolution failed"

[[ -n "${PROVIDER}" ]] \
    || fail "Service Discovery provider resolution returned no provider"

pass "Service Discovery provider resolves generically"

ENTRYPOINT="$("${REGISTRY}" entrypoint "${PROVIDER}" service-discovery)" \
    || fail "Service Discovery provider does not expose service-discovery entrypoint"

[[ -n "${ENTRYPOINT}" ]] \
    || fail "Service Discovery provider entrypoint is empty"

[[ -f "${ENTRYPOINT}" ]] \
    || fail "Service Discovery provider entrypoint does not exist: ${ENTRYPOINT}"

[[ -x "${ENTRYPOINT}" ]] \
    || fail "Service Discovery provider entrypoint is not executable: ${ENTRYPOINT}"

case "${ENTRYPOINT}" in
    *"/compose/discovery/nmap/scripts/discover-services.sh")
        ;;
    *)
        fail "unexpected Service Discovery provider entrypoint: ${ENTRYPOINT}"
        ;;
esac

pass "Service Discovery execution is exposed through provider metadata"
pass "Service Discovery provider entrypoint is executable"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery provider-entrypoint regression PASSED"
