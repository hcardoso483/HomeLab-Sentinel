#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="${APP_ROOT:-/opt/homelab-sentinel/app}"
READ_MODEL="${APP_ROOT}/core/status/read_model.py"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo "HomeLab Sentinel structured status read-model regression"
echo

[[ -f "${READ_MODEL}" ]] \
    || fail "Canonical status read model not implemented: ${READ_MODEL}"

python3 - "${READ_MODEL}" <<'PY'
import importlib.util
import sys
from pathlib import Path

path = Path(sys.argv[1])

spec = importlib.util.spec_from_file_location(
    "homelab_sentinel_status_read_model",
    path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

if not hasattr(module, "build_status"):
    raise SystemExit("[FAIL] read model does not expose build_status()")

payload = module.build_status(
    ignore_verification_result=True,
)

if not isinstance(payload, dict):
    raise SystemExit("[FAIL] build_status() did not return a dict")

if payload.get("schema_version") != 1:
    raise SystemExit("[FAIL] status schema_version is not 1")

required_sections = (
    "platform",
    "core_api",
    "discovery",
    "inventory",
    "service_discovery",
    "monitoring",
    "verification",
)

for section in required_sections:
    if not isinstance(payload.get(section), dict):
        raise SystemExit(
            f"[FAIL] missing structured status section: {section}"
        )

if payload.get("overall") not in {
    "READY",
    "DEGRADED",
    "NOT INSTALLED",
}:
    raise SystemExit("[FAIL] invalid overall status")

service_discovery = payload["service_discovery"]

if service_discovery.get("readiness") != "READY":
    raise SystemExit(
        "[FAIL] Service Discovery readiness is not READY: "
        f"{service_discovery.get('readiness')!r}"
    )

provider = service_discovery.get("provider")
if not isinstance(provider, str) or not provider:
    raise SystemExit(
        "[FAIL] Service Discovery provider is not a non-empty string"
    )

service_targets = service_discovery.get("targets")
if (
    not isinstance(service_targets, int)
    or isinstance(service_targets, bool)
    or service_targets < 0
):
    raise SystemExit(
        "[FAIL] Service Discovery targets is not a non-negative integer"
    )

endpoints = service_discovery.get("endpoints")

if not isinstance(endpoints, dict):
    raise SystemExit(
        "[FAIL] Service Discovery endpoints summary missing"
    )

for state in ("observed", "stale"):
    value = endpoints.get(state)

    if (
        not isinstance(value, int)
        or isinstance(value, bool)
        or value < 0
    ):
        raise SystemExit(
            "[FAIL] Service Discovery endpoint count is invalid: "
            f"{state}"
        )

last_inspection = service_discovery.get("last_inspection")

if (
    last_inspection is not None
    and not isinstance(last_inspection, str)
):
    raise SystemExit(
        "[FAIL] Service Discovery last_inspection is invalid"
    )

retry_pool = service_discovery.get("retry_pool")

if (
    not isinstance(retry_pool, int)
    or isinstance(retry_pool, bool)
    or retry_pool < 0
):
    raise SystemExit(
        "[FAIL] Service Discovery retry_pool is invalid"
    )

for timer_name in ("normal_timer", "retry_timer"):
    timer = service_discovery.get(timer_name)

    if not isinstance(timer, dict):
        raise SystemExit(
            f"[FAIL] Service Discovery {timer_name} missing"
        )

    if timer.get("state") not in (
        "ACTIVE",
        "INACTIVE",
        "FAILED",
        "ACTIVATING",
        "DEACTIVATING",
        "UNKNOWN",
    ):
        raise SystemExit(
            f"[FAIL] Service Discovery {timer_name}.state invalid"
        )

    if timer.get("runtime") not in (
        "RUNNING",
        "WAITING",
        "INACTIVE",
        "UNKNOWN",
    ):
        raise SystemExit(
            f"[FAIL] Service Discovery {timer_name}.runtime invalid"
        )

    if not isinstance(timer.get("enabled"), bool):
        raise SystemExit(
            f"[FAIL] Service Discovery {timer_name}.enabled invalid"
        )

    schedule = timer.get("schedule")
    if schedule is not None and not isinstance(schedule, str):
        raise SystemExit(
            f"[FAIL] Service Discovery {timer_name}.schedule invalid"
        )

    last_trigger = timer.get("last_trigger")
    if (
        last_trigger is not None
        and not isinstance(last_trigger, str)
    ):
        raise SystemExit(
            f"[FAIL] Service Discovery {timer_name}.last_trigger invalid"
        )

    next_elapse = timer.get("next_elapse_monotonic")
    if (
        next_elapse is not None
        and not isinstance(next_elapse, str)
    ):
        raise SystemExit(
            f"[FAIL] Service Discovery "
            f"{timer_name}.next_elapse_monotonic invalid"
        )

print(
    "[PASS] Service Discovery="
    f"{service_discovery['readiness']}, "
    f"provider={provider}, "
    f"targets={service_targets}"
)

monitoring = payload["monitoring"]

entities = monitoring.get("entities")
if not isinstance(entities, dict):
    raise SystemExit("[FAIL] Monitoring entities summary missing")

for state in ("healthy", "degraded", "down", "unknown"):
    value = entities.get(state)
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise SystemExit(
            f"[FAIL] Monitoring entity count is not a non-negative integer: {state}"
        )

targets = monitoring.get("targets")
if not isinstance(targets, int) or isinstance(targets, bool) or targets < 0:
    raise SystemExit(
        "[FAIL] Monitoring targets is not a non-negative integer"
    )

if sum(entities.values()) != targets:
    raise SystemExit(
        "[FAIL] Monitoring entity counts do not equal target count"
    )


# The structured contract must distinguish an actual zero from
# unavailable Monitoring evaluation. Exercise that path by temporarily
# replacing the legacy evaluator used by the read model.
original_monitoring_health_status = (
    module.legacy.monitoring_health_status
)

try:
    module.legacy.monitoring_health_status = lambda: None

    unavailable = module.build_status(
        ignore_verification_result=True,
    )
finally:
    module.legacy.monitoring_health_status = (
        original_monitoring_health_status
    )

monitoring = unavailable["monitoring"]

if monitoring["evidence"] != "UNKNOWN":
    raise SystemExit(
        "[FAIL] unavailable Monitoring evidence is not UNKNOWN"
    )

if monitoring["targets"] is not None:
    raise SystemExit(
        "[FAIL] unavailable Monitoring targets must be null, "
        f"got {monitoring['targets']!r}"
    )

for state, value in monitoring["entities"].items():
    if value is not None:
        raise SystemExit(
            "[FAIL] unavailable Monitoring entity count must be null: "
            f"{state}={value!r}"
        )

if unavailable["overall"] != "DEGRADED":
    raise SystemExit(
        "[FAIL] unavailable Monitoring evidence must degrade Sentinel"
    )

print("[PASS] unavailable Monitoring remains unknown")

print("[PASS] canonical status read-model contract")
print(f"[PASS] overall={payload['overall']}")
print(
    "[PASS] monitoring="
    f"{entities['healthy']} healthy, "
    f"{entities['degraded']} degraded, "
    f"{entities['down']} down, "
    f"{entities['unknown']} unknown"
)
PY

pass "structured status read-model regression"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel structured status read-model regression PASSED"
