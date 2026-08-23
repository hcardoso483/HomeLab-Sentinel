#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path

import yaml


MINIMUM_INTERVAL_MINUTES = 5
DEFAULT_INTERVAL_MINUTES = 15
MAXIMUM_INTERVAL_MINUTES = 30
DEFAULT_CONFIG = Path(
    "/opt/homelab-sentinel/app/config/sentinel/discovery.yml"
)


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def load_interval(config_file):
    with config_file.open("r", encoding="utf-8") as file:
        data = yaml.safe_load(file) or {}

    if not isinstance(data, dict):
        raise ValueError(
            "discovery configuration must be a YAML mapping"
        )

    discovery = data.get("discovery")

    if not isinstance(discovery, dict):
        raise ValueError(
            "missing or invalid top-level field: discovery"
        )

    schedule = discovery.get("schedule")

    if not isinstance(schedule, dict):
        raise ValueError(
            "missing or invalid field: discovery.schedule"
        )

    interval = schedule.get(
        "interval_minutes",
        DEFAULT_INTERVAL_MINUTES,
    )

    if isinstance(interval, bool) or not isinstance(interval, int):
        raise ValueError(
            "discovery.schedule.interval_minutes must be an integer"
        )

    if not MINIMUM_INTERVAL_MINUTES <= interval <= MAXIMUM_INTERVAL_MINUTES:
        raise ValueError(
            "discovery.schedule.interval_minutes must be between "
            f"{MINIMUM_INTERVAL_MINUTES} and "
            f"{MAXIMUM_INTERVAL_MINUTES}"
        )

    return interval


def render_dropin(interval):
    return (
        "[Timer]\n"
        "OnUnitActiveSec=\n"
        f"OnUnitActiveSec={interval}min\n"
    )


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel discovery scheduling policy"
    )

    parser.add_argument(
        "action",
        choices=("validate", "interval", "dropin"),
    )

    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
    )

    args = parser.parse_args()

    if not args.config.is_file():
        error(
            f"Discovery configuration not found: {args.config}"
        )
        return 1

    try:
        interval = load_interval(args.config)
    except (OSError, yaml.YAMLError, ValueError) as exc:
        error(f"Invalid discovery configuration: {exc}")
        return 1

    if args.action == "validate":
        print(
            "[PASS] Discovery scheduling policy valid: "
            f"{interval} minutes "
            f"(allowed {MINIMUM_INTERVAL_MINUTES}-"
            f"{MAXIMUM_INTERVAL_MINUTES})"
        )
        return 0

    if args.action == "interval":
        print(interval)
        return 0

    sys.stdout.write(render_dropin(interval))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
