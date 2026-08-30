#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SERVICE_DISCOVERY="${APP_ROOT}/core/service_discovery/service_discovery.py"
HLS="${APP_ROOT}/installer/hls"
TMP_DIR="$(mktemp -d /tmp/hls-service-discovery-targets-test.XXXXXX)"
DATABASE="${TMP_DIR}/inventory.db"

cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

echo "HomeLab Sentinel Service Discovery target regression test"
echo
echo "Database : ${DATABASE}"
echo

python3 - "${DATABASE}" <<'PY'
import hashlib, json, sqlite3, sys

database = sys.argv[1]

schema = '''
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
'''

entities = [
    ("dev-a", "device"),
    ("dev-b", "device"),
    ("dev-c", "device"),
]

observations = [
    (
        "obs-a-old", "dev-a", "host-discovery", "2026-08-25T06:00:00Z",
        {
            "schema_version":"1.0", "provider":"test", "discovery_method":"host-discovery",
            "discovered_at":"2026-08-25T06:00:00Z",
            "ip_addresses":["192.0.2.10"],
            "mac_address":"00:11:22:33:44:55",
            "hostname":"alpha",
        },
    ),
    (
        "obs-a-current", "dev-a", "host-discovery", "2026-08-25T06:15:00Z",
        {
            "schema_version":"1.0", "provider":"test", "discovery_method":"host-discovery",
            "discovered_at":"2026-08-25T06:15:00Z",
            "ip_addresses":["192.0.2.11", "198.51.100.11"],
            "mac_address":"00:11:22:33:44:55",
            "hostname":"alpha",
        },
    ),
    (
        "obs-b-current", "dev-b", "host-discovery", "2026-08-25T06:20:00Z",
        {
            "schema_version":"1.0", "provider":"test", "discovery_method":"host-discovery",
            "discovered_at":"2026-08-25T06:20:00Z",
            "ip_addresses":["192.0.2.20"],
            "mac_address":"00:11:22:33:44:66",
            "hostname":None,
        },
    ),
    (
        "obs-c-service", "dev-c", "service-discovery", "2026-08-25T06:25:00Z",
        {
            "schema_version":"1.0", "provider":"test", "discovery_method":"service-discovery",
            "discovered_at":"2026-08-25T06:25:00Z",
            "ip_addresses":["192.0.2.30"],
            "mac_address":"00:11:22:33:44:77",
            "hostname":"charlie-old-context",
        },
    ),
]

with sqlite3.connect(database) as con:
    con.execute("PRAGMA foreign_keys = ON")
    con.executescript(schema)
    con.execute("PRAGMA user_version = 2")

    for entity_id, entity_type in entities:
        con.execute(
            "INSERT INTO entities VALUES (?, ?, ?, ?)",
            (entity_id, entity_type, "2026-08-25T06:00:00Z", "2026-08-25T06:30:00Z"),
        )

    for observation_id, entity_id, discovery_method, discovered_at, payload in observations:
        payload_json = json.dumps(payload, separators=(",", ":"), sort_keys=True)
        payload_hash = hashlib.sha256(payload_json.encode()).hexdigest()
        con.execute(
            '''INSERT INTO observations
               VALUES (?, '1.0', 'test', ?, ?, ?, ?, ?)''',
            (observation_id, discovery_method, discovered_at, discovered_at, payload_json, payload_hash),
        )
        con.execute(
            '''INSERT INTO entity_observations
               VALUES (?, ?, ?, 'test-seed')''',
            (entity_id, observation_id, discovered_at),
        )
        con.execute(
            '''INSERT INTO correlation_state
               VALUES (?, 'resolved', ?, 'test-seed', 1.0, NULL, ?)''',
            (observation_id, entity_id, discovered_at),
        )

    con.commit()
PY

pass "deterministic Living Inventory fixture created"

[[ -x "${SERVICE_DISCOVERY}" ]] || fail "Service Discovery Core missing or not executable: ${SERVICE_DISCOVERY}"

DIRECT_JSON="${TMP_DIR}/direct.jsonl"
"${SERVICE_DISCOVERY}" targets --database "${DATABASE}" --json >"${DIRECT_JSON}"

python3 - "${DIRECT_JSON}" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8") as handle:
    rows = [json.loads(line) for line in handle if line.strip()]

expected = [
    ("dev-a", "192.0.2.11"),
    ("dev-a", "198.51.100.11"),
    ("dev-b", "192.0.2.20"),
]
actual = [(row.get("entity_id"), row.get("address")) for row in rows]
if actual != expected:
    raise SystemExit(f"unexpected Service Discovery targets: {rows}")

for row in rows:
    if row.get("schema_version") != "1.0":
        raise SystemExit("target schema_version must be 1.0")
    if row.get("eligible") is not True:
        raise SystemExit("emitted Service Discovery target must be eligible")
    if row.get("state") != "UNKNOWN":
        raise SystemExit("unevaluated Service Discovery target must begin UNKNOWN")

if any(row["address"] == "192.0.2.10" for row in rows):
    raise SystemExit("historical Living Inventory address was incorrectly reused")

if any(row["entity_id"] == "dev-c" for row in rows):
    raise SystemExit("entity without a current Living Inventory address became scan eligible")

alpha = [row for row in rows if row["entity_id"] == "dev-a"]
if len(alpha) != 2:
    raise SystemExit("multiple current addresses were not expanded into distinct scan targets")

if any(row.get("entity_type") != "device" for row in rows):
    raise SystemExit("entity_type was not preserved")
PY

pass "entity_id remains canonical Service Discovery identity"
pass "current Living Inventory addresses become scan targets"
pass "multiple current addresses become distinct scan targets"
pass "historical addresses are not reused"
pass "entity without current address is not emitted as eligible"

HUMAN="${TMP_DIR}/human.txt"
"${SERVICE_DISCOVERY}" targets --database "${DATABASE}" >"${HUMAN}"

grep -Fq "HomeLab Sentinel Service Discovery Targets" "${HUMAN}" ||
    fail "human Service Discovery target header missing"
grep -Fq "dev-a" "${HUMAN}" ||
    fail "human Service Discovery target output missing dev-a"
grep -Fq "192.0.2.11" "${HUMAN}" ||
    fail "human Service Discovery target output missing first current address"
grep -Fq "198.51.100.11" "${HUMAN}" ||
    fail "human Service Discovery target output missing second current address"

authorized_count="$(grep -c '^dev-' "${HUMAN}" || true)"
[[ "${authorized_count}" -eq 3 ]] || fail "human output emitted unexpected target count"

pass "human Service Discovery target output"

HLS_JSON="${TMP_DIR}/hls.jsonl"
"${HLS}" service-discovery targets --database "${DATABASE}" --json >"${HLS_JSON}"

cmp -s "${DIRECT_JSON}" "${HLS_JSON}" ||
    fail "hls service-discovery targets does not match Service Discovery Core"

pass "hls service-discovery targets routes to Service Discovery Core"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery target regression PASSED"
