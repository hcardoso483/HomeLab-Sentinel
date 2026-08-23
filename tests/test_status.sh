#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

STATUS_ENGINE="${APP_ROOT}/core/status/status.py"

pass() {
    echo "[PASS] $*"
}

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

require_contains() {
    local output="$1"
    local expected="$2"
    local description="$3"

    if grep -Fq "${expected}" <<< "${output}"; then
        pass "${description}"
    else
        echo "--- output ---" >&2
        echo "${output}" >&2
        echo "--------------" >&2
        fail "${description}: missing ${expected}"
    fi
}

run_case() {
    local name="$1"
    local expected_exit="$2"
    shift 2

    local output
    local result

    echo
    echo "=== ${name} ==="

    set +e
    output="$("${STATUS_ENGINE}" "$@" 2>&1)"
    result=$?
    set -e

    echo "${output}"

    if [[ "${result}" -eq "${expected_exit}" ]]; then
        pass "${name} exit=${result}"
    else
        fail \
            "${name}: expected exit ${expected_exit}, got ${result}"
    fi

    CASE_OUTPUT="${output}"
}

[[ -x "${STATUS_ENGINE}" ]] ||
    fail "Status engine not executable: ${STATUS_ENGINE}"

echo "HomeLab Sentinel Status regression test"

run_case "HEALTHY LIVE STATUS" 0

require_contains \
    "${CASE_OUTPUT}" \
    "HomeLab Sentinel Status" \
    "status header"

require_contains \
    "${CASE_OUTPUT}" \
    "Schedule policy      COMPLIANT" \
    "healthy Discovery schedule policy"

require_contains \
    "${CASE_OUTPUT}" \
    "Runtime              HEALTHY" \
    "healthy Discovery runtime"

require_contains \
    "${CASE_OUTPUT}" \
    "Freshness            FRESH" \
    "healthy Discovery freshness"

require_contains \
    "${CASE_OUTPUT}" \
    "  READY" \
    "healthy Overall state"

run_case \
    "DISCOVERY FAILED" \
    1 \
    --simulate discovery-failed

require_contains \
    "${CASE_OUTPUT}" \
    "Health               HEALTHY" \
    "Core API remains healthy during Discovery failure"

require_contains \
    "${CASE_OUTPUT}" \
    "Runtime              DEGRADED" \
    "Discovery failure is degraded"

require_contains \
    "${CASE_OUTPUT}" \
    "Freshness            STALE" \
    "failed Discovery data is stale"

require_contains \
    "${CASE_OUTPUT}" \
    "Recovery             FAILED" \
    "failed Discovery recovery reported"

require_contains \
    "${CASE_OUTPUT}" \
    "Database             READY" \
    "Inventory remains ready during Discovery failure"

require_contains \
    "${CASE_OUTPUT}" \
    "  DEGRADED" \
    "Overall degraded by Discovery failure"

run_case \
    "DISCOVERY RUNNING" \
    0 \
    --simulate discovery-running

require_contains \
    "${CASE_OUTPUT}" \
    "Runtime              RUNNING" \
    "Discovery running state reported"

require_contains \
    "${CASE_OUTPUT}" \
    "Last run             RUNNING" \
    "Discovery running last-run state reported"

require_contains \
    "${CASE_OUTPUT}" \
    "Freshness            IN PROGRESS" \
    "Discovery running freshness reported"

require_contains \
    "${CASE_OUTPUT}" \
    "Recovery             NOT REQUIRED" \
    "Discovery running does not imply recovery"

require_contains \
    "${CASE_OUTPUT}" \
    "Health               HEALTHY" \
    "Core API remains healthy while Discovery runs"

require_contains \
    "${CASE_OUTPUT}" \
    "Database             READY" \
    "Inventory remains ready while Discovery runs"

require_contains \
    "${CASE_OUTPUT}" \
    "  READY" \
    "Overall remains ready while Discovery runs"

run_case \
    "DISCOVERY SCHEDULE DRIFT" \
    1 \
    --simulate discovery-schedule-drift

require_contains \
    "${CASE_OUTPUT}" \
    "Scheduler            ACTIVE" \
    "scheduler remains active during policy drift"

require_contains \
    "${CASE_OUTPUT}" \
    "Schedule             ENABLED" \
    "schedule remains enabled during policy drift"

require_contains \
    "${CASE_OUTPUT}" \
    "Schedule policy      DRIFT" \
    "Discovery schedule policy drift detected"

require_contains \
    "${CASE_OUTPUT}" \
    "Runtime              HEALTHY" \
    "historical Discovery runtime remains healthy during policy drift"

require_contains \
    "${CASE_OUTPUT}" \
    "  DEGRADED" \
    "Overall degraded by Discovery schedule policy drift"

run_case \
    "DISCOVERY RECOVERING" \
    1 \
    --simulate discovery-recovering

require_contains \
    "${CASE_OUTPUT}" \
    "Runtime              RECOVERING" \
    "Discovery recovery in progress"

require_contains \
    "${CASE_OUTPUT}" \
    "Recovery             IN PROGRESS" \
    "recovery progress reported"

require_contains \
    "${CASE_OUTPUT}" \
    "Health               HEALTHY" \
    "Core API remains healthy during recovery"

require_contains \
    "${CASE_OUTPUT}" \
    "  DEGRADED" \
    "Overall degraded while Discovery recovers"

run_case \
    "DISCOVERY SCHEDULER DISABLED" \
    1 \
    --simulate discovery-scheduler-disabled

require_contains \
    "${CASE_OUTPUT}" \
    "Scheduler            INACTIVE" \
    "inactive scheduler detected"

require_contains \
    "${CASE_OUTPUT}" \
    "Schedule             DISABLED" \
    "disabled schedule detected"

require_contains \
    "${CASE_OUTPUT}" \
    "Schedule policy      COMPLIANT" \
    "disabled scheduler remains distinct from policy drift"

require_contains \
    "${CASE_OUTPUT}" \
    "Runtime              HEALTHY" \
    "last Discovery runtime remains historically healthy"

require_contains \
    "${CASE_OUTPUT}" \
    "  DEGRADED" \
    "Overall degraded by scheduler failure"

run_case \
    "DISCOVERY STATE UNREADABLE" \
    1 \
    --simulate discovery-state-unreadable

require_contains \
    "${CASE_OUTPUT}" \
    "Runtime              UNKNOWN" \
    "unreadable Discovery runtime detected"

require_contains \
    "${CASE_OUTPUT}" \
    "Freshness            UNKNOWN" \
    "unreadable Discovery freshness detected"

require_contains \
    "${CASE_OUTPUT}" \
    "Health               HEALTHY" \
    "Core API remains healthy with unreadable Discovery state"

require_contains \
    "${CASE_OUTPUT}" \
    "Database             READY" \
    "Inventory remains ready with unreadable Discovery state"

require_contains \
    "${CASE_OUTPUT}" \
    "  DEGRADED" \
    "Overall degraded by unreadable Discovery state"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Status regression PASSED"
