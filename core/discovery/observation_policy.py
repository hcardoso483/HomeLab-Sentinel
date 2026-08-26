#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path

import yaml


DEFAULT_CONFIG = Path(
    "/opt/homelab-sentinel/app/config/sentinel/discovery.yml"
)

DEFAULT_PASSES = 3
DEFAULT_INTERVAL_SECONDS = 2

MIN_PASSES = 1
MAX_PASSES = 5

MIN_INTERVAL_SECONDS = 0
MAX_INTERVAL_SECONDS = 30


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def load_policy(path):
    if not path.is_file():
        raise ValueError(
            f"Discovery configuration not found: {path}"
        )

    try:
        data = yaml.safe_load(
            path.read_text(encoding="utf-8")
        )
    except yaml.YAMLError as exc:
        raise ValueError(
            f"Invalid discovery configuration: {exc}"
        ) from exc

    if not isinstance(data, dict):
        raise ValueError(
            "Discovery configuration must be a YAML mapping"
        )

    discovery = data.get("discovery")

    if not isinstance(discovery, dict):
        raise ValueError(
            "missing or invalid discovery configuration"
        )

    observation = discovery.get("observation", {})

    if not isinstance(observation, dict):
        raise ValueError(
            "discovery.observation must be a mapping"
        )

    passes = observation.get(
        "passes",
        DEFAULT_PASSES,
    )

    interval = observation.get(
        "interval_seconds",
        DEFAULT_INTERVAL_SECONDS,
    )

    if isinstance(passes, bool) or not isinstance(passes, int):
        raise ValueError(
            "discovery.observation.passes must be an integer"
        )

    if not MIN_PASSES <= passes <= MAX_PASSES:
        raise ValueError(
            "discovery.observation.passes must be between "
            f"{MIN_PASSES} and {MAX_PASSES}"
        )

    if isinstance(interval, bool) or not isinstance(
        interval,
        (int, float),
    ):
        raise ValueError(
            "discovery.observation.interval_seconds "
            "must be numeric"
        )

    if not MIN_INTERVAL_SECONDS <= interval <= MAX_INTERVAL_SECONDS:
        raise ValueError(
            "discovery.observation.interval_seconds must be between "
            f"{MIN_INTERVAL_SECONDS} and {MAX_INTERVAL_SECONDS}"
        )

    return passes, interval


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Discovery observation policy"
    )

    parser.add_argument(
        "action",
        choices=("passes", "interval", "show"),
    )

    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
    )

    args = parser.parse_args()

    try:
        passes, interval = load_policy(args.config)
    except (OSError, ValueError) as exc:
        error(str(exc))
        return 1

    if args.action == "passes":
        print(passes)

    elif args.action == "interval":
        print(interval)

    else:
        print(f"passes={passes}")
        print(f"interval_seconds={interval}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
