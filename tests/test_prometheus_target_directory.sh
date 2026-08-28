#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

INSTALLER="${APP_ROOT}/compose/monitoring/prometheus/scripts/install.sh"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

[[ -x "${INSTALLER}" ]] ||
    fail "Prometheus installer is not executable"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

TARGET_DIR="${TMP_ROOT}/targets"

SERVICE_USER="$(id -un)"
SERVICE_GROUP="$(id -gn)"

TARGET_DIR="${TARGET_DIR}" \
SERVICE_USER="${SERVICE_USER}" \
SERVICE_GROUP="${SERVICE_GROUP}" \
"${INSTALLER}" >/dev/null

[[ -d "${TARGET_DIR}" ]] ||
    fail "Target directory was not created"

mode="$(stat -c '%a' "${TARGET_DIR}")"
owner="$(stat -c '%U:%G' "${TARGET_DIR}")"

[[ "${mode}" == "775" ]] ||
    fail "Unexpected target directory mode: ${mode}"

[[ "${owner}" == "${SERVICE_USER}:${SERVICE_GROUP}" ]] ||
    fail "Unexpected target directory owner: ${owner}"

touch "${TARGET_DIR}/write-test" ||
    fail "Target directory is not writable by configured owner"

pass "Prometheus target directory is created"
pass "Prometheus target directory mode is 0775"
pass "Prometheus target directory ownership is configurable"
pass "Configured service identity can write provider runtime state"
