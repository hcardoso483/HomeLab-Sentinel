#!/usr/bin/env python3

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = "1.0"
PROVIDER = "prometheus"
CHECK_TYPE = "reachability"
DEFAULT_PROMETHEUS_URL = "http://127.0.0.1:9090"
DEFAULT_TIMEOUT = 5.0


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


def load_live(prometheus_url, query, timeout):
    base = prometheus_url.rstrip("/")
    params = urllib.parse.urlencode({"query": query})
    url = f"{base}/api/v1/query?{params}"

    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json"},
        method="GET",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8")
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise ValueError(f"Prometheus live query failed: {exc}") from exc

    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"Prometheus live query returned invalid JSON: {exc.msg}"
        ) from exc


def select_result(payload, instance=None, job=None):
    if not isinstance(payload, dict):
        return None

    if payload.get("status") != "success":
        return None

    data = payload.get("data")
    if not isinstance(data, dict):
        return None

    result = data.get("result")
    if not isinstance(result, list):
        return None

    matches = []

    for sample in result:
        if not isinstance(sample, dict):
            continue

        metric = sample.get("metric")
        if not isinstance(metric, dict):
            continue

        if instance is not None and metric.get("instance") != instance:
            continue

        if job is not None and metric.get("job") != job:
            continue

        matches.append(sample)

    if len(matches) != 1:
        return None

    return matches[0]


def prometheus_status(payload, instance=None, job=None):
    sample = select_result(payload, instance=instance, job=job)
    if sample is None:
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


def canonical_observation(
    entity_id,
    target,
    checked_at,
    payload,
    instance=None,
    job=None,
):
    return {
        "schema_version": SCHEMA_VERSION,
        "entity_id": entity_id,
        "provider": PROVIDER,
        "check_type": CHECK_TYPE,
        "target": target,
        "checked_at": checked_at,
        "status": prometheus_status(
            payload,
            instance=instance,
            job=job,
        ),
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

    source = parser.add_mutually_exclusive_group(required=False)

    source.add_argument(
        "--fixture",
        type=Path,
        help="Prometheus HTTP API JSON fixture",
    )

    source.add_argument(
        "--live",
        action="store_true",
        help="Query the live Prometheus HTTP API",
    )

    parser.add_argument(
        "--prometheus-url",
        default=DEFAULT_PROMETHEUS_URL,
        help=f"Prometheus base URL (default: {DEFAULT_PROMETHEUS_URL})",
    )

    parser.add_argument(
        "--query",
        default="up",
        help="Prometheus instant query used in live mode (default: up)",
    )

    parser.add_argument(
        "--instance",
        default=None,
        help="Require exactly one result with this Prometheus instance label",
    )

    parser.add_argument(
        "--job",
        default=None,
        help="Require exactly one result with this Prometheus job label",
    )

    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT,
        help=f"Live HTTP timeout in seconds (default: {DEFAULT_TIMEOUT})",
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

    if args.timeout <= 0:
        error("timeout must be greater than zero")
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
        if args.fixture is not None:
            payload = load_fixture(args.fixture)
        else:
            payload = load_live(
                args.prometheus_url,
                args.query,
                args.timeout,
            )
    except ValueError as exc:
        error(str(exc))
        return 1

    observation = canonical_observation(
        args.entity_id,
        args.target,
        checked_at,
        payload,
        instance=(
            args.instance
            if args.instance is not None
            else (args.target if args.fixture is None else None)
        ),
        job=args.job,
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
