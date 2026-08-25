#!/usr/bin/env python3

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = "1.0"
PROVIDER = "prometheus"
CHECK_TYPE = "reachability"


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def utc_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load_fixture(path):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"unable to read Prometheus fixture: {exc}") from exc


def prometheus_status(payload):
    if not isinstance(payload, dict):
        return "unknown"

    if payload.get("status") != "success":
        return "unknown"

    data = payload.get("data")
    if not isinstance(data, dict):
        return "unknown"

    result = data.get("result")
    if not isinstance(result, list) or len(result) != 1:
        return "unknown"

    sample = result[0]
    if not isinstance(sample, dict):
        return "unknown"

    value = sample.get("value")
    if not isinstance(value, list) or len(value) < 2:
        return "unknown"

    raw = str(value[1])

    if raw == "1":
        return "success"

    if raw == "0":
        return "failed"

    return "unknown"


def canonical_observation(entity_id, target, checked_at, payload):
    return {
        "schema_version": SCHEMA_VERSION,
        "entity_id": entity_id,
        "provider": PROVIDER,
        "check_type": CHECK_TYPE,
        "target": target,
        "checked_at": checked_at,
        "status": prometheus_status(payload),
        "latency_ms": None,
    }


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Prometheus Monitoring adapter"
    )

    parser.add_argument(
        "--entity-id",
        required=True,
        help="Canonical Living Inventory entity_id",
    )

    parser.add_argument(
        "--target",
        required=True,
        help="Monitoring target represented by the Prometheus result",
    )

    parser.add_argument(
        "--fixture",
        type=Path,
        required=True,
        help="Prometheus HTTP API JSON fixture",
    )

    parser.add_argument(
        "--checked-at",
        default=None,
        help="Observation UTC timestamp; defaults to current UTC time",
    )

    args = parser.parse_args()

    if not args.entity_id.startswith("dev-"):
        error("entity_id must be a Sentinel device entity ID")
        return 2

    if not args.target.strip():
        error("target must be a non-empty string")
        return 2

    checked_at = args.checked_at or utc_now()

    if not checked_at.endswith("Z"):
        error("checked_at must be a UTC timestamp ending in Z")
        return 2

    try:
        datetime.fromisoformat(checked_at[:-1] + "+00:00")
    except ValueError:
        error("checked_at must be a valid UTC timestamp")
        return 2

    try:
        payload = load_fixture(args.fixture)
    except ValueError as exc:
        error(str(exc))
        return 1

    observation = canonical_observation(
        args.entity_id,
        args.target,
        checked_at,
        payload,
    )

    print(
        json.dumps(
            observation,
            separators=(",", ":"),
            sort_keys=True,
        )
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
