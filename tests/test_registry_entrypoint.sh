#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
REGISTRY="${APP_ROOT}/registry/registry.sh"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

echo "HomeLab Sentinel Registry entrypoint regression test"
echo

EXPECTED="${APP_ROOT}/compose/monitoring/prometheus/scripts/observe.py"
ACTUAL="$("${REGISTRY}" entrypoint prometheus monitoring-observer)"

[[ "${ACTUAL}" == "${EXPECTED}" ]] ||
    fail "unexpected monitoring-observer entrypoint: ${ACTUAL}"

pass "Registry resolves provider-owned monitoring observer"

if "${REGISTRY}" entrypoint prometheus does-not-exist >/dev/null 2>&1; then
    fail "unknown entrypoint role unexpectedly resolved"
fi
pass "unknown entrypoint role rejected"

if "${REGISTRY}" entrypoint does-not-exist monitoring-observer >/dev/null 2>&1; then
    fail "unknown module unexpectedly resolved"
fi
pass "unknown module rejected"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Registry entrypoint regression PASSED"
