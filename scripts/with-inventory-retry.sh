#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

LOCK_WRAPPER="${APP_ROOT}/scripts/with-inventory-lock.sh"
LOCK_RETRY_DELAY="${LOCK_RETRY_DELAY:-30}"

if [[ "$#" -eq 0 ]]; then
    echo "Usage: $0 COMMAND [ARG ...]" >&2
    exit 64
fi

if [[ ! -x "${LOCK_WRAPPER}" ]]; then
    echo "Inventory lock wrapper is not executable: ${LOCK_WRAPPER}" >&2
    exit 69
fi

if [[ ! "${LOCK_RETRY_DELAY}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "LOCK_RETRY_DELAY must be a non-negative number" >&2
    exit 64
fi

set +e
"${LOCK_WRAPPER}" "$@"
rc=$?
set -e

if [[ "${rc}" -ne 75 ]]; then
    exit "${rc}"
fi

echo "Inventory runtime lock busy; retrying once after ${LOCK_RETRY_DELAY}s" >&2
sleep "${LOCK_RETRY_DELAY}"

set +e
"${LOCK_WRAPPER}" "$@"
rc=$?
set -e

if [[ "${rc}" -eq 75 ]]; then
    echo "Inventory runtime lock remained busy after retry; deferring this execution" >&2
fi

exit "${rc}"
