#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_DISCOVERY="${APP_ROOT}/core/service_discovery/service_discovery.py"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

[[ -f "${SERVICE_DISCOVERY}" ]] ||
    fail "Service Discovery core missing: ${SERVICE_DISCOVERY}"

python3 - "${SERVICE_DISCOVERY}" <<'PY'
import importlib.util
import sqlite3
import sys
from pathlib import Path

service_discovery_path = Path(sys.argv[1])

spec = importlib.util.spec_from_file_location(
    "hls_service_discovery_retry_pool",
    service_discovery_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

connection = sqlite3.connect(":memory:")

connection.executescript(
    """
    CREATE TABLE service_discovery_runs (
        service_discovery_run_id TEXT PRIMARY KEY,
        entity_id TEXT NOT NULL,
        address TEXT NOT NULL,
        provider TEXT NOT NULL,
        started_at TEXT NOT NULL,
        completed_at TEXT NOT NULL,
        outcome TEXT NOT NULL,
        detail TEXT
    );

    INSERT INTO service_discovery_runs VALUES
    (
        'run-a1',
        'dev-a',
        '192.0.2.10',
        'nmap',
        '2026-09-01T10:00:00Z',
        '2026-09-01T10:01:00Z',
        'success',
        NULL
    );

    INSERT INTO service_discovery_runs VALUES
    (
        'run-a2',
        'dev-a',
        '192.0.2.10',
        'nmap',
        '2026-09-01T11:00:00Z',
        '2026-09-01T11:01:00Z',
        'inconclusive',
        'bounded probing exhausted'
    );

    INSERT INTO service_discovery_runs VALUES
    (
        'run-b1',
        'dev-b',
        '192.0.2.20',
        'nmap',
        '2026-09-01T10:00:00Z',
        '2026-09-01T10:01:00Z',
        'inconclusive',
        'bounded probing exhausted'
    );

    INSERT INTO service_discovery_runs VALUES
    (
        'run-b2',
        'dev-b',
        '192.0.2.20',
        'nmap',
        '2026-09-01T11:00:00Z',
        '2026-09-01T11:01:00Z',
        'success',
        NULL
    );

    INSERT INTO service_discovery_runs VALUES
    (
        'run-d1',
        'dev-d',
        '192.0.2.40',
        'nmap',
        '2026-09-01T11:00:00Z',
        '2026-09-01T11:01:00Z',
        'provider_error',
        'synthetic provider failure'
    );

    INSERT INTO service_discovery_runs VALUES
    (
        'run-e1',
        'dev-e',
        '192.0.2.50',
        'nmap',
        '2026-09-01T10:00:00Z',
        '2026-09-01T10:01:00Z',
        'inconclusive',
        'bounded probing exhausted'
    );

    INSERT INTO service_discovery_runs VALUES
    (
        'run-e2',
        'dev-e',
        '192.0.2.50',
        'nmap',
        '2026-09-01T11:00:00Z',
        '2026-09-01T11:01:00Z',
        'provider_error',
        'synthetic provider failure'
    );
    """
)

try:
    targets = [
        {
            "entity_id": "dev-a",
            "address": "192.0.2.10",
            "eligible": True,
        },
        {
            "entity_id": "dev-b",
            "address": "192.0.2.20",
            "eligible": True,
        },
        {
            "entity_id": "dev-c",
            "address": "192.0.2.30",
            "eligible": True,
        },
        {
            "entity_id": "dev-d",
            "address": "192.0.2.40",
            "eligible": True,
        },
        {
            "entity_id": "dev-e",
            "address": "192.0.2.50",
            "eligible": True,
        },
    ]

    pooled = module.service_discovery_retry_pool(
        connection,
        targets,
    )
finally:
    connection.close()

expected = [
    {
        "entity_id": "dev-a",
        "address": "192.0.2.10",
        "eligible": True,
    }
]

if pooled != expected:
    raise SystemExit(
        "[FAIL] Retry Pool did not derive membership from "
        f"the latest target outcome: {pooled!r}"
    )
PY

pass "latest inconclusive target enters Retry Pool"
pass "newer success removes target from Retry Pool"
pass "target with no run history does not enter Retry Pool"
pass "latest provider failure does not enter Retry Pool"
pass "newer provider failure removes stale inconclusive membership"

echo
python3 - "${SERVICE_DISCOVERY}" <<'PY'
import importlib.util
import sys
from pathlib import Path

service_discovery_path = Path(sys.argv[1])

spec = importlib.util.spec_from_file_location(
    "hls_service_discovery_retry_pool_cli",
    service_discovery_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

all_targets = [
    {
        "schema_version": "1.0",
        "entity_id": "dev-a",
        "entity_type": "device",
        "address": "192.0.2.10",
        "eligible": True,
        "state": "UNKNOWN",
    },
    {
        "schema_version": "1.0",
        "entity_id": "dev-b",
        "entity_type": "device",
        "address": "192.0.2.20",
        "eligible": True,
        "state": "UNKNOWN",
    },
]

retry_pool_targets = [all_targets[0]]
normal_targets = [all_targets[1]]

calls = {
    "targets": 0,
    "retry_pool": 0,
    "emit": [],
}

class FakeConnection:
    def close(self):
        pass

def fake_targets(database):
    calls["targets"] += 1
    return list(all_targets)

def fake_connect_read_only(database):
    return FakeConnection()

def fake_require_schema(connection):
    return None

def fake_retry_pool(connection, targets):
    calls["retry_pool"] += 1
    if targets != all_targets:
        raise SystemExit(
            f"Retry Pool received unexpected target set: {targets!r}"
        )
    return list(retry_pool_targets)

def fake_emit_json(records):
    calls["emit"].append(list(records))

module.service_discovery_targets = fake_targets
module.connect_read_only = fake_connect_read_only
module.require_schema = fake_require_schema
module.service_discovery_retry_pool = fake_retry_pool
module.emit_json = fake_emit_json

original_argv = list(sys.argv)

try:
    sys.argv = [
        str(service_discovery_path),
        "targets",
        "--database",
        "/tmp/inventory.db",
        "--json",
        "--exclude-retry-pool",
    ]
    returncode = module.main()
finally:
    sys.argv = original_argv

if returncode != 0:
    raise SystemExit(
        f"targets --exclude-retry-pool returned {returncode}, expected 0"
    )

if calls["targets"] != 1:
    raise SystemExit(
        f"current targets were derived {calls['targets']} times, expected once"
    )

if calls["retry_pool"] != 1:
    raise SystemExit(
        f"Retry Pool selector was invoked {calls['retry_pool']} times, expected once"
    )

if calls["emit"] != [normal_targets]:
    raise SystemExit(
        f"CLI emitted unexpected target set: {calls['emit']!r}"
    )
PY

pass "targets CLI excludes Retry Pool members when requested"

echo

echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery Retry Pool regression PASSED"
