#!/usr/bin/env bash

set -Eeuo pipefail

TIMEOUT_SECONDS=10
ATTEMPTS=3
INTERVAL=5

while (( $# > 0 )); do
    case "$1" in
        --timeout)
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --attempts)
            ATTEMPTS="$2"
            shift 2
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "[ERROR] Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

(( $# > 0 )) || {
    echo "[ERROR] No command provided." >&2
    exit 2
}

(( ATTEMPTS >= 1 )) || {
    echo "[ERROR] Attempts must be at least 1." >&2
    exit 2
}

attempt=1

while (( attempt <= ATTEMPTS )); do
    set +e
    output="$(timeout "${TIMEOUT_SECONDS}" "$@" 2>&1)"
    rc=$?
    set -e

    if (( rc == 0 )); then
        printf '%s\n' "${output}"
        exit 0
    fi

    if (( rc != 124 )); then
        [[ -n "${output}" ]] && printf '%s\n' "${output}" >&2
        exit "${rc}"
    fi

    if (( attempt >= ATTEMPTS )); then
        [[ -n "${output}" ]] && printf '%s\n' "${output}" >&2
        exit 124
    fi

    echo \
        "[INFO] Command timed out; retrying " \
        "$((attempt + 1))/${ATTEMPTS}..." \
        >&2

    sleep "${INTERVAL}"

    attempt=$((attempt + 1))
done

exit 124
