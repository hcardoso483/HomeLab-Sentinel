#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MONITORING="${APP_ROOT}/core/monitoring/monitoring.py"
HLS="${APP_ROOT}/installer/hls"
TMP_DIR="$(mktemp -d /tmp/hls-monitoring-targets-test.XXXXXX)"
DATABASE="${TMP_DIR}/inventory.db"

cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

[[ -x "${MONITORING}" ]] || fail "Monitoring Core missing or not executable: ${MONITORING}"
[[ -x "${HLS}" ]] || fail "HLS CLI missing or not executable: ${HLS}"

echo "HomeLab Sentinel Monitoring target regression test"
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
    PRIMARY KEY (entity_id, observation_id),
    FOREIGN KEY (entity_id) REFERENCES entities (entity_id) ON DELETE CASCADE,
    FOREIGN KEY (observation_id) REFERENCES observations (observation_id) ON DELETE RESTRICT
);
CREATE TABLE correlation_state (
    observation_id TEXT PRIMARY KEY,
    status TEXT NOT NULL DEFAULT 'pending',
    entity_id TEXT,
    correlation_method TEXT,
    confidence REAL,
    reason TEXT,
    decided_at TEXT,
    FOREIGN KEY (observation_id) REFERENCES observations (observation_id) ON DELETE RESTRICT,
    FOREIGN KEY (entity_id) REFERENCES entities (entity_id) ON DELETE RESTRICT,
    CHECK (status IN ('pending', 'resolved', 'unresolved')),
    CHECK (confidence IS NULL OR (confidence >= 0.0 AND confidence <= 1.0))
);
'''

entities = [("dev-a", "device"), ("dev-b", "device"), ("dev-c", "device")]

observations = [
    ("obs-a-old", "dev-a", "host-discovery", "2026-08-25T06:00:00Z",
     {"schema_version":"1.0","provider":"test","discovery_method":"host-discovery",
      "discovered_at":"2026-08-25T06:00:00Z","ip_addresses":["192.0.2.10"],
      "mac_address":"00:11:22:33:44:55","hostname":"alpha"}),
    ("obs-a-current", "dev-a", "host-discovery", "2026-08-25T06:15:00Z",
     {"schema_version":"1.0","provider":"test","discovery_method":"host-discovery",
      "discovered_at":"2026-08-25T06:15:00Z","ip_addresses":["192.0.2.11"],
      "mac_address":"00:11:22:33:44:55","hostname":"alpha"}),
    ("obs-b-current", "dev-b", "host-discovery", "2026-08-25T06:20:00Z",
     {"schema_version":"1.0","provider":"test","discovery_method":"host-discovery",
      "discovered_at":"2026-08-25T06:20:00Z","ip_addresses":["192.0.2.20"],
      "mac_address":"00:11:22:33:44:66","hostname":None}),
    ("obs-c-service", "dev-c", "service-discovery", "2026-08-25T06:25:00Z",
     {"schema_version":"1.0","provider":"test","discovery_method":"service-discovery",
      "discovered_at":"2026-08-25T06:25:00Z","ip_addresses":["192.0.2.30"],
      "mac_address":"00:11:22:33:44:77","hostname":"charlie-old-context"}),
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
            (observation_id, discovery_method, discovered_at, discovered_at,
             payload_json, payload_hash),
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

DIRECT_JSON="${TMP_DIR}/direct.jsonl"
"${MONITORING}" targets --database "${DATABASE}" --json >"${DIRECT_JSON}"

python3 - "${DIRECT_JSON}" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    rows = [json.loads(line) for line in handle if line.strip()]

if [r["entity_id"] for r in rows] != ["dev-a", "dev-b", "dev-c"]:
    raise SystemExit(f"unexpected target ordering/identity: {rows}")

by_id = {r["entity_id"]: r for r in rows}

a = by_id["dev-a"]
if a["endpoints"]["ip_addresses"] != ["192.0.2.11"]:
    raise SystemExit("current Living Inventory IP was not used")
if "192.0.2.10" in a["endpoints"]["ip_addresses"]:
    raise SystemExit("historical IP was incorrectly reused")
if a["endpoints"]["hostname"] != "alpha":
    raise SystemExit("current hostname was not preserved")
if a["state"] != "UNKNOWN":
    raise SystemExit("unevaluated target must begin UNKNOWN")

b = by_id["dev-b"]
if b["endpoints"]["ip_addresses"] != ["192.0.2.20"]:
    raise SystemExit("current endpoint was not preserved")

c = by_id["dev-c"]
if c["endpoints"]["ip_addresses"] != []:
    raise SystemExit("current IP was invented from historical context")
if c["endpoints"]["hostname"] is not None:
    raise SystemExit("current hostname was invented from historical context")
if c["eligible"] is not False or c["state"] != "UNKNOWN":
    raise SystemExit("entity without current endpoint must remain ineligible and UNKNOWN")
PY

pass "entity_id remains canonical Monitoring identity"
pass "current endpoint is derived from Living Inventory"
pass "historical endpoint is not reused as current"
pass "entity without usable current endpoint remains UNKNOWN"

HLS_JSON="${TMP_DIR}/hls.jsonl"
"${HLS}" monitoring targets --database "${DATABASE}" --json >"${HLS_JSON}"
cmp -s "${DIRECT_JSON}" "${HLS_JSON}" ||
    fail "hls monitoring targets does not match Monitoring Core"
pass "hls monitoring targets routes to Monitoring Core"

HUMAN="${TMP_DIR}/human.txt"
"${MONITORING}" targets --database "${DATABASE}" >"${HUMAN}"
grep -Fq "HomeLab Sentinel Monitoring Targets" "${HUMAN}" ||
    fail "human Monitoring target header missing"
grep -Fq "dev-a" "${HUMAN}" ||
    fail "human Monitoring target output missing dev-a"
grep -Fq "192.0.2.11" "${HUMAN}" ||
    fail "human Monitoring target output missing current IP"
grep -Fq "UNKNOWN" "${HUMAN}" ||
    fail "human Monitoring target output missing UNKNOWN state"
pass "human Monitoring target output"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Monitoring target regression PASSED"
