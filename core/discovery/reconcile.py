#!/usr/bin/env python3

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

APP_ROOT = Path("/opt/homelab-sentinel/app")

DEFAULT_CONFIG = APP_ROOT / "config" / "sentinel" / "discovery.yml"
SCHEDULE_HELPER = APP_ROOT / "core" / "discovery" / "schedule.py"

TIMER_UNIT = "homelab-sentinel-discovery.timer"

FRAGMENT = Path(
    "/etc/systemd/system/homelab-sentinel-discovery.timer"
)
DROPIN = Path(
    "/etc/systemd/system/"
    "homelab-sentinel-discovery.timer.d/"
    "schedule.conf"
)


SIMULATIONS = (
    "disabled",
    "inactive",
    "missing-dropin",
    "wrong-dropin",
    "wrong-effective-interval",
)


def run_command(*args):
    return subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def resolve_desired_interval(config):
    result = run_command(
        str(SCHEDULE_HELPER),
        "interval",
        "--config",
        str(config),
    )

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()

        if detail.startswith("[ERROR] "):
            detail = detail[len("[ERROR] "):]

        raise RuntimeError(
            detail or "Unable to resolve Discovery scheduling policy"
        )

    try:
        return int(result.stdout.strip())
    except ValueError as exc:
        raise RuntimeError(
            "Discovery scheduling helper returned "
            f"an invalid interval: {result.stdout.strip()!r}"
        ) from exc


def systemctl_value(property_name):
    result = run_command(
        "systemctl",
        "show",
        TIMER_UNIT,
        f"--property={property_name}",
        "--value",
    )

    if result.returncode != 0:
        return None

    return result.stdout.strip()


def systemctl_state(command):
    result = run_command(
        "systemctl",
        command,
        TIMER_UNIT,
    )

    return (
        result.returncode == 0,
        result.stdout.strip(),
    )


def parse_effective_interval(value):
    if not value:
        return None

    match = re.search(
        r"(?:^|[ {;])OnUnitActiveUSec=([^ ;}]+)",
        value,
    )

    if match is None:
        return None

    token = match.group(1)

    minute_match = re.fullmatch(r"([0-9]+)min", token)

    if minute_match is not None:
        return int(minute_match.group(1))

    second_match = re.fullmatch(r"([0-9]+)s", token)

    if second_match is not None:
        seconds = int(second_match.group(1))

        if seconds % 60 == 0:
            return seconds // 60

    return None


def expected_dropin(interval):
    return (
        "[Timer]\n"
        "OnUnitActiveSec=\n"
        f"OnUnitActiveSec={interval}min\n"
    )


def read_dropin():
    if not DROPIN.is_file():
        return None

    try:
        return DROPIN.read_text(encoding="utf-8")
    except OSError:
        return None


def audit(config, simulation=None):
    desired_interval = resolve_desired_interval(config)

    enabled_ok, enabled_value = systemctl_state("is-enabled")
    active_ok, active_value = systemctl_state("is-active")

    load_state = systemctl_value("LoadState")
    fragment_path = systemctl_value("FragmentPath")
    dropin_paths = systemctl_value("DropInPaths")
    timers_monotonic = systemctl_value("TimersMonotonic")

    effective_interval = parse_effective_interval(
        timers_monotonic
    )

    fragment_present = FRAGMENT.is_file()
    dropin_present = DROPIN.is_file()

    actual_dropin = read_dropin()
    dropin_matches = (
        actual_dropin == expected_dropin(desired_interval)
        if actual_dropin is not None
        else False
    )

    interval_matches = (
        effective_interval == desired_interval
        if effective_interval is not None
        else False
    )

    loaded = load_state == "loaded"
    enabled = enabled_ok and enabled_value == "enabled"
    active = active_ok and active_value == "active"

    dropin_registered = False

    if dropin_paths:
        registered_paths = dropin_paths.split()
        dropin_registered = str(DROPIN) in registered_paths

    fragment_matches = (
        fragment_path == str(FRAGMENT)
        if fragment_path
        else False
    )

    facts = {
        "policy_valid": True,
        "desired_interval_minutes": desired_interval,
        "effective_interval_minutes": effective_interval,
        "fragment_present": fragment_present,
        "fragment_matches": fragment_matches,
        "dropin_present": dropin_present,
        "dropin_registered": dropin_registered,
        "dropin_matches_policy": dropin_matches,
        "interval_matches_policy": interval_matches,
        "loaded": loaded,
        "enabled": enabled,
        "active": active,
    }

    if simulation == "disabled":
        facts["enabled"] = False

    elif simulation == "inactive":
        facts["active"] = False

    elif simulation == "missing-dropin":
        facts["dropin_present"] = False
        facts["dropin_registered"] = False
        facts["dropin_matches_policy"] = False

    elif simulation == "wrong-dropin":
        facts["dropin_matches_policy"] = False

    elif simulation == "wrong-effective-interval":
        simulated_interval = (
            desired_interval + 5
            if desired_interval < 30
            else desired_interval - 5
        )
        facts["effective_interval_minutes"] = simulated_interval
        facts["interval_matches_policy"] = False

    compliant = all(
        (
            facts["policy_valid"],
            facts["fragment_present"],
            facts["fragment_matches"],
            facts["dropin_present"],
            facts["dropin_registered"],
            facts["dropin_matches_policy"],
            facts["interval_matches_policy"],
            facts["loaded"],
            facts["enabled"],
            facts["active"],
        )
    )

    return {
        "version": 1,
        "unit": TIMER_UNIT,
        "compliant": compliant,
        "facts": facts,
    }


def print_human(result):
    facts = result["facts"]

    print("HomeLab Sentinel Discovery Reconciliation Audit")
    print()
    print(
        f"Desired interval   "
        f"{facts['desired_interval_minutes']} min"
    )

    effective = facts["effective_interval_minutes"]

    if effective is None:
        effective_text = "UNKNOWN"
    else:
        effective_text = f"{effective} min"

    print(f"Effective interval {effective_text}")
    print(
        f"Fragment present   "
        f"{'YES' if facts['fragment_present'] else 'NO'}"
    )
    print(
        f"Fragment canonical "
        f"{'YES' if facts['fragment_matches'] else 'NO'}"
    )
    print(
        f"Drop-in present    "
        f"{'YES' if facts['dropin_present'] else 'NO'}"
    )
    print(
        f"Drop-in registered "
        f"{'YES' if facts['dropin_registered'] else 'NO'}"
    )
    print(
        f"Drop-in policy     "
        f"{'MATCH' if facts['dropin_matches_policy'] else 'DRIFT'}"
    )
    print(
        f"Effective policy   "
        f"{'MATCH' if facts['interval_matches_policy'] else 'DRIFT'}"
    )
    print(
        f"Loaded             "
        f"{'YES' if facts['loaded'] else 'NO'}"
    )
    print(
        f"Enabled            "
        f"{'YES' if facts['enabled'] else 'NO'}"
    )
    print(
        f"Active             "
        f"{'YES' if facts['active'] else 'NO'}"
    )
    print()
    print(
        "Result             "
        f"{'COMPLIANT' if result['compliant'] else 'DRIFT'}"
    )


def main():
    parser = argparse.ArgumentParser(
        description=(
            "HomeLab Sentinel Discovery scheduling reconciliation"
        )
    )

    parser.add_argument(
        "action",
        choices=("audit",),
    )

    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
    )

    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON",
    )

    parser.add_argument(
        "--simulate",
        choices=SIMULATIONS,
        help="TEST ONLY: simulate one Discovery scheduling drift condition",
    )

    args = parser.parse_args()

    if not args.config.is_file():
        error(f"Discovery configuration not found: {args.config}")
        return 2

    try:
        result = audit(args.config, args.simulate)
    except RuntimeError as exc:
        error(str(exc))
        return 2

    if args.json:
        print(
            json.dumps(
                result,
                indent=2,
                sort_keys=True,
            )
        )
    else:
        print_human(result)

    return 0 if result["compliant"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
