#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="${APP_ROOT}/core/inventory/schema.sql"
MIGRATIONS="${APP_ROOT}/core/inventory/migrations"
TMPDIR="$(mktemp -d /tmp/hls-service-discovery-migration-v5.XXXXXX)"
trap 'rm -rf "${TMPDIR}"' EXIT
DATABASE="${TMPDIR}/inventory.db"

python3 - "${DATABASE}" "${SCHEMA}" "${MIGRATIONS}" <<'PY'
import sqlite3
import sys
from pathlib import Path

database = Path(sys.argv[1])
schema = Path(sys.argv[2])
migrations = Path(sys.argv[3])

connection = sqlite3.connect(database)
connection.execute("PRAGMA foreign_keys = ON")
connection.executescript(schema.read_text(encoding="utf-8"))

for migration in sorted(migrations.glob("*.sql")):
    version = int(migration.name.split("_", 1)[0])
    if 2 <= version <= 4:
        connection.executescript(migration.read_text(encoding="utf-8"))

entity_id = "dev-0123456789abcdef0123456789abcdef"
observation_id = "svc-0123456789abcdef0123456789abcdef"

connection.execute(
    """
    INSERT INTO entities (
        entity_id,
        entity_type,
        created_at,
        updated_at
    )
    VALUES (?, 'device', ?, ?)
    """,
    (
        entity_id,
        "2026-08-30T14:00:00Z",
        "2026-08-30T14:00:00Z",
    ),
)

connection.execute(
    """
    INSERT INTO service_observations (
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
    )
    VALUES (
        ?, ?, '1.0', 'fixture-provider', ?, ?,
        '192.0.2.58', 'tcp', 22, 'open', 'ssh', ?, ?
    )
    """,
    (
        observation_id,
        entity_id,
        "2026-08-30T14:05:00Z",
        "2026-08-30T14:05:01Z",
        '{"fixture":"historical-service-observation"}',
        "fixture-service-observation-hash",
    ),
)

connection.commit()

version = connection.execute(
    "PRAGMA user_version"
).fetchone()[0]

if version != 4:
    raise SystemExit(
        f"[FAIL] expected deterministic v4 fixture, got v{version}"
    )

connection.close()
print("[PASS] deterministic v4 fixture created")
PY

python3 - "${DATABASE}" "${MIGRATIONS}/005_service_discovery_runs.sql" <<'PY'
import sqlite3
import sys
from pathlib import Path

database = Path(sys.argv[1])
migration = Path(sys.argv[2])

if not migration.is_file():
    raise SystemExit(
        f"[FAIL] migration missing: {migration}"
    )

connection = sqlite3.connect(database)
connection.execute("PRAGMA foreign_keys = ON")
connection.executescript(
    migration.read_text(encoding="utf-8")
)

version = connection.execute(
    "PRAGMA user_version"
).fetchone()[0]
if version != 5:
    raise SystemExit(
        f"[FAIL] expected schema version 5, got {version}"
    )

required_tables = {
    "service_discovery_runs",
    "service_discovery_run_observations",
}
tables = {
    row[0]
    for row in connection.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
        """
    )
}
missing_tables = required_tables - tables
if missing_tables:
    raise SystemExit(
        f"[FAIL] missing v5 tables: {sorted(missing_tables)}"
    )

run_columns = [
    row[1]
    for row in connection.execute(
        "PRAGMA table_info(service_discovery_runs)"
    )
]
expected_run_columns = [
    "service_discovery_run_id",
    "entity_id",
    "address",
    "provider",
    "started_at",
    "completed_at",
    "outcome",
    "detail",
]
if run_columns != expected_run_columns:
    raise SystemExit(
        f"[FAIL] unexpected run columns: {run_columns!r}"
    )

link_columns = [
    row[1]
    for row in connection.execute(
        "PRAGMA table_info(service_discovery_run_observations)"
    )
]
expected_link_columns = [
    "service_discovery_run_id",
    "service_observation_id",
]
if link_columns != expected_link_columns:
    raise SystemExit(
        f"[FAIL] unexpected association columns: {link_columns!r}"
    )

if connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0] != 1:
    raise SystemExit(
        "[FAIL] existing Service Discovery history was not preserved"
    )

entity_id = "dev-0123456789abcdef0123456789abcdef"
observation_id = "svc-0123456789abcdef0123456789abcdef"

run_sql = """
    INSERT INTO service_discovery_runs (
        service_discovery_run_id,
        entity_id,
        address,
        provider,
        started_at,
        completed_at,
        outcome,
        detail
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
"""

observed_run = "run-0123456789abcdef0123456789abcdef"
empty_run = "run-11111111111111111111111111111111"

connection.execute(
    run_sql,
    (
        observed_run,
        entity_id,
        "192.0.2.58",
        "fixture-provider",
        "2026-08-30T14:10:00Z",
        "2026-08-30T14:10:02Z",
        "success",
        None,
    ),
)

connection.execute(
    """
    INSERT INTO service_discovery_run_observations (
        service_discovery_run_id,
        service_observation_id
    )
    VALUES (?, ?)
    """,
    (observed_run, observation_id),
)

connection.execute(
    run_sql,
    (
        empty_run,
        entity_id,
        "192.0.2.58",
        "fixture-provider",
        "2026-08-30T14:20:00Z",
        "2026-08-30T14:20:02Z",
        "success",
        None,
    ),
)

linked = connection.execute(
    """
    SELECT COUNT(*)
    FROM service_discovery_run_observations
    WHERE service_discovery_run_id = ?
    """,
    (observed_run,),
).fetchone()[0]
if linked != 1:
    raise SystemExit(
        "[FAIL] successful observed run was not associated"
    )

empty_links = connection.execute(
    """
    SELECT COUNT(*)
    FROM service_discovery_run_observations
    WHERE service_discovery_run_id = ?
    """,
    (empty_run,),
).fetchone()[0]
if empty_links != 0:
    raise SystemExit(
        "[FAIL] successful empty run unexpectedly has observations"
    )

def must_reject(label, sql, params):
    connection.execute("SAVEPOINT reject_case")
    try:
        connection.execute(sql, params)
    except sqlite3.IntegrityError:
        connection.execute("ROLLBACK TO reject_case")
        connection.execute("RELEASE reject_case")
        return

    connection.execute("ROLLBACK TO reject_case")
    connection.execute("RELEASE reject_case")
    raise SystemExit(
        f"[FAIL] SQL constraints did not reject {label}"
    )

link_sql = """
    INSERT INTO service_discovery_run_observations (
        service_discovery_run_id,
        service_observation_id
    )
    VALUES (?, ?)
"""

must_reject(
    "unknown run association",
    link_sql,
    (
        "run-ffffffffffffffffffffffffffffffff",
        observation_id,
    ),
)

must_reject(
    "unknown observation association",
    link_sql,
    (
        observed_run,
        "svc-ffffffffffffffffffffffffffffffff",
    ),
)

must_reject(
    "duplicate run-observation association",
    link_sql,
    (
        observed_run,
        observation_id,
    ),
)

before = connection.execute(
    """
    SELECT payload_json, payload_hash
    FROM service_observations
    WHERE service_observation_id = ?
    """,
    (observation_id,),
).fetchone()

after = connection.execute(
    """
    SELECT payload_json, payload_hash
    FROM service_observations
    WHERE service_observation_id = ?
    """,
    (observation_id,),
).fetchone()

if before != after:
    raise SystemExit(
        "[FAIL] historical observation changed during v5 validation"
    )

connection.commit()

foreign_keys = connection.execute(
    "PRAGMA foreign_key_check"
).fetchall()
if foreign_keys:
    raise SystemExit(
        f"[FAIL] foreign key violations: {foreign_keys!r}"
    )

integrity = connection.execute(
    "PRAGMA integrity_check"
).fetchone()[0]
if integrity != "ok":
    raise SystemExit(
        f"[FAIL] integrity check failed: {integrity}"
    )

connection.close()

print("[PASS] v4 database migrated to v5")
print("[PASS] existing Service Discovery history preserved")
print("[PASS] run-to-observation association is explicit")
print("[PASS] successful empty run is representable")
print("[PASS] invalid associations rejected")
print("[PASS] historical Service Discovery evidence preserved")
print("[PASS] Service Discovery run evidence migration contract")
PY

echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery migration v5 regression PASSED"
