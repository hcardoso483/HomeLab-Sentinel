#!/usr/bin/env python3

import argparse
import json
import sqlite3
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

APP_ROOT = Path("/opt/homelab-sentinel/app")
DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")
DISCOVERY_STATE = Path(
    "/srv/homelab-sentinel/sentinel/runtime/discovery.json"
)
API_UNIT = "homelab-sentinel-api.service"
VERIFY_UNIT = "homelab-sentinel-verify.service"
DISCOVERY_UNIT = "homelab-sentinel-discovery.service"
DISCOVERY_RECONCILER = APP_ROOT / "core/discovery/reconcile.py"
EXPECTED_USER = "homelab-sentinel"
EXPECTED_GROUP = "homelab-sentinel"
API_HEALTH_URL = "http://127.0.0.1:8000/api/v1/health"

SIMULATIONS = (
    "not-installed",
    "wrong-runtime-identity",
    "missing-database",
    "unsupported-schema",
    "failed-verification",
    "discovery-failed",
    "discovery-recovering",
    "discovery-running",
    "discovery-scheduler-disabled",
    "discovery-schedule-drift",
    "discovery-state-unreadable",
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
    args = parser.parse_args()
    simulation = args.simulate

    if simulation:
        print(f"[TEST] Status simulation enabled: {simulation}")
        print()

    status = Status()

    print("HomeLab Sentinel Status")
    print()

    print("Platform")

    installation_present = APP_ROOT.is_dir()

    if simulation == "not-installed":
        installation_present = False

    if installation_present:
        status.ready("Installation")
    else:
        status.missing("Installation", "NOT INSTALLED")

    if simulation == "not-installed":
        status.ready("Service identity", "N/A")

        print()
        print("Core API")
        status.ready("Service", "N/A")
        status.ready("Runtime identity", "N/A")
        status.ready("Health", "N/A")
        status.ready("Endpoint", "127.0.0.1:8000")

        print()
        print("Discovery")
        status.ready("Scheduler", "N/A")
        status.ready("Schedule", "N/A")
        status.ready("Schedule policy", "N/A")
        status.ready("Runtime", "N/A")
        status.ready("Provider", "N/A")
        status.ready("Last run", "N/A")
        status.ready("Last success", "N/A")
        status.ready("Freshness", "N/A")
        status.ready("Attempt", "N/A")
        status.ready("Recovery", "N/A")

        print()
        print("Inventory")
        status.ready("Database", "N/A")
        status.ready("Schema", "N/A")
        status.ready("Integrity", "N/A")

        print()
        print("Verification")
        status.ready("Post-boot unit", "N/A")

        print()
        print("Overall")
        print("  NOT INSTALLED")
        return 2

    user = service_property(API_UNIT, "User")
    group = service_property(API_UNIT, "Group")
    if simulation == "wrong-runtime-identity":
        user = "wrong-user"
        group = "wrong-group"

    if user == EXPECTED_USER and group == EXPECTED_GROUP:
        status.ready("Service identity")
    elif user is None or group is None:
        status.fail("Service identity", "UNKNOWN")
    else:
        status.fail(
            "Service identity",
            f"INCORRECT ({user or '?'}:{group or '?'})",
        )

    print()
    print("Core API")

    active = run_command("systemctl", "is-active", API_UNIT)
    if active.returncode == 0 and active.stdout.strip() == "active":
        status.ready("Service", "ACTIVE")
    else:
        status.fail("Service", "INACTIVE")

    runtime_user = service_property(API_UNIT, "User")
    runtime_group = service_property(API_UNIT, "Group")
    if simulation == "wrong-runtime-identity":
        runtime_user = "wrong-user"
        runtime_group = "wrong-group"

    if runtime_user == EXPECTED_USER and runtime_group == EXPECTED_GROUP:
        status.ready("Runtime identity", "CORRECT")
    else:
        status.fail("Runtime identity", "INCORRECT")

    if api_health():
        status.ready("Health", "HEALTHY")
    else:
        status.fail("Health", "UNHEALTHY")

    status.ready("Endpoint", "127.0.0.1:8000")

    print()
    print("Discovery")

    reconciliation = discovery_reconciliation_status()

    if reconciliation is None:
        scheduler_active = False
        scheduler_enabled = False
        schedule_compliant = False
        reconciliation_readable = False
    else:
        scheduler_active = reconciliation["active"]
        scheduler_enabled = reconciliation["enabled"]
        schedule_compliant = reconciliation["compliant"]
        reconciliation_readable = True

    if simulation == "discovery-scheduler-disabled":
        scheduler_active = False
        scheduler_enabled = False
    elif simulation == "discovery-schedule-drift":
        schedule_compliant = False

    if scheduler_active:
        status.ready("Scheduler", "ACTIVE")
    else:
        status.fail("Scheduler", "INACTIVE")

    if scheduler_enabled:
        status.ready("Schedule", "ENABLED")
    else:
        status.fail("Schedule", "DISABLED")

    if not reconciliation_readable:
        status.fail("Schedule policy", "UNKNOWN")
    elif schedule_compliant:
        status.ready("Schedule policy", "COMPLIANT")
    else:
        status.fail("Schedule policy", "DRIFT")

    discovery = discovery_runtime_status()

    if simulation == "discovery-state-unreadable":
        discovery = {"readable": False}

    elif simulation in {
        "discovery-failed",
        "discovery-recovering",
        "discovery-running",
    }:
        simulated = dict(discovery or {})
        simulated["readable"] = True
        simulated.setdefault("provider", "nmap")
        simulated.setdefault("last_success_at", "2026-01-01T00:00:00Z")
        simulated.setdefault("attempt", 1)
        simulated.setdefault("max_attempts", 2)

        if simulation == "discovery-failed":
            simulated["state"] = "FAILED"
            simulated["freshness"] = "STALE"
            simulated["attempt"] = 2
            simulated["recovery_action"] = "retry"
            simulated["recovery_result"] = "failed"

        elif simulation == "discovery-recovering":
            simulated["state"] = "RECOVERING"
            simulated["freshness"] = "STALE"
            simulated["attempt"] = 1
            simulated["recovery_action"] = "retry"
            simulated["recovery_result"] = "in-progress"

        else:
            simulated["state"] = "RUNNING"
            simulated["freshness"] = "UNKNOWN"
            simulated["attempt"] = 1
            simulated["recovery_action"] = "none"
            simulated["recovery_result"] = "not-attempted"

        discovery = simulated

    if discovery is None:
        status.fail("Runtime", "NEVER RUN")
        status.ready("Provider", "N/A")
        status.ready("Last run", "NEVER RUN")
        status.ready("Last success", "N/A")
        status.fail("Freshness", "UNKNOWN")
        status.ready("Attempt", "N/A")
        status.fail("Recovery", "UNKNOWN")

    elif not discovery.get("readable"):
        status.fail("Runtime", "UNKNOWN")
        status.ready("Provider", "UNKNOWN")
        status.ready("Last run", "UNKNOWN")
        status.ready("Last success", "UNKNOWN")
        status.fail("Freshness", "UNKNOWN")
        status.ready("Attempt", "UNKNOWN")
        status.fail("Recovery", "UNKNOWN")

    else:
        runtime_state = discovery.get("state") or "UNKNOWN"
        freshness = discovery.get("freshness") or "UNKNOWN"

        if runtime_state == "SUCCESS" and freshness == "FRESH":
            status.ready("Runtime", "HEALTHY")
        elif runtime_state == "RUNNING":
            status.ready("Runtime", "RUNNING")
        elif runtime_state == "RECOVERING":
            status.fail("Runtime", "RECOVERING")
        elif runtime_state == "FAILED":
            status.fail("Runtime", "DEGRADED")
        else:
            status.fail("Runtime", "UNKNOWN")

        status.ready(
            "Provider",
            discovery.get("provider") or "UNKNOWN",
        )
        status.ready(
            "Last run",
            runtime_state,
        )
        status.ready(
            "Last success",
            discovery.get("last_success_at") or "N/A",
        )

        if runtime_state == "RUNNING":
            status.ready("Freshness", "IN PROGRESS")
        elif freshness == "FRESH":
            status.ready("Freshness", "FRESH")
        else:
            status.fail("Freshness", freshness)

        attempt = discovery.get("attempt")
        max_attempts = discovery.get("max_attempts")

        if attempt is None or max_attempts is None:
            attempt_value = "UNKNOWN"
        else:
            attempt_value = f"{attempt}/{max_attempts}"

        status.ready("Attempt", attempt_value)

        recovery = discovery.get("recovery_result")

        if recovery == "not-attempted":
            status.ready("Recovery", "NOT REQUIRED")
        elif recovery == "recovered":
            status.ready("Recovery", "RECOVERED")
        elif recovery == "in-progress":
            status.fail("Recovery", "IN PROGRESS")
        elif recovery == "failed":
            status.fail("Recovery", "FAILED")
        else:
            status.fail(
                "Recovery",
                recovery or "UNKNOWN",
            )

    print()
    print("Inventory")

    version, integrity = inventory_status()
    if simulation == "missing-database":
        version, integrity = None, None
    elif simulation == "unsupported-schema":
        version, integrity = 1, "ok"

    if version is None:
        status.fail("Database", "MISSING")
        status.fail("Schema", "UNKNOWN")
        status.fail("Integrity", "UNKNOWN")
    elif version == "error":
        status.fail("Database", "UNREADABLE")
        status.fail("Schema", "UNKNOWN")
        status.fail("Integrity", "UNKNOWN")
    else:
        status.ready("Database")
        if version >= 2:
            status.ready("Schema", f"v{version}")
        else:
            status.fail("Schema", f"UNSUPPORTED v{version}")

        if integrity == "ok":
            status.ready("Integrity", "OK")
        else:
            status.fail("Integrity", str(integrity))

    print()
    print("Verification")

    enabled = run_command("systemctl", "is-enabled", VERIFY_UNIT)
    if enabled.returncode == 0 and enabled.stdout.strip() == "enabled":
        status.ready("Post-boot unit", "ENABLED")
    else:
        status.fail("Post-boot unit", "DISABLED")

    verify_result = service_property(VERIFY_UNIT, "Result")
    verify_exit = service_property(VERIFY_UNIT, "ExecMainStatus")

    if simulation == "failed-verification":
        verify_result = "exit-code"
        verify_exit = "1"

    if verify_result == "success" and verify_exit == "0":
        status.ready("Last result", "SUCCESS")
    elif verify_result is None or verify_exit is None:
        status.fail("Last result", "UNKNOWN")
    else:
        status.fail(
            "Last result",
            f"FAILED ({verify_result or 'unknown'}, exit {verify_exit or '?'})",
        )

    print()
    print("Overall")

    if status.not_installed:
        print("  NOT INSTALLED")
        return 2

    if status.degraded:
        print("  DEGRADED")
        return 1

    print("  READY")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
