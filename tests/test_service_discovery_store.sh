#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
STORE="${APP_ROOT}/core/service_discovery/store.py"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT
DB="${TMPDIR}/inventory.db"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

echo "HomeLab Sentinel Service Discovery persistence regression test"
echo "Database : ${DB}"
echo

[[ -f "${STORE}" ]] || fail "Service Discovery store not found: ${STORE}"

python3 - "${DB}" <<'PY'
import sqlite3
import sys

db = sys.argv[1]
entity_id = "dev-0123456789abcdef0123456789abcdef"

with sqlite3.connect(db) as con:
    con.execute("PRAGMA foreign_keys = ON")
    con.executescript("""
        CREATE TABLE entities (
            entity_id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL DEFAULT 'device',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE service_observations (
            service_observation_id TEXT PRIMARY KEY,
            entity_id TEXT NOT NULL,
            schema_version TEXT NOT NULL,
            provider TEXT NOT NULL,
            observed_at TEXT NOT NULL,
            received_at TEXT NOT NULL,
            address TEXT NOT NULL,
            protocol TEXT NOT NULL,
            port INTEGER NOT NULL,
            state TEXT NOT NULL,
            service TEXT,
            payload_json TEXT NOT NULL,
            payload_hash TEXT NOT NULL UNIQUE,
            FOREIGN KEY (entity_id)
                REFERENCES entities (entity_id)
                ON DELETE RESTRICT,
            CHECK (protocol IN ('tcp')),
            CHECK (port >= 1 AND port <= 65535),
            CHECK (state IN ('open')),
            CHECK (service IS NULL OR length(trim(service)) > 0),
            CHECK (json_valid(payload_json))
        );

        PRAGMA user_version = 4;
    """)

    con.execute(
        "INSERT INTO entities VALUES (?, 'device', ?, ?)",
        (
            entity_id,
            "2026-08-30T12:00:00Z",
            "2026-08-30T12:00:00Z",
        ),
    )
    con.commit()
PY

pass "schema v4 fixture created"

VALID='{"schema_version":"1.0","entity_id":"dev-0123456789abcdef0123456789abcdef","provider":"nmap","observed_at":"2026-08-30T12:10:00Z","address":"192.168.1.58","protocol":"tcp","port":8006,"state":"open","service":null}'

printf '%s\n' "${VALID}" | python3 "${STORE}" --database "${DB}" >/dev/null
pass "valid Service Discovery observation stored"

python3 - "${DB}" <<'PY'
import json
import sqlite3
import sys

db = sys.argv[1]

with sqlite3.connect(db) as con:
    row = con.execute("""
        SELECT
            service_observation_id,
            entity_id,
            schema_version,
            provider,
            observed_at,
            received_at,
            address,
            protocol,
            port,
            state,
            service,
            payload_json,
            payload_hash
        FROM service_observations
    """).fetchone()

assert row is not None
assert row[0].startswith("svc-")
assert len(row[0]) == 36
assert row[1] == "dev-0123456789abcdef0123456789abcdef"
assert row[2] == "1.0"
assert row[3] == "nmap"
assert row[4] == "2026-08-30T12:10:00Z"
assert row[5]
assert row[6] == "192.168.1.58"
assert row[7] == "tcp"
assert row[8] == 8006
assert row[9] == "open"
assert row[10] is None

payload = json.loads(row[11])
assert payload["entity_id"] == row[1]
assert payload["port"] == row[8]
assert len(row[12]) == 64
PY

pass "Service Discovery evidence uses dedicated table"

printf '%s\n' "${VALID}" | python3 "${STORE}" --database "${DB}" >/dev/null

COUNT="$(python3 - "${DB}" <<'PY'
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as con:
    print(
        con.execute(
            "SELECT COUNT(*) FROM service_observations"
        ).fetchone()[0]
    )
PY
)"

[[ "${COUNT}" == "1" ]] || fail "exact duplicate created another observation"
pass "exact duplicate ingestion is idempotent"

if printf '%s\n' \
    '{"schema_version":"1.0","entity_id":"dev-0123456789abcdef0123456789abcdef","provider":"nmap","observed_at":"2026-08-30T12:11:00Z","address":"192.168.1.58","protocol":"udp","port":53,"state":"open","service":"domain"}' \
    | python3 "${STORE}" --database "${DB}" >/dev/null 2>&1
then
    fail "invalid Service Discovery protocol was accepted"
fi

pass "invalid Service Discovery protocol rejected"

if printf '%s\n' \
    '{"schema_version":"1.0","entity_id":"dev-ffffffffffffffffffffffffffffffff","provider":"nmap","observed_at":"2026-08-30T12:12:00Z","address":"192.168.1.59","protocol":"tcp","port":22,"state":"open","service":"ssh"}' \
    | python3 "${STORE}" --database "${DB}" >/dev/null 2>&1
then
    fail "observation for unknown entity was accepted"
fi

pass "Service Discovery evidence requires canonical entity"

if printf '%s\n' '{"not":"canonical"}' \
    | python3 "${STORE}" --database "${DB}" >/dev/null 2>&1
then
    fail "invalid Service Discovery observation was accepted"
fi

pass "invalid Service Discovery observation rejected"

BEFORE="$(python3 - "${DB}" <<'PY'
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as con:
    print(
        con.execute(
            "SELECT COUNT(*) FROM service_observations"
        ).fetchone()[0]
    )
PY
)"

if printf '%s\n%s\n' \
    '{"schema_version":"1.0","entity_id":"dev-0123456789abcdef0123456789abcdef","provider":"nmap","observed_at":"2026-08-30T12:20:00Z","address":"192.168.1.58","protocol":"tcp","port":22,"state":"open","service":"ssh"}' \
    '{"not":"canonical"}' \
    | python3 "${STORE}" --database "${DB}" >/dev/null 2>&1
then
    fail "mixed valid/invalid observation batch was accepted"
fi

AFTER="$(python3 - "${DB}" <<'PY'
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as con:
    print(
        con.execute(
            "SELECT COUNT(*) FROM service_observations"
        ).fetchone()[0]
    )
PY
)"

[[ "${AFTER}" == "${BEFORE}" ]] || \
    fail "failed observation batch left partial persisted evidence"

pass "failed observation batch is atomic"

VERSION="$(python3 - "${DB}" <<'PY'
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as con:
    print(con.execute("PRAGMA user_version").fetchone()[0])
PY
)"

[[ "${VERSION}" == "5" ]] || fail "expected schema version 5, got ${VERSION}"
pass "inventory schema version is v5"

python3 - "${DB}" <<'PY'
import sqlite3
import sys

with sqlite3.connect(sys.argv[1]) as con:
    assert con.execute(
        """
        SELECT 1
        FROM sqlite_master
        WHERE type = 'table'
          AND name = 'service_discovery_runs'
        """
    ).fetchone()

    assert con.execute(
        """
        SELECT 1
        FROM sqlite_master
        WHERE type = 'table'
          AND name = 'service_discovery_run_observations'
        """
    ).fetchone()
PY

pass "Service Discovery run evidence tables are available"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery persistence regression PASSED"
