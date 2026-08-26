#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

POLICY="${APP_ROOT}/core/discovery/observation_policy.py"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

pass() {
    echo "[PASS] $*"
}

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

echo "HomeLab Sentinel Discovery observation policy regression"
echo

[[ -x "${POLICY}" ]] ||
    fail "Observation policy helper not executable"

cat > "${TMP_DIR}/valid.yml" <<'YAML'
discovery:
  schedule:
    interval_minutes: 15
  observation:
    passes: 3
    interval_seconds: 2
YAML

PASSES="$(
    "${POLICY}" passes \
        --config "${TMP_DIR}/valid.yml"
)"

[[ "${PASSES}" == "3" ]] ||
    fail "expected passes=3, got ${PASSES}"

pass "three-pass policy accepted"

INTERVAL="$(
    "${POLICY}" interval \
        --config "${TMP_DIR}/valid.yml"
)"

[[ "${INTERVAL}" == "2" ]] ||
    fail "expected interval=2, got ${INTERVAL}"

pass "two-second pass interval accepted"

cat > "${TMP_DIR}/defaults.yml" <<'YAML'
discovery:
  schedule:
    interval_minutes: 15
YAML

PASSES="$(
    "${POLICY}" passes \
        --config "${TMP_DIR}/defaults.yml"
)"

INTERVAL="$(
    "${POLICY}" interval \
        --config "${TMP_DIR}/defaults.yml"
)"

[[ "${PASSES}" == "3" ]] ||
    fail "default pass policy changed"

[[ "${INTERVAL}" == "2" ]] ||
    fail "default interval policy changed"

pass "observation defaults remain deterministic"

cat > "${TMP_DIR}/bad-passes.yml" <<'YAML'
discovery:
  observation:
    passes: 0
    interval_seconds: 2
YAML

if "${POLICY}" passes \
    --config "${TMP_DIR}/bad-passes.yml" \
    >/dev/null 2>&1; then
    fail "invalid pass count accepted"
fi

pass "invalid pass count rejected"

cat > "${TMP_DIR}/bad-interval.yml" <<'YAML'
discovery:
  observation:
    passes: 3
    interval_seconds: -1
YAML

if "${POLICY}" interval \
    --config "${TMP_DIR}/bad-interval.yml" \
    >/dev/null 2>&1; then
    fail "invalid pass interval accepted"
fi

pass "invalid pass interval rejected"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Discovery observation policy regression PASSED"
