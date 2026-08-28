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

echo "HomeLab Sentinel structured status simulation regression"
echo

[[ -f "${READ_MODEL}" ]] \
    || fail "Canonical status read model not found: ${READ_MODEL}"

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


def build(simulation, ignore=True):
    try:
        return module.build_status(
            simulation=simulation,
            ignore_verification_result=ignore,
        )
    except TypeError as exc:
        raise SystemExit(
            "[FAIL] read model does not support simulation contract: "
            f"{exc}"
        )


def expect(description, actual, expected):
    if actual != expected:
        raise SystemExit(
            f"[FAIL] {description}: "
            f"expected={expected!r}, actual={actual!r}"
        )

    print(f"[PASS] {description}: {actual}")


# Discovery failure.
payload = build("discovery-failed")

expect(
    "Discovery failure runtime",
    payload["discovery"]["runtime"],
    "DEGRADED",
)
expect(
    "Discovery failure freshness",
    payload["discovery"]["freshness"],
    "STALE",
)
expect(
    "Discovery failure recovery",
    payload["discovery"]["recovery"],
    "FAILED",
)
expect(
    "Discovery failure overall",
    payload["overall"],
    "DEGRADED",
)


# Discovery running must remain non-degrading.
payload = build("discovery-running")

expect(
    "Discovery running runtime",
    payload["discovery"]["runtime"],
    "RUNNING",
)
expect(
    "Discovery running freshness",
    payload["discovery"]["freshness"],
    "IN PROGRESS",
)
expect(
    "Discovery running overall",
    payload["overall"],
    "READY",
)


# Discovery scheduler policy drift.
payload = build("discovery-schedule-drift")

expect(
    "Discovery schedule drift",
    payload["discovery"]["schedule_policy"],
    "DRIFT",
)
expect(
    "Discovery schedule drift overall",
    payload["overall"],
    "DEGRADED",
)


# Discovery recovering.
payload = build("discovery-recovering")

expect(
    "Discovery recovering runtime",
    payload["discovery"]["runtime"],
    "RECOVERING",
)
expect(
    "Discovery recovering recovery",
    payload["discovery"]["recovery"],
    "IN PROGRESS",
)
expect(
    "Discovery recovering overall",
    payload["overall"],
    "DEGRADED",
)


# Discovery scheduler disabled.
payload = build("discovery-scheduler-disabled")

expect(
    "Discovery disabled scheduler",
    payload["discovery"]["scheduler"],
    "INACTIVE",
)
expect(
    "Discovery disabled schedule",
    payload["discovery"]["schedule"],
    "DISABLED",
)
expect(
    "Discovery disabled overall",
    payload["overall"],
    "DEGRADED",
)


# Discovery runtime unreadable.
payload = build("discovery-state-unreadable")

expect(
    "Discovery unreadable runtime",
    payload["discovery"]["runtime"],
    "UNKNOWN",
)
expect(
    "Discovery unreadable overall",
    payload["overall"],
    "DEGRADED",
)


# Verification currently running must override stale failure.
payload = build(
    "verification-running",
    ignore=False,
)

expect(
    "Verification running result",
    payload["verification"]["last_result"],
    "IN PROGRESS",
)
expect(
    "Verification running overall",
    payload["overall"],
    "READY",
)


# Failed verification normally degrades.
payload = build(
    "failed-verification",
    ignore=False,
)

if not payload["verification"]["last_result"].startswith(
    "FAILED ("
):
    raise SystemExit(
        "[FAIL] failed verification result was not preserved"
    )

print(
    "[PASS] failed verification result: "
    f"{payload['verification']['last_result']}"
)

expect(
    "Failed verification overall",
    payload["overall"],
    "DEGRADED",
)


# Verification context ignores historical result.
payload = build(
    "failed-verification",
    ignore=True,
)

expect(
    "Verification context result",
    payload["verification"]["last_result"],
    "IGNORED (verification context)",
)
expect(
    "Verification context overall",
    payload["overall"],
    "READY",
)


# Monitoring collection failure is a Sentinel subsystem failure.
payload = build("monitoring-collection-failed")

expect(
    "Monitoring collection failure",
    payload["monitoring"]["collection"],
    "FAILED",
)
expect(
    "Monitoring collection failure overall",
    payload["overall"],
    "DEGRADED",
)


# Stale Monitoring evidence degrades Sentinel.
payload = build("monitoring-evidence-stale")

expect(
    "Monitoring stale evidence",
    payload["monitoring"]["evidence"],
    "STALE",
)
expect(
    "Monitoring stale evidence overall",
    payload["overall"],
    "DEGRADED",
)


# Down monitored entities do NOT mean Sentinel itself is degraded.
payload = build("monitoring-entities-down")

expect(
    "Monitoring simulated target count",
    payload["monitoring"]["targets"],
    3,
)
expect(
    "Monitoring simulated healthy count",
    payload["monitoring"]["entities"]["healthy"],
    1,
)
expect(
    "Monitoring simulated down count",
    payload["monitoring"]["entities"]["down"],
    2,
)
expect(
    "Monitoring entities-down evidence",
    payload["monitoring"]["evidence"],
    "FRESH",
)
expect(
    "Monitoring entities-down overall",
    payload["overall"],
    "READY",
)


print()

# Installation absent: unavailable subsystem measurements must remain
# unavailable rather than being represented as genuine zeroes.
not_installed = module.build_status(
    simulation="not-installed",
    ignore_verification_result=True,
)

expect(
    "Not-installed platform state",
    not_installed["platform"]["installation"],
    "NOT INSTALLED",
)

expect(
    "Not-installed service identity",
    not_installed["platform"]["service_identity"],
    "N/A",
)

expect(
    "Not-installed Core API service",
    not_installed["core_api"]["service"],
    "N/A",
)

expect(
    "Not-installed Discovery runtime",
    not_installed["discovery"]["runtime"],
    "N/A",
)

expect(
    "Not-installed Inventory database",
    not_installed["inventory"]["database"],
    "N/A",
)

expect(
    "Not-installed Monitoring evidence",
    not_installed["monitoring"]["evidence"],
    "N/A",
)

if not_installed["monitoring"]["targets"] is not None:
    raise SystemExit(
        "[FAIL] Not-installed Monitoring targets must be null, "
        f"got {not_installed['monitoring']['targets']!r}"
    )

for state, value in not_installed["monitoring"]["entities"].items():
    if value is not None:
        raise SystemExit(
            "[FAIL] Not-installed Monitoring entity count must be null: "
            f"{state}={value!r}"
        )

expect(
    "Not-installed Verification schedule",
    not_installed["verification"]["post_boot_schedule"],
    "N/A",
)

expect(
    "Not-installed overall",
    not_installed["overall"],
    "NOT INSTALLED",
)

wrong_identity = module.build_status(
    simulation="wrong-runtime-identity",
    ignore_verification_result=True,
)

expect(
    "Wrong runtime service identity",
    wrong_identity["platform"]["service_identity"],
    "INCORRECT (wrong-user:wrong-group)",
)

expect(
    "Wrong Core API runtime identity",
    wrong_identity["core_api"]["runtime_identity"],
    "INCORRECT",
)

expect(
    "Wrong runtime identity overall",
    wrong_identity["overall"],
    "DEGRADED",
)

missing_database = module.build_status(
    simulation="missing-database",
    ignore_verification_result=True,
)

expect(
    "Missing database state",
    missing_database["inventory"]["database"],
    "MISSING",
)

expect(
    "Missing database schema",
    missing_database["inventory"]["schema"],
    "UNKNOWN",
)

expect(
    "Missing database integrity",
    missing_database["inventory"]["integrity"],
    "UNKNOWN",
)

expect(
    "Missing database overall",
    missing_database["overall"],
    "DEGRADED",
)

unsupported_schema = module.build_status(
    simulation="unsupported-schema",
    ignore_verification_result=True,
)

expect(
    "Unsupported schema database state",
    unsupported_schema["inventory"]["database"],
    "READY",
)

expect(
    "Unsupported schema state",
    unsupported_schema["inventory"]["schema"],
    "UNSUPPORTED v1",
)

expect(
    "Unsupported schema integrity",
    unsupported_schema["inventory"]["integrity"],
    "OK",
)

expect(
    "Unsupported schema overall",
    unsupported_schema["overall"],
    "DEGRADED",
)

print("[PASS] structured status simulation contract")
PY

pass "structured status simulation regression"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel structured status simulation regression PASSED"

# Marker retained for contract documentation:
# unavailable Monitoring evaluation must not be represented as zero counts.
