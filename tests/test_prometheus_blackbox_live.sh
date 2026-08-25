#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
PROM_ROOT="${APP_ROOT}/compose/monitoring/prometheus"
TARGET="${HLS_BLACKBOX_TEST_TARGET:-192.168.1.254}"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

echo "HomeLab Sentinel Blackbox live ICMP probe test"
echo
echo "Target : ${TARGET}"
echo

cd "${PROM_ROOT}"
docker compose up -d blackbox >/dev/null

READY=false
for _ in $(seq 1 30); do
    if docker exec homelab-sentinel-prometheus         wget -qO- http://blackbox:9115/ >/dev/null 2>&1; then
        READY=true
        break
    fi
    sleep 1
done

[[ "${READY}" == "true" ]] ||     fail "Blackbox provider endpoint did not become reachable"

pass "Blackbox provider sidecar reachable"

OUTPUT="$(
    docker exec homelab-sentinel-prometheus       wget -qO-       "http://blackbox:9115/probe?target=${TARGET}&module=icmp_ipv4"
)"

grep -q '^probe_success 1$' <<<"${OUTPUT}" || fail "ICMP probe did not report probe_success 1"
pass "Blackbox ICMP probe succeeded"

grep -q '^probe_duration_seconds ' <<<"${OUTPUT}" || fail "Blackbox probe duration metric missing"
pass "Blackbox probe timing evidence available"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Blackbox live ICMP probe PASSED"
