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
API_UNIT = "homelab-sentinel-api.service"
VERIFY_UNIT = "homelab-sentinel-verify.service"
EXPECTED_USER = "homelab-sentinel"
EXPECTED_GROUP = "homelab-sentinel"
API_HEALTH_URL = "http://127.0.0.1:8000/api/v1/health"

SIMULATIONS = (
    "not-installed",
    "wrong-runtime-identity",
    "missing-database",
    "unsupported-schema",
    "failed-verification",
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
