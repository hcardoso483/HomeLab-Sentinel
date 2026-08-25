#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="${APP_ROOT:-/opt/homelab-sentinel/app}"
DATABASE="${DATABASE:-/srv/homelab-sentinel/sentinel/inventory.db}"
REGRESSION_TEST="${REGRESSION_TEST:-${APP_ROOT}/tests/test_core_api.sh}"
STATUS_TEST="${STATUS_TEST:-${APP_ROOT}/tests/test_status.sh}"
CORRELATION_TEST="${CORRELATION_TEST:-${APP_ROOT}/tests/test_correlation.sh}"
DISCOVERY_CONTRACT_TEST="${DISCOVERY_CONTRACT_TEST:-${APP_ROOT}/tests/test_discovery_contracts.sh}"
DISCOVERY_PIPELINE_TEST="${DISCOVERY_PIPELINE_TEST:-${APP_ROOT}/tests/test_discovery_pipeline.sh}"
DISCOVERY_RECONCILE_TEST="${DISCOVERY_RECONCILE_TEST:-${APP_ROOT}/tests/test_discovery_reconcile.sh}"
HLS_SOURCE="${HLS_SOURCE:-${APP_ROOT}/installer/hls}"
HLS_INSTALLED="${HLS_INSTALLED:-/usr/local/bin/hls}"
HLS_COMMAND_TIMEOUT="${HLS_COMMAND_TIMEOUT:-10}"
BOOT_READY_CHECK="${BOOT_READY_CHECK:-${APP_ROOT}/scripts/check-boot-ready.sh}"
TEST_API_PORT="${TEST_API_PORT:-18000}"
API_PROCESS_PATTERN="${API_PROCESS_PATTERN:-[a]pi/server.py.*--port ${TEST_API_PORT}}"

FAILURES=0
PROCESS_FILE=""

pass() {
    echo "[PASS] $*"
}

fail() {
    echo "[FAIL] $*" >&2
    FAILURES=$((FAILURES + 1))
}

section() {
    echo
    echo "=== $* ==="
}

cleanup() {
    if [[ -n "${PROCESS_FILE}" && -f "${PROCESS_FILE}" ]]; then
        rm -f "${PROCESS_FILE}"
    fi
}
trap cleanup EXIT

check_file() {
    local path="$1"
    local description="$2"

    if [[ -f "${path}" ]]; then
        pass "${description}"
    else
        fail "${description}: missing ${path}"
    fi
}

check_executable() {
    local path="$1"
    local description="$2"

    if [[ -x "${path}" ]]; then
        pass "${description}"
    else
        fail "${description}: not executable ${path}"
    fi
}

echo "HomeLab Sentinel post-boot verification"
echo "App root : ${APP_ROOT}"
echo "Database : ${DATABASE}"
echo

section "BOOT READINESS"

if [[ ! -x "${BOOT_READY_CHECK}" ]]; then
    echo "[FAIL] Boot readiness checker unavailable: ${BOOT_READY_CHECK}" >&2
    exit 1
fi

if "${BOOT_READY_CHECK}"; then
    pass "Current-boot platform readiness"
else
    echo "[FAIL] Post-boot verification refused before platform readiness" >&2
    exit 1
fi

section "APPLICATION TREE"

if [[ -d "${APP_ROOT}" ]]; then
    pass "Application root exists"
else
    fail "Application root missing: ${APP_ROOT}"
fi

check_file "${APP_ROOT}/api/server.py" "Core API server present"
check_file "${APP_ROOT}/core/inventory/inventory.py" "Living Inventory CLI present"
check_file "${APP_ROOT}/core/inventory/schema.sql" "Inventory schema present"
check_file "${REGRESSION_TEST}" "Core API regression test present"
check_file "${CORRELATION_TEST}" "Correlation regression test present"
check_file "${STATUS_TEST}" "Status regression test present"
check_file "${DISCOVERY_CONTRACT_TEST}" "Discovery contract regression test present"
check_file "${DISCOVERY_PIPELINE_TEST}" "Discovery pipeline regression test present"
check_file "${DISCOVERY_RECONCILE_TEST}" "Discovery reconciliation regression test present"
check_file "${APP_ROOT}/scripts/wait-core-api.sh" "Core API readiness helper present"

check_executable "${APP_ROOT}/api/server.py" "Core API server executable"
check_executable "${APP_ROOT}/core/inventory/inventory.py" "Living Inventory CLI executable"
check_executable "${REGRESSION_TEST}" "Core API regression test executable"
check_executable "${CORRELATION_TEST}" "Correlation regression test executable"
check_executable "${STATUS_TEST}" "Status regression test executable"
check_executable "${DISCOVERY_CONTRACT_TEST}" "Discovery contract regression test executable"
check_executable "${DISCOVERY_PIPELINE_TEST}" "Discovery pipeline regression test executable"
check_executable "${DISCOVERY_RECONCILE_TEST}" "Discovery reconciliation regression test executable"
check_executable "${APP_ROOT}/scripts/wait-core-api.sh" "Core API readiness helper executable"

section "HLS CLI"

check_file "${HLS_SOURCE}" "Canonical HLS source present"
check_executable "${HLS_SOURCE}" "Canonical HLS source executable"
check_file "${HLS_INSTALLED}" "Permanent HLS CLI installed"
check_executable "${HLS_INSTALLED}" "Permanent HLS CLI executable"

if [[ -f "${HLS_SOURCE}" && -f "${HLS_INSTALLED}" ]]; then
    if cmp -s "${HLS_SOURCE}" "${HLS_INSTALLED}"; then
        pass "Installed HLS CLI matches canonical source"
    else
        fail "Installed HLS CLI differs from canonical source"
    fi
else
    fail "Installed HLS CLI source comparison unavailable"
fi

if command -v timeout >/dev/null 2>&1; then
    pass "HLS command timeout protection available"

    HLS_OUTPUT=""

    if HLS_OUTPUT="$(timeout "${HLS_COMMAND_TIMEOUT}" "${HLS_INSTALLED}" help 2>&1)"; then
        if grep -Fq "HomeLab Sentinel CLI" <<< "${HLS_OUTPUT}"; then
            pass "hls help"
        else
            fail "hls help returned unexpected output"
        fi
    else
        HLS_RESULT=$?
        fail "hls help failed (exit ${HLS_RESULT})"
        [[ -n "${HLS_OUTPUT}" ]] && echo "${HLS_OUTPUT}" >&2
    fi

    HLS_OUTPUT=""
    if HLS_OUTPUT="$(
        timeout "${HLS_COMMAND_TIMEOUT}"             "${HLS_INSTALLED}"             status             --ignore-verification-result             2>&1
    )"; then
        if grep -Fq "HomeLab Sentinel Status" <<< "${HLS_OUTPUT}" &&
           grep -Fxq "  READY" <<< "${HLS_OUTPUT}"; then
            pass "hls status"
        else
            fail "hls status returned unexpected output"
        fi
    else
        HLS_RESULT=$?
        fail "hls status failed (exit ${HLS_RESULT})"
        [[ -n "${HLS_OUTPUT}" ]] && echo "${HLS_OUTPUT}" >&2
    fi

    HLS_OUTPUT=""
    if HLS_OUTPUT="$(timeout "${HLS_COMMAND_TIMEOUT}" "${HLS_INSTALLED}" inventory list 2>&1)"; then
        pass "hls inventory"
    else
        HLS_RESULT=$?
        fail "hls inventory failed (exit ${HLS_RESULT})"
        [[ -n "${HLS_OUTPUT}" ]] && echo "${HLS_OUTPUT}" >&2
    fi

    HLS_OUTPUT=""
    if HLS_OUTPUT="$(timeout "${HLS_COMMAND_TIMEOUT}" "${HLS_INSTALLED}" verify --route-check 2>&1)"; then
        if grep -Fq "[PASS] hls verify route ->" <<< "${HLS_OUTPUT}"; then
            pass "hls verify route"
        else
            fail "hls verify route returned unexpected output"
        fi
    else
        HLS_RESULT=$?
        fail "hls verify route failed (exit ${HLS_RESULT})"
        [[ -n "${HLS_OUTPUT}" ]] && echo "${HLS_OUTPUT}" >&2
    fi

    HLS_OUTPUT=""
    if HLS_OUTPUT="$(timeout "${HLS_COMMAND_TIMEOUT}" "${HLS_INSTALLED}" install --route-check 2>&1)"; then
        if grep -Fq "[PASS] hls install route ->" <<< "${HLS_OUTPUT}"; then
            pass "hls install route"
        else
            fail "hls install route returned unexpected output"
        fi
    else
        HLS_RESULT=$?
        fail "hls install route failed (exit ${HLS_RESULT})"
        [[ -n "${HLS_OUTPUT}" ]] && echo "${HLS_OUTPUT}" >&2
    fi
else
    fail "HLS command timeout protection unavailable"
fi

section "INVENTORY DATABASE"

if [[ ! -f "${DATABASE}" ]]; then
    fail "Inventory database missing: ${DATABASE}"
else
    pass "Inventory database exists"

    DB_RESULT=""
    if DB_RESULT="$(
        python3 - "${DATABASE}" <<'PY'
import sqlite3
import sys

database = sys.argv[1]

try:
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        observations = connection.execute("SELECT COUNT(*) FROM observations").fetchone()[0]
        entities = connection.execute("SELECT COUNT(*) FROM entities").fetchone()[0]
        resolved = connection.execute(
            "SELECT COUNT(*) FROM correlation_state WHERE status='resolved'"
        ).fetchone()[0]
        unresolved = connection.execute(
            "SELECT COUNT(*) FROM correlation_state WHERE status='unresolved'"
        ).fetchone()[0]
        pending = connection.execute(
            "SELECT COUNT(*) FROM correlation_state WHERE status='pending'"
        ).fetchone()[0]
    finally:
        connection.close()
except (sqlite3.Error, OSError) as exc:
    print(f"ERROR={exc}")
    raise SystemExit(1)

print(f"SCHEMA={version}")
print(f"INTEGRITY={integrity}")
print(f"OBSERVATIONS={observations}")
print(f"ENTITIES={entities}")
print(f"RESOLVED={resolved}")
print(f"UNRESOLVED={unresolved}")
print(f"PENDING={pending}")
PY
    )"; then
        SCHEMA_VERSION=""
        INTEGRITY_RESULT=""
        OBSERVATIONS=""
        ENTITIES=""
        RESOLVED=""
        UNRESOLVED=""
        PENDING=""

        while IFS='=' read -r key value; do
            case "${key}" in
                SCHEMA) SCHEMA_VERSION="${value}" ;;
                INTEGRITY) INTEGRITY_RESULT="${value}" ;;
                OBSERVATIONS) OBSERVATIONS="${value}" ;;
                ENTITIES) ENTITIES="${value}" ;;
                RESOLVED) RESOLVED="${value}" ;;
                UNRESOLVED) UNRESOLVED="${value}" ;;
                PENDING) PENDING="${value}" ;;
            esac
        done <<< "${DB_RESULT}"

        if [[ "${SCHEMA_VERSION}" =~ ^[0-9]+$ ]] && (( SCHEMA_VERSION >= 2 )); then
            pass "Inventory schema supported (version ${SCHEMA_VERSION})"
        else
            fail "Inventory schema unsupported (version ${SCHEMA_VERSION:-unknown})"
        fi

        if [[ "${INTEGRITY_RESULT}" == "ok" ]]; then
            pass "SQLite integrity_check = ok"
        else
            fail "SQLite integrity_check failed: ${INTEGRITY_RESULT:-unknown}"
        fi

        echo "Inventory counts: observations=${OBSERVATIONS:-?} entities=${ENTITIES:-?} resolved=${RESOLVED:-?} unresolved=${UNRESOLVED:-?} pending=${PENDING:-?}"
    else
        fail "Unable to inspect inventory database in read-only mode"
        [[ -n "${DB_RESULT}" ]] && echo "${DB_RESULT}" >&2
    fi
fi

section "DISCOVERY CONTRACT REGRESSION"

if [[ -x "${DISCOVERY_CONTRACT_TEST}" ]]; then
    if "${DISCOVERY_CONTRACT_TEST}"; then
        pass "Discovery contract regression suite"
    else
        fail "Discovery contract regression suite"
    fi
else
    fail "Discovery contract regression test cannot run: ${DISCOVERY_CONTRACT_TEST}"
fi

section "DISCOVERY PIPELINE REGRESSION"

if [[ -x "${DISCOVERY_PIPELINE_TEST}" ]]; then
    if "${DISCOVERY_PIPELINE_TEST}"; then
        pass "Discovery pipeline regression suite"
    else
        fail "Discovery pipeline regression suite"
    fi
else
    fail "Discovery pipeline regression test cannot run: ${DISCOVERY_PIPELINE_TEST}"
fi

section "DISCOVERY RECONCILIATION REGRESSION"

if [[ -x "${DISCOVERY_RECONCILE_TEST}" ]]; then
    if "${DISCOVERY_RECONCILE_TEST}"; then
        pass "Discovery reconciliation regression suite"
    else
        fail "Discovery reconciliation regression suite"
    fi
else
    fail "Discovery reconciliation regression test cannot run: ${DISCOVERY_RECONCILE_TEST}"
fi

section "CORRELATION REGRESSION"

if [[ -x "${CORRELATION_TEST}" ]]; then
    if "${CORRELATION_TEST}"; then
        pass "Correlation regression suite"
    else
        fail "Correlation regression suite"
    fi
else
    fail "Correlation regression test cannot run: ${CORRELATION_TEST}"
fi

section "STATUS REGRESSION"

if [[ -x "${STATUS_TEST}" ]]; then
    if "${STATUS_TEST}"; then
        pass "Status regression suite"
    else
        fail "Status regression suite"
    fi
else
    fail "Status regression test cannot run: ${STATUS_TEST}"
fi

section "CORE API REGRESSION"

if [[ -x "${REGRESSION_TEST}" ]]; then
    if API_PORT="${TEST_API_PORT}" "${REGRESSION_TEST}"; then
        pass "Core API regression suite"
    else
        fail "Core API regression suite"
    fi
else
    fail "Regression test cannot run: ${REGRESSION_TEST}"
fi

section "PROCESS CLEANUP"

PROCESS_FILE="$(mktemp)"
if pgrep -af "${API_PROCESS_PATTERN}" >"${PROCESS_FILE}" 2>/dev/null; then
    echo "Unexpected Core API process(es) still running:" >&2
    cat "${PROCESS_FILE}" >&2
    fail "No temporary Core API process remains"
else
    pass "No temporary Core API process remains"
fi

section "RESULT"

if (( FAILURES == 0 )); then
    echo "HomeLab Sentinel verification PASSED"
    exit 0
fi

echo "HomeLab Sentinel verification FAILED (${FAILURES} check(s))" >&2
exit 1
