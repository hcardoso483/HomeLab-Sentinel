#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

NORMALIZER="${APP_ROOT}/compose/discovery/nmap/scripts/normalize-services.py"

TMP_DIR="$(mktemp -d /tmp/hls-service-discovery-nmap-test.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

XML="${TMP_DIR}/scan.xml"
OUTPUT="${TMP_DIR}/output.jsonl"

ENTITY_ID="dev-service-test"
ADDRESS="192.168.1.50"

pass() {
    echo "[PASS] $*"
}

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

echo
echo "HomeLab Sentinel Nmap Service Discovery normalizer regression"
echo

[[ -x "${NORMALIZER}" ]] ||
    fail "Nmap Service Discovery normalizer missing or not executable: ${NORMALIZER}"

cat > "${XML}" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<nmaprun scanner="nmap">
  <host starttime="1788032400" endtime="1788032405">
    <status state="up"/>
    <address addr="192.168.1.50" addrtype="ipv4"/>
    <ports>
      <port protocol="tcp" portid="8006">
        <state state="open"/>
        <service name="http" method="probed" conf="10"/>
      </port>
      <port protocol="tcp" portid="2222">
        <state state="open"/>
        <service name="ssh" method="probed" conf="10"/>
      </port>
      <port protocol="tcp" portid="12345">
        <state state="open"/>
      </port>
      <port protocol="tcp" portid="9999">
        <state state="closed"/>
        <service name="unknown"/>
      </port>
    </ports>
  </host>
</nmaprun>
XML

"${NORMALIZER}" \
    --entity-id "${ENTITY_ID}" \
    --address "${ADDRESS}" \
    < "${XML}" > "${OUTPUT}"

python3 - "${OUTPUT}" "${ENTITY_ID}" "${ADDRESS}" <<'PY'
import json
import sys

output_file, entity_id, address = sys.argv[1:4]

with open(output_file, "r", encoding="utf-8") as handle:
    records = [json.loads(line) for line in handle if line.strip()]

if len(records) != 3:
    raise SystemExit(
        f"[FAIL] expected exactly 3 open TCP endpoint records, got {len(records)}"
    )

by_port = {record["port"]: record for record in records}

if set(by_port) != {8006, 2222, 12345}:
    raise SystemExit(
        f"[FAIL] unexpected endpoint ports: {sorted(by_port)}"
    )

required = {
    "schema_version",
    "entity_id",
    "provider",
    "observed_at",
    "address",
    "protocol",
    "port",
    "state",
    "service",
}

for port, record in by_port.items():
    missing = required - set(record)
    if missing:
        raise SystemExit(
            f"[FAIL] port {port} missing fields: {sorted(missing)}"
        )

    if record["schema_version"] != "1.0":
        raise SystemExit("[FAIL] unexpected schema_version")

    if record["entity_id"] != entity_id:
        raise SystemExit("[FAIL] entity_id was not preserved")

    if record["provider"] != "nmap":
        raise SystemExit("[FAIL] provider should be nmap")

    if record["address"] != address:
        raise SystemExit("[FAIL] target address was not preserved")

    if record["protocol"] != "tcp":
        raise SystemExit("[FAIL] v1 normalizer emitted non-TCP evidence")

    if record["state"] != "open":
        raise SystemExit("[FAIL] closed endpoint leaked into canonical output")

if by_port[8006]["service"] != "http":
    raise SystemExit("[FAIL] non-default HTTP port was not preserved")

if by_port[2222]["service"] != "ssh":
    raise SystemExit("[FAIL] non-default SSH port was not preserved")

if by_port[12345]["service"] is not None:
    raise SystemExit("[FAIL] unidentified service should normalize to null")

print("[PASS] only open TCP endpoints are emitted")
print("[PASS] entity_id and address remain authoritative target context")
print("[PASS] non-default service ports are preserved")
print("[PASS] unidentified open service remains valid endpoint evidence")
print("[PASS] closed endpoint is not emitted")
PY

pass "Nmap Service Discovery normalization contract"

echo
echo "=== SERVICE IDENTIFICATION TRUST REGRESSION ==="

TRUST_XML="$(mktemp)"
trap 'rm -f "${TRUST_XML}"' EXIT

cat > "${TRUST_XML}" <<'XML'
<?xml version="1.0"?>
<nmaprun>
  <host starttime="1788055079" endtime="1788055079">
    <status state="up"/>
    <ports>
      <port protocol="tcp" portid="22">
        <state state="open"/>
        <service name="ssh" product="OpenSSH" method="probed" conf="10"/>
      </port>
      <port protocol="tcp" portid="3128">
        <state state="open"/>
        <service name="http"
                 product="Proxmox Virtual Environment REST API"
                 method="probed"
                 conf="10"/>
      </port>
      <port protocol="tcp" portid="8006">
        <state state="open"/>
        <service name="wpl-analytics" method="table" conf="3"/>
      </port>
      <port protocol="tcp" portid="33393">
        <state state="open"/>
      </port>
    </ports>
  </host>
</nmaprun>
XML

TRUST_OUTPUT="$(
    "${NORMALIZER}" \
        --entity-id "dev-trust-test" \
        --address "192.168.1.58" \
        < "${TRUST_XML}"
)"

python3 - "${TRUST_OUTPUT}" <<'PY'
import json
import sys

records = [
    json.loads(line)
    for line in sys.argv[1].splitlines()
    if line.strip()
]

by_port = {record["port"]: record for record in records}

assert by_port[22]["service"] == "ssh", by_port[22]
assert by_port[3128]["service"] == "http", by_port[3128]

assert by_port[8006]["service"] is None, (
    "table-derived Nmap service label leaked into canonical evidence: "
    + repr(by_port[8006])
)

assert by_port[33393]["service"] is None, by_port[33393]
PY

echo "[PASS] only probed Nmap service identity becomes canonical evidence"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Nmap Service Discovery normalizer regression PASSED"
