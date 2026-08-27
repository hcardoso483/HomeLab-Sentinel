#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

STORE="${APP_ROOT}/core/inventory/store.py"
CORRELATE="${APP_ROOT}/core/inventory/correlate.py"

TMP_DIR="$(mktemp -d /tmp/hls-correlation-test.XXXXXX)"
DATABASE="${TMP_DIR}/inventory.db"
IDENTITY_DATABASE="${TMP_DIR}/identity.db"

cleanup() {
    rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

for required in "${STORE}" "${CORRELATE}"; do
    [[ -x "${required}" ]] ||
        fail "Required executable missing: ${required}"
done

echo "HomeLab Sentinel correlation regression test"
echo
echo "Database : ${DATABASE}"
echo

echo "=== FIRST PASS ==="

python3 - <<'PY' |
import json
from datetime import datetime, timezone

def now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

records = [
    {
        "schema_version": "1.0",
        "provider": "correlation-test",
        "discovery_method": "host-discovery",
        "discovered_at": now(),
        "ip_addresses": ["192.0.2.10"],
        "mac_address": "3A:22:33:44:55:66",
        "hostname": None,
    },
    {
        "schema_version": "1.0",
        "provider": "correlation-test",
        "discovery_method": "host-discovery",
        "discovered_at": now(),
        "ip_addresses": ["192.0.2.11"],
        "mac_address": "00:11:22:33:44:55",
        "hostname": None,
    },
    {
        "schema_version": "1.0",
        "provider": "correlation-test",
        "discovery_method": "host-discovery",
        "discovered_at": now(),
        "ip_addresses": ["192.0.2.12"],
        "mac_address": None,
        "hostname": None,
    },
]

for record in records:
    print(json.dumps(record, separators=(",", ":"), sort_keys=True))
PY

"${STORE}" --database "${DATABASE}"
"${CORRELATE}" --database "${DATABASE}" --identity-database "${IDENTITY_DATABASE}"

python3 - "${DATABASE}" <<'PY'
import sqlite3
import sys

db = sys.argv[1]

with sqlite3.connect(db) as con:
    rows = con.execute("""
        SELECT
            json_extract(o.payload_json, '$.mac_address'),
            c.status,
            c.correlation_method,
            c.confidence,
            c.entity_id,
            c.reason
        FROM correlation_state AS c
        JOIN observations AS o
          ON o.observation_id = c.observation_id
        WHERE o.provider = 'correlation-test'
        ORDER BY o.received_at, o.observation_id
    """).fetchall()

if len(rows) != 3:
    raise SystemExit(f"expected 3 first-pass rows, got {len(rows)}")

local_mac, global_mac, no_mac = rows

if not (
    local_mac[0] == "3A:22:33:44:55:66"
    and local_mac[1] == "resolved"
    and local_mac[2] == "new-entity-local-mac-evidence"
    and local_mac[3] == 0.60
    and local_mac[4]
):
    raise SystemExit(
        f"unexpected new local-MAC result: {local_mac}"
    )

if not (
    global_mac[0] == "00:11:22:33:44:55"
    and global_mac[1] == "resolved"
    and global_mac[2] == "new-entity-mac-evidence"
    and global_mac[3] == 0.90
    and global_mac[4]
):
    raise SystemExit(
        f"unexpected new global-MAC result: {global_mac}"
    )

if not (
    no_mac[0] is None
    and no_mac[1] == "unresolved"
    and no_mac[2] is None
    and no_mac[3] is None
    and no_mac[4] is None
    and no_mac[5] == "no strong identity evidence available"
):
    raise SystemExit(
        f"unexpected no-MAC result: {no_mac}"
    )

print(f"LOCAL_ENTITY={local_mac[4]}")
print(f"GLOBAL_ENTITY={global_mac[4]}")
PY

pass "new local MAC -> confidence 0.60"
pass "new global MAC -> confidence 0.90"
pass "no MAC -> unresolved"

LOCAL_ENTITY="$(
python3 - "${DATABASE}" <<'PY'
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as con:
    print(con.execute("""
        SELECT c.entity_id
        FROM correlation_state c
        JOIN observations o
          ON o.observation_id = c.observation_id
        WHERE json_extract(
            o.payload_json,
            '$.mac_address'
        ) = '3A:22:33:44:55:66'
        ORDER BY o.received_at
        LIMIT 1
    """).fetchone()[0])
PY
)"

GLOBAL_ENTITY="$(
python3 - "${DATABASE}" <<'PY'
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as con:
    print(con.execute("""
        SELECT c.entity_id
        FROM correlation_state c
        JOIN observations o
          ON o.observation_id = c.observation_id
        WHERE json_extract(
            o.payload_json,
            '$.mac_address'
        ) = '00:11:22:33:44:55'
        ORDER BY o.received_at
        LIMIT 1
    """).fetchone()[0])
PY
)"

sleep 1

echo
echo "=== SECOND PASS ==="

python3 - <<'PY' |
import json
from datetime import datetime, timezone

def now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

records = [
    {
        "schema_version": "1.0",
        "provider": "correlation-test-repeat",
        "discovery_method": "host-discovery",
        "discovered_at": now(),
        "ip_addresses": ["192.0.2.20"],
        "mac_address": "3A:22:33:44:55:66",
        "hostname": None,
    },
    {
        "schema_version": "1.0",
        "provider": "correlation-test-repeat",
        "discovery_method": "host-discovery",
        "discovered_at": now(),
        "ip_addresses": ["192.0.2.21"],
        "mac_address": "00:11:22:33:44:55",
        "hostname": None,
    },
]

for record in records:
    print(json.dumps(record, separators=(",", ":"), sort_keys=True))
PY

"${STORE}" --database "${DATABASE}"
"${CORRELATE}" --database "${DATABASE}" --identity-database "${IDENTITY_DATABASE}"

python3 - "${DATABASE}" "${LOCAL_ENTITY}" "${GLOBAL_ENTITY}" <<'PY'
import sqlite3
import sys

db, local_entity, global_entity = sys.argv[1:4]

with sqlite3.connect(db) as con:
    rows = con.execute("""
        SELECT
            json_extract(o.payload_json, '$.mac_address'),
            c.status,
            c.correlation_method,
            c.confidence,
            c.entity_id
        FROM correlation_state AS c
        JOIN observations AS o
          ON o.observation_id = c.observation_id
        WHERE o.provider = 'correlation-test-repeat'
        ORDER BY o.received_at, o.observation_id
    """).fetchall()

if len(rows) != 2:
    raise SystemExit(
        f"expected 2 second-pass rows, got {len(rows)}"
    )

local_mac, global_mac = rows

if not (
    local_mac[0] == "3A:22:33:44:55:66"
    and local_mac[1] == "resolved"
    and local_mac[2] == "local-mac-history-match"
    and local_mac[3] == 0.60
    and local_mac[4] == local_entity
):
    raise SystemExit(
        f"unexpected local-MAC history result: {local_mac}"
    )

if not (
    global_mac[0] == "00:11:22:33:44:55"
    and global_mac[1] == "resolved"
    and global_mac[2] == "mac-history-match"
    and global_mac[3] == 0.90
    and global_mac[4] == global_entity
):
    raise SystemExit(
        f"unexpected global-MAC history result: {global_mac}"
    )
PY

pass "known local MAC -> same entity, confidence 0.60"
pass "known global MAC -> same entity, confidence 0.90"

echo
echo "=== IP HISTORY FALLBACK ==="

python3 - <<'PY' |
import json
from datetime import datetime, timezone

def now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

records = [
    {
        "schema_version": "1.0",
        "provider": "correlation-test-ip-history",
        "discovery_method": "host-discovery",
        "discovered_at": now(),
        "ip_addresses": ["192.0.2.21"],
        "mac_address": None,
        "hostname": None,
    },
    {
        "schema_version": "1.0",
        "provider": "correlation-test-ip-history",
        "discovery_method": "host-discovery",
        "discovered_at": now(),
        "ip_addresses": ["192.0.2.99"],
        "mac_address": None,
        "hostname": None,
    },
]

for record in records:
    print(json.dumps(record, separators=(",", ":"), sort_keys=True))
PY

"${STORE}" --database "${DATABASE}"
"${CORRELATE}" --database "${DATABASE}" --identity-database "${IDENTITY_DATABASE}"

python3 - "${DATABASE}" "${GLOBAL_ENTITY}" <<'PY'
import sqlite3
import sys

db, global_entity = sys.argv[1:3]

with sqlite3.connect(db) as con:
    rows = con.execute("""
        SELECT
            json_extract(
                o.payload_json,
                '$.ip_addresses[0]'
            ),
            c.status,
            c.correlation_method,
            c.confidence,
            c.entity_id,
            c.reason
        FROM correlation_state AS c
        JOIN observations AS o
          ON o.observation_id = c.observation_id
        WHERE o.provider = 'correlation-test-ip-history'
        ORDER BY o.received_at, o.observation_id
    """).fetchall()

if len(rows) != 2:
    raise SystemExit(
        f"expected 2 IP-history rows, got {len(rows)}"
    )

known_ip, unknown_ip = rows

if not (
    known_ip[0] == "192.0.2.21"
    and known_ip[1] == "resolved"
    and known_ip[2] == "ip-history-match"
    and known_ip[3] == 0.40
    and known_ip[4] == global_entity
    and known_ip[5] is None
):
    raise SystemExit(
        f"unexpected known IP-history result: {known_ip}"
    )

if not (
    unknown_ip[0] == "192.0.2.99"
    and unknown_ip[1] == "unresolved"
    and unknown_ip[2] is None
    and unknown_ip[3] is None
    and unknown_ip[4] is None
    and unknown_ip[5] == "no strong identity evidence available"
):
    raise SystemExit(
        f"unexpected unknown IP result: {unknown_ip}"
    )
PY

pass "known historical IP -> same entity, confidence 0.40"
pass "unknown IP without MAC -> unresolved"

echo
echo "=== AMBIGUOUS IP HISTORY SEED ==="

python3 - <<'PY' |
import json
from datetime import datetime, timezone

record = {
    "schema_version": "1.0",
    "provider": "correlation-test-ambiguity-seed",
    "discovery_method": "host-discovery",
    "discovered_at": datetime.now(
        timezone.utc
    ).isoformat().replace("+00:00", "Z"),
    "ip_addresses": ["192.0.2.21"],
    "mac_address": "00:AA:BB:CC:DD:EE",
    "hostname": None,
}

print(json.dumps(record, separators=(",", ":"), sort_keys=True))
PY

"${STORE}" --database "${DATABASE}"
"${CORRELATE}" --database "${DATABASE}" --identity-database "${IDENTITY_DATABASE}"

AMBIGUITY_ENTITY_COUNT="$(
python3 - "${DATABASE}" <<'PY'
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as con:
    row = con.execute("""
        SELECT COUNT(DISTINCT eo.entity_id)
        FROM entity_observations AS eo
        JOIN observations AS o
          ON o.observation_id = eo.observation_id
        WHERE EXISTS (
            SELECT 1
            FROM json_each(
                o.payload_json,
                '$.ip_addresses'
            )
            WHERE json_each.value = '192.0.2.21'
        )
    """).fetchone()

    print(row[0])
PY
)"

[[ "${AMBIGUITY_ENTITY_COUNT}" -eq 2 ]] ||
    fail \
        "ambiguity seed expected 2 entities for historical IP, got ${AMBIGUITY_ENTITY_COUNT}"

pass "ambiguous IP history seeded with two entities"

echo
echo "=== AMBIGUOUS IP HISTORY ==="

python3 - <<'PY' |
import json
from datetime import datetime, timezone

record = {
    "schema_version": "1.0",
    "provider": "correlation-test-ambiguous-ip",
    "discovery_method": "host-discovery",
    "discovered_at": datetime.now(
        timezone.utc
    ).isoformat().replace("+00:00", "Z"),
    "ip_addresses": ["192.0.2.21"],
    "mac_address": None,
    "hostname": None,
}

print(json.dumps(record, separators=(",", ":"), sort_keys=True))
PY

"${STORE}" --database "${DATABASE}"
"${CORRELATE}" --database "${DATABASE}" --identity-database "${IDENTITY_DATABASE}"

python3 - "${DATABASE}" <<'PY'
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as con:
    row = con.execute("""
        SELECT
            c.status,
            c.correlation_method,
            c.confidence,
            c.entity_id,
            c.reason
        FROM correlation_state AS c
        JOIN observations AS o
          ON o.observation_id = c.observation_id
        WHERE o.provider = 'correlation-test-ambiguous-ip'
    """).fetchone()

if row is None:
    raise SystemExit(
        "ambiguous IP test observation missing"
    )

if not (
    row[0] == "unresolved"
    and row[1] is None
    and row[2] is None
    and row[3] is None
):
    raise SystemExit(
        f"unexpected ambiguous IP result: {row}"
    )
PY

pass "ambiguous historical IP -> unresolved"

echo
echo "=== RESULT ==="

echo "HomeLab Sentinel correlation regression PASSED"
