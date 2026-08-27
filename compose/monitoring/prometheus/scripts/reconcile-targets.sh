#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="${APP_ROOT:-/opt/homelab-sentinel/app}"

DATABASE="${DATABASE:-/srv/homelab-sentinel/sentinel/inventory.db}"
OUTPUT="${OUTPUT:-/srv/homelab-sentinel/prometheus/targets/reachability.json}"

MONITORING_CORE="${MONITORING_CORE:-${APP_ROOT}/core/monitoring/monitoring.py}"
RENDERER="${RENDERER:-${APP_ROOT}/compose/monitoring/prometheus/scripts/render-targets.py}"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

[[ -x "${MONITORING_CORE}" ]] ||
    fail "Monitoring Core unavailable: ${MONITORING_CORE}"

[[ -x "${RENDERER}" ]] ||
    fail "Prometheus target renderer unavailable: ${RENDERER}"

[[ -f "${DATABASE}" ]] ||
    fail "Inventory database unavailable: ${DATABASE}"

tmp_targets="$(mktemp)"
trap 'rm -f "${tmp_targets}"' EXIT

if ! "${MONITORING_CORE}" \
    --database "${DATABASE}" \
    targets \
    --json >"${tmp_targets}"; then

    fail "Unable to derive canonical Monitoring targets"
fi

canonical_count="$(
    awk 'NF {count++} END {print count+0}' "${tmp_targets}"
)"

if ! "${RENDERER}" \
    --output "${OUTPUT}" \
    <"${tmp_targets}"; then

    fail "Unable to reconcile Prometheus runtime targets"
fi

rendered_count="$(
    python3 - "${OUTPUT}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    groups = json.load(handle)

if not isinstance(groups, list):
    raise SystemExit("rendered Prometheus target state is not a JSON array")

print(len(groups))
PY
)" || fail "Unable to inspect rendered Prometheus target state"

echo "[PASS] Prometheus target reconciliation complete."
echo "Canonical targets : ${canonical_count}"
echo "Rendered targets  : ${rendered_count}"
echo "Output            : ${OUTPUT}"
