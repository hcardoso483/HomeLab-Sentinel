#!/usr/bin/env python3
"""Derived Service Discovery current-state read model.

This module is intentionally read-only. It derives endpoint lifecycle state
from immutable Service Discovery observations and authoritative run evidence.

#16 semantics:
- endpoint identity is entity_id + address + protocol + port
- latest successful inspection determines OBSERVED vs STALE
- latest overall inspection outcome is exposed separately
- run-observation association, not observation timestamp, proves an endpoint
  was seen in a particular inspection
- provider service evidence is preserved without application/port guessing
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path
from typing import Any


MIN_SCHEMA_VERSION = 5


def connect_read_only(database: str | Path) -> sqlite3.Connection:
    path = Path(database).resolve()
    uri = f"{path.as_uri()}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def require_schema(conn: sqlite3.Connection) -> None:
    version = int(conn.execute("PRAGMA user_version").fetchone()[0])
    if version < MIN_SCHEMA_VERSION:
        raise RuntimeError(
            f"Service Discovery current-state requires schema version "
            f"{MIN_SCHEMA_VERSION} or newer; got {version}"
        )


def _latest_inspections(
    conn: sqlite3.Connection, entity_id: str
) -> dict[tuple[str, str], dict[str, Any]]:
    rows = conn.execute(
        """
        SELECT
            service_discovery_run_id,
            address,
            provider,
            completed_at,
            outcome,
            detail
        FROM service_discovery_runs
        WHERE entity_id = ?
        ORDER BY completed_at DESC, service_discovery_run_id DESC
        """,
        (entity_id,),
    )

    latest: dict[tuple[str, str], dict[str, Any]] = {}
    for row in rows:
        key = (row["address"], row["provider"])
        if key in latest:
            continue
        latest[key] = {
            "service_discovery_run_id": row["service_discovery_run_id"],
            "outcome": row["outcome"],
            "completed_at": row["completed_at"],
            "provider": row["provider"],
            "detail": row["detail"],
        }
    return latest


def _latest_successful_runs(
    conn: sqlite3.Connection, entity_id: str
) -> dict[tuple[str, str], str]:
    rows = conn.execute(
        """
        SELECT
            service_discovery_run_id,
            address,
            provider,
            completed_at
        FROM service_discovery_runs
        WHERE entity_id = ?
          AND outcome = 'success'
        ORDER BY completed_at DESC, service_discovery_run_id DESC
        """,
        (entity_id,),
    )

    latest: dict[tuple[str, str], str] = {}
    for row in rows:
        key = (row["address"], row["provider"])
        if key not in latest:
            latest[key] = row["service_discovery_run_id"]
    return latest


def derive_current_services(
    conn: sqlite3.Connection, entity_id: str
) -> list[dict[str, Any]]:
    """Return derived endpoint state for all historical endpoints of an entity."""

    require_schema(conn)

    latest_inspections = _latest_inspections(conn, entity_id)
    latest_successful = _latest_successful_runs(conn, entity_id)

    rows = conn.execute(
        """
        SELECT
            o.service_observation_id,
            o.entity_id,
            o.address,
            o.protocol,
            o.port,
            o.service,
            o.provider,
            o.observed_at
        FROM service_observations AS o
        WHERE o.entity_id = ?
        ORDER BY
            o.address,
            o.protocol,
            o.port,
            o.provider,
            o.observed_at DESC,
            o.service_observation_id DESC
        """,
        (entity_id,),
    ).fetchall()

    # One read-model row per endpoint/provider identity. Multiple immutable
    # observations can describe the same endpoint over time; the most recent
    # observation supplies the provider evidence and last_observed_at.
    endpoints: dict[tuple[str, str, int, str], dict[str, Any]] = {}

    for row in rows:
        endpoint_key = (
            row["address"],
            row["protocol"],
            int(row["port"]),
            row["provider"],
        )
        if endpoint_key in endpoints:
            continue

        target_key = (row["address"], row["provider"])
        latest_success_run_id = latest_successful.get(target_key)

        observed_in_latest_success = False
        if latest_success_run_id is not None:
            observed_in_latest_success = (
                conn.execute(
                    """
                    SELECT 1
                    FROM service_discovery_run_observations
                    WHERE service_discovery_run_id = ?
                      AND service_observation_id = ?
                    LIMIT 1
                    """,
                    (
                        latest_success_run_id,
                        row["service_observation_id"],
                    ),
                ).fetchone()
                is not None
            )

            # A newer observation row for the same endpoint may exist while a
            # deduplicated older row is what the latest successful run linked.
            # Endpoint membership therefore must consider every historical
            # observation with the same endpoint identity, not only this row.
            if not observed_in_latest_success:
                observed_in_latest_success = (
                    conn.execute(
                        """
                        SELECT 1
                        FROM service_discovery_run_observations AS l
                        JOIN service_observations AS candidate
                          ON candidate.service_observation_id =
                             l.service_observation_id
                        WHERE l.service_discovery_run_id = ?
                          AND candidate.entity_id = ?
                          AND candidate.address = ?
                          AND candidate.protocol = ?
                          AND candidate.port = ?
                          AND candidate.provider = ?
                        LIMIT 1
                        """,
                        (
                            latest_success_run_id,
                            row["entity_id"],
                            row["address"],
                            row["protocol"],
                            row["port"],
                            row["provider"],
                        ),
                    ).fetchone()
                    is not None
                )

        endpoint_state = "OBSERVED" if observed_in_latest_success else "STALE"

        inspection = latest_inspections.get(target_key)
        latest_inspection = None
        if inspection is not None:
            latest_inspection = {
                "outcome": inspection["outcome"],
                "completed_at": inspection["completed_at"],
            }

        endpoints[endpoint_key] = {
            "entity_id": row["entity_id"],
            "address": row["address"],
            "protocol": row["protocol"],
            "port": int(row["port"]),
            "service": row["service"],
            "endpoint_state": endpoint_state,
            "last_observed_at": row["observed_at"],
            "latest_inspection": latest_inspection,
        }

    return sorted(
        endpoints.values(),
        key=lambda item: (
            item["address"],
            item["protocol"],
            item["port"],
        ),
    )


def query_database(database: str | Path, entity_id: str) -> list[dict[str, Any]]:
    conn = connect_read_only(database)
    try:
        return derive_current_services(conn, entity_id)
    finally:
        conn.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Derive Service Discovery current endpoint state."
    )
    parser.add_argument("--database", required=True, help="Inventory SQLite database")
    parser.add_argument("--entity-id", required=True, help="Canonical device entity ID")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        result = query_database(args.database, args.entity_id)
    except (OSError, sqlite3.Error, RuntimeError) as exc:
        print(f"[ERROR] {exc}", file=__import__("sys").stderr)
        return 1

    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
