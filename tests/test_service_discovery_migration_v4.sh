#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
MIGRATION="${APP_ROOT}/core/inventory/migrations/004_service_observations.sql"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT
DB="${TMPDIR}/inventory-v3.db"

fail() { echo "[FAIL] $*" >&2; exit 1; }

[[ -f "${MIGRATION}" ]] || fail "Service Discovery migration not found: ${MIGRATION}"

python3 - "${DB}" "${MIGRATION}" <<'PY'
import sqlite3
import sys
from pathlib import Path

db_path = Path(sys.argv[1])
migration_path = Path(sys.argv[2])
entity_id = "dev-0123456789abcdef0123456789abcdef"

with sqlite3.connect(db_path) as con:
    con.execute("PRAGMA foreign_keys = ON")
    con.executescript('''
        CREATE TABLE entities (
            entity_id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL DEFAULT 'device',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE monitoring_observations (
            monitoring_observation_id TEXT PRIMARY KEY,
            entity_id TEXT NOT NULL,
            schema_version TEXT NOT NULL,
            provider TEXT NOT NULL,
            check_type TEXT NOT NULL,
            target TEXT NOT NULL,
            checked_at TEXT NOT NULL,
            received_at TEXT NOT NULL,
            status TEXT NOT NULL,
            latency_ms REAL,
            payload_json TEXT NOT NULL,
            payload_hash TEXT NOT NULL UNIQUE,
            FOREIGN KEY (entity_id) REFERENCES entities (entity_id) ON DELETE RESTRICT,
            CHECK (status IN ('success', 'failed', 'unknown')),
            CHECK (latency_ms IS NULL OR latency_ms >= 0.0),
            CHECK (json_valid(payload_json))
        );
        PRAGMA user_version = 3;
    ''')
    con.execute(
        "INSERT INTO entities VALUES (?, 'device', '2026-08-30T12:00:00Z', '2026-08-30T12:00:00Z')",
        (entity_id,),
    )
    con.execute(
        '''INSERT INTO monitoring_observations VALUES
           ('mon-existing', ?, '1.0', 'prometheus', 'icmp', '192.168.1.58',
            '2026-08-30T12:00:00Z', '2026-08-30T12:00:01Z',
            'success', 1.25, '{"existing":true}', 'existing-monitoring-hash')''',
        (entity_id,),
    )
    con.commit()

    con.executescript(migration_path.read_text(encoding="utf-8"))

    assert con.execute("PRAGMA user_version").fetchone()[0] == 4

    columns = {r[1] for r in con.execute("PRAGMA table_info(service_observations)")}
    expected_columns = {
        "service_observation_id", "entity_id", "schema_version", "provider",
        "observed_at", "received_at", "address", "protocol", "port", "state",
        "service", "payload_json", "payload_hash",
    }
    assert expected_columns <= columns, f"missing columns: {sorted(expected_columns - columns)}"

    indexes = {r[1] for r in con.execute("PRAGMA index_list(service_observations)")}
    expected_indexes = {
        "idx_service_observations_entity_observed",
        "idx_service_observations_endpoint_observed",
    }
    assert expected_indexes <= indexes, f"missing indexes: {sorted(expected_indexes - indexes)}"

    assert con.execute(
        "SELECT entity_id FROM entities WHERE entity_id = ?", (entity_id,)
    ).fetchone() == (entity_id,)
    assert con.execute(
        "SELECT payload_hash FROM monitoring_observations WHERE monitoring_observation_id='mon-existing'"
    ).fetchone() == ("existing-monitoring-hash",)

    insert_sql = '''INSERT INTO service_observations (
        service_observation_id, entity_id, schema_version, provider,
        observed_at, received_at, address, protocol, port, state,
        service, payload_json, payload_hash
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'''

    def row(obs_id, *, eid=entity_id, protocol="tcp", port=22, state="open",
            service="ssh", payload='{"test":true}', payload_hash=None):
        return (
            obs_id, eid, "1.0", "nmap",
            "2026-08-30T12:10:00Z", "2026-08-30T12:10:01Z",
            "192.168.1.58", protocol, port, state, service,
            payload, payload_hash or f"hash-{obs_id}",
        )

    con.execute(insert_sql, row("svc-valid", port=8006, service=None,
                                payload_hash="service-valid-hash"))

    def reject(label, values):
        try:
            con.execute(insert_sql, values)
        except sqlite3.IntegrityError:
            return
        raise AssertionError(f"{label} was accepted")

    reject("unknown entity", row("bad-entity", eid="dev-ffffffffffffffffffffffffffffffff"))
    reject("UDP protocol", row("bad-protocol", protocol="udp"))
    reject("port zero", row("bad-port-low", port=0))
    reject("port 65536", row("bad-port-high", port=65536))
    reject("closed state", row("bad-state", state="closed"))
    reject("empty service", row("bad-service", service=""))
    reject("invalid JSON", row("bad-json", payload="{invalid"))
    reject("duplicate payload hash", row("bad-hash", payload_hash="service-valid-hash"))

print("[PASS] v3 database migrated to v4")
print("[PASS] service_observations schema and indexes present")
print("[PASS] existing v3 data preserved")
print("[PASS] valid Service Discovery observation accepted")
print("[PASS] Service Discovery SQL constraints enforced")
print("[PASS] Service Discovery persistence migration contract")
PY
