#!/usr/bin/env bash
set -euo pipefail

ENTITY_ID=""
ADDRESS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --entity-id)
            [[ $# -ge 2 ]] || {
                echo "[ERROR] Missing value for --entity-id" >&2
                exit 1
            }
            ENTITY_ID="$2"
            shift 2
            ;;
        --address)
            [[ $# -ge 2 ]] || {
                echo "[ERROR] Missing value for --address" >&2
                exit 1
            }
            ADDRESS="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Unknown argument: $1" >&2
            echo "[ERROR] Usage: $0 --entity-id <entity-id> --address <address>" >&2
            exit 1
            ;;
    esac
done

if [[ -z "${ENTITY_ID}" || -z "${ADDRESS}" ]]; then
    echo "[ERROR] Usage: $0 --entity-id <entity-id> --address <address>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NORMALIZER="${SCRIPT_DIR}/normalize-services.py"

if ! command -v nmap >/dev/null 2>&1; then
    echo "[ERROR] Required command not found: nmap" >&2
    exit 1
fi

if [[ ! -x "${NORMALIZER}" ]]; then
    echo "[ERROR] Nmap Service Discovery normalizer is missing or not executable: ${NORMALIZER}" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d /tmp/hls-nmap-service-discovery.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

STAGE1_XML="${TMP_DIR}/stage1.xml"
STAGE2_XML="${TMP_DIR}/stage2.xml"
STAGE1_JSON="${TMP_DIR}/stage1.jsonl"
STAGE2_JSON="${TMP_DIR}/stage2.jsonl"

#
# Stage 1:
# Discover every open TCP endpoint.
#
nmap \
    --privileged \
    -n \
    -Pn \
    -sS \
    -p- \
    -oX - \
    -- \
    "${ADDRESS}" \
    > "${STAGE1_XML}"

#
# Derive the exact set of open TCP ports from Stage 1 evidence.
#
OPEN_PORTS="$(
    python3 - "${STAGE1_XML}" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]

try:
    tree = ET.parse(path)
except ET.ParseError as error:
    print(f"[ERROR] Invalid Stage 1 Nmap XML: {error}", file=sys.stderr)
    raise SystemExit(1)

ports = set()

for host in tree.getroot().findall("host"):
    status = host.find("status")

    if status is not None and status.get("state") != "up":
        continue

    for port in host.findall("./ports/port"):
        if port.get("protocol") != "tcp":
            continue

        state = port.find("state")

        if state is None or state.get("state") != "open":
            continue

        try:
            number = int(port.get("portid"))
        except (TypeError, ValueError):
            continue

        if 1 <= number <= 65535:
            ports.add(number)

print(",".join(str(port) for port in sorted(ports)))
PY
)"

#
# No open TCP endpoints means Stage 1 is already authoritative.
#
if [[ -z "${OPEN_PORTS}" ]]; then
    "${NORMALIZER}" \
        --entity-id "${ENTITY_ID}" \
        --address "${ADDRESS}" \
        --suppress-services \
        < "${STAGE1_XML}"

    exit 0
fi

#
# Stage 2:
# Perform lightweight service identification only against ports
# that Stage 1 actually observed open.
#
if nmap \
    --privileged \
    -n \
    -Pn \
    -sS \
    -sV \
    --version-light \
    -p "${OPEN_PORTS}" \
    -oX - \
    -- \
    "${ADDRESS}" \
    > "${STAGE2_XML}"
then
    #
    # Stage 1 remains authoritative for endpoint existence.
    # Stage 2 may enrich matching endpoints with trusted service identity,
    # but it must not create or remove endpoint facts.
    #
    "${NORMALIZER}" \
        --entity-id "${ENTITY_ID}" \
        --address "${ADDRESS}" \
        --suppress-services \
        < "${STAGE1_XML}" \
        > "${STAGE1_JSON}"

    "${NORMALIZER}" \
        --entity-id "${ENTITY_ID}" \
        --address "${ADDRESS}" \
        < "${STAGE2_XML}" \
        > "${STAGE2_JSON}"

    python3 - "${STAGE1_JSON}" "${STAGE2_JSON}" <<'MERGEPY'
import json
import pathlib
import sys

stage1_path = pathlib.Path(sys.argv[1])
stage2_path = pathlib.Path(sys.argv[2])


def load(path):
    return [
        json.loads(line)
        for line in path.read_text().splitlines()
        if line.strip()
    ]


stage1 = load(stage1_path)
stage2 = load(stage2_path)

enrichment = {
    (record["protocol"], record["port"]): record.get("service")
    for record in stage2
    if record.get("service") is not None
}

for record in stage1:
    key = (record["protocol"], record["port"])

    if key in enrichment:
        record["service"] = enrichment[key]

    print(json.dumps(record, sort_keys=True))
MERGEPY

    exit 0
fi

#
# Service identification is enrichment, not endpoint authority.
# If Stage 2 fails, preserve Stage 1 open-port evidence while
# suppressing port-database service guesses.
#
echo "[WARN] Nmap service identification failed for ${ADDRESS}; preserving open-port evidence without service identity." >&2

"${NORMALIZER}" \
    --entity-id "${ENTITY_ID}" \
    --address "${ADDRESS}" \
    --suppress-services \
    < "${STAGE1_XML}"
