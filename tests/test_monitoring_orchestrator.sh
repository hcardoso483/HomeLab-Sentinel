#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
ORCH="${APP_ROOT}/core/monitoring/orchestrate.py"
TMP_ROOT="$(mktemp -d /tmp/hls-monitoring-orchestrator-test.XXXXXX)"
DB="${TMP_ROOT}/inventory.db"

cleanup() { rm -rf "${TMP_ROOT}"; }
trap cleanup EXIT

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

echo "HomeLab Sentinel Monitoring orchestrator regression test"
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

for entity_id in ("dev-orch-a", "dev-orch-b", "dev-orch-skip"):
    con.execute(
        """
        INSERT INTO entities (
            entity_id, entity_type, created_at, updated_at
        )
        VALUES (?, 'device',
                '2026-08-25T12:00:00Z',
                '2026-08-25T12:00:00Z')
        """,
        (entity_id,),
    )

con.commit()
con.close()
PY

pass "schema v3 fixture created"

python3 - "${DB}" "${ORCH}" <<'PY'
import importlib.util
import sys
from pathlib import Path

db = Path(sys.argv[1])
path = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location("hls_orchestrate", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

targets = [
    {
        "schema_version": "1.0",
        "entity_id": "dev-orch-a",
        "entity_type": "device",
        "endpoints": {"ip_addresses": ["192.0.2.10"], "hostname": None},
        "eligible": True,
        "state": "UNKNOWN",
    },
    {
        "schema_version": "1.0",
        "entity_id": "dev-orch-b",
        "entity_type": "device",
        "endpoints": {"ip_addresses": ["192.0.2.11"], "hostname": None},
        "eligible": True,
        "state": "UNKNOWN",
    },
    {
        "schema_version": "1.0",
        "entity_id": "dev-orch-skip",
        "entity_type": "device",
        "endpoints": {"ip_addresses": [], "hostname": None},
        "eligible": False,
        "state": "UNKNOWN",
    },
]

module.resolve_provider = lambda: "fixture-provider"
module.resolve_adapter = lambda provider: Path("/fixture/observe")
module.load_targets = lambda database: targets

def fake_adapter(adapter, target, endpoint):
    if target["entity_id"] == "dev-orch-b":
        return None, "fixture adapter failure"

    return {
        "schema_version": "1.0",
        "entity_id": target["entity_id"],
        "provider": "fixture-provider",
        "check_type": "reachability",
        "target": endpoint,
        "checked_at": "2026-08-25T12:05:00Z",
        "status": "success",
        "latency_ms": None,
    }, None

module.invoke_adapter = fake_adapter
module.persist_observation = lambda database, observation: ("SUCCESS", None)

summary = module.collect(db)

assert summary["provider"] == "fixture-provider"
assert summary["targets_considered"] == 3
assert summary["targets_attempted"] == 2
assert summary["success"] == 1
assert summary["skipped"] == 1
assert summary["adapter_error"] == 1
assert summary["provider_error"] == 0
assert summary["invalid_evidence"] == 0
assert summary["store_error"] == 0

outcomes = {
    row["entity_id"]: row["outcome"]
    for row in summary["outcomes"]
    if row["entity_id"] is not None
}

assert outcomes == {
    "dev-orch-a": "SUCCESS",
    "dev-orch-b": "ADAPTER_ERROR",
    "dev-orch-skip": "SKIPPED",
}
PY

pass "orchestrator preserves independent target outcomes"
pass "eligible targets attempted"
pass "ineligible target skipped"
pass "target adapter failure isolated"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Monitoring orchestrator regression PASSED"
