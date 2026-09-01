#!/usr/bin/env bash
set -euo pipefail

ENTITY_ID=""
ADDRESS=""
SCAN_BUDGET_SECONDS="600"

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
        --scan-budget-seconds)
            [[ $# -ge 2 ]] || {
                echo "[ERROR] Missing value for --scan-budget-seconds" >&2
                exit 1
            }
            SCAN_BUDGET_SECONDS="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Unknown argument: $1" >&2
            echo "[ERROR] Usage: $0 --entity-id <entity-id> --address <address> [--scan-budget-seconds <seconds>]" >&2
            exit 1
            ;;
    esac
done

if [[ -z "${ENTITY_ID}" || -z "${ADDRESS}" ]]; then
    echo "[ERROR] Usage: $0 --entity-id <entity-id> --address <address> [--scan-budget-seconds <seconds>]" >&2
    exit 1
fi

if [[ ! "${SCAN_BUDGET_SECONDS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] --scan-budget-seconds must be a positive integer" >&2
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

ATTEMPT_STARTED_SECONDS="${SECONDS}"

remaining_budget_seconds() {
    local elapsed
    local remaining

    elapsed=$((SECONDS - ATTEMPT_STARTED_SECONDS))
    remaining=$((SCAN_BUDGET_SECONDS - elapsed))

    if (( remaining <= 0 )); then
        printf '0\n'
    else
        printf '%s\n' "${remaining}"
    fi
}

xml_host_timed_out() {
    python3 - "$1" <<'PYXML'
import sys
import xml.etree.ElementTree as ET

try:
    root = ET.parse(sys.argv[1]).getroot()
except (ET.ParseError, OSError):
    raise SystemExit(1)

for host in root.findall("host"):
    if host.get("timedout", "").lower() == "true":
        raise SystemExit(0)

raise SystemExit(1)
PYXML
}

#
# Stage 1:
# Discover every open TCP endpoint.
#
STAGE1_REMAINING="$(remaining_budget_seconds)"

if (( STAGE1_REMAINING <= 0 )); then
    echo "[WARN] Nmap endpoint discovery exhausted the attempt budget for ${ADDRESS}." >&2
    exit 75
fi

STAGE1_HOST_TIMEOUT="${STAGE1_REMAINING}s"

nmap \
    --privileged \
    -n \
    -Pn \
    -sS \
    -p- \
    --defeat-rst-ratelimit \
    --host-timeout "${STAGE1_HOST_TIMEOUT}" \
    -oX - \
    -- \
    "${ADDRESS}" \
    > "${STAGE1_XML}"

if xml_host_timed_out "${STAGE1_XML}"; then
    echo "[WARN] Nmap endpoint discovery exhausted the attempt budget for ${ADDRESS}." >&2
    exit 75
fi

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
STAGE2_REMAINING="$(remaining_budget_seconds)"

if (( STAGE2_REMAINING > 0 )); then
    STAGE2_HOST_TIMEOUT="${STAGE2_REMAINING}s"

    if nmap \
    --privileged \
    -n \
    -Pn \
    -sS \
    -sV \
        --version-light \
        -p "${OPEN_PORTS}" \
        --host-timeout "${STAGE2_HOST_TIMEOUT}" \
        -oX - \
    -- \
    "${ADDRESS}" \
    > "${STAGE2_XML}"
then
        if xml_host_timed_out "${STAGE2_XML}"; then
            echo "[WARN] Nmap service identification exhausted the remaining attempt budget for ${ADDRESS}; preserving Stage 1 endpoint evidence." >&2
        else
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
    fi
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
