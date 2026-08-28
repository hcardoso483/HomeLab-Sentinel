#!/usr/bin/env bash

set -Eeuo pipefail

LOCK_FILE="${LOCK_FILE:-/srv/homelab-sentinel/sentinel/runtime/inventory-runtime.lock}"
LOCK_TIMEOUT="${LOCK_TIMEOUT:-120}"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

[[ "$#" -gt 0 ]] ||
    fail "No command supplied."

command -v flock >/dev/null 2>&1 ||
    fail "flock is not available."

LOCK_DIR="$(dirname "${LOCK_FILE}")"

[[ -d "${LOCK_DIR}" ]] ||
    fail "Lock directory does not exist: ${LOCK_DIR}"

[[ -w "${LOCK_DIR}" ]] ||
    fail "Lock directory is not writable: ${LOCK_DIR}"

echo "[INFO] Waiting for Sentinel inventory runtime lock: ${LOCK_FILE}"

if flock \
    --exclusive \
    --wait "${LOCK_TIMEOUT}" \
    --conflict-exit-code 75 \
    "${LOCK_FILE}" \
    "$@"
then
    exit 0
else
    rc=$?

    if [[ "${rc}" -eq 75 ]]; then
        echo "[ERROR] Timed out waiting for Sentinel inventory runtime lock." >&2
    else
        echo "[ERROR] Locked command failed with exit code ${rc}." >&2
    fi

    exit "${rc}"
fi
