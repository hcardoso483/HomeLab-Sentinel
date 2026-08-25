#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
EVALUATOR="${APP_ROOT}/core/monitoring/evaluate.py"
HLS="${APP_ROOT}/installer/hls"
TMP_ROOT="$(mktemp -d /tmp/hls-monitoring-health-test.XXXXXX)"
DB="${TMP_ROOT}/inventory.db"

cleanup() { rm -rf "${TMP_ROOT}"; }
trap cleanup EXIT

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

[[ -x "${EVALUATOR}" ]] || fail "Monitoring evaluator missing or not executable"
[[ -x "${HLS}" ]] || fail "HLS CLI missing or not executable"

echo "HomeLab Sentinel Monitoring health regression test"
echo
echo "Database : ${DB}"
echo

python3 - "${DB}" <<'PY'
import hashlib, json, sqlite3, sys
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

entities = [
    "dev-healthy",
    "dev-one-failure",
    "dev-down",
    "dev-conflict",
    "dev-stale",
    "dev-unknown",
]
for entity_id in entities:
    con.execute(
        '''
        INSERT INTO entities (
            entity_id, entity_type, created_at, updated_at
        )
        VALUES (?, 'device',
                '2026-08-25T08:00:00Z',
                '2026-08-25T08:00:00Z')
        ''',
        (entity_id,),
    )

def add(entity_id, checked_at, status, suffix):
    record = {
        "schema_version": "1.0",
        "entity_id": entity_id,
        "provider": "prometheus",
        "check_type": "reachability",
        "target": "192.0.2.1",
        "checked_at": checked_at,
        "status": status,
        "latency_ms": 1.0 if status == "success" else None,
    }
    payload_json = json.dumps(record, separators=(",", ":"), sort_keys=True)
    payload_hash = hashlib.sha256(payload_json.encode()).hexdigest()
    con.execute(
        '''
        INSERT INTO monitoring_observations (
            monitoring_observation_id, entity_id, schema_version,
            provider, check_type, target, checked_at, received_at,
            status, latency_ms, payload_json, payload_hash
        )
        VALUES (?, ?, '1.0', 'prometheus', 'reachability',
                '192.0.2.1', ?, ?, ?, ?, ?, ?)
        ''',
        (
            f"mon-{entity_id}-{suffix}",
            entity_id,
            checked_at,
            checked_at,
            status,
            record["latency_ms"],
            payload_json,
            payload_hash,
        ),
    )

add("dev-healthy", "2026-08-25T08:09:00Z", "success", "1")
add("dev-one-failure", "2026-08-25T08:09:00Z", "failed", "1")
add("dev-down", "2026-08-25T08:09:00Z", "failed", "1")
add("dev-down", "2026-08-25T08:08:00Z", "failed", "2")
add("dev-conflict", "2026-08-25T08:09:00Z", "failed", "1")
add("dev-conflict", "2026-08-25T08:08:00Z", "success", "2")
add("dev-stale", "2026-08-25T07:50:00Z", "success", "1")
add("dev-unknown", "2026-08-25T08:09:00Z", "unknown", "1")

con.commit()
con.close()
PY

pass "deterministic Monitoring health fixture created"

JSON_OUT="${TMP_ROOT}/health.jsonl"

"${EVALUATOR}"   --database "${DB}"   --now "2026-08-25T08:10:00Z"   --freshness-seconds 300   --json >"${JSON_OUT}"

python3 - "${JSON_OUT}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    rows = [json.loads(line) for line in handle if line.strip()]

states = {row["entity_id"]: row["state"] for row in rows}
expected = {
    "dev-healthy": "HEALTHY",
    "dev-one-failure": "DEGRADED",
    "dev-down": "DOWN",
    "dev-conflict": "DEGRADED",
    "dev-stale": "UNKNOWN",
    "dev-unknown": "UNKNOWN",
}
if states != expected:
    raise SystemExit(f"unexpected Monitoring health states: {states}")
PY

pass "fresh success -> HEALTHY"
pass "single fresh failure -> DEGRADED"
pass "repeated fresh failures -> DOWN"
pass "conflicting fresh evidence -> DEGRADED"
pass "stale evidence -> UNKNOWN"
pass "insufficient fresh evidence -> UNKNOWN"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Monitoring health regression PASSED"
