#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

STORE="${APP_ROOT}/core/inventory/store.py"
CORRELATE="${APP_ROOT}/core/inventory/correlate.py"

TMP_DIR="$(mktemp -d)"
DATABASE="${TMP_DIR}/inventory.db"

trap 'rm -rf "${TMP_DIR}"' EXIT

pass() {
    echo "[PASS] $*"
}

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

run_capture() {
    local name="$1"
    shift

    local output
    local result

    echo
    echo "=== ${name} ==="

    set +e
    output="$("$@" 2>&1)"
    result=$?
    set -e

    echo "${output}"

    if [[ "${result}" -ne 0 ]]; then
        fail "${name}: exit=${result}"
    fi

    CASE_OUTPUT="${output}"
}

require_contains() {
    local expected="$1"
    local description="$2"

    if grep -Fq "${expected}" <<< "${CASE_OUTPUT}"; then
        pass "${description}"
    else
        fail "${description}: missing ${expected}"
    fi
}

sql_scalar() {
    python3 - "${DATABASE}" "$1" <<'PY'
import sqlite3
import sys

database = sys.argv[1]
query = sys.argv[2]

connection = sqlite3.connect(database)
try:
    row = connection.execute(query).fetchone()
finally:
    connection.close()

if row is None:
    raise SystemExit("query returned no row")

print(row[0])
PY
}

[[ -x "${STORE}" ]] ||
    fail "Observation store not executable: ${STORE}"

[[ -x "${CORRELATE}" ]] ||
    fail "Correlation engine not executable: ${CORRELATE}"

OBSERVATION_ONE='{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-23T18:10:00Z","ip_addresses":["192.0.2.10"],"mac_address":"00:11:22:33:44:55","hostname":"test-host-a"}'

OBSERVATION_TWO='{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-23T18:11:00Z","ip_addresses":["192.0.2.11"],"mac_address":"00:11:22:33:44:55","hostname":"test-host-a-renamed"}'

OBSERVATION_NO_MAC='{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-23T18:12:00Z","ip_addresses":["192.0.2.20"],"mac_address":null,"hostname":"test-host-no-mac"}'

echo "HomeLab Sentinel Discovery pipeline regression"

echo
echo "=== TEMPORARY DATABASE ==="
echo "${DATABASE}"
[[ "${DATABASE}" == "${TMP_DIR}/inventory.db" ]] ||
    fail "temporary database path contract violated"
pass "isolated temporary database selected"

echo
echo "=== FIRST OBSERVATION ==="

set +e
CASE_OUTPUT="$(
    printf '%s\n' "${OBSERVATION_ONE}" |
        "${STORE}" --database "${DATABASE}" 2>&1
)"
result=$?
set -e

echo "${CASE_OUTPUT}"

[[ "${result}" -eq 0 ]] ||
    fail "first observation store exit=${result}"

require_contains \
    "Stored: 1, duplicates: 0" \
    "first observation stored"

run_capture \
    "FIRST CORRELATION" \
    "${CORRELATE}" --database "${DATABASE}"

require_contains \
    "Processed: 1, created: 1, resolved: 0, unresolved: 0" \
    "first MAC observation creates one entity"

OBSERVATIONS="$(sql_scalar 'SELECT COUNT(*) FROM observations')"
ENTITIES="$(sql_scalar 'SELECT COUNT(*) FROM entities')"
RESOLVED="$(sql_scalar "SELECT COUNT(*) FROM correlation_state WHERE status = 'resolved'")"
UNRESOLVED="$(sql_scalar "SELECT COUNT(*) FROM correlation_state WHERE status = 'unresolved'")"

[[ "${OBSERVATIONS}" -eq 1 ]] ||
    fail "expected 1 observation, got ${OBSERVATIONS}"

[[ "${ENTITIES}" -eq 1 ]] ||
    fail "expected 1 entity, got ${ENTITIES}"

[[ "${RESOLVED}" -eq 1 ]] ||
    fail "expected 1 resolved observation, got ${RESOLVED}"

[[ "${UNRESOLVED}" -eq 0 ]] ||
    fail "expected 0 unresolved observations, got ${UNRESOLVED}"

pass "first-pass database state correct"

echo
echo "=== SECOND OBSERVATION SAME MAC ==="

set +e
CASE_OUTPUT="$(
    printf '%s\n' "${OBSERVATION_TWO}" |
        "${STORE}" --database "${DATABASE}" 2>&1
)"
result=$?
set -e

echo "${CASE_OUTPUT}"

[[ "${result}" -eq 0 ]] ||
    fail "second observation store exit=${result}"

require_contains \
    "Stored: 1, duplicates: 0" \
    "second observation stored"

run_capture \
    "SECOND CORRELATION" \
    "${CORRELATE}" --database "${DATABASE}"

require_contains \
    "Processed: 1, created: 0, resolved: 1, unresolved: 0" \
    "same MAC resolves to existing entity"

OBSERVATIONS="$(sql_scalar 'SELECT COUNT(*) FROM observations')"
ENTITIES="$(sql_scalar 'SELECT COUNT(*) FROM entities')"
RESOLVED="$(sql_scalar "SELECT COUNT(*) FROM correlation_state WHERE status = 'resolved'")"

[[ "${OBSERVATIONS}" -eq 2 ]] ||
    fail "expected 2 observations, got ${OBSERVATIONS}"

[[ "${ENTITIES}" -eq 1 ]] ||
    fail "same MAC created unexpected second entity"

[[ "${RESOLVED}" -eq 2 ]] ||
    fail "expected 2 resolved observations, got ${RESOLVED}"

pass "historical MAC identity remains stable"

echo
echo "=== OBSERVATION WITHOUT MAC ==="

set +e
CASE_OUTPUT="$(
    printf '%s\n' "${OBSERVATION_NO_MAC}" |
        "${STORE}" --database "${DATABASE}" 2>&1
)"
result=$?
set -e

echo "${CASE_OUTPUT}"

[[ "${result}" -eq 0 ]] ||
    fail "no-MAC observation store exit=${result}"

run_capture \
    "NO-MAC CORRELATION" \
    "${CORRELATE}" --database "${DATABASE}"

require_contains \
    "Processed: 1, created: 0, resolved: 0, unresolved: 1" \
    "observation without strong identity remains unresolved"

UNRESOLVED="$(sql_scalar "SELECT COUNT(*) FROM correlation_state WHERE status = 'unresolved'")"

[[ "${UNRESOLVED}" -eq 1 ]] ||
    fail "expected 1 unresolved observation, got ${UNRESOLVED}"

pass "weak identity evidence does not invent an entity"

echo
echo "=== DUPLICATE INGESTION ==="

set +e
CASE_OUTPUT="$(
    printf '%s\n' "${OBSERVATION_ONE}" |
        "${STORE}" --database "${DATABASE}" 2>&1
)"
result=$?
set -e

echo "${CASE_OUTPUT}"

[[ "${result}" -eq 0 ]] ||
    fail "duplicate observation store exit=${result}"

require_contains \
    "Stored: 0, duplicates: 1" \
    "duplicate observation rejected from storage"

OBSERVATIONS="$(sql_scalar 'SELECT COUNT(*) FROM observations')"

[[ "${OBSERVATIONS}" -eq 3 ]] ||
    fail "duplicate ingestion changed observation count"

pass "duplicate ingestion is idempotent"

run_capture \
    "FINAL CORRELATION IDEMPOTENCE" \
    "${CORRELATE}" --database "${DATABASE}"

require_contains \
    "Processed: 0, created: 0, resolved: 0, unresolved: 0" \
    "correlation has no pending work after completed pass"

OBSERVATIONS="$(sql_scalar 'SELECT COUNT(*) FROM observations')"
ENTITIES="$(sql_scalar 'SELECT COUNT(*) FROM entities')"
RESOLVED="$(sql_scalar "SELECT COUNT(*) FROM correlation_state WHERE status = 'resolved'")"
UNRESOLVED="$(sql_scalar "SELECT COUNT(*) FROM correlation_state WHERE status = 'unresolved'")"
PENDING="$(sql_scalar "SELECT COUNT(*) FROM correlation_state WHERE status = 'pending'")"
SCHEMA="$(sql_scalar 'PRAGMA user_version')"

echo
echo "=== FINAL DATABASE CONTRACT ==="
echo "Schema       ${SCHEMA}"
echo "Observations ${OBSERVATIONS}"
echo "Entities     ${ENTITIES}"
echo "Resolved     ${RESOLVED}"
echo "Unresolved   ${UNRESOLVED}"
echo "Pending      ${PENDING}"

[[ "${SCHEMA}" -ge 2 ]] ||
    fail "inventory schema does not support correlation"

[[ "${OBSERVATIONS}" -eq 3 ]] ||
    fail "expected final observation count 3"

[[ "${ENTITIES}" -eq 1 ]] ||
    fail "expected final entity count 1"

[[ "${RESOLVED}" -eq 2 ]] ||
    fail "expected final resolved count 2"

[[ "${UNRESOLVED}" -eq 1 ]] ||
    fail "expected final unresolved count 1"

[[ "${PENDING}" -eq 0 ]] ||
    fail "expected no pending correlation work"

pass "final database contract correct"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Discovery pipeline regression PASSED"

echo
echo "=== MULTI-PASS EVIDENCE PERSISTENCE ==="

MULTI_PASS_OBSERVATION='{"schema_version":"1.0","provider":"test-multipass","discovery_method":"host-discovery","discovered_at":"2026-08-26T08:30:00Z","ip_addresses":["192.0.2.30"],"mac_address":"00:11:22:33:44:66","hostname":"multi-pass-storage-test","passes_observed":2,"passes_total":3,"observed_passes":[1,3]}'

set +e
CASE_OUTPUT="$(
    printf '%s\n' "${MULTI_PASS_OBSERVATION}" |
        "${STORE}" --database "${DATABASE}" 2>&1
)"
result=$?
set -e

echo "${CASE_OUTPUT}"

[[ "${result}" -eq 0 ]] ||
    fail "Multi-Pass observation store exit=${result}"

python3 - "${DATABASE}" <<'PY'
import json
import sqlite3
import sys

database = sys.argv[1]

connection = sqlite3.connect(database)

try:
    row = connection.execute("""
        SELECT payload_json
        FROM observations
        WHERE provider = 'test-multipass'
        ORDER BY received_at DESC
        LIMIT 1
    """).fetchone()
finally:
    connection.close()

if row is None:
    raise SystemExit(
        "Multi-Pass observation was not stored"
    )

record = json.loads(row[0])

expected = {
    "passes_observed": 2,
    "passes_total": 3,
    "observed_passes": [1, 3],
}

for key, value in expected.items():
    if record.get(key) != value:
        raise SystemExit(
            f"{key}: expected {value!r}, "
            f"got {record.get(key)!r}"
        )

print("[PASS] Multi-Pass evidence survived payload storage")
PY

echo
echo "=== MULTI-PASS STORAGE RESULT ==="
echo "HomeLab Sentinel Multi-Pass storage persistence PASSED"
