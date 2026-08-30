#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
ORCHESTRATOR="${APP_ROOT}/core/service_discovery/orchestrate.py"
TMP_ROOT="$(mktemp -d /tmp/hls-service-discovery-persistence-integration.XXXXXX)"
DB="${TMP_ROOT}/inventory.db"

cleanup() {
    rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo
echo "HomeLab Sentinel Service Discovery provider-to-persistence regression"
echo
echo "Database : ${DB}"
echo

python3 - "${DB}" <<'PY'
import sqlite3
import sys
from pathlib import Path

db = sys.argv[1]
app_root = Path("/opt/homelab-sentinel/app")
schema = app_root / "core" / "inventory" / "schema.sql"
migrations = app_root / "core" / "inventory" / "migrations"

connection = sqlite3.connect(db)
connection.execute("PRAGMA foreign_keys = ON")
connection.executescript(schema.read_text(encoding="utf-8"))

for version, path in sorted(
    (int(item.name.split("_", 1)[0]), item)
    for item in migrations.glob("*.sql")
):
    current = connection.execute("PRAGMA user_version").fetchone()[0]
    if version == current + 1:
        connection.executescript(path.read_text(encoding="utf-8"))

entity_id = "dev-0123456789abcdef0123456789abcdef"
connection.execute(
    """
    INSERT INTO entities (
        entity_id,
        entity_type,
        created_at,
        updated_at
    )
    VALUES (?, 'device',
            '2026-08-30T14:00:00Z',
            '2026-08-30T14:00:00Z')
    """,
    (entity_id,),
)

connection.commit()
connection.close()
PY

pass "synthetic inventory fixture created"

python3 - "${DB}" "${ORCHESTRATOR}" <<'PY'
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path

database = Path(sys.argv[1])
orchestrator_path = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "hls_service_discovery_orchestrate",
    orchestrator_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

entity_id = "dev-0123456789abcdef0123456789abcdef"
address = "192.0.2.58"

provider_output = "\n".join([
    json.dumps({
        "schema_version": "1.0",
        "entity_id": entity_id,
        "provider": "fixture-provider",
        "observed_at": "2026-08-30T14:05:00Z",
        "address": address,
        "protocol": "tcp",
        "port": 22,
        "state": "open",
        "service": "ssh",
    }, separators=(",", ":"), sort_keys=True),
    json.dumps({
        "schema_version": "1.0",
        "entity_id": entity_id,
        "provider": "fixture-provider",
        "observed_at": "2026-08-30T14:05:00Z",
        "address": address,
        "protocol": "tcp",
        "port": 8006,
        "state": "open",
        "service": None,
    }, separators=(",", ":"), sort_keys=True),
]) + "\n"

module.resolve_provider = lambda: "fixture-provider"
module.resolve_entrypoint = lambda provider: Path("/fixture/discover-services")
module.invoke_provider = (
    lambda entrypoint, supplied_entity_id, supplied_address: provider_output
)

sys.argv = [
    str(orchestrator_path),
    "--entity-id",
    entity_id,
    "--address",
    address,
    "--database",
    str(database),
]

result = module.main()
if result != 0:
    raise SystemExit(
        f"[FAIL] orchestrator returned {result}; expected successful persistence"
    )

connection = sqlite3.connect(database)
rows = connection.execute(
    """
    SELECT entity_id, provider, address, protocol, port, state, service
    FROM service_observations
    ORDER BY port
    """
).fetchall()
connection.close()

expected = [
    (
        entity_id,
        "fixture-provider",
        address,
        "tcp",
        22,
        "open",
        "ssh",
    ),
    (
        entity_id,
        "fixture-provider",
        address,
        "tcp",
        8006,
        "open",
        None,
    ),
]

if rows != expected:
    raise SystemExit(
        f"[FAIL] expected persisted provider observations {expected!r}, got {rows!r}"
    )
PY

pass "canonical provider NDJSON reaches Service Discovery persistence"
pass "multiple endpoint observations persist as one provider batch"

python3 - "${DB}" "${ORCHESTRATOR}" <<'PY'
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path

database = Path(sys.argv[1])
orchestrator_path = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "hls_service_discovery_orchestrate_atomic",
    orchestrator_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

entity_id = "dev-0123456789abcdef0123456789abcdef"
address = "192.0.2.58"

connection = sqlite3.connect(database)
before = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]
connection.close()

provider_output = "\n".join([
    json.dumps({
        "schema_version": "1.0",
        "entity_id": entity_id,
        "provider": "fixture-provider",
        "observed_at": "2026-08-30T14:06:00Z",
        "address": address,
        "protocol": "tcp",
        "port": 443,
        "state": "open",
        "service": "https",
    }, separators=(",", ":"), sort_keys=True),
    json.dumps({
        "schema_version": "1.0",
        "entity_id": entity_id,
        "provider": "fixture-provider",
        "observed_at": "2026-08-30T14:06:00Z",
        "address": address,
        "protocol": "udp",
        "port": 53,
        "state": "open",
        "service": "domain",
    }, separators=(",", ":"), sort_keys=True),
]) + "\n"

module.resolve_provider = lambda: "fixture-provider"
module.resolve_entrypoint = lambda provider: Path("/fixture/discover-services")
module.invoke_provider = (
    lambda entrypoint, supplied_entity_id, supplied_address: provider_output
)

sys.argv = [
    str(orchestrator_path),
    "--entity-id",
    entity_id,
    "--address",
    address,
    "--database",
    str(database),
]

result = module.main()
if result == 0:
    raise SystemExit(
        "[FAIL] invalid provider batch unexpectedly succeeded"
    )

connection = sqlite3.connect(database)
after = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]
connection.close()

if after != before:
    raise SystemExit(
        f"[FAIL] failed provider batch changed row count from {before} to {after}"
    )
PY

pass "invalid provider evidence fails orchestration"
pass "failed provider batch preserves persistence atomicity"

python3 - "${DB}" "${ORCHESTRATOR}" <<'PY'
import importlib.util
import sqlite3
import sys
from pathlib import Path

database = Path(sys.argv[1])
orchestrator_path = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "hls_service_discovery_orchestrate_empty",
    orchestrator_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

entity_id = "dev-0123456789abcdef0123456789abcdef"
address = "192.0.2.58"

connection = sqlite3.connect(database)
before = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]
connection.close()

module.resolve_provider = lambda: "fixture-provider"
module.resolve_entrypoint = lambda provider: Path("/fixture/discover-services")
module.invoke_provider = (
    lambda entrypoint, supplied_entity_id, supplied_address: ""
)

sys.argv = [
    str(orchestrator_path),
    "--entity-id",
    entity_id,
    "--address",
    address,
    "--database",
    str(database),
]

result = module.main()
if result != 0:
    raise SystemExit(
        f"[FAIL] empty provider batch returned {result}; expected success"
    )

connection = sqlite3.connect(database)
after = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]
connection.close()

if after != before:
    raise SystemExit(
        f"[FAIL] empty provider batch changed row count from {before} to {after}"
    )
PY

pass "empty provider stream is a successful empty batch"
pass "zero observations create no additional service evidence"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery provider-to-persistence regression PASSED"
