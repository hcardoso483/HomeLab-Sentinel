#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSTEMD_DIR="${APP_ROOT}/installer/systemd"
SERVICE="${SYSTEMD_DIR}/homelab-sentinel-service-discovery.service"
TIMER="${SYSTEMD_DIR}/homelab-sentinel-service-discovery.timer"
RETRY="${APP_ROOT}/scripts/with-inventory-retry.sh"
BATCH="${APP_ROOT}/core/service_discovery/batch.py"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo "HomeLab Sentinel Service Discovery systemd regression"
echo

[[ -f "${SERVICE}" ]] || fail "Service Discovery systemd service missing: ${SERVICE}"
[[ -f "${TIMER}" ]] || fail "Service Discovery systemd timer missing: ${TIMER}"
[[ -x "${RETRY}" ]] || fail "inventory retry wrapper missing or not executable: ${RETRY}"
[[ -x "${BATCH}" ]] || fail "Service Discovery batch orchestrator missing or not executable: ${BATCH}"

grep -Fqx "Type=oneshot" "${SERVICE}" \
    || fail "Service Discovery service is not Type=oneshot"
pass "Service Discovery service is oneshot"

grep -Fqx "User=homelab-sentinel" "${SERVICE}" \
    || fail "Service Discovery service does not run as homelab-sentinel"
grep -Fqx "Group=homelab-sentinel" "${SERVICE}" \
    || fail "Service Discovery service does not run as homelab-sentinel group"
pass "Service Discovery service uses the canonical service identity"

grep -Fqx "WorkingDirectory=/opt/homelab-sentinel/app" "${SERVICE}" \
    || fail "Service Discovery service has unexpected WorkingDirectory"
pass "Service Discovery service uses the canonical application root"

grep -Fqx "ConditionPathExists=/opt/homelab-sentinel/app/scripts/with-inventory-lock.sh" "${SERVICE}" \
    || fail "Service Discovery service does not require the canonical inventory lock wrapper"
grep -Fqx "ConditionPathExists=/opt/homelab-sentinel/app/scripts/with-inventory-retry.sh" "${SERVICE}" \
    || fail "Service Discovery service does not require the bounded inventory retry wrapper"
grep -Fqx "ConditionPathExists=/opt/homelab-sentinel/app/core/service_discovery/batch.py" "${SERVICE}" \
    || fail "Service Discovery service does not require the batch orchestrator"
pass "Service Discovery service declares its scheduling/runtime dependencies"

exec_line="$(
    grep '^ExecStart=' "${SERVICE}" || true
)"
[[ -n "${exec_line}" ]] || fail "Service Discovery service has no ExecStart"

expected_exec="ExecStart=/opt/homelab-sentinel/app/scripts/with-inventory-retry.sh /opt/homelab-sentinel/app/core/service_discovery/batch.py --database /srv/homelab-sentinel/sentinel/inventory.db --json"
[[ "${exec_line}" == "${expected_exec}" ]] \
    || fail "Service Discovery ExecStart does not use retry wrapper -> batch orchestrator"
pass "Service Discovery scheduled execution uses bounded retry and the canonical batch"

if [[ "${exec_line}" == *"/scripts/with-inventory-lock.sh"* ]]; then
    fail "Service Discovery ExecStart bypasses retry policy by invoking the lock wrapper directly"
fi
pass "Service Discovery ExecStart does not bypass the retry policy"

grep -Fqx "AmbientCapabilities=CAP_NET_RAW" "${SERVICE}" \
    || fail "Service Discovery service does not grant CAP_NET_RAW"
grep -Fqx "CapabilityBoundingSet=CAP_NET_RAW" "${SERVICE}" \
    || fail "Service Discovery service does not bound capabilities to CAP_NET_RAW"
pass "Service Discovery service grants only the raw-socket capability required by the current provider"

grep -Fqx "NoNewPrivileges=true" "${SERVICE}" \
    || fail "Service Discovery service does not enable NoNewPrivileges"
grep -Fqx "PrivateTmp=true" "${SERVICE}" \
    || fail "Service Discovery service does not enable PrivateTmp"
pass "Service Discovery service retains basic systemd hardening"

grep -Fqx "Unit=homelab-sentinel-service-discovery.service" "${TIMER}" \
    || fail "Service Discovery timer does not activate the canonical service"
grep -Fqx "OnBootSec=10min" "${TIMER}" \
    || fail "Service Discovery timer does not use the expected conservative boot delay"
grep -Fqx "OnUnitActiveSec=30min" "${TIMER}" \
    || fail "Service Discovery timer does not use the expected 30 minute cadence"
grep -Fqx "AccuracySec=1min" "${TIMER}" \
    || fail "Service Discovery timer does not use the expected accuracy window"
grep -Fqx "Persistent=true" "${TIMER}" \
    || fail "Service Discovery timer is not persistent"
pass "Service Discovery timer uses the conservative v1 schedule"

grep -Fqx "WantedBy=timers.target" "${TIMER}" \
    || fail "Service Discovery timer is not installable through timers.target"
pass "Service Discovery timer is enableable through timers.target"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery systemd regression PASSED"
