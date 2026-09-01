#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="${APP_ROOT}/core/inventory/schema.sql"
MIGRATIONS="${APP_ROOT}/core/inventory/migrations"
MIGRATION_V6="${MIGRATIONS}/006_service_discovery_run_outcomes.sql"

TMPDIR="$(mktemp -d /tmp/hls-service-discovery-migration-v6.XXXXXX)"
trap 'rm -rf "${TMPDIR}"' EXIT
DATABASE="${TMPDIR}/inventory.db"

echo
echo "HomeLab Sentinel Service Discovery migration v6 regression"
echo "Database : ${DATABASE}"
echo

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
    if 2 <= version <= 5:
        connection.executescript(migration.read_text(encoding="utf-8"))

version = connection.execute("PRAGMA user_version").fetchone()[0]
if version != 5:
    raise SystemExit(f"[FAIL] expected deterministic v5 fixture, got v{version}")

entity_id = "dev-0123456789abcdef0123456789abcdef"
observation_id = "svc-0123456789abcdef0123456789abcdef"
run_id = "run-0123456789abcdef0123456789abcdef"

connection.execute(
    """
    INSERT INTO entities (
        entity_id, entity_type, created_at, updated_at
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
        '{"fixture":"v5-service-observation"}',
        "fixture-v5-service-observation-hash",
    ),
)

connection.execute(
    """
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
    VALUES (?, ?, ?, ?, ?, ?, 'success', NULL)
    """,
    (
        run_id,
        entity_id,
        "192.0.2.58",
        "fixture-provider",
        "2026-08-30T14:10:00Z",
        "2026-08-30T14:10:02Z",
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
    (run_id, observation_id),
)

connection.commit()
connection.close()
print("[PASS] deterministic populated v5 fixture created")
PY

if [[ ! -f "${MIGRATION_V6}" ]]; then
    echo "[FAIL] migration missing: ${MIGRATION_V6}" >&2
    exit 1
fi

python3 - "${DATABASE}" "${MIGRATION_V6}" <<'PY'
import sqlite3
import sys
from pathlib import Path

database = Path(sys.argv[1])
migration = Path(sys.argv[2])

connection = sqlite3.connect(database)
connection.execute("PRAGMA foreign_keys = ON")
connection.executescript(migration.read_text(encoding="utf-8"))

version = connection.execute("PRAGMA user_version").fetchone()[0]
if version != 6:
    raise SystemExit(f"[FAIL] expected schema version 6, got {version}")

expected_run = (
    "run-0123456789abcdef0123456789abcdef",
    "dev-0123456789abcdef0123456789abcdef",
    "192.0.2.58",
    "fixture-provider",
    "2026-08-30T14:10:00Z",
    "2026-08-30T14:10:02Z",
    "success",
    None,
)
actual_run = connection.execute(
    """
    SELECT
        service_discovery_run_id,
        entity_id,
        address,
        provider,
        started_at,
        completed_at,
        outcome,
        detail
    FROM service_discovery_runs
    """
).fetchone()
if actual_run != expected_run:
    raise SystemExit(f"[FAIL] historical run changed during v6 migration: {actual_run!r}")

expected_observation = (
    "svc-0123456789abcdef0123456789abcdef",
    "dev-0123456789abcdef0123456789abcdef",
    "192.0.2.58",
    "tcp",
    22,
    "open",
    "ssh",
    '{"fixture":"v5-service-observation"}',
    "fixture-v5-service-observation-hash",
)
actual_observation = connection.execute(
    """
    SELECT
        service_observation_id,
        entity_id,
        address,
        protocol,
        port,
        state,
        service,
        payload_json,
        payload_hash
    FROM service_observations
    """
).fetchone()
if actual_observation != expected_observation:
    raise SystemExit(
        f"[FAIL] historical observation changed during v6 migration: "
        f"{actual_observation!r}"
    )

association = connection.execute(
    """
    SELECT service_discovery_run_id, service_observation_id
    FROM service_discovery_run_observations
    """
).fetchone()
expected_association = (
    "run-0123456789abcdef0123456789abcdef",
    "svc-0123456789abcdef0123456789abcdef",
)
if association != expected_association:
    raise SystemExit(
        f"[FAIL] historical run-observation association changed: {association!r}"
    )

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

inconclusive_run = "run-22222222222222222222222222222222"
connection.execute(
    run_sql,
    (
        inconclusive_run,
        "dev-0123456789abcdef0123456789abcdef",
        "192.0.2.58",
        "fixture-provider",
        "2026-08-30T14:20:00Z",
        "2026-08-30T14:21:00Z",
        "inconclusive",
        "bounded probing exhausted without authoritative conclusion",
    ),
)

links = connection.execute(
    """
    SELECT COUNT(*)
    FROM service_discovery_run_observations
    WHERE service_discovery_run_id = ?
    """,
    (inconclusive_run,),
).fetchone()[0]
if links != 0:
    raise SystemExit(
        f"[FAIL] inconclusive run unexpectedly has {links} observation associations"
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
    raise SystemExit(f"[FAIL] SQL constraints did not reject {label}")

must_reject(
    "unknown Service Discovery run outcome",
    run_sql,
    (
        "run-33333333333333333333333333333333",
        "dev-0123456789abcdef0123456789abcdef",
        "192.0.2.58",
        "fixture-provider",
        "2026-08-30T14:30:00Z",
        "2026-08-30T14:31:00Z",
        "mystery_outcome",
        "must be rejected",
    ),
)

must_reject(
    "unknown entity reference",
    run_sql,
    (
        "run-44444444444444444444444444444444",
        "dev-ffffffffffffffffffffffffffffffff",
        "192.0.2.58",
        "fixture-provider",
        "2026-08-30T14:40:00Z",
        "2026-08-30T14:41:00Z",
        "inconclusive",
        "must be rejected",
    ),
)

connection.commit()

foreign_keys = connection.execute("PRAGMA foreign_key_check").fetchall()
if foreign_keys:
    raise SystemExit(f"[FAIL] foreign key violations: {foreign_keys!r}")

integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
if integrity != "ok":
    raise SystemExit(f"[FAIL] integrity check failed: {integrity}")

connection.close()

print("[PASS] populated v5 database migrated to v6")
print("[PASS] historical Service Discovery run preserved")
print("[PASS] historical endpoint observation preserved")
print("[PASS] historical run-observation association preserved")
print("[PASS] inconclusive run outcome accepted with zero associations")
print("[PASS] unknown run outcome rejected")
print("[PASS] Service Discovery run foreign key preserved")
print("[PASS] Service Discovery migration v6 integrity valid")
PY

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery migration v6 regression PASSED"
