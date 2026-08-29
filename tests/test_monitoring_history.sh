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

with sqlite3.connect(database) as connection:
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
            ('dev-history'),
            ('dev-other');

        INSERT INTO monitoring_observations VALUES
        (
            'obs-old',
            'dev-history',
            '1.0',
            'prometheus',
            'reachability',
            '192.0.2.10',
            '2026-08-29T08:00:00Z',
            '2026-08-29T08:00:01Z',
            'failed',
            NULL,
            '{}',
            'hash-old'
        );

        INSERT INTO monitoring_observations VALUES
        (
            'obs-new',
            'dev-history',
            '1.0',
            'prometheus',
            'reachability',
            '192.0.2.10',
            '2026-08-29T08:02:00Z',
            '2026-08-29T08:02:01Z',
            'success',
            1.25,
            '{}',
            'hash-new'
        );

        INSERT INTO monitoring_observations VALUES
        (
            'obs-other',
            'dev-other',
            '1.0',
            'prometheus',
            'reachability',
            '192.0.2.20',
            '2026-08-29T08:03:00Z',
            '2026-08-29T08:03:01Z',
            'success',
            2.50,
            '{}',
            'hash-other'
        );
    """)
PY

echo "=== Monitoring history command must exist ==="

set +e
OUTPUT="$(
    "${MONITORING}" history dev-history \
        --database "${DB}" \
        --json 2>&1
)"
RC=$?
set -e

if [ "${RC}" -ne 0 ]; then
    echo "[FAIL] monitoring history command failed rc=${RC}"
    printf '%s\n' "${OUTPUT}"
    exit 1
fi

python3 - "${OUTPUT}" <<'PY'
import json
import sys

lines = [
    line
    for line in sys.argv[1].splitlines()
    if line.strip()
]

records = [json.loads(line) for line in lines]

assert len(records) == 2, records

assert [record["status"] for record in records] == [
    "success",
    "failed",
], records

assert [
    record["checked_at"]
    for record in records
] == [
    "2026-08-29T08:02:00Z",
    "2026-08-29T08:00:00Z",
], records

for record in records:
    assert record["entity_id"] == "dev-history", record
    assert record["provider"] == "prometheus", record
    assert record["check_type"] == "reachability", record
    assert record["target"] == "192.0.2.10", record

assert records[0]["received_at"] == "2026-08-29T08:02:01Z"
assert records[0]["latency_ms"] == 1.25
assert records[1]["latency_ms"] is None

for forbidden in (
    "monitoring_observation_id",
    "payload_json",
    "payload_hash",
):
    assert forbidden not in records[0], records[0]
    assert forbidden not in records[1], records[1]
PY

echo "[PASS] Monitoring history preserves canonical entity evidence."

echo "=== Human history must tolerate a closed output pipe ==="

set +e
set -o pipefail
"${MONITORING}" history dev-history \
    --database "${DB}" \
    | head -4 >/dev/null
PIPE_RC=$?
set +o pipefail
set -e

if [ "${PIPE_RC}" -ne 0 ]; then
    echo "[FAIL] human Monitoring history does not tolerate a closed pipe"
    exit 1
fi

echo "[PASS] Human Monitoring history tolerates a closed output pipe."
