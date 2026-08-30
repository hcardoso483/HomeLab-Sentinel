#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENTRYPOINT="${APP_ROOT}/compose/discovery/nmap/scripts/discover-services.sh"

TMP_DIR="$(mktemp -d /tmp/hls-service-discovery-policy.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${FAKE_BIN}"

ENTITY_ID="dev-policy-test"
ADDRESS="192.168.1.50"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

[[ -x "${ENTRYPOINT}" ]] ||
    fail "Service Discovery entrypoint missing: ${ENTRYPOINT}"

cat > "${FAKE_BIN}/nmap" <<'FAKE'
#!/usr/bin/env bash

set -euo pipefail

STATE_DIR="${HLS_TEST_STATE_DIR}"
COUNT_FILE="${STATE_DIR}/count"

if [[ -f "${COUNT_FILE}" ]]; then
    COUNT="$(cat "${COUNT_FILE}")"
else
    COUNT=0
fi

COUNT=$((COUNT + 1))
printf '%s\n' "${COUNT}" > "${COUNT_FILE}"
printf '%s\n' "$@" > "${STATE_DIR}/args-${COUNT}.txt"

if [[ "${COUNT}" -eq 1 ]]; then
    cat <<'XML'
<nmaprun>
  <host starttime="1788032400" endtime="1788032405">
    <status state="up"/>
    <address addr="192.168.1.50" addrtype="ipv4"/>
    <ports>
      <port protocol="tcp" portid="8006">
        <state state="open"/>
        <service name="http-alt"/>
      </port>
      <port protocol="tcp" portid="2222">
        <state state="open"/>
        <service name="EtherNetIP-1"/>
      </port>
      <port protocol="tcp" portid="12345">
        <state state="open"/>
        <service name="netbus"/>
      </port>
    </ports>
  </host>
</nmaprun>
XML
    exit 0
fi

if [[ "${HLS_TEST_STAGE2_FAIL:-0}" == "1" ]]; then
    echo "simulated service-identification failure" >&2
    exit 7
fi

cat <<'XML'
<nmaprun>
  <host starttime="1788032410" endtime="1788032415">
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
    </ports>
  </host>
</nmaprun>
XML
FAKE

chmod +x "${FAKE_BIN}/nmap"

echo
echo "HomeLab Sentinel Nmap Service Discovery scan-policy regression"
echo

SUCCESS_STATE="${TMP_DIR}/success"
mkdir -p "${SUCCESS_STATE}"

PATH="${FAKE_BIN}:${PATH}" \
HLS_TEST_STATE_DIR="${SUCCESS_STATE}" \
"${ENTRYPOINT}" \
    "${ENTITY_ID}" \
    "${ADDRESS}" \
    > "${TMP_DIR}/success.jsonl"

python3 - \
    "${SUCCESS_STATE}" \
    "${TMP_DIR}/success.jsonl" \
    "${ENTITY_ID}" \
    "${ADDRESS}" <<'PY'
import json
import pathlib
import sys

state_dir = pathlib.Path(sys.argv[1])
output_file = pathlib.Path(sys.argv[2])
entity_id = sys.argv[3]
address = sys.argv[4]

count = int((state_dir / "count").read_text().strip())

if count != 2:
    raise SystemExit(
        f"[FAIL] expected exactly 2 Nmap invocations, got {count}"
    )

args1 = (state_dir / "args-1.txt").read_text().splitlines()
args2 = (state_dir / "args-2.txt").read_text().splitlines()

required_stage1 = {
    "--privileged",
    "-n",
    "-Pn",
    "-sS",
    "-p-",
    "-oX",
    "-",
    "--",
    address,
}

missing = required_stage1 - set(args1)

if missing:
    raise SystemExit(
        f"[FAIL] Stage 1 missing arguments: {sorted(missing)}"
    )

if "-sV" in args1:
    raise SystemExit(
        "[FAIL] Stage 1 must not perform service identification"
    )

required_stage2 = {
    "--privileged",
    "-n",
    "-Pn",
    "-sS",
    "-sV",
    "--version-light",
    "-oX",
    "-",
    "--",
    address,
}

missing = required_stage2 - set(args2)

if missing:
    raise SystemExit(
        f"[FAIL] Stage 2 missing arguments: {sorted(missing)}"
    )

if "-p-" in args2:
    raise SystemExit(
        "[FAIL] Stage 2 must not service-probe all 65535 ports"
    )

if "-p" not in args2:
    raise SystemExit(
        "[FAIL] Stage 2 did not receive discovered-port selection"
    )

port_index = args2.index("-p")

if port_index + 1 >= len(args2):
    raise SystemExit(
        "[FAIL] Stage 2 -p has no port list"
    )

ports = {
    int(value)
    for value in args2[port_index + 1].split(",")
}

if ports != {2222, 8006, 12345}:
    raise SystemExit(
        f"[FAIL] Stage 2 ports incorrect: {sorted(ports)}"
    )

records = [
    json.loads(line)
    for line in output_file.read_text().splitlines()
    if line.strip()
]

if len(records) != 3:
    raise SystemExit(
        f"[FAIL] expected 3 final endpoint records, got {len(records)}"
    )

by_port = {
    record["port"]: record
    for record in records
}

expected_services = {
    2222: "ssh",
    8006: "http",
    12345: None,
}

for port, expected_service in expected_services.items():
    record = by_port.get(port)

    if record is None:
        raise SystemExit(
            f"[FAIL] missing endpoint {port}/tcp"
        )

    if record["entity_id"] != entity_id:
        raise SystemExit(
            "[FAIL] authoritative entity_id changed"
        )

    if record["address"] != address:
        raise SystemExit(
            "[FAIL] authoritative address changed"
        )

    if record["service"] != expected_service:
        raise SystemExit(
            f"[FAIL] port {port} service={record['service']!r}, "
            f"expected {expected_service!r}"
        )

print("[PASS] Stage 1 scans the full TCP range with SYN discovery")
print("[PASS] Stage 1 does not perform service identification")
print("[PASS] Stage 2 probes only ports discovered open by Stage 1")
print("[PASS] Stage 2 performs lightweight service identification")
print("[PASS] final evidence uses Stage 2 service identification")
PY

FAIL_STATE="${TMP_DIR}/failure"
mkdir -p "${FAIL_STATE}"

set +e
PATH="${FAKE_BIN}:${PATH}" \
HLS_TEST_STATE_DIR="${FAIL_STATE}" \
HLS_TEST_STAGE2_FAIL=1 \
"${ENTRYPOINT}" \
    "${ENTITY_ID}" \
    "${ADDRESS}" \
    > "${TMP_DIR}/failure.jsonl" \
    2> "${TMP_DIR}/failure.stderr"

FAIL_RC=$?
set -e

if [[ "${FAIL_RC}" -ne 0 ]]; then
    fail "Stage 2 identification failure caused provider failure: exit=${FAIL_RC}"
fi

python3 - \
    "${FAIL_STATE}" \
    "${TMP_DIR}/failure.jsonl" <<'PY'
import json
import pathlib
import sys

state_dir = pathlib.Path(sys.argv[1])
output_file = pathlib.Path(sys.argv[2])

count = int((state_dir / "count").read_text().strip())

if count != 2:
    raise SystemExit(
        f"[FAIL] failure scenario expected 2 Nmap calls, got {count}"
    )

records = [
    json.loads(line)
    for line in output_file.read_text().splitlines()
    if line.strip()
]

if len(records) != 3:
    raise SystemExit(
        "[FAIL] Stage 1 endpoint evidence was lost after Stage 2 failure"
    )

ports = {record["port"] for record in records}

if ports != {2222, 8006, 12345}:
    raise SystemExit(
        f"[FAIL] wrong fallback endpoints: {sorted(ports)}"
    )

for record in records:
    if record["service"] is not None:
        raise SystemExit(
            "[FAIL] Stage 1 port-number labels leaked into service identity"
        )

print("[PASS] Stage 2 failure preserves Stage 1 open-port evidence")
print("[PASS] Stage 1 port-database labels are not treated as service identity")
PY

if ! grep -qi 'service' "${TMP_DIR}/failure.stderr"; then
    fail "Stage 2 failure did not produce a diagnostic"
fi

pass "Nmap Service Discovery two-stage policy contract"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Nmap Service Discovery scan-policy regression PASSED"
