#!/usr/bin/env bash

set -euo pipefail

PROMETHEUS_URL="http://localhost:9090/-/healthy"

if curl -fsS "${PROMETHEUS_URL}" >/dev/null; then
    echo "[HEALTHY] Prometheus is responding."
    exit 0
else
    echo "[UNHEALTHY] Prometheus is not responding."
    exit 1
fi
