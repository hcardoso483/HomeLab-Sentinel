#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HELPER="${APP_ROOT}/scripts/verify-cli-command.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo "HomeLab Sentinel verification CLI retry regression"

[[ -x "${HELPER}" ]] ||
    fail "Verification CLI helper not executable: ${HELPER}"

echo
echo "=== TRANSIENT TIMEOUT RECOVERY ==="

COUNTER="${TMP_DIR}/counter"
printf '0\n' > "${COUNTER}"

TRANSIENT="${TMP_DIR}/transient.sh"

cat > "${TRANSIENT}" <<'COMMAND'
#!/usr/bin/env bash
set -Eeuo pipefail

count="$(cat "${TEST_COUNTER}")"
count=$((count + 1))
printf '%s\n' "${count}" > "${TEST_COUNTER}"

if (( count < 3 )); then
    exit 124
fi

echo "READY"
COMMAND

chmod +x "${TRANSIENT}"

OUTPUT="$(
    TEST_COUNTER="${COUNTER}" \
    "${HELPER}" \
        --timeout 1 \
        --attempts 3 \
        --interval 0 \
        -- \
        "${TRANSIENT}"
)"

[[ "${OUTPUT}" == *"READY"* ]] ||
    fail "transient timeout did not recover"

[[ "$(cat "${COUNTER}")" == "3" ]] ||
    fail "transient command did not execute exactly three times"

pass "transient timeout recovered within retry budget"

echo
echo "=== PERSISTENT TIMEOUT ==="

COUNTER="${TMP_DIR}/persistent-counter"
printf '0\n' > "${COUNTER}"

PERSISTENT="${TMP_DIR}/persistent.sh"

cat > "${PERSISTENT}" <<'COMMAND'
#!/usr/bin/env bash
set -Eeuo pipefail

count="$(cat "${TEST_COUNTER}")"
count=$((count + 1))
printf '%s\n' "${count}" > "${TEST_COUNTER}"

exit 124
COMMAND

chmod +x "${PERSISTENT}"

set +e
TEST_COUNTER="${COUNTER}" \
"${HELPER}" \
    --timeout 1 \
    --attempts 3 \
    --interval 0 \
    -- \
    "${PERSISTENT}" \
    >/dev/null 2>&1
RC=$?
set -e

[[ "${RC}" -eq 124 ]] ||
    fail "persistent timeout returned ${RC}, expected 124"

[[ "$(cat "${COUNTER}")" == "3" ]] ||
    fail "persistent timeout did not exhaust exactly three attempts"

pass "persistent timeout exhausts retry budget"

echo
echo "=== NON-TIMEOUT FAILURE ==="

COUNTER="${TMP_DIR}/failure-counter"
printf '0\n' > "${COUNTER}"

FAILURE="${TMP_DIR}/failure.sh"

cat > "${FAILURE}" <<'COMMAND'
#!/usr/bin/env bash
set -Eeuo pipefail

count="$(cat "${TEST_COUNTER}")"
count=$((count + 1))
printf '%s\n' "${count}" > "${TEST_COUNTER}"

exit 42
COMMAND

chmod +x "${FAILURE}"

set +e
TEST_COUNTER="${COUNTER}" \
"${HELPER}" \
    --timeout 1 \
    --attempts 3 \
    --interval 0 \
    -- \
    "${FAILURE}" \
    >/dev/null 2>&1
RC=$?
set -e

[[ "${RC}" -eq 42 ]] ||
    fail "ordinary failure returned ${RC}, expected 42"

[[ "$(cat "${COUNTER}")" == "1" ]] ||
    fail "ordinary failure was incorrectly retried"

pass "non-timeout failure is not retried"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel verification CLI retry regression PASSED"
