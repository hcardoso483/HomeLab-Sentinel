#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
TMP_ROOT="$(mktemp -d /tmp/hls-monitoring-observations-test.XXXXXX)"
DB="${TMP_ROOT}/inventory.db"

cleanup() {
    rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

echo "HomeLab Sentinel Monitoring observation regression test"
echo
echo "Database : ${DB}"
echo

python3 - "${DB}" <<'PY'
import sqlite3
import sys
from pathlib import Path

db = sys.argv[1]
schema = Path("/opt/homelab-sentinel/app/core/inventory/schema.sql")
migrations = Path("/opt/homelab-sentinel/app/core/inventory/migrations")

con = sqlite3.connect(db)
con.execute("PRAGMA foreign_keys = ON")
con.executescript(schema.read_text())

for version, path in sorted(
    (int(p.name.split("_", 1)[0]), p)
    for p in migrations.glob("*.sql")
):
    current = con.execute("PRAGMA user_version").fetchone()[0]
    if version == current + 1:
        con.executescript(path.read_text())

con.execute(
    """
    INSERT INTO entities (entity_id, entity_type, created_at, updated_at)
    VALUES ('dev-monitoring-test', 'device',
            '2026-08-25T07:00:00Z', '2026-08-25T07:00:00Z')
    """
)
con.commit()
con.close()
PY
pass "schema v3 fixture created"

OBS='{"schema_version":"1.0","entity_id":"dev-monitoring-test","provider":"prometheus","check_type":"reachability","target":"192.168.1.20","checked_at":"2026-08-25T07:30:00Z","status":"success","latency_ms":0.84}'

printf '%s\n' "${OBS}" |
    "${APP_ROOT}/core/monitoring/store.py" --database "${DB}" >/dev/null 2>&1
pass "valid Monitoring observation stored"

COUNT="$(python3 - "${DB}" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
print(con.execute("SELECT COUNT(*) FROM monitoring_observations").fetchone()[0])
PY
)"
[[ "${COUNT}" == "1" ]] || fail "expected one Monitoring observation"
pass "Monitoring evidence uses dedicated table"

printf '%s\n' "${OBS}" |
    "${APP_ROOT}/core/monitoring/store.py" --database "${DB}" >/dev/null 2>&1

COUNT="$(python3 - "${DB}" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
print(con.execute("SELECT COUNT(*) FROM monitoring_observations").fetchone()[0])
PY
)"
[[ "${COUNT}" == "1" ]] || fail "duplicate observation was stored"
pass "exact duplicate ingestion is idempotent"

BAD_STATUS='{"schema_version":"1.0","entity_id":"dev-monitoring-test","provider":"prometheus","check_type":"reachability","target":"192.168.1.20","checked_at":"2026-08-25T07:31:00Z","status":"broken","latency_ms":null}'
if printf '%s\n' "${BAD_STATUS}" |
    "${APP_ROOT}/core/monitoring/store.py" --database "${DB}" >/dev/null 2>&1; then
    fail "invalid status was accepted"
fi
pass "invalid Monitoring status rejected"

BAD_ENTITY='{"schema_version":"1.0","entity_id":"dev-does-not-exist","provider":"prometheus","check_type":"reachability","target":"192.168.1.20","checked_at":"2026-08-25T07:32:00Z","status":"failed","latency_ms":null}'
if printf '%s\n' "${BAD_ENTITY}" |
    "${APP_ROOT}/core/monitoring/store.py" --database "${DB}" >/dev/null 2>&1; then
    fail "unknown entity was accepted"
fi
pass "Monitoring evidence requires canonical entity"

NEGATIVE='{"schema_version":"1.0","entity_id":"dev-monitoring-test","provider":"prometheus","check_type":"reachability","target":"192.168.1.20","checked_at":"2026-08-25T07:33:00Z","status":"success","latency_ms":-1}'
if printf '%s\n' "${NEGATIVE}" |
    "${APP_ROOT}/core/monitoring/store.py" --database "${DB}" >/dev/null 2>&1; then
    fail "negative latency was accepted"
fi
pass "negative latency rejected"

VERSION="$(python3 - "${DB}" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
print(con.execute("PRAGMA user_version").fetchone()[0])
PY
)"
[[ "${VERSION}" == "4" ]] || fail "expected schema version 4, got ${VERSION}"
pass "inventory schema version is v4"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Monitoring observation regression PASSED"
