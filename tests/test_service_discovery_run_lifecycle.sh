#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
ORCHESTRATOR="${APP_ROOT}/core/service_discovery/orchestrate.py"
TMP_ROOT="$(mktemp -d /tmp/hls-service-discovery-run-lifecycle.XXXXXX)"
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
echo "HomeLab Sentinel Service Discovery run lifecycle regression"
echo
echo "Database : ${DB}"
echo

python3 - "${DB}" <<'PY'
import sqlite3
import sys
from pathlib import Path

db = Path(sys.argv[1])
app = Path("/opt/homelab-sentinel/app")
schema = app / "core/inventory/schema.sql"
migrations = app / "core/inventory/migrations"

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

version = connection.execute("PRAGMA user_version").fetchone()[0]
if version < 5:
    raise SystemExit(f"[FAIL] lifecycle regression requires schema v5, got v{version}")

entity_id = "dev-0123456789abcdef0123456789abcdef"
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
connection.commit()
connection.close()
PY

pass "synthetic schema v5 inventory fixture created"

python3 - "${DB}" "${ORCHESTRATOR}" <<'PY'
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path

database = Path(sys.argv[1])
orchestrator_path = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "hls_sd_lifecycle_observed",
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
    "--entity-id", entity_id,
    "--address", address,
    "--database", str(database),
]

result = module.main()
if result != 0:
    raise SystemExit(f"[FAIL] observed run returned {result}")

connection = sqlite3.connect(database)

runs = connection.execute(
    """
    SELECT service_discovery_run_id, outcome
    FROM service_discovery_runs
    ORDER BY completed_at, service_discovery_run_id
    """
).fetchall()

observations = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]

associations = connection.execute(
    "SELECT COUNT(*) FROM service_discovery_run_observations"
).fetchone()[0]

connection.close()

if len(runs) != 1 or runs[0][1] != "success":
    raise SystemExit(
        f"[FAIL] expected one successful observed run, got {runs!r}"
    )

if observations != 2:
    raise SystemExit(
        f"[FAIL] expected two observations, got {observations}"
    )

if associations != 2:
    raise SystemExit(
        f"[FAIL] expected two run-observation associations, got {associations}"
    )
PY

pass "successful observed run records one success boundary"
pass "successful observed run associates both endpoint observations"

python3 - "${DB}" "${ORCHESTRATOR}" <<'PY'
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path

database = Path(sys.argv[1])
orchestrator_path = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "hls_sd_lifecycle_duplicate_run",
    orchestrator_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

entity_id = "dev-0123456789abcdef0123456789abcdef"
address = "192.0.2.58"

provider_output = json.dumps({
    "schema_version": "1.0",
    "entity_id": entity_id,
    "provider": "fixture-provider",
    "observed_at": "2026-08-30T14:05:00Z",
    "address": address,
    "protocol": "tcp",
    "port": 22,
    "state": "open",
    "service": "ssh",
}, separators=(",", ":"), sort_keys=True) + "\n"

module.resolve_provider = lambda: "fixture-provider"
module.resolve_entrypoint = lambda provider: Path("/fixture/discover-services")
module.invoke_provider = (
    lambda entrypoint, supplied_entity_id, supplied_address: provider_output
)

connection = sqlite3.connect(database)
before_runs = connection.execute(
    "SELECT COUNT(*) FROM service_discovery_runs"
).fetchone()[0]
before_observations = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]
before_links = connection.execute(
    "SELECT COUNT(*) FROM service_discovery_run_observations"
).fetchone()[0]
connection.close()

sys.argv = [
    str(orchestrator_path),
    "--entity-id", entity_id,
    "--address", address,
    "--database", str(database),
]

result = module.main()
if result != 0:
    raise SystemExit(
        f"[FAIL] repeated canonical observation run returned {result}"
    )

connection = sqlite3.connect(database)
after_runs = connection.execute(
    "SELECT COUNT(*) FROM service_discovery_runs"
).fetchone()[0]
after_observations = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]
after_links = connection.execute(
    "SELECT COUNT(*) FROM service_discovery_run_observations"
).fetchone()[0]

matching_observation = connection.execute(
    """
    SELECT service_observation_id
    FROM service_observations
    WHERE entity_id = ?
      AND address = ?
      AND protocol = 'tcp'
      AND port = 22
      AND observed_at = '2026-08-30T14:05:00Z'
    """,
    (entity_id, address),
).fetchone()

if matching_observation is None:
    raise SystemExit(
        "[FAIL] canonical repeated observation is missing"
    )

linked_runs = connection.execute(
    """
    SELECT COUNT(DISTINCT service_discovery_run_id)
    FROM service_discovery_run_observations
    WHERE service_observation_id = ?
    """,
    (matching_observation[0],),
).fetchone()[0]

connection.close()

if after_runs != before_runs + 1:
    raise SystemExit(
        f"[FAIL] repeated evidence did not add one run: "
        f"{before_runs} -> {after_runs}"
    )

if after_observations != before_observations:
    raise SystemExit(
        "[FAIL] repeated canonical evidence created a duplicate observation"
    )

if after_links != before_links + 1:
    raise SystemExit(
        f"[FAIL] repeated evidence did not add one association: "
        f"{before_links} -> {after_links}"
    )

if linked_runs != 2:
    raise SystemExit(
        f"[FAIL] canonical observation expected in two runs, got {linked_runs}"
    )
PY

pass "repeated canonical evidence remains deduplicated"
pass "deduplicated observation can belong to multiple successful runs"

python3 - "${DB}" "${ORCHESTRATOR}" <<'PY'
import importlib.util
import sqlite3
import sys
from pathlib import Path

database = Path(sys.argv[1])
orchestrator_path = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "hls_sd_lifecycle_empty",
    orchestrator_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

entity_id = "dev-0123456789abcdef0123456789abcdef"
address = "192.0.2.58"

module.resolve_provider = lambda: "fixture-provider"
module.resolve_entrypoint = lambda provider: Path("/fixture/discover-services")
module.invoke_provider = (
    lambda entrypoint, supplied_entity_id, supplied_address: ""
)

connection = sqlite3.connect(database)
before_runs = connection.execute(
    "SELECT COUNT(*) FROM service_discovery_runs"
).fetchone()[0]
before_observations = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]
connection.close()

sys.argv = [
    str(orchestrator_path),
    "--entity-id", entity_id,
    "--address", address,
    "--database", str(database),
]

result = module.main()
if result != 0:
    raise SystemExit(f"[FAIL] empty successful run returned {result}")

connection = sqlite3.connect(database)
after_runs = connection.execute(
    "SELECT COUNT(*) FROM service_discovery_runs"
).fetchone()[0]
after_observations = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]

latest = connection.execute(
    """
    SELECT service_discovery_run_id, outcome
    FROM service_discovery_runs
    ORDER BY completed_at DESC, service_discovery_run_id DESC
    LIMIT 1
    """
).fetchone()

links = 0
if latest is not None:
    links = connection.execute(
        """
        SELECT COUNT(*)
        FROM service_discovery_run_observations
        WHERE service_discovery_run_id = ?
        """,
        (latest[0],),
    ).fetchone()[0]

connection.close()

if after_runs != before_runs + 1:
    raise SystemExit(
        f"[FAIL] successful empty run did not add one run: {before_runs} -> {after_runs}"
    )

if latest is None or latest[1] != "success":
    raise SystemExit(
        f"[FAIL] successful empty inspection lacks success run: {latest!r}"
    )

if after_observations != before_observations:
    raise SystemExit(
        "[FAIL] successful empty inspection changed observation history"
    )

if links != 0:
    raise SystemExit(
        f"[FAIL] successful empty inspection has {links} associations"
    )
PY

pass "successful empty inspection records success with zero associations"
pass "successful empty inspection preserves historical observations"

python3 - "${DB}" "${ORCHESTRATOR}" <<'PY'
import importlib.util
import sqlite3
import sys
from pathlib import Path

database = Path(sys.argv[1])
orchestrator_path = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "hls_sd_lifecycle_provider_error",
    orchestrator_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

entity_id = "dev-0123456789abcdef0123456789abcdef"
address = "192.0.2.58"

module.resolve_provider = lambda: "fixture-provider"
module.resolve_entrypoint = lambda provider: Path("/fixture/discover-services")

def fail_provider(entrypoint, supplied_entity_id, supplied_address):
    raise RuntimeError("synthetic provider failure")

module.invoke_provider = fail_provider

connection = sqlite3.connect(database)
before_runs = connection.execute(
    "SELECT COUNT(*) FROM service_discovery_runs"
).fetchone()[0]
before_observations = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]
connection.close()

sys.argv = [
    str(orchestrator_path),
    "--entity-id", entity_id,
    "--address", address,
    "--database", str(database),
]

result = module.main()
if result == 0:
    raise SystemExit("[FAIL] provider failure unexpectedly succeeded")

connection = sqlite3.connect(database)
after_runs = connection.execute(
    "SELECT COUNT(*) FROM service_discovery_runs"
).fetchone()[0]
after_observations = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]

latest = connection.execute(
    """
    SELECT service_discovery_run_id, outcome
    FROM service_discovery_runs
    ORDER BY completed_at DESC, service_discovery_run_id DESC
    LIMIT 1
    """
).fetchone()

links = 0
if latest is not None:
    links = connection.execute(
        """
        SELECT COUNT(*)
        FROM service_discovery_run_observations
        WHERE service_discovery_run_id = ?
        """,
        (latest[0],),
    ).fetchone()[0]

connection.close()

if after_runs != before_runs + 1:
    raise SystemExit(
        f"[FAIL] provider failure did not add one run: {before_runs} -> {after_runs}"
    )

if latest is None or latest[1] != "provider_error":
    raise SystemExit(
        f"[FAIL] provider failure lacks provider_error run: {latest!r}"
    )

if after_observations != before_observations:
    raise SystemExit(
        "[FAIL] provider failure changed positive observation history"
    )

if links != 0:
    raise SystemExit(
        f"[FAIL] provider failure has {links} observation associations"
    )
PY

pass "provider failure records provider_error with zero associations"
pass "provider failure cannot masquerade as endpoint absence"

python3 - "${DB}" "${ORCHESTRATOR}" <<'PY'
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path

database = Path(sys.argv[1])
orchestrator_path = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "hls_sd_lifecycle_invalid",
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
        "observed_at": "2026-08-30T14:30:00Z",
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
        "observed_at": "2026-08-30T14:30:00Z",
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

connection = sqlite3.connect(database)
before_runs = connection.execute(
    "SELECT COUNT(*) FROM service_discovery_runs"
).fetchone()[0]
before_observations = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]
connection.close()

sys.argv = [
    str(orchestrator_path),
    "--entity-id", entity_id,
    "--address", address,
    "--database", str(database),
]

result = module.main()
if result == 0:
    raise SystemExit("[FAIL] invalid evidence unexpectedly succeeded")

connection = sqlite3.connect(database)
after_runs = connection.execute(
    "SELECT COUNT(*) FROM service_discovery_runs"
).fetchone()[0]
after_observations = connection.execute(
    "SELECT COUNT(*) FROM service_observations"
).fetchone()[0]

latest = connection.execute(
    """
    SELECT service_discovery_run_id, outcome
    FROM service_discovery_runs
    ORDER BY completed_at DESC, service_discovery_run_id DESC
    LIMIT 1
    """
).fetchone()

links = 0
if latest is not None:
    links = connection.execute(
        """
        SELECT COUNT(*)
        FROM service_discovery_run_observations
        WHERE service_discovery_run_id = ?
        """,
        (latest[0],),
    ).fetchone()[0]

connection.close()

if after_runs != before_runs + 1:
    raise SystemExit(
        f"[FAIL] invalid evidence did not add one run: {before_runs} -> {after_runs}"
    )

if latest is None or latest[1] != "invalid_evidence":
    raise SystemExit(
        f"[FAIL] invalid evidence lacks invalid_evidence run: {latest!r}"
    )

if after_observations != before_observations:
    raise SystemExit(
        "[FAIL] invalid evidence partially persisted positive observations"
    )

if links != 0:
    raise SystemExit(
        f"[FAIL] invalid evidence has {links} observation associations"
    )
PY

pass "invalid evidence records invalid_evidence with zero associations"
pass "invalid evidence preserves observation batch atomicity"

python3 - "${DB}" <<'PY'
import sqlite3
import sys

database = sys.argv[1]
connection = sqlite3.connect(database)
connection.execute("PRAGMA foreign_keys = ON")

foreign_keys = connection.execute(
    "PRAGMA foreign_key_check"
).fetchall()

integrity = connection.execute(
    "PRAGMA integrity_check"
).fetchone()[0]

connection.close()

if foreign_keys:
    raise SystemExit(
        f"[FAIL] foreign key violations: {foreign_keys!r}"
    )

if integrity != "ok":
    raise SystemExit(
        f"[FAIL] integrity check failed: {integrity}"
    )
PY

pass "Service Discovery lifecycle foreign keys are valid"
pass "Service Discovery lifecycle database integrity is valid"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery run lifecycle regression PASSED"
