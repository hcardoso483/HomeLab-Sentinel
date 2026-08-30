#!/usr/bin/env bash

set -euo pipefail

ENTITY_ID="${1:-}"
ADDRESS="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NORMALIZER="${SCRIPT_DIR}/normalize-services.py"

if [[ -z "${ENTITY_ID}" || -z "${ADDRESS}" ]]; then
    echo "[ERROR] Usage: $0 <entity-id> <address>" >&2
    exit 1
fi

if ! command -v nmap >/dev/null 2>&1; then
    echo "[ERROR] Required command not found: nmap" >&2
    exit 1
fi

if [[ ! -x "${NORMALIZER}" ]]; then
    echo "[ERROR] Nmap Service Discovery normalizer is missing or not executable: ${NORMALIZER}" >&2
    exit 1
fi

nmap \
    -oX - \
    -- \
    "${ADDRESS}" |
    "${NORMALIZER}" \
        --entity-id "${ENTITY_ID}" \
        --address "${ADDRESS}"
