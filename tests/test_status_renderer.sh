#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="${APP_ROOT:-/opt/homelab-sentinel/app}"
RENDERER="${APP_ROOT}/core/status/render.py"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo "HomeLab Sentinel status renderer regression"
echo

[[ -f "${RENDERER}" ]] \
    || fail "Canonical status renderer not found: ${RENDERER}"

python3 - "${RENDERER}" <<'PY'
import importlib.util
import sys
from pathlib import Path


path = Path(sys.argv[1])

spec = importlib.util.spec_from_file_location(
    "homelab_sentinel_status_renderer",
    path,
)

module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def expect(description, actual, expected):
    if actual != expected:
        raise SystemExit(
            f"[FAIL] {description}: "
            f"expected={expected!r}, actual={actual!r}"
        )

    print(f"[PASS] {description}")


def ready_payload():
    return {
        "schema_version": 1,
        "overall": "READY",
        "platform": {
            "installation": "READY",
            "service_identity": "READY",
        },
        "core_api": {
            "service": "ACTIVE",
            "runtime_identity": "CORRECT",
            "health": "HEALTHY",
            "endpoint": "127.0.0.1:8000",
        },
        "discovery": {
            "scheduler": "ACTIVE",
            "schedule": "ENABLED",
            "schedule_policy": "COMPLIANT",
            "runtime": "HEALTHY",
            "provider": "nmap",
            "last_run": "SUCCESS",
            "last_success": "2026-01-01T00:00:00Z",
            "freshness": "FRESH",
            "attempt": "1/2",
            "recovery": "NOT REQUIRED",
        },
        "inventory": {
            "database": "READY",
            "schema": "v3",
            "integrity": "OK",
        },
        "monitoring": {
            "scheduler": "ACTIVE",
            "schedule": "ENABLED",
            "reconciliation": "HEALTHY",
            "provider": "prometheus",
            "collection": "HEALTHY",
            "evidence": "FRESH",
            "targets": 71,
            "entities": {
                "healthy": 48,
                "degraded": 1,
                "down": 22,
                "unknown": 0,
            },
        },
        "verification": {
            "post_boot_schedule": "ENABLED",
            "last_result": "SUCCESS",
        },
    }


payload = ready_payload()
text, exit_code = module.render_status(payload)

expected = """HomeLab Sentinel Status

Platform
  Installation         READY
  Service identity     READY

Core API
  Service              ACTIVE
  Runtime identity     CORRECT
  Health               HEALTHY
  Endpoint             127.0.0.1:8000

Discovery
  Scheduler            ACTIVE
  Schedule             ENABLED
  Schedule policy      COMPLIANT
  Runtime              HEALTHY
  Provider             nmap
  Last run             SUCCESS
  Last success         2026-01-01T00:00:00Z
  Freshness            FRESH
  Attempt              1/2
  Recovery             NOT REQUIRED

Inventory
  Database             READY
  Schema               v3
  Integrity            OK

Monitoring
  Scheduler            ACTIVE
  Schedule             ENABLED
  Reconciliation       HEALTHY
  Provider             prometheus
  Collection           HEALTHY
  Evidence             FRESH
  Targets              71
  Healthy              48
  Degraded             1
  Down                 22
  Unknown              0

Verification
  Post-boot schedule   ENABLED
  Last result          SUCCESS

Overall
  READY
"""

expect(
    "READY renderer output",
    text,
    expected,
)

expect(
    "READY renderer exit code",
    exit_code,
    0,
)


# NOT INSTALLED has a legacy presentation distinction:
# Verification uses "Post-boot unit", and unavailable numeric
# Monitoring values render as N/A.
payload = ready_payload()

payload["platform"] = {
    "installation": "NOT INSTALLED",
    "service_identity": "N/A",
}

payload["core_api"] = {
    "service": "N/A",
    "runtime_identity": "N/A",
    "health": "N/A",
    "endpoint": "127.0.0.1:8000",
}

payload["discovery"] = {
    key: "N/A"
    for key in payload["discovery"]
}

payload["inventory"] = {
    "database": "N/A",
    "schema": "N/A",
    "integrity": "N/A",
}

payload["monitoring"] = {
    "scheduler": "N/A",
    "schedule": "N/A",
    "reconciliation": "N/A",
    "provider": "N/A",
    "collection": "N/A",
    "evidence": "N/A",
    "targets": None,
    "entities": {
        "healthy": None,
        "degraded": None,
        "down": None,
        "unknown": None,
    },
}

payload["verification"] = {
    "post_boot_schedule": "N/A",
    "last_result": "N/A",
}

payload["overall"] = "NOT INSTALLED"

text, exit_code = module.render_status(payload)

if "  Post-boot unit       N/A" not in text:
    raise SystemExit(
        "[FAIL] NOT INSTALLED must use legacy Post-boot unit label"
    )

for line in (
    "  Targets              N/A",
    "  Healthy              N/A",
    "  Degraded             N/A",
    "  Down                 N/A",
    "  Unknown              N/A",
):
    if line not in text:
        raise SystemExit(
            f"[FAIL] NOT INSTALLED missing renderer line: {line}"
        )

expect(
    "NOT INSTALLED renderer exit code",
    exit_code,
    2,
)


# Current verification has a distinct legacy label.
payload = ready_payload()

payload["verification"]["last_result"] = "IN PROGRESS"

text, exit_code = module.render_status(payload)

if "  Current verification IN PROGRESS" not in text:
    raise SystemExit(
        "[FAIL] running verification must use "
        "Current verification label"
    )

expect(
    "running verification renderer exit code",
    exit_code,
    0,
)


# Structured unavailable Monitoring evaluation is rendered as UNKNOWN,
# never as Python None.
payload = ready_payload()

payload["monitoring"]["evidence"] = "UNKNOWN"
payload["monitoring"]["targets"] = None

for state in payload["monitoring"]["entities"]:
    payload["monitoring"]["entities"][state] = None

payload["overall"] = "DEGRADED"

text, exit_code = module.render_status(payload)

for line in (
    "  Evidence             UNKNOWN",
    "  Targets              UNKNOWN",
    "  Healthy              UNKNOWN",
    "  Degraded             UNKNOWN",
    "  Down                 UNKNOWN",
    "  Unknown              UNKNOWN",
):
    if line not in text:
        raise SystemExit(
            f"[FAIL] unavailable Monitoring rendering: {line}"
        )

if "None" in text:
    raise SystemExit(
        "[FAIL] renderer exposed Python None"
    )

expect(
    "DEGRADED renderer exit code",
    exit_code,
    1,
)

print("[PASS] canonical status renderer contract")
PY

pass "status renderer regression"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel status renderer regression PASSED"
