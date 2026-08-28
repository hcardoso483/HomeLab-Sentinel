#!/usr/bin/env bash

set -Eeuo pipefail

SERVICE_USER="${SERVICE_USER:-homelab-sentinel}"
SERVICE_GROUP="${SERVICE_GROUP:-homelab-sentinel}"
TARGET_DIR="${TARGET_DIR:-/srv/homelab-sentinel/prometheus/targets}"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

id "${SERVICE_USER}" >/dev/null 2>&1 ||
    fail "Service user does not exist: ${SERVICE_USER}"

getent group "${SERVICE_GROUP}" >/dev/null 2>&1 ||
    fail "Service group does not exist: ${SERVICE_GROUP}"

install \
    -d \
    -m 0775 \
    -o "${SERVICE_USER}" \
    -g "${SERVICE_GROUP}" \
    "${TARGET_DIR}"

echo "[PASS] Prometheus runtime target directory prepared."
echo "Path  : ${TARGET_DIR}"
echo "Owner : ${SERVICE_USER}:${SERVICE_GROUP}"
echo "Mode  : 0775"
