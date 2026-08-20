#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="${APP_ROOT:-/opt/homelab-sentinel/app}"
DATABASE="${DATABASE:-/srv/homelab-sentinel/sentinel/inventory.db}"
REGRESSION_TEST="${REGRESSION_TEST:-${APP_ROOT}/tests/test_core_api.sh}"
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

check_executable "${APP_ROOT}/api/server.py" "Core API server executable"
check_executable "${APP_ROOT}/core/inventory/inventory.py" "Living Inventory CLI executable"
check_executable "${REGRESSION_TEST}" "Core API regression test executable"

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
