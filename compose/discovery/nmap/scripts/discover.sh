#!/usr/bin/env bash

set -euo pipefail

TARGET="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NORMALIZER="${SCRIPT_DIR}/normalize.py"

if [[ -z "${TARGET}" ]]; then
    echo "[ERROR] Usage: $0 <target>" >&2
    exit 1
fi

if ! command -v nmap >/dev/null 2>&1; then
    echo "[ERROR] Required command not found: nmap" >&2
    exit 1
fi

if [[ ! -x "${NORMALIZER}" ]]; then
    echo "[ERROR] Nmap normalizer is missing or not executable: ${NORMALIZER}" >&2
    exit 1
fi

nmap --privileged -sn -oX - -- "${TARGET}" | "${NORMALIZER}"
