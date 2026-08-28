#!/usr/bin/env python3

import argparse
import json
import sqlite3
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

APP_ROOT = Path("/opt/homelab-sentinel/app")

# status.py is executed directly by installer/hls. In that mode Python
# places core/status on sys.path rather than the application root, so make
# the canonical core package importable before main() loads read_model.
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))
DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")
DISCOVERY_STATE = Path(
    "/srv/homelab-sentinel/sentinel/runtime/discovery.json"
)
API_UNIT = "homelab-sentinel-api.service"
VERIFY_UNIT = "homelab-sentinel-verify.service"
VERIFY_TIMER = "homelab-sentinel-verify.timer"
DISCOVERY_UNIT = "homelab-sentinel-discovery.service"
DISCOVERY_RECONCILER = APP_ROOT / "core/discovery/reconcile.py"

MONITORING_CORE = APP_ROOT / "core/monitoring/monitoring.py"
MONITORING_EVALUATOR = APP_ROOT / "core/monitoring/evaluate.py"
MONITORING_UNIT = "homelab-sentinel-monitoring.service"
MONITORING_TIMER = "homelab-sentinel-monitoring.timer"
MONITORING_RECONCILE_UNIT = "homelab-sentinel-monitoring-reconcile.service"
MONITORING_RECONCILE_TIMER = "homelab-sentinel-monitoring-reconcile.timer"
MONITORING_FRESHNESS_SECONDS = 300
EXPECTED_USER = "homelab-sentinel"
EXPECTED_GROUP = "homelab-sentinel"
API_HEALTH_URL = "http://127.0.0.1:8000/api/v1/health"

SIMULATIONS = (
    "not-installed",
    "wrong-runtime-identity",
    "missing-database",
    "unsupported-schema",
    "failed-verification",
    "verification-running",
    "discovery-failed",
    "discovery-recovering",
    "discovery-running",
    "discovery-scheduler-disabled",
    "discovery-schedule-drift",
    "discovery-state-unreadable",
    "monitoring-collection-failed",
    "monitoring-evidence-stale",
    "monitoring-entities-down",
)


class Status:
    def __init__(self):
        self.degraded = False
        self.not_installed = False

    def ready(self, label, value="READY"):
        print(f"  {label:<20} {value}")

    def fail(self, label, value):
        print(f"  {label:<20} {value}")
        self.degraded = True

    def missing(self, label, value):
        print(f"  {label:<20} {value}")
        self.not_installed = True


def run_command(*args):
    return subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )


def service_property(unit, property_name):
    result = run_command(
        "systemctl",
        "show",
        unit,
        f"--property={property_name}",
        "--value",
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def api_health():
    try:
        with urllib.request.urlopen(API_HEALTH_URL, timeout=5) as response:
            if response.status != 200:
                return False
            payload = json.load(response)
            return payload.get("status") == "ok"
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        return False


def discovery_reconciliation_status():
    result = run_command(
        str(DISCOVERY_RECONCILER),
        "audit",
        "--json",
    )

    if result.returncode not in (0, 1):
        return None

    try:
        payload = json.loads(result.stdout)
    except (json.JSONDecodeError, TypeError):
        return None

    facts = payload.get("facts")
    if not isinstance(facts, dict):
        return None

    if payload.get("version") != 1:
        return None

    return {
        "compliant": payload.get("compliant") is True,
        "active": facts.get("active") is True,
        "enabled": facts.get("enabled") is True,
    }


def discovery_runtime_status():
    if not DISCOVERY_STATE.is_file():
        return None

    try:
        payload = json.loads(
            DISCOVERY_STATE.read_text(encoding="utf-8")
        )
    except (OSError, json.JSONDecodeError):
        return {"readable": False}

    if not isinstance(payload, dict):
        return {"readable": False}

    return {
        "readable": True,
        "state": payload.get("state"),
        "provider": payload.get("provider"),
        "last_success_at": payload.get("last_success_at"),
        "last_failure_at": payload.get("last_failure_at"),
        "failure_class": payload.get("last_failure_class"),
        "failure_component": payload.get("last_failure_component"),
        "failure_retryable": payload.get("last_failure_retryable"),
        "freshness": payload.get("freshness"),
        "attempt": payload.get("attempt"),
        "max_attempts": payload.get("max_attempts"),
        "recovery_action": payload.get("recovery_action"),
        "recovery_result": payload.get("recovery_result"),
    }


def monitoring_provider_status():
    if not MONITORING_CORE.is_file():
        return None

    result = run_command(
        str(MONITORING_CORE),
        "provider",
        "--json",
    )

    if result.returncode != 0:
        return None

    try:
        payload = json.loads(result.stdout)
    except (json.JSONDecodeError, TypeError):
        return None

    if not isinstance(payload, dict):
        return None

    provider = payload.get("provider")

    if payload.get("status") != "valid":
        return None

    if not isinstance(provider, str) or not provider:
        return None

    return provider


def parse_utc_timestamp(value):
    if not isinstance(value, str) or not value.endswith("Z"):
        return None

    try:
        return datetime.fromisoformat(
            value[:-1] + "+00:00"
        )
    except ValueError:
        return None


def monitoring_health_status():
    if not MONITORING_EVALUATOR.is_file():
        return None

    result = run_command(
        str(MONITORING_EVALUATOR),
        "--database",
        str(DATABASE),
        "--json",
    )

    if result.returncode != 0:
        return None

    counts = {
        "HEALTHY": 0,
        "DEGRADED": 0,
        "DOWN": 0,
        "UNKNOWN": 0,
    }

    latest_time = None

    try:
        for line in result.stdout.splitlines():
            if not line.strip():
                continue

            record = json.loads(line)

            if not isinstance(record, dict):
                return None

            state = record.get("state")

            if state not in counts:
                return None

            counts[state] += 1

            checked_at = record.get("latest_checked_at")

            if checked_at is not None:
                parsed = parse_utc_timestamp(checked_at)

                if parsed is None:
                    return None

                if latest_time is None or parsed > latest_time:
                    latest_time = parsed

    except (json.JSONDecodeError, TypeError):
        return None

    freshness = "UNKNOWN"

    if latest_time is not None:
        age_seconds = (
            datetime.now(timezone.utc) - latest_time
        ).total_seconds()

        if age_seconds <= MONITORING_FRESHNESS_SECONDS:
            freshness = "FRESH"
        else:
            freshness = "STALE"

    return {
        "counts": counts,
        "targets": sum(counts.values()),
        "freshness": freshness,
    }


def oneshot_health(unit):
    active = service_property(unit, "ActiveState")
    result = service_property(unit, "Result")
    exit_status = service_property(unit, "ExecMainStatus")

    if active in ("activating", "active"):
        return "IN PROGRESS"

    if result == "success" and exit_status == "0":
        return "HEALTHY"

    if result is None or exit_status is None:
        return "UNKNOWN"

    return "FAILED"


def inventory_status():
    if not DATABASE.is_file():
        return None, None

    try:
        connection = sqlite3.connect(f"file:{DATABASE}?mode=ro", uri=True)
        try:
            version = connection.execute("PRAGMA user_version").fetchone()[0]
            integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
            return version, integrity
        finally:
            connection.close()
    except sqlite3.Error:
        return "error", "error"


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel platform status"
    )
    parser.add_argument(
        "--simulate",
        choices=SIMULATIONS,
        help="TEST ONLY: simulate one platform status condition",
    )
    parser.add_argument(
        "--ignore-verification-result",
        action="store_true",
        help=(
            "Ignore the previous post-boot verification result when "
            "evaluating current platform readiness"
        ),
    )

    args = parser.parse_args()

    # Import the canonical evaluator and renderer only after this module
    # has finished defining the low-level status probes they depend on.
    #
    # read_model imports core.status.status as its legacy probe provider,
    # so keeping these imports local avoids a module-level import cycle.
    from core.status.read_model import build_status
    from core.status.render import render_status

    payload = build_status(
        simulation=args.simulate,
        ignore_verification_result=args.ignore_verification_result,
    )

    text, exit_code = render_status(payload)

    if args.simulate:
        print(
            f"[TEST] Status simulation enabled: {args.simulate}"
        )
        print()

    print(text, end="")

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
