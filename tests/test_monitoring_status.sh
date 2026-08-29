#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
MONITORING="${APP_ROOT}/core/monitoring/monitoring.py"
TMPDIR="$(mktemp -d)"
DB="${TMPDIR}/inventory.db"

cleanup() {
    rm -rf "${TMPDIR}"
}
trap cleanup EXIT

python3 - "${DB}" <<'PY'
import sqlite3
import sys

database = sys.argv[1]

connection = sqlite3.connect(database)

connection.executescript("""
PRAGMA user_version = 3;

CREATE TABLE entities (
    entity_id TEXT PRIMARY KEY
);

CREATE TABLE monitoring_observations (
    monitoring_observation_id TEXT PRIMARY KEY,
    entity_id TEXT NOT NULL,
    schema_version TEXT NOT NULL,
    provider TEXT NOT NULL,
    check_type TEXT NOT NULL,
    target TEXT NOT NULL,
    checked_at TEXT NOT NULL,
    received_at TEXT NOT NULL,
    status TEXT NOT NULL,
    latency_ms REAL,
    payload_json TEXT NOT NULL,
    payload_hash TEXT NOT NULL UNIQUE
);

INSERT INTO entities(entity_id) VALUES
('dev-healthy'),
('dev-down'),
('dev-unknown');

INSERT INTO monitoring_observations VALUES
(
    'obs-h1',
    'dev-healthy',
    '1.0',
    'prometheus',
    'reachability',
    '192.0.2.10',
    '2026-08-29T08:00:00Z',
    '2026-08-29T08:00:00Z',
    'success',
    1.0,
    '{}',
    'hash-h1'
);

INSERT INTO monitoring_observations VALUES
(
    'obs-d1',
    'dev-down',
    '1.0',
    'prometheus',
    'reachability',
    '192.0.2.20',
    '2026-08-29T08:00:00Z',
    '2026-08-29T08:00:00Z',
    'failed',
    NULL,
    '{}',
    'hash-d1'
);

INSERT INTO monitoring_observations VALUES
(
    'obs-d2',
    'dev-down',
    '1.0',
    'prometheus',
    'reachability',
    '192.0.2.20',
    '2026-08-29T07:59:30Z',
    '2026-08-29T07:59:30Z',
    'failed',
    NULL,
    '{}',
    'hash-d2'
);
""")

connection.commit()
connection.close()
PY

echo "=== Monitoring status command must exist ==="

set +e
OUTPUT="$(
    "${MONITORING}" status \
        --database "${DB}" \
        --now "2026-08-29T08:00:30Z" \
        --json 2>&1
)"
RC=$?
set -e

if [ "${RC}" -ne 0 ]; then
    echo "[FAIL] monitoring status command failed rc=${RC}"
    printf '%s\n' "${OUTPUT}"
    exit 1
fi

python3 - "${OUTPUT}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])

assert payload["targets"] == 3, payload
assert payload["entities"]["healthy"] == 1, payload
assert payload["entities"]["degraded"] == 0, payload
assert payload["entities"]["down"] == 1, payload
assert payload["entities"]["unknown"] == 1, payload
assert payload["last_evaluation"] == "2026-08-29T08:00:00Z", payload

provider = payload["provider"]
assert provider["capability"] == "monitoring", payload
assert provider["provider"], payload
assert provider["status"], payload
PY

echo "[PASS] Monitoring status exposes canonical subsystem summary."
