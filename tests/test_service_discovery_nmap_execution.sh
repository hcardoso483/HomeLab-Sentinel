#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENTRYPOINT="${APP_ROOT}/compose/discovery/nmap/scripts/discover-services.sh"

TMP_DIR="$(mktemp -d /tmp/hls-service-discovery-execution.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
OUTPUT="${TMP_DIR}/output.jsonl"
ARGS="${TMP_DIR}/nmap-args.txt"

ENTITY_ID="dev-execution-test"
ADDRESS="192.168.1.50"

mkdir -p "${FAKE_BIN}"

pass() {
    echo "[PASS] $*"
}

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

echo
echo "HomeLab Sentinel Nmap Service Discovery execution regression"
echo

[[ -x "${ENTRYPOINT}" ]] ||
    fail "Nmap Service Discovery entrypoint missing or not executable: ${ENTRYPOINT}"

cat > "${FAKE_BIN}/nmap" <<'FAKE'
#!/usr/bin/env bash

set -euo pipefail

printf '%s\n' "$@" > "${HLS_TEST_NMAP_ARGS}"

cat <<'XML'
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
    </ports>
  </host>
</nmaprun>
XML
FAKE

chmod +x "${FAKE_BIN}/nmap"

PATH="${FAKE_BIN}:${PATH}" \
HLS_TEST_NMAP_ARGS="${ARGS}" \
"${ENTRYPOINT}" \
    --entity-id "${ENTITY_ID}" \
    --address "${ADDRESS}" \
    > "${OUTPUT}"

python3 - "${OUTPUT}" "${ENTITY_ID}" "${ADDRESS}" <<'PY'
import json
import sys

output_file, entity_id, address = sys.argv[1:4]

with open(output_file, "r", encoding="utf-8") as handle:
    records = [json.loads(line) for line in handle if line.strip()]

if len(records) != 3:
    raise SystemExit(
        f"[FAIL] expected 3 normalized endpoint records, got {len(records)}"
    )

ports = {record["port"] for record in records}

if ports != {8006, 2222, 12345}:
    raise SystemExit(
        f"[FAIL] unexpected normalized ports: {sorted(ports)}"
    )

for record in records:
    if record["entity_id"] != entity_id:
        raise SystemExit("[FAIL] authoritative entity_id was not preserved")

    if record["address"] != address:
        raise SystemExit("[FAIL] authoritative target address was not preserved")

print("[PASS] provider output passes through Service Discovery normalizer")
print("[PASS] authoritative entity_id survives provider execution")
print("[PASS] authoritative target address survives provider execution")
PY

python3 - "${ARGS}" "${ADDRESS}" <<'PY'
import sys

args_file, address = sys.argv[1:3]

with open(args_file, "r", encoding="utf-8") as handle:
    args = [line.rstrip("\n") for line in handle]

if "-oX" not in args:
    raise SystemExit("[FAIL] Nmap XML output was not requested")

xml_index = args.index("-oX")

if xml_index + 1 >= len(args) or args[xml_index + 1] != "-":
    raise SystemExit("[FAIL] Nmap XML output is not directed to stdout")

if address not in args:
    raise SystemExit("[FAIL] target address was not passed to Nmap")

if args[-1] != address:
    raise SystemExit("[FAIL] target address is not the final Nmap argument")

print("[PASS] Nmap XML is emitted on stdout for normalization")
print("[PASS] requested target address is passed to Nmap")
PY

pass "Nmap Service Discovery provider execution contract"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Nmap Service Discovery execution regression PASSED"
