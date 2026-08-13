#!/usr/bin/env bash

set -euo pipefail

HOST="${HOMEPAGE_HEALTHCHECK_HOST:-127.0.0.1}"
PORT="${HOMEPAGE_HEALTHCHECK_PORT:-3000}"
URL="http://${HOST}:${PORT}/api/healthcheck"

if curl --fail --silent --show-error --max-time 5 "${URL}" >/dev/null; then
    echo "[HEALTHY] Homepage is responding."
    exit 0
fi

echo "[ERROR] Homepage healthcheck failed."
echo "[DETAIL] Unable to reach: ${URL}"
exit 1
