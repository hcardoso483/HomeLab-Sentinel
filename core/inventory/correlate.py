#!/usr/bin/env python3

import argparse
import json
import sqlite3
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")


def info(message):
    print(f"[INFO] {message}", file=sys.stderr)


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def utc_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def pending_observations(connection):
    return connection.execute(
        """
        SELECT
            o.observation_id,
            o.payload_json
        FROM observations AS o
        JOIN correlation_state AS c
            ON c.observation_id = o.observation_id
        WHERE c.status = 'pending'
        ORDER BY o.received_at, o.observation_id
        """
    ).fetchall()


def entities_for_mac(connection, mac_address):
    rows = connection.execute(
        """
        SELECT DISTINCT eo.entity_id
        FROM entity_observations AS eo
        JOIN observations AS o
            ON o.observation_id = eo.observation_id
        WHERE json_extract(o.payload_json, '$.mac_address') = ?
        ORDER BY eo.entity_id
        """,
        (mac_address,),
    ).fetchall()

    return [row[0] for row in rows]


def create_entity(connection):
    entity_id = f"dev-{uuid.uuid4().hex}"
    now = utc_now()

    connection.execute(
        """
        INSERT INTO entities (
            entity_id,
            entity_type,
            created_at,
            updated_at
        )
        VALUES (?, 'device', ?, ?)
        """,
        (entity_id, now, now),
    )

    return entity_id


def resolve_observation(
    connection,
    observation_id,
    entity_id,
    method,
    confidence,
):
    now = utc_now()

    connection.execute(
        """
        INSERT INTO entity_observations (
            entity_id,
            observation_id,
            correlated_at,
            correlation_method
        )
        VALUES (?, ?, ?, ?)
        """,
        (
            entity_id,
            observation_id,
            now,
            method,
        ),
    )

    connection.execute(
        """
        UPDATE correlation_state
        SET
            status = 'resolved',
            entity_id = ?,
            correlation_method = ?,
            confidence = ?,
            reason = NULL,
            decided_at = ?
        WHERE observation_id = ?
        """,
        (
            entity_id,
            method,
            confidence,
            now,
            observation_id,
        ),
    )

    connection.execute(
        """
        UPDATE entities
        SET updated_at = ?
        WHERE entity_id = ?
        """,
        (now, entity_id),
    )


def mark_unresolved(connection, observation_id, reason):
    connection.execute(
        """
        UPDATE correlation_state
        SET
            status = 'unresolved',
            entity_id = NULL,
            correlation_method = NULL,
            confidence = NULL,
            reason = ?,
            decided_at = ?
        WHERE observation_id = ?
        """,
        (
            reason,
            utc_now(),
            observation_id,
        ),
    )


def correlate_observation(connection, observation_id, payload_json):
    record = json.loads(payload_json)
    mac_address = record.get("mac_address")

    if mac_address is None:
        mark_unresolved(
            connection,
            observation_id,
            "no strong identity evidence available",
        )
        return "unresolved", None

    matches = entities_for_mac(connection, mac_address)

    if len(matches) == 0:
        entity_id = create_entity(connection)

        resolve_observation(
            connection,
            observation_id,
            entity_id,
            "new-entity-mac-evidence",
            0.90,
        )

        return "new", entity_id

    if len(matches) == 1:
        entity_id = matches[0]

        resolve_observation(
            connection,
            observation_id,
            entity_id,
            "mac-history-match",
            0.90,
        )

        return "resolved", entity_id

    mark_unresolved(
        connection,
        observation_id,
        "multiple entities share matching MAC evidence",
    )

    return "unresolved", None


def run_correlation(connection):
    pending = pending_observations(connection)

    created = 0
    resolved = 0
    unresolved = 0

    for observation_id, payload_json in pending:
        result, entity_id = correlate_observation(
            connection,
            observation_id,
            payload_json,
        )

        if result == "new":
            created += 1
            info(
                f"{observation_id}: created entity {entity_id}"
            )

        elif result == "resolved":
            resolved += 1
            info(
                f"{observation_id}: linked to entity {entity_id}"
            )

        else:
            unresolved += 1
            info(
                f"{observation_id}: left unresolved"
            )

    connection.commit()

    return len(pending), created, resolved, unresolved


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Correlation Engine"
    )

    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help=f"SQLite database path (default: {DEFAULT_DATABASE})",
    )

    args = parser.parse_args()

    if not args.database.is_file():
        error(f"Inventory database not found: {args.database}")
        return 1

    try:
        connection = sqlite3.connect(args.database)

        try:
            connection.execute("PRAGMA foreign_keys = ON")

            version = connection.execute(
                "PRAGMA user_version"
            ).fetchone()[0]

            if version < 2:
                raise ValueError(
                    f"inventory schema version {version} does not "
                    f"support correlation"
                )

            total, created, resolved, unresolved = run_correlation(
                connection
            )

        finally:
            connection.close()

    except (sqlite3.Error, ValueError, json.JSONDecodeError) as exc:
        error(f"Correlation failed: {exc}")
        return 1

    info(
        f"Correlation complete. "
        f"Processed: {total}, "
        f"created: {created}, "
        f"resolved: {resolved}, "
        f"unresolved: {unresolved}"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
