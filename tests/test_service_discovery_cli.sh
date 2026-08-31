#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
SERVICE_DISCOVERY="${APP_ROOT}/core/service_discovery/service_discovery.py"
TMPDIR="$(mktemp -d)"
DB="${TMPDIR}/inventory.db"

cleanup() {
    rm -rf "${TMPDIR}"
}
trap cleanup EXIT

fail() {
    echo "[FAIL] $*"
    exit 1
}

pass() {
    echo "[PASS] $*"
}

# This fixture is intentionally limited to the canonical Service Discovery
# persistence/read-model schema needed by services/history. The status command
# is first contract-tested at the parser boundary; aggregate status behavior
# will be exercised once routed through the existing target derivation path.
python3 - "${DB}" <<'PY'
import sqlite3
import sys

database = sys.argv[1]
conn = sqlite3.connect(database)
conn.executescript("""
PRAGMA foreign_keys = ON;
PRAGMA user_version = 5;

CREATE TABLE entities (
    entity_id TEXT PRIMARY KEY
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
    FOREIGN KEY (entity_id) REFERENCES entities(entity_id) ON DELETE RESTRICT,
    CHECK (protocol IN ('tcp')),
    CHECK (port >= 1 AND port <= 65535),
    CHECK (state IN ('open')),
    CHECK (service IS NULL OR length(trim(service)) > 0),
    CHECK (json_valid(payload_json))
);

CREATE TABLE service_discovery_runs (
    service_discovery_run_id TEXT PRIMARY KEY,
    entity_id TEXT NOT NULL,
    address TEXT NOT NULL,
    provider TEXT NOT NULL,
    started_at TEXT NOT NULL,
    completed_at TEXT NOT NULL,
    outcome TEXT NOT NULL,
    detail TEXT,
    FOREIGN KEY (entity_id) REFERENCES entities(entity_id) ON DELETE RESTRICT,
    CHECK (length(trim(address)) > 0),
    CHECK (length(trim(provider)) > 0),
    CHECK (outcome IN ('success','provider_error','invalid_evidence','store_error')),
    CHECK (detail IS NULL OR length(trim(detail)) > 0)
);

CREATE TABLE service_discovery_run_observations (
    service_discovery_run_id TEXT NOT NULL,
    service_observation_id TEXT NOT NULL,
    PRIMARY KEY (service_discovery_run_id, service_observation_id),
    FOREIGN KEY (service_discovery_run_id)
        REFERENCES service_discovery_runs(service_discovery_run_id)
        ON DELETE RESTRICT,
    FOREIGN KEY (service_observation_id)
        REFERENCES service_observations(service_observation_id)
        ON DELETE RESTRICT
);

INSERT INTO entities(entity_id) VALUES
    ('dev-cli'),
    ('dev-empty'),
    ('dev-other');

-- Historical HTTP evidence: deliberately non-default port.
INSERT INTO service_observations VALUES (
    'svc-http',
    'dev-cli',
    '1.0',
    'nmap',
    '2026-08-31T06:00:00Z',
    '2026-08-31T06:00:01Z',
    '192.0.2.10',
    'tcp',
    8099,
    'open',
    'http',
    '{}',
    'hash-http'
);

-- Trusted non-HTTP evidence on a deliberately non-default port.
INSERT INTO service_observations VALUES (
    'svc-ssh',
    'dev-cli',
    '1.0',
    'nmap',
    '2026-08-31T06:10:00Z',
    '2026-08-31T06:10:01Z',
    '192.0.2.10',
    'tcp',
    22222,
    'open',
    'ssh',
    '{}',
    'hash-ssh'
);

-- Open endpoint with no trustworthy service identity.
INSERT INTO service_observations VALUES (
    'svc-unknown',
    'dev-cli',
    '1.0',
    'nmap',
    '2026-08-31T06:10:00Z',
    '2026-08-31T06:10:01Z',
    '192.0.2.10',
    'tcp',
    54321,
    'open',
    NULL,
    '{}',
    'hash-unknown'
);

-- Evidence for another entity must never leak into dev-cli queries.
INSERT INTO service_observations VALUES (
    'svc-other',
    'dev-other',
    '1.0',
    'nmap',
    '2026-08-31T06:20:00Z',
    '2026-08-31T06:20:01Z',
    '192.0.2.20',
    'tcp',
    80,
    'open',
    'http',
    '{}',
    'hash-other'
);

-- Run 1 saw HTTP.
INSERT INTO service_discovery_runs VALUES (
    'run-1',
    'dev-cli',
    '192.0.2.10',
    'nmap',
    '2026-08-31T05:59:50Z',
    '2026-08-31T06:00:10Z',
    'success',
    NULL
);
INSERT INTO service_discovery_run_observations VALUES ('run-1', 'svc-http');

-- Run 2 succeeded empty: HTTP becomes STALE.
INSERT INTO service_discovery_runs VALUES (
    'run-2',
    'dev-cli',
    '192.0.2.10',
    'nmap',
    '2026-08-31T06:04:50Z',
    '2026-08-31T06:05:10Z',
    'success',
    NULL
);

-- Run 3 saw SSH and an unidentified open endpoint.
INSERT INTO service_discovery_runs VALUES (
    'run-3',
    'dev-cli',
    '192.0.2.10',
    'nmap',
    '2026-08-31T06:09:50Z',
    '2026-08-31T06:10:10Z',
    'success',
    NULL
);
INSERT INTO service_discovery_run_observations VALUES
    ('run-3', 'svc-ssh'),
    ('run-3', 'svc-unknown');

-- Latest overall inspection failed. This must be exposed separately and must
-- not turn the latest successfully observed endpoints into false absences.
INSERT INTO service_discovery_runs VALUES (
    'run-4',
    'dev-cli',
    '192.0.2.10',
    'nmap',
    '2026-08-31T06:14:50Z',
    '2026-08-31T06:15:10Z',
    'provider_error',
    'synthetic provider failure'
);

-- Other entity run for isolation.
INSERT INTO service_discovery_runs VALUES (
    'run-other',
    'dev-other',
    '192.0.2.20',
    'nmap',
    '2026-08-31T06:19:50Z',
    '2026-08-31T06:20:10Z',
    'success',
    NULL
);
INSERT INTO service_discovery_run_observations VALUES ('run-other', 'svc-other');

PRAGMA foreign_key_check;
""")
assert conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
assert conn.execute("PRAGMA foreign_key_check").fetchall() == []
conn.commit()
conn.close()
PY

echo "=== #17 command surface must exist ==="

for command in status services history; do
    set +e
    OUTPUT="$("${SERVICE_DISCOVERY}" "${command}" --help 2>&1)"
    RC=$?
    set -e

    if [ "${RC}" -ne 0 ]; then
        echo "[FAIL] Service Discovery '${command}' command is not available"
        printf '%s\n' "${OUTPUT}"
        exit 1
    fi
done

pass "status, services, and history command surfaces exist"

echo "=== status summarizes real Living Inventory targets and Service Discovery endpoint evidence ==="

STATUS_DB="${TMPDIR}/status.db"

python3 - "${STATUS_DB}" <<'PY'
import hashlib
import json
import sqlite3
import sys

database = sys.argv[1]

with sqlite3.connect(database) as con:
    con.executescript("""
        PRAGMA foreign_keys = ON;

        CREATE TABLE observations (
            observation_id TEXT PRIMARY KEY,
            schema_version TEXT NOT NULL,
            provider TEXT NOT NULL,
            discovery_method TEXT NOT NULL,
            discovered_at TEXT NOT NULL,
            received_at TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            payload_hash TEXT NOT NULL UNIQUE,
            CHECK (json_valid(payload_json))
        );

        CREATE TABLE entities (
            entity_id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL DEFAULT 'device',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE entity_observations (
            entity_id TEXT NOT NULL,
            observation_id TEXT NOT NULL,
            correlated_at TEXT NOT NULL,
            correlation_method TEXT,
            PRIMARY KEY (entity_id, observation_id)
        );

        CREATE TABLE correlation_state (
            observation_id TEXT PRIMARY KEY,
            status TEXT NOT NULL DEFAULT 'pending',
            entity_id TEXT,
            correlation_method TEXT,
            confidence REAL,
            reason TEXT,
            decided_at TEXT
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
            FOREIGN KEY (entity_id) REFERENCES entities(entity_id) ON DELETE RESTRICT
        );

        CREATE TABLE service_discovery_runs (
            service_discovery_run_id TEXT PRIMARY KEY,
            entity_id TEXT NOT NULL,
            address TEXT NOT NULL,
            provider TEXT NOT NULL,
            started_at TEXT NOT NULL,
            completed_at TEXT NOT NULL,
            outcome TEXT NOT NULL,
            detail TEXT,
            FOREIGN KEY (entity_id) REFERENCES entities(entity_id) ON DELETE RESTRICT
        );

        CREATE TABLE service_discovery_run_observations (
            service_discovery_run_id TEXT NOT NULL,
            service_observation_id TEXT NOT NULL,
            PRIMARY KEY (service_discovery_run_id, service_observation_id),
            FOREIGN KEY (service_discovery_run_id)
                REFERENCES service_discovery_runs(service_discovery_run_id)
                ON DELETE RESTRICT,
            FOREIGN KEY (service_observation_id)
                REFERENCES service_observations(service_observation_id)
                ON DELETE RESTRICT
        );

        PRAGMA user_version = 5;
    """)

    for entity_id in ("dev-status-a", "dev-status-b", "dev-status-c"):
        con.execute(
            "INSERT INTO entities VALUES (?, 'device', ?, ?)",
            (entity_id, "2026-08-31T05:00:00Z", "2026-08-31T06:30:00Z"),
        )

    inventory = [
        (
            "obs-status-a-old",
            "dev-status-a",
            "2026-08-31T05:00:00Z",
            ["192.0.2.9"],
        ),
        (
            "obs-status-a-current",
            "dev-status-a",
            "2026-08-31T06:00:00Z",
            ["192.0.2.10", "198.51.100.10"],
        ),
        (
            "obs-status-b-current",
            "dev-status-b",
            "2026-08-31T06:01:00Z",
            ["192.0.2.20"],
        ),
    ]

    for observation_id, entity_id, discovered_at, addresses in inventory:
        payload = {
            "schema_version": "1.0",
            "provider": "test",
            "discovery_method": "host-discovery",
            "discovered_at": discovered_at,
            "ip_addresses": addresses,
            "mac_address": None,
            "hostname": None,
        }
        payload_json = json.dumps(payload, separators=(",", ":"), sort_keys=True)
        payload_hash = hashlib.sha256(payload_json.encode()).hexdigest()

        con.execute(
            """INSERT INTO observations
               VALUES (?, '1.0', 'test', 'host-discovery', ?, ?, ?, ?)""",
            (
                observation_id,
                discovered_at,
                discovered_at,
                payload_json,
                payload_hash,
            ),
        )
        con.execute(
            """INSERT INTO entity_observations
               VALUES (?, ?, ?, 'test-seed')""",
            (entity_id, observation_id, discovered_at),
        )
        con.execute(
            """INSERT INTO correlation_state
               VALUES (?, 'resolved', ?, 'test-seed', 1.0, NULL, ?)""",
            (observation_id, entity_id, discovered_at),
        )

    service_rows = [
        (
            "svc-status-stale",
            "dev-status-a",
            "2026-08-31T06:05:00Z",
            "192.0.2.10",
            8099,
            "http",
            "status-hash-stale",
        ),
        (
            "svc-status-observed",
            "dev-status-a",
            "2026-08-31T06:15:00Z",
            "192.0.2.10",
            22222,
            "ssh",
            "status-hash-observed",
        ),
        (
            "svc-status-unknown",
            "dev-status-b",
            "2026-08-31T06:16:00Z",
            "192.0.2.20",
            54321,
            None,
            "status-hash-unknown",
        ),
    ]

    for obs_id, entity_id, observed_at, address, port, service, payload_hash in service_rows:
        payload = {
            "schema_version": "1.0",
            "entity_id": entity_id,
            "provider": "nmap",
            "observed_at": observed_at,
            "address": address,
            "protocol": "tcp",
            "port": port,
            "state": "open",
            "service": service,
        }
        con.execute(
            """INSERT INTO service_observations
               VALUES (?, ?, '1.0', 'nmap', ?, ?, ?, 'tcp', ?, 'open', ?, ?, ?)""",
            (
                obs_id,
                entity_id,
                observed_at,
                observed_at,
                address,
                port,
                service,
                json.dumps(payload, separators=(",", ":"), sort_keys=True),
                payload_hash,
            ),
        )

    runs = [
        (
            "run-status-1",
            "dev-status-a",
            "192.0.2.10",
            "2026-08-31T06:04:50Z",
            "2026-08-31T06:05:10Z",
            "success",
        ),
        (
            "run-status-2",
            "dev-status-a",
            "192.0.2.10",
            "2026-08-31T06:09:50Z",
            "2026-08-31T06:10:10Z",
            "success",
        ),
        (
            "run-status-3",
            "dev-status-a",
            "192.0.2.10",
            "2026-08-31T06:14:50Z",
            "2026-08-31T06:15:10Z",
            "success",
        ),
        (
            "run-status-4",
            "dev-status-b",
            "192.0.2.20",
            "2026-08-31T06:15:50Z",
            "2026-08-31T06:16:10Z",
            "success",
        ),
        (
            "run-status-5",
            "dev-status-b",
            "192.0.2.20",
            "2026-08-31T06:19:50Z",
            "2026-08-31T06:20:10Z",
            "provider_error",
        ),
    ]

    for run_id, entity_id, address, started_at, completed_at, outcome in runs:
        con.execute(
            """INSERT INTO service_discovery_runs
               VALUES (?, ?, ?, 'nmap', ?, ?, ?, NULL)""",
            (
                run_id,
                entity_id,
                address,
                started_at,
                completed_at,
                outcome,
            ),
        )

    con.execute(
        "INSERT INTO service_discovery_run_observations VALUES (?, ?)",
        ("run-status-1", "svc-status-stale"),
    )
    con.execute(
        "INSERT INTO service_discovery_run_observations VALUES (?, ?)",
        ("run-status-3", "svc-status-observed"),
    )
    con.execute(
        "INSERT INTO service_discovery_run_observations VALUES (?, ?)",
        ("run-status-4", "svc-status-unknown"),
    )

    assert con.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    assert con.execute("PRAGMA foreign_key_check").fetchall() == []
PY

set +e
STATUS_OUTPUT="$(
    "${SERVICE_DISCOVERY}" status \
        --database "${STATUS_DB}" \
        --json 2>&1
)"
STATUS_RC=$?
set -e

if [ "${STATUS_RC}" -ne 0 ]; then
    echo "[FAIL] Service Discovery status command failed rc=${STATUS_RC}"
    printf '%s\n' "${STATUS_OUTPUT}"
    exit 1
fi

python3 - "${STATUS_OUTPUT}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])

assert isinstance(payload["provider"], str), payload
assert payload["provider"], payload

# Three CURRENT Living Inventory addresses:
# dev-status-a has two, dev-status-b has one.
# The old 192.0.2.9 address must not be counted.
assert payload["targets"] == 3, payload

# Endpoint counts are endpoint units, not target/entity units.
assert payload["endpoints"] == {
    "observed": 2,
    "stale": 1,
}, payload

# A failed latest inspection remains operational evidence and therefore is
# still the subsystem's newest inspection timestamp.
assert payload["last_inspection"] == "2026-08-31T06:20:10Z", payload

for forbidden in (
    "entities",
    "unknown",
    "healthy",
    "degraded",
    "down",
):
    assert forbidden not in payload, payload
PY

pass "status separates Living Inventory targets from OBSERVED/STALE endpoint evidence"

echo "=== human status exposes the same canonical summary ==="

STATUS_HUMAN="$(
    "${SERVICE_DISCOVERY}" status \
        --database "${STATUS_DB}"
)"

grep -Fq "HomeLab Sentinel Service Discovery" <<<"${STATUS_HUMAN}" ||
    fail "human Service Discovery status header missing"
grep -Fq "Targets" <<<"${STATUS_HUMAN}" ||
    fail "human Service Discovery status missing target count"
grep -Fq "Observed endpoints" <<<"${STATUS_HUMAN}" ||
    fail "human Service Discovery status missing observed endpoint count"
grep -Fq "Stale endpoints" <<<"${STATUS_HUMAN}" ||
    fail "human Service Discovery status missing stale endpoint count"
grep -Fq "2026-08-31T06:20:10Z" <<<"${STATUS_HUMAN}" ||
    fail "human Service Discovery status missing last inspection"

pass "human status exposes canonical target, endpoint, and inspection summary"

echo "=== services exposes canonical #16 current-state semantics ==="

set +e
OUTPUT="$(
    "${SERVICE_DISCOVERY}" services dev-cli \
        --database "${DB}" \
        --json 2>&1
)"
RC=$?
set -e

if [ "${RC}" -ne 0 ]; then
    echo "[FAIL] Service Discovery services command failed rc=${RC}"
    printf '%s\n' "${OUTPUT}"
    exit 1
fi

python3 - "${OUTPUT}" <<'PY'
import json
import sys

lines = [line for line in sys.argv[1].splitlines() if line.strip()]
records = [json.loads(line) for line in lines]
assert len(records) == 3, records

by_port = {record["port"]: record for record in records}
assert set(by_port) == {8099, 22222, 54321}, records

http = by_port[8099]
assert http["service"] == "http", http
assert http["endpoint_state"] == "STALE", http
assert "application" not in http, http

ssh = by_port[22222]
assert ssh["service"] == "ssh", ssh
assert ssh["endpoint_state"] == "OBSERVED", ssh

unknown = by_port[54321]
assert unknown["service"] is None, unknown
assert unknown["endpoint_state"] == "OBSERVED", unknown

for record in records:
    assert record["entity_id"] == "dev-cli", record
    assert record["address"] == "192.0.2.10", record
    assert record["protocol"] == "tcp", record
    assert record["latest_inspection"] == {
        "outcome": "provider_error",
        "completed_at": "2026-08-31T06:15:10Z",
    }, record
    for forbidden in (
        "service_observation_id",
        "service_discovery_run_id",
        "payload_json",
        "payload_hash",
        "application",
    ):
        assert forbidden not in record, record
PY

pass "services preserves OBSERVED/STALE, trusted service evidence, UNKNOWN, and latest inspection outcome"

echo "=== services for an entity with no history invents nothing ==="

OUTPUT="$(
    "${SERVICE_DISCOVERY}" services dev-empty \
        --database "${DB}" \
        --json
)"

if [ -n "${OUTPUT}" ]; then
    echo "[FAIL] no-history entity produced invented service rows"
    printf '%s\n' "${OUTPUT}"
    exit 1
fi

pass "services emits no invented endpoints for an entity with no service history"

echo "=== services rejects a nonexistent canonical entity ==="

set +e
OUTPUT="$(
    "${SERVICE_DISCOVERY}" services dev-missing \
        --database "${DB}" \
        --json 2>&1
)"
RC=$?
set -e

if [ "${RC}" -eq 0 ]; then
    fail "services accepted a nonexistent entity"
fi

pass "services rejects a nonexistent entity"

echo "=== history exposes both observation and inspection evidence ==="

set +e
OUTPUT="$(
    "${SERVICE_DISCOVERY}" history dev-cli \
        --database "${DB}" \
        --json 2>&1
)"
RC=$?
set -e

if [ "${RC}" -ne 0 ]; then
    echo "[FAIL] Service Discovery history command failed rc=${RC}"
    printf '%s\n' "${OUTPUT}"
    exit 1
fi

python3 - "${OUTPUT}" <<'PY'
import json
import sys

lines = [line for line in sys.argv[1].splitlines() if line.strip()]
records = [json.loads(line) for line in lines]

inspections = [record for record in records if record.get("type") == "inspection"]
observations = [record for record in records if record.get("type") == "observation"]

assert len(inspections) == 4, records
assert len(observations) == 3, records

# All evidence is entity-isolated.
for record in records:
    assert record["entity_id"] == "dev-cli", record

# Inspection history preserves success, successful-empty, and provider failure.
by_completed = {record["completed_at"]: record for record in inspections}
assert by_completed["2026-08-31T06:00:10Z"]["outcome"] == "success"
assert by_completed["2026-08-31T06:05:10Z"]["outcome"] == "success"
assert by_completed["2026-08-31T06:15:10Z"]["outcome"] == "provider_error"
assert by_completed["2026-08-31T06:15:10Z"]["detail"] == "synthetic provider failure"

# Observation history preserves provider evidence without application guessing.
by_port = {record["port"]: record for record in observations}
assert by_port[8099]["service"] == "http", by_port[8099]
assert by_port[22222]["service"] == "ssh", by_port[22222]
assert by_port[54321]["service"] is None, by_port[54321]

for record in records:
    for forbidden in (
        "service_observation_id",
        "service_discovery_run_id",
        "payload_json",
        "payload_hash",
        "application",
    ):
        assert forbidden not in record, record

# The public stream is newest evidence first. Inspection ordering uses
# completed_at; observation ordering uses observed_at. The implementation may
# choose a deterministic tie-breaker for equal timestamps.
def event_time(record):
    if record["type"] == "inspection":
        return record["completed_at"]
    return record["observed_at"]

times = [event_time(record) for record in records]
assert times == sorted(times, reverse=True), times
PY

pass "history preserves observations, successful-empty inspection, provider failure, ordering, and entity isolation"

echo "=== history for an entity with no evidence is empty ==="

OUTPUT="$(
    "${SERVICE_DISCOVERY}" history dev-empty \
        --database "${DB}" \
        --json
)"

if [ -n "${OUTPUT}" ]; then
    echo "[FAIL] no-history entity produced invented history rows"
    printf '%s\n' "${OUTPUT}"
    exit 1
fi

pass "history emits no invented evidence"

echo "=== entity-requiring commands reject a missing entity id ==="

for command in services history; do
    set +e
    "${SERVICE_DISCOVERY}" "${command}" \
        --database "${DB}" \
        --json >/dev/null 2>&1
    RC=$?
    set -e

    if [ "${RC}" -eq 0 ]; then
        fail "${command} accepted a missing entity id"
    fi
done

pass "services and history require an entity id"

echo "=== human services/history tolerate a closed output pipe ==="

set +e
set -o pipefail
"${SERVICE_DISCOVERY}" services dev-cli \
    --database "${DB}" \
    | head -4 >/dev/null
SERVICES_PIPE_RC=$?

"${SERVICE_DISCOVERY}" history dev-cli \
    --database "${DB}" \
    | head -4 >/dev/null
HISTORY_PIPE_RC=$?
set +o pipefail
set -e

if [ "${SERVICES_PIPE_RC}" -ne 0 ]; then
    fail "human Service Discovery services does not tolerate a closed pipe"
fi
if [ "${HISTORY_PIPE_RC}" -ne 0 ]; then
    fail "human Service Discovery history does not tolerate a closed pipe"
fi

pass "human services/history tolerate closed output pipes"

echo "[PASS] Service Discovery CLI regression"
