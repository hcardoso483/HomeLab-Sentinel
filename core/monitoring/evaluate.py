#!/usr/bin/env python3

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")
DEFAULT_FRESHNESS_SECONDS = 300
FAILURES_FOR_DOWN = 2


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def parse_utc(value):
    if not isinstance(value, str) or not value.endswith("Z"):
        raise ValueError(f"invalid UTC timestamp: {value!r}")
    return datetime.fromisoformat(value[:-1] + "+00:00")


def utc_now():
    return datetime.now(timezone.utc)


def recent_observations(connection, entity_id):
    return connection.execute(
        """
        SELECT
            checked_at,
            status,
            check_type,
            target,
            provider,
            latency_ms
        FROM monitoring_observations
        WHERE entity_id = ?
        ORDER BY checked_at DESC, monitoring_observation_id DESC
        """,
        (entity_id,),
    ).fetchall()


def evaluate_entity(rows, *, now, freshness_seconds):
    if not rows:
        return {
            "state": "UNKNOWN",
            "reason": "no monitoring evidence",
            "latest_checked_at": None,
            "fresh_observations": 0,
        }

    latest_checked_at = rows[0][0]
    latest_time = parse_utc(latest_checked_at)
    age_seconds = (now - latest_time).total_seconds()

    if age_seconds > freshness_seconds:
        return {
            "state": "UNKNOWN",
            "reason": "monitoring evidence is stale",
            "latest_checked_at": latest_checked_at,
            "fresh_observations": 0,
        }

    fresh = []
    for row in rows:
        checked_at = parse_utc(row[0])
        age = (now - checked_at).total_seconds()
        if age < 0:
            continue
        if age <= freshness_seconds:
            fresh.append(row)

    if not fresh:
        return {
            "state": "UNKNOWN",
            "reason": "no fresh monitoring evidence",
            "latest_checked_at": latest_checked_at,
            "fresh_observations": 0,
        }

    statuses = [row[1] for row in fresh]
    successes = statuses.count("success")
    failures = statuses.count("failed")
    unknowns = statuses.count("unknown")

    if successes > 0 and failures == 0 and unknowns == 0:
        return {
            "state": "HEALTHY",
            "reason": "fresh monitoring evidence is successful",
            "latest_checked_at": latest_checked_at,
            "fresh_observations": len(fresh),
        }

    if successes > 0 and failures > 0:
        return {
            "state": "DEGRADED",
            "reason": "fresh monitoring evidence is conflicting",
            "latest_checked_at": latest_checked_at,
            "fresh_observations": len(fresh),
        }

    if failures >= FAILURES_FOR_DOWN and successes == 0:
        return {
            "state": "DOWN",
            "reason": f"{failures} fresh failed observations with no fresh success",
            "latest_checked_at": latest_checked_at,
            "fresh_observations": len(fresh),
        }

    if failures == 1 and successes == 0:
        return {
            "state": "DEGRADED",
            "reason": "single fresh failed observation",
            "latest_checked_at": latest_checked_at,
            "fresh_observations": len(fresh),
        }

    return {
        "state": "UNKNOWN",
        "reason": "fresh evidence is insufficient for health determination",
        "latest_checked_at": latest_checked_at,
        "fresh_observations": len(fresh),
    }


def entity_ids(connection):
    return [
        row[0]
        for row in connection.execute(
            """
            SELECT entity_id
            FROM entities
            ORDER BY entity_id
            """
        ).fetchall()
    ]


def evaluate_database(connection, *, now, freshness_seconds):
    results = []
    for entity_id in entity_ids(connection):
        state = evaluate_entity(
            recent_observations(connection, entity_id),
            now=now,
            freshness_seconds=freshness_seconds,
        )
        results.append({"entity_id": entity_id, **state})
    return results


def emit_json(results):
    try:
        for result in results:
            print(json.dumps(result, separators=(",", ":"), sort_keys=True))
            sys.stdout.flush()
    except BrokenPipeError:
        try:
            sys.stdout.close()
        except BrokenPipeError:
            pass


def emit_human(results):
    print("HomeLab Sentinel Monitoring Health")
    print()
    if not results:
        print("No Living Inventory entities are available.")
        return

    print(f"{'ENTITY_ID':<38} {'STATE':<10} {'LATEST':<24} REASON")
    for result in results:
        latest = result["latest_checked_at"] or "-"
        print(
            f"{result['entity_id']:<38} "
            f"{result['state']:<10} "
            f"{latest:<24} "
            f"{result['reason']}"
        )


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Monitoring Health Evaluator"
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help=f"SQLite database path (default: {DEFAULT_DATABASE})",
    )
    parser.add_argument(
        "--freshness-seconds",
        type=int,
        default=DEFAULT_FRESHNESS_SECONDS,
        help=f"Maximum evidence age in seconds (default: {DEFAULT_FRESHNESS_SECONDS})",
    )
    parser.add_argument(
        "--now",
        help="TEST ONLY: override evaluation time with a UTC timestamp",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit one canonical JSON health record per line",
    )
    args = parser.parse_args()

    if args.freshness_seconds <= 0:
        error("--freshness-seconds must be greater than zero")
        return 2

    if not args.database.is_file():
        error(f"Inventory database not found: {args.database}")
        return 1

    try:
        now = parse_utc(args.now) if args.now else utc_now()
        with sqlite3.connect(args.database) as connection:
            version = connection.execute("PRAGMA user_version").fetchone()[0]
            if version < 3:
                raise ValueError(
                    f"inventory schema version {version} "
                    "does not support Monitoring health evaluation"
                )
            results = evaluate_database(
                connection,
                now=now,
                freshness_seconds=args.freshness_seconds,
            )
    except (sqlite3.Error, ValueError) as exc:
        error(f"Monitoring health evaluation failed: {exc}")
        return 1

    if args.json:
        emit_json(results)
    else:
        emit_human(results)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
