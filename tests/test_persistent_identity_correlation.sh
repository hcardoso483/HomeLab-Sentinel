#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

STORE="${APP_ROOT}/core/inventory/store.py"
CORRELATE="${APP_ROOT}/core/inventory/correlate.py"
IDENTITY="${APP_ROOT}/core/identity/identity.py"

TMP_DIR="$(mktemp -d)"
INVENTORY_A="${TMP_DIR}/inventory-a.db"
INVENTORY_B="${TMP_DIR}/inventory-b.db"
IDENTITY_DB="${TMP_DIR}/identity.db"

trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

for executable in \
    "${STORE}" \
    "${CORRELATE}" \
    "${IDENTITY}"
do
    [[ -x "${executable}" ]] ||
        fail "Required executable missing: ${executable}"
done

echo "HomeLab Sentinel Persistent Identity correlation regression"
echo

echo "=== TEMPORARY STORES ==="
echo "Inventory A : ${INVENTORY_A}"
echo "Inventory B : ${INVENTORY_B}"
echo "Identity    : ${IDENTITY_DB}"

"${IDENTITY}" \
    --database "${IDENTITY_DB}" \
    init >/dev/null

[[ -f "${IDENTITY_DB}" ]] ||
    fail "Persistent Identity database was not created"

pass "isolated Persistent Identity database initialized"

echo
echo "=== INVENTORY A GLOBAL MAC ==="

OBSERVATION_A='{"schema_version":"1.0","provider":"identity-correlation-test","discovery_method":"host-discovery","discovered_at":"2026-08-27T06:45:00Z","ip_addresses":["192.0.2.10"],"mac_address":"00:11:22:33:44:55","hostname":"identity-test"}'

printf '%s\n' "${OBSERVATION_A}" |
    "${STORE}" --database "${INVENTORY_A}" >/dev/null

"${CORRELATE}" \
        --database "${INVENTORY_A}" \
        --identity-database "${IDENTITY_DB}" >/dev/null

ENTITY_A="$(
    python3 - "${INVENTORY_A}" <<'PYSQL'
import sqlite3
import sys

con = sqlite3.connect(sys.argv[1])

try:
    row = con.execute("""
        SELECT entity_id
        FROM entities
        ORDER BY created_at
        LIMIT 1
    """).fetchone()
finally:
    con.close()

if row is None:
    raise SystemExit("Inventory A canonical entity missing")

print(row[0])
PYSQL
)"

[[ -n "${ENTITY_A}" ]] ||
    fail "Inventory A canonical entity unavailable"

pass "Inventory A created canonical entity ${ENTITY_A}"

set +e
IDENTITY_ENTITY="$(
    "${IDENTITY}" \
        --database "${IDENTITY_DB}" \
        lookup \
        --mac "00:11:22:33:44:55" \
        2>/dev/null
)"
LOOKUP_RC=$?
set -e

[[ "${LOOKUP_RC}" -eq 0 ]] ||
    fail "global MAC was not registered in Persistent Identity"

[[ "${IDENTITY_ENTITY}" == "${ENTITY_A}" ]] ||
    fail "Persistent Identity entity differs from Inventory A"

pass "global MAC registered against Inventory A canonical entity"

echo
echo "=== FRESH INVENTORY B IDENTITY RECOVERY ==="

OBSERVATION_B='{"schema_version":"1.0","provider":"identity-correlation-test","discovery_method":"host-discovery","discovered_at":"2026-08-27T07:00:00Z","ip_addresses":["192.0.2.99"],"mac_address":"00:11:22:33:44:55","hostname":"identity-test-renumbered"}'

printf '%s\n' "${OBSERVATION_B}" |
    "${STORE}" --database "${INVENTORY_B}" >/dev/null

"${CORRELATE}" \
        --database "${INVENTORY_B}" \
        --identity-database "${IDENTITY_DB}" >/dev/null

ENTITY_B="$(
    python3 - "${INVENTORY_B}" <<'PYSQL'
import sqlite3
import sys

con = sqlite3.connect(sys.argv[1])

try:
    row = con.execute("""
        SELECT entity_id
        FROM entities
        ORDER BY created_at
        LIMIT 1
    """).fetchone()
finally:
    con.close()

if row is None:
    raise SystemExit("Inventory B canonical entity missing")

print(row[0])
PYSQL
)"

[[ -n "${ENTITY_B}" ]] ||
    fail "Inventory B canonical entity unavailable"

echo "Inventory A entity : ${ENTITY_A}"
echo "Inventory B entity : ${ENTITY_B}"

[[ "${ENTITY_B}" == "${ENTITY_A}" ]] ||
    fail "fresh Inventory did not recover canonical Persistent Identity"

pass "fresh Inventory recovered the same canonical entity"

echo
echo "=== LOCAL MAC MUST NOT RESURRECT IDENTITY ==="

LOCAL_MAC="02:AA:BB:CC:DD:EE"
LOCAL_ENTITY="dev-33333333333333333333333333333333"

# Persistent Identity may retain local-MAC evidence, but it must remain
# non-authoritative and therefore unusable for canonical resurrection.
"${IDENTITY}" \
    --database "${IDENTITY_DB}" \
    register \
    --entity-id "${LOCAL_ENTITY}" \
    --mac "${LOCAL_MAC}" \
    --seen-at "2026-08-27T07:10:00Z" \
    >/dev/null

INVENTORY_LOCAL="${TMP_DIR}/inventory-local.db"

LOCAL_OBSERVATION='{"schema_version":"1.0","provider":"identity-correlation-test","discovery_method":"host-discovery","discovered_at":"2026-08-27T07:15:00Z","ip_addresses":["192.0.2.120"],"mac_address":"02:AA:BB:CC:DD:EE","hostname":"local-mac-test"}'

printf '%s\n' "${LOCAL_OBSERVATION}" |
    "${STORE}" --database "${INVENTORY_LOCAL}" >/dev/null

"${CORRELATE}" \
        --database "${INVENTORY_LOCAL}" \
        --identity-database "${IDENTITY_DB}" >/dev/null

LOCAL_CURRENT_ENTITY="$(
    python3 - "${INVENTORY_LOCAL}" <<'PYSQL'
import sqlite3
import sys

con = sqlite3.connect(sys.argv[1])

try:
    row = con.execute("""
        SELECT entity_id
        FROM entities
        ORDER BY created_at
        LIMIT 1
    """).fetchone()
finally:
    con.close()

if row is None:
    raise SystemExit("local-MAC Inventory entity missing")

print(row[0])
PYSQL
)"

echo "Persistent evidence entity : ${LOCAL_ENTITY}"
echo "Current Inventory entity   : ${LOCAL_CURRENT_ENTITY}"

[[ "${LOCAL_CURRENT_ENTITY}" != "${LOCAL_ENTITY}" ]] ||
    fail "local MAC resurrected a Persistent Identity"

pass "local MAC did not resurrect Persistent Identity"

echo
echo "=== EXISTING INVENTORY ENTITY CONFIRMS IDENTITY ==="

INVENTORY_EXISTING="${TMP_DIR}/inventory-existing.db"
IDENTITY_EXISTING="${TMP_DIR}/identity-existing.db"

"${IDENTITY}" \
    --database "${IDENTITY_EXISTING}" \
    init >/dev/null

EXISTING_ONE='{"schema_version":"1.0","provider":"identity-correlation-test","discovery_method":"host-discovery","discovered_at":"2026-08-27T07:20:00Z","ip_addresses":["192.0.2.130"],"mac_address":"00:AA:BB:CC:DD:10","hostname":"existing-one"}'

EXISTING_TWO='{"schema_version":"1.0","provider":"identity-correlation-test","discovery_method":"host-discovery","discovered_at":"2026-08-27T07:25:00Z","ip_addresses":["192.0.2.131"],"mac_address":"00:AA:BB:CC:DD:10","hostname":"existing-two"}'

printf '%s\n' "${EXISTING_ONE}" |
    "${STORE}" --database "${INVENTORY_EXISTING}" >/dev/null

"${CORRELATE}" \
    --database "${INVENTORY_EXISTING}" \
    --identity-database "${IDENTITY_EXISTING}" \
    >/dev/null

EXISTING_ENTITY="$(
    "${IDENTITY}" \
        --database "${IDENTITY_EXISTING}" \
        lookup \
        --mac "00:AA:BB:CC:DD:10"
)"

[[ -n "${EXISTING_ENTITY}" ]] ||
    fail "initial global identity registration missing"

# Remove only Persistent Identity, while keeping the established current
# Inventory entity and its observation history.
rm -f "${IDENTITY_EXISTING}"

"${IDENTITY}" \
    --database "${IDENTITY_EXISTING}" \
    init >/dev/null

printf '%s\n' "${EXISTING_TWO}" |
    "${STORE}" --database "${INVENTORY_EXISTING}" >/dev/null

"${CORRELATE}" \
    --database "${INVENTORY_EXISTING}" \
    --identity-database "${IDENTITY_EXISTING}" \
    >/dev/null

set +e
CONFIRMED_ENTITY="$(
    "${IDENTITY}" \
        --database "${IDENTITY_EXISTING}" \
        lookup \
        --mac "00:AA:BB:CC:DD:10" \
        2>/dev/null
)"
CONFIRM_RC=$?
set -e

[[ "${CONFIRM_RC}" -eq 0 ]] ||
    fail "existing Inventory entity did not confirm Persistent Identity"

[[ "${CONFIRMED_ENTITY}" == "${EXISTING_ENTITY}" ]] ||
    fail "existing Inventory confirmation changed canonical entity"

pass "existing global-MAC entity confirmed into Persistent Identity"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Persistent Identity correlation regression PASSED"
