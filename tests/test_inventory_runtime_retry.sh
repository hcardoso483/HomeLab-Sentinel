#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

RETRY_WRAPPER="${APP_ROOT}/scripts/with-inventory-retry.sh"
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

[[ -x "${RETRY_WRAPPER}" ]] ||
    fail "Inventory retry wrapper is not executable: ${RETRY_WRAPPER}"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

LOCK_FILE="${TMP_ROOT}/inventory-runtime.lock"
MARKER="${TMP_ROOT}/marker"
COUNT_FILE="${TMP_ROOT}/count"

echo "HomeLab Sentinel inventory runtime retry regression"

echo
echo "=== FREE LOCK EXECUTES ONCE ==="

: > "${COUNT_FILE}"

LOCK_FILE="${LOCK_FILE}" LOCK_TIMEOUT=1 LOCK_RETRY_DELAY=0 "${RETRY_WRAPPER}" bash -c 'echo run >> "$1"; touch "$2"' _ "${COUNT_FILE}" "${MARKER}"

[[ -e "${MARKER}" ]] || fail "Command did not execute with a free lock"
[[ "$(wc -l < "${COUNT_FILE}")" -eq 1 ]] || fail "Free-lock command did not execute exactly once"
pass "Free lock executes command exactly once"

rm -f "${MARKER}"
: > "${COUNT_FILE}"

echo
echo "=== FIRST CONTENTION RETRIES AFTER RELEASE ==="

LOCK_FILE="${LOCK_FILE}" LOCK_TIMEOUT=5 "${LOCK_WRAPPER}" bash -c 'sleep 1.5' &
holder_pid=$!
sleep 0.2

LOCK_FILE="${LOCK_FILE}" LOCK_TIMEOUT=1 LOCK_RETRY_DELAY=1 "${RETRY_WRAPPER}" bash -c 'echo run >> "$1"; touch "$2"' _ "${COUNT_FILE}" "${MARKER}"

wait "${holder_pid}"
[[ -e "${MARKER}" ]] || fail "Retry did not execute command after lock release"
[[ "$(wc -l < "${COUNT_FILE}")" -eq 1 ]] || fail "Retried command did not execute exactly once"
pass "Exit 75 contention is retried once and succeeds after release"

rm -f "${MARKER}"
: > "${COUNT_FILE}"

echo
echo "=== REPEATED CONTENTION STOPS AFTER SECOND ATTEMPT ==="

LOCK_FILE="${LOCK_FILE}" LOCK_TIMEOUT=5 "${LOCK_WRAPPER}" bash -c 'sleep 3' &
holder_pid=$!
sleep 0.2

set +e
LOCK_FILE="${LOCK_FILE}" LOCK_TIMEOUT=1 LOCK_RETRY_DELAY=0 "${RETRY_WRAPPER}" bash -c 'echo run >> "$1"; touch "$2"' _ "${COUNT_FILE}" "${MARKER}"
rc=$?
set -e

wait "${holder_pid}"
[[ "${rc}" -eq 75 ]] || fail "Expected final contention exit code 75, got ${rc}"
[[ ! -e "${MARKER}" ]] || fail "Command executed despite repeated lock contention"
[[ ! -s "${COUNT_FILE}" ]] || fail "Command executed during repeated contention"
pass "Repeated contention returns 75 without a third attempt"

echo
echo "=== COMMAND FAILURE IS NOT RETRIED ==="

: > "${COUNT_FILE}"

set +e
LOCK_FILE="${LOCK_FILE}" LOCK_TIMEOUT=1 LOCK_RETRY_DELAY=0 "${RETRY_WRAPPER}" bash -c 'echo run >> "$1"; exit 42' _ "${COUNT_FILE}"
rc=$?
set -e

[[ "${rc}" -eq 42 ]] || fail "Expected wrapped command exit code 42, got ${rc}"
[[ "$(wc -l < "${COUNT_FILE}")" -eq 1 ]] || fail "Failed command was retried unexpectedly"
pass "Executed command failure propagates without retry"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel inventory runtime retry regression PASSED"
