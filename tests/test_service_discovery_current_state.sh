#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURRENT="${ROOT}/core/service_discovery/current.py"

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

pass() {
    printf '[PASS] %s\n' "$*"
}

[[ -f "${CURRENT}" ]] || fail "current-state read model not implemented yet: ${CURRENT}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
DB="${TMP}/inventory.db"

export ROOT DB

python3 - <<'PY'
import os
import sqlite3
from pathlib import Path

root = Path(os.environ["ROOT"])
db = os.environ["DB"]

conn = sqlite3.connect(db)
conn.execute("PRAGMA foreign_keys = ON")

# Minimal canonical identity table required by the Service Discovery FKs.
conn.execute("""
CREATE TABLE entities (
    entity_id TEXT PRIMARY KEY
)
""")

entity = "dev-" + ("a" * 32)
conn.execute("INSERT INTO entities(entity_id) VALUES (?)", (entity,))

# Apply production migrations 004 and 005 exactly as shipped.
for name in (
    "004_service_observations.sql",
    "005_service_discovery_runs.sql",
):
    sql = (root / "core" / "inventory" / "migrations" / name).read_text()
    conn.executescript(sql)

conn.commit()
conn.close()
PY

# Exercise the read model through a deliberately small public CLI boundary.
# Expected implementation:
#   python3 core/service_discovery/current.py --database DB --entity-id ENTITY
query_current() {
    python3 "${CURRENT}" \
        --database "${DB}" \
        --entity-id "dev-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}

python3 - <<'PY'
import hashlib
import json
import os
import sqlite3

db = os.environ["DB"]
entity = "dev-" + ("a" * 32)

def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"))

def add_run(conn, run_id, address, started, completed, outcome, detail=None):
    conn.execute(
        """
        INSERT INTO service_discovery_runs(
            service_discovery_run_id,
            entity_id,
            address,
            provider,
            started_at,
            completed_at,
            outcome,
            detail
        ) VALUES (?, ?, ?, 'nmap', ?, ?, ?, ?)
        """,
        (run_id, entity, address, started, completed, outcome, detail),
    )

def add_observation(conn, obs_id, run_id, address, port, service, observed_at):
    payload = {
        "address": address,
        "entity_id": entity,
        "observed_at": observed_at,
        "port": port,
        "protocol": "tcp",
        "provider": "nmap",
        "schema_version": "1.0",
        "service": service,
        "state": "open",
    }
    payload_json = canonical(payload)
    payload_hash = hashlib.sha256(payload_json.encode()).hexdigest()
    conn.execute(
        """
        INSERT INTO service_observations(
            service_observation_id,
            schema_version,
            entity_id,
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
        ) VALUES (?, '1.0', ?, 'nmap', ?, ?, ?, 'tcp', ?, 'open', ?, ?, ?)
        """,
        (
            obs_id,
            entity,
            observed_at,
            observed_at,
            address,
            port,
            service,
            payload_json,
            payload_hash,
        ),
    )
    conn.execute(
        """
        INSERT INTO service_discovery_run_observations(
            service_discovery_run_id,
            service_observation_id
        ) VALUES (?, ?)
        """,
        (run_id, obs_id),
    )

conn = sqlite3.connect(db)
conn.execute("PRAGMA foreign_keys = ON")

# Run 1: successful inspection sees HTTP on a deliberately non-default port.
add_run(
    conn,
    "run-00000000000000000000000000000001",
    "192.0.2.10",
    "2026-08-30T10:00:00+00:00",
    "2026-08-30T10:00:10+00:00",
    "success",
)
add_observation(
    conn,
    "svc-00000000000000000000000000000001",
    "run-00000000000000000000000000000001",
    "192.0.2.10",
    8099,
    "http",
    "2026-08-30T10:00:05+00:00",
)

conn.commit()
conn.close()
PY

OUT1="$(query_current)" || fail "read model failed for first successful observation"
export OUT1
python3 - <<'PY'
import json, os, sys

rows = json.loads(os.environ["OUT1"])
if not isinstance(rows, list) or len(rows) != 1:
    sys.exit(f"expected exactly one endpoint, got {rows!r}")

row = rows[0]
expected = {
    "entity_id": "dev-" + ("a" * 32),
    "address": "192.0.2.10",
    "protocol": "tcp",
    "port": 8099,
    "service": "http",
    "endpoint_state": "OBSERVED",
    "last_observed_at": "2026-08-30T10:00:05+00:00",
}
for key, value in expected.items():
    if row.get(key) != value:
        sys.exit(f"{key}: expected {value!r}, got {row.get(key)!r}")

inspection = row.get("latest_inspection")
if not isinstance(inspection, dict):
    sys.exit("latest_inspection missing")
if inspection.get("outcome") != "success":
    sys.exit(f"expected latest inspection success, got {inspection!r}")
if inspection.get("completed_at") != "2026-08-30T10:00:10+00:00":
    sys.exit(f"unexpected latest inspection timestamp: {inspection!r}")

# Application identity must not be guessed from port 8099.
for forbidden in ("application", "application_name", "product", "device_service"):
    if forbidden in row:
        sys.exit(f"read model invented/prematurely exposed {forbidden}: {row!r}")
if "agent dvr" in json.dumps(row).lower():
    sys.exit(f"port 8099 was incorrectly mapped to Agent DVR: {row!r}")
PY
pass "successful endpoint is OBSERVED and non-default HTTP remains evidence, not an application guess"

python3 - <<'PY'
import os, sqlite3

db = os.environ["DB"]
entity = "dev-" + ("a" * 32)
conn = sqlite3.connect(db)
conn.execute("PRAGMA foreign_keys = ON")
conn.execute(
    """
    INSERT INTO service_discovery_runs(
        service_discovery_run_id, entity_id, address, provider,
        started_at, completed_at, outcome, detail
    ) VALUES (?, ?, ?, 'nmap', ?, ?, 'success', NULL)
    """,
    (
        "run-00000000000000000000000000000002",
        entity,
        "192.0.2.10",
        "2026-08-30T10:15:00+00:00",
        "2026-08-30T10:15:10+00:00",
    ),
)
conn.commit()
conn.close()
PY

OUT2="$(query_current)" || fail "read model failed after successful empty inspection"
export OUT2
python3 - <<'PY'
import json, os, sys
rows = json.loads(os.environ["OUT2"])
if len(rows) != 1:
    sys.exit(f"historical endpoint disappeared: {rows!r}")
row = rows[0]
if row.get("endpoint_state") != "STALE":
    sys.exit(f"expected STALE after later successful miss, got {row!r}")
if row.get("last_observed_at") != "2026-08-30T10:00:05+00:00":
    sys.exit(f"last_observed_at was not preserved: {row!r}")
inspection = row.get("latest_inspection", {})
if inspection.get("outcome") != "success":
    sys.exit(f"expected latest inspection success, got {inspection!r}")
if inspection.get("completed_at") != "2026-08-30T10:15:10+00:00":
    sys.exit(f"expected latest empty successful inspection, got {inspection!r}")
PY
pass "later successful empty inspection makes historical endpoint STALE without deleting it"

python3 - <<'PY'
import os, sqlite3

db = os.environ["DB"]
entity = "dev-" + ("a" * 32)
conn = sqlite3.connect(db)
conn.execute("PRAGMA foreign_keys = ON")
conn.execute(
    """
    INSERT INTO service_discovery_runs(
        service_discovery_run_id, entity_id, address, provider,
        started_at, completed_at, outcome, detail
    ) VALUES (?, ?, ?, 'nmap', ?, ?, 'provider_error', ?)
    """,
    (
        "run-00000000000000000000000000000003",
        entity,
        "192.0.2.10",
        "2026-08-30T10:30:00+00:00",
        "2026-08-30T10:30:03+00:00",
        "synthetic provider failure",
    ),
)
conn.commit()
conn.close()
PY

OUT3="$(query_current)" || fail "read model failed after provider error"
export OUT3
python3 - <<'PY'
import json, os, sys
rows = json.loads(os.environ["OUT3"])
if len(rows) != 1:
    sys.exit(f"expected retained historical endpoint, got {rows!r}")
row = rows[0]
# It was already STALE because run 2 was a successful miss. A provider error
# must not create another miss or invent a stronger disappearance state.
if row.get("endpoint_state") != "STALE":
    sys.exit(f"provider failure changed endpoint evidence incorrectly: {row!r}")
inspection = row.get("latest_inspection", {})
if inspection.get("outcome") != "provider_error":
    sys.exit(f"provider failure not exposed separately: {inspection!r}")
if inspection.get("completed_at") != "2026-08-30T10:30:03+00:00":
    sys.exit(f"wrong latest inspection after provider failure: {inspection!r}")
PY
pass "provider failure is exposed separately and does not count as another endpoint miss"

python3 - <<'PY'
import hashlib, json, os, sqlite3

db = os.environ["DB"]
entity = "dev-" + ("a" * 32)
conn = sqlite3.connect(db)
conn.execute("PRAGMA foreign_keys = ON")

# A later successful run re-observes the exact same canonical observation.
# The observation row remains deduplicated; the run association is the
# authoritative proof that the endpoint was seen again.
conn.execute(
    """
    INSERT INTO service_discovery_runs(
        service_discovery_run_id, entity_id, address, provider,
        started_at, completed_at, outcome, detail
    ) VALUES (?, ?, ?, 'nmap', ?, ?, 'success', NULL)
    """,
    (
        "run-00000000000000000000000000000004",
        entity,
        "192.0.2.10",
        "2026-08-30T10:45:00+00:00",
        "2026-08-30T10:45:10+00:00",
    ),
)
conn.execute(
    """
    INSERT INTO service_discovery_run_observations(
        service_discovery_run_id, service_observation_id
    ) VALUES (?, ?)
    """,
    (
        "run-00000000000000000000000000000004",
        "svc-00000000000000000000000000000001",
    ),
)

# Same trusted service on a completely different non-default port. This
# explicitly proves that the read model preserves provider evidence rather
# than assigning service/application identity from a port-number table.
payload = {
    "address": "192.0.2.10",
    "entity_id": entity,
    "observed_at": "2026-08-30T10:45:05+00:00",
    "port": 12345,
    "protocol": "tcp",
    "provider": "nmap",
    "schema_version": "1.0",
    "service": "http",
    "state": "open",
}
payload_json = json.dumps(payload, sort_keys=True, separators=(",", ":"))
payload_hash = hashlib.sha256(payload_json.encode()).hexdigest()
conn.execute(
    """
    INSERT INTO service_observations(
        service_observation_id, schema_version, entity_id, provider,
        observed_at, received_at, address, protocol, port, state,
        service, payload_json, payload_hash
    ) VALUES (?, '1.0', ?, 'nmap', ?, ?, ?, 'tcp', ?, 'open', ?, ?, ?)
    """,
    (
        "svc-00000000000000000000000000000002",
        entity,
        payload["observed_at"],
        payload["observed_at"],
        payload["address"],
        payload["port"],
        payload["service"],
        payload_json,
        payload_hash,
    ),
)
conn.execute(
    """
    INSERT INTO service_discovery_run_observations(
        service_discovery_run_id, service_observation_id
    ) VALUES (?, ?)
    """,
    (
        "run-00000000000000000000000000000004",
        "svc-00000000000000000000000000000002",
    ),
)
conn.commit()
conn.close()
PY

OUT4="$(query_current)" || fail "read model failed after re-observation"
export OUT4
python3 - <<'PY'
import json, os, sys

rows = json.loads(os.environ["OUT4"])
by_port = {row.get("port"): row for row in rows}
if set(by_port) != {8099, 12345}:
    sys.exit(f"expected ports 8099 and 12345, got {rows!r}")

for port in (8099, 12345):
    row = by_port[port]
    if row.get("service") != "http":
        sys.exit(f"trusted HTTP evidence not preserved on port {port}: {row!r}")
    if row.get("endpoint_state") != "OBSERVED":
        sys.exit(f"port {port} should be OBSERVED in latest successful run: {row!r}")
    inspection = row.get("latest_inspection", {})
    if inspection.get("outcome") != "success":
        sys.exit(f"wrong latest inspection on port {port}: {inspection!r}")
    if "agent dvr" in json.dumps(row).lower():
        sys.exit(f"application identity guessed from port {port}: {row!r}")

# Critical deduplication semantic: 8099's old observation timestamp did not
# change, yet its association with run 4 makes it OBSERVED again.
if by_port[8099].get("last_observed_at") != "2026-08-30T10:00:05+00:00":
    sys.exit(f"deduplicated observation timestamp unexpectedly changed: {by_port[8099]!r}")
PY
pass "run association, not observation timestamp, makes deduplicated evidence current again"
pass "HTTP evidence is independent of port number and no application identity is guessed"

# Add a non-HTTP service on a deliberately non-default port plus an open
# endpoint whose service remains unknown. This proves that the read model is
# generic: trusted provider evidence is preserved for any service, while a
# port number alone never supplies functionality.
python3 - <<'PY'
import hashlib, json, os, sqlite3

db = os.environ["DB"]
entity = "dev-" + ("a" * 32)
conn = sqlite3.connect(db)
conn.execute("PRAGMA foreign_keys = ON")

run_id = "run-00000000000000000000000000000005"
conn.execute(
    """
    INSERT INTO service_discovery_runs(
        service_discovery_run_id, entity_id, address, provider,
        started_at, completed_at, outcome, detail
    ) VALUES (?, ?, ?, 'nmap', ?, ?, 'success', NULL)
    """,
    (
        run_id,
        entity,
        "192.0.2.10",
        "2026-08-30T11:00:00+00:00",
        "2026-08-30T11:00:10+00:00",
    ),
)

def add(port, service, observation_id):
    payload = {
        "address": "192.0.2.10",
        "entity_id": entity,
        "observed_at": "2026-08-30T11:00:05+00:00",
        "port": port,
        "protocol": "tcp",
        "provider": "nmap",
        "schema_version": "1.0",
        "service": service,
        "state": "open",
    }
    payload_json = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    payload_hash = hashlib.sha256(payload_json.encode()).hexdigest()
    conn.execute(
        """
        INSERT INTO service_observations(
            service_observation_id, schema_version, entity_id, provider,
            observed_at, received_at, address, protocol, port, state,
            service, payload_json, payload_hash
        ) VALUES (?, '1.0', ?, 'nmap', ?, ?, ?, 'tcp', ?, 'open', ?, ?, ?)
        """,
        (
            observation_id,
            entity,
            payload["observed_at"],
            payload["observed_at"],
            payload["address"],
            port,
            service,
            payload_json,
            payload_hash,
        ),
    )
    conn.execute(
        """
        INSERT INTO service_discovery_run_observations(
            service_discovery_run_id, service_observation_id
        ) VALUES (?, ?)
        """,
        (run_id, observation_id),
    )

add(22222, "ssh", "svc-00000000000000000000000000000003")
add(54321, None, "svc-00000000000000000000000000000004")

conn.commit()
conn.close()
PY

OUT_SERVICE="$(query_current)" || fail "read model failed for generic service evidence"
export OUT_SERVICE
python3 - <<'PY'
import json, os, sys

rows = json.loads(os.environ["OUT_SERVICE"])
by_port = {row.get("port"): row for row in rows}

ssh = by_port.get(22222)
if ssh is None:
    sys.exit(f"non-default SSH endpoint missing: {rows!r}")
if ssh.get("service") != "ssh":
    sys.exit(f"trusted SSH evidence not preserved: {ssh!r}")
if ssh.get("endpoint_state") != "OBSERVED":
    sys.exit(f"non-default SSH endpoint should be OBSERVED: {ssh!r}")

unknown = by_port.get(54321)
if unknown is None:
    sys.exit(f"unknown-service endpoint missing: {rows!r}")
if unknown.get("service") is not None:
    sys.exit(f"port-only endpoint was assigned functionality: {unknown!r}")
if unknown.get("endpoint_state") != "OBSERVED":
    sys.exit(f"unknown-service endpoint should still be OBSERVED: {unknown!r}")

encoded = json.dumps(rows).lower()
if "agent dvr" in encoded:
    sys.exit("application identity was guessed from endpoint evidence")
PY
pass "trusted non-HTTP service evidence survives unchanged on a non-default port"
pass "open endpoint without trusted service evidence remains UNKNOWN rather than port-guessed"

# Query a canonical entity with no service history. The read model must not
# invent endpoints from runs, common ports, or service assumptions.
python3 - <<'PY'
import os, sqlite3
db = os.environ["DB"]
conn = sqlite3.connect(db)
conn.execute("INSERT INTO entities(entity_id) VALUES (?)", ("dev-" + ("b" * 32),))
conn.commit()
conn.close()
PY

OUT5="$(python3 "${CURRENT}" --database "${DB}" --entity-id "dev-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")" \
    || fail "read model failed for entity with no service history"
export OUT5
python3 - <<'PY'
import json, os, sys
rows = json.loads(os.environ["OUT5"])
if rows != []:
    sys.exit(f"read model invented endpoints for entity with no history: {rows!r}")
PY
pass "entity with no service history has no invented endpoints"

python3 - <<'PY'
import os, sqlite3, sys
db = os.environ["DB"]
conn = sqlite3.connect(db)
obs = conn.execute("SELECT COUNT(*) FROM service_observations").fetchone()[0]
runs = conn.execute("SELECT COUNT(*) FROM service_discovery_runs").fetchone()[0]
links = conn.execute("SELECT COUNT(*) FROM service_discovery_run_observations").fetchone()[0]
integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
fk = conn.execute("PRAGMA foreign_key_check").fetchall()
conn.close()

if obs != 4:
    sys.exit(f"expected 4 deduplicated observations, got {obs}")
if runs != 5:
    sys.exit(f"expected 5 runs, got {runs}")
if links != 5:
    sys.exit(f"expected 5 run-observation associations, got {links}")
if integrity != "ok":
    sys.exit(f"integrity_check failed: {integrity}")
if fk:
    sys.exit(f"foreign_key_check failed: {fk!r}")
PY
pass "fixture preserves deduplicated history, run evidence, and database integrity"

printf '[PASS] Service Discovery current-state regression\n'
