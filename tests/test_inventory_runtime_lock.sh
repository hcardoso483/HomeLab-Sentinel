#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

LOCK_WRAPPER="${APP_ROOT}/scripts/with-inventory-lock.sh"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

[[ -x "${LOCK_WRAPPER}" ]] ||
    fail "Inventory lock wrapper is not executable"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

LOCK_FILE="${TMP_ROOT}/inventory-runtime.lock"
MARKER="${TMP_ROOT}/marker"

echo "=== FIRST PROCESS HOLDS LOCK ==="

LOCK_FILE="${LOCK_FILE}" \
LOCK_TIMEOUT=5 \
"${LOCK_WRAPPER}" \
    bash -c 'sleep 3' &

holder_pid=$!

sleep 0.5

echo
echo "=== SECOND PROCESS MUST TIME OUT ==="

set +e
LOCK_FILE="${LOCK_FILE}" \
LOCK_TIMEOUT=1 \
"${LOCK_WRAPPER}" \
    touch "${MARKER}"
rc=$?
set -e

[[ "${rc}" -eq 75 ]] ||
    fail "Expected lock timeout exit code 75, got ${rc}"

[[ ! -e "${MARKER}" ]] ||
    fail "Contending command executed while lock was held"

pass "Concurrent inventory runtime execution is blocked"

wait "${holder_pid}"

echo
echo "=== LOCK RELEASE TEST ==="

LOCK_FILE="${LOCK_FILE}" \
LOCK_TIMEOUT=1 \
"${LOCK_WRAPPER}" \
    touch "${MARKER}"

[[ -e "${MARKER}" ]] ||
    fail "Command did not execute after lock release"

pass "Runtime lock is released after command completion"
pass "Subsequent inventory operation can proceed"

echo
echo "=== FAILURE PROPAGATION TEST ==="

set +e
LOCK_FILE="${LOCK_FILE}" \
LOCK_TIMEOUT=1 \
"${LOCK_WRAPPER}" \
    bash -c 'exit 42'
rc=$?
set -e

[[ "${rc}" -eq 42 ]] ||
    fail "Expected wrapped command exit code 42, got ${rc}"

pass "Wrapped command failures propagate correctly"
