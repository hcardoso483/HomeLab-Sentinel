#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
ENTRYPOINT="${APP_ROOT}/compose/discovery/nmap/scripts/discover-services.sh"

TMP_DIR="$(mktemp -d /tmp/hls-service-discovery-provider-args.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
OUTPUT="${TMP_DIR}/output.jsonl"
ENTITY_ID="dev-0123456789abcdef0123456789abcdef"
ADDRESS="192.168.1.58"

mkdir -p "${FAKE_BIN}"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo
echo "HomeLab Sentinel Service Discovery provider argument regression"
echo

[[ -x "${ENTRYPOINT}" ]] \
    || fail "Service Discovery provider entrypoint missing or not executable: ${ENTRYPOINT}"

cat > "${FAKE_BIN}/nmap" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

cat <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<nmaprun scanner="nmap">
  <host>
    <status state="up"/>
    <address addr="192.168.1.58" addrtype="ipv4"/>
    <ports>
      <port protocol="tcp" portid="8006">
        <state state="open"/>
        <service name="http" method="probed" conf="10"/>
      </port>
    </ports>
  </host>
</nmaprun>
XML
FAKE

chmod +x "${FAKE_BIN}/nmap"

if ! PATH="${FAKE_BIN}:${PATH}" \
    "${ENTRYPOINT}" \
    --entity-id "${ENTITY_ID}" \
    --address "${ADDRESS}" \
    > "${OUTPUT}"
then
    fail "provider rejected canonical named arguments"
fi

python3 - "${OUTPUT}" "${ENTITY_ID}" "${ADDRESS}" <<'PY'
import json
import sys

output_file, entity_id, address = sys.argv[1:4]

with open(output_file, "r", encoding="utf-8") as handle:
    records = [
        json.loads(line)
        for line in handle
        if line.strip()
    ]

if len(records) != 1:
    raise SystemExit(
        f"[FAIL] expected 1 normalized endpoint record, got {len(records)}"
    )

record = records[0]

if record["entity_id"] != entity_id:
    raise SystemExit(
        f"[FAIL] expected entity_id {entity_id}, got {record['entity_id']}"
    )

if record["address"] != address:
    raise SystemExit(
        f"[FAIL] expected address {address}, got {record['address']}"
    )

if record["protocol"] != "tcp" or record["port"] != 8006:
    raise SystemExit("[FAIL] provider output endpoint was not preserved")
PY

pass "provider accepts canonical --entity-id/--address arguments"
pass "canonical entity_id survives provider argument boundary"
pass "canonical address survives provider argument boundary"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery provider argument regression PASSED"
