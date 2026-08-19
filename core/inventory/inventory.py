#!/usr/bin/env python3

import argparse
import json
import sqlite3
import sys
from pathlib import Path


DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def current_schema_version(connection):
    return connection.execute("PRAGMA user_version").fetchone()[0]


def entity_observations(connection, entity_id):
    return connection.execute(
        """
        SELECT
            o.observation_id,
            o.provider,
            o.discovery_method,
            o.discovered_at,
            o.received_at,
            o.payload_json,
            eo.correlation_method
        FROM observations AS o
        JOIN entity_observations AS eo
            ON eo.observation_id = o.observation_id
        JOIN correlation_state AS c
            ON c.observation_id = o.observation_id
        WHERE eo.entity_id = ?
          AND c.status = 'resolved'
          AND c.entity_id = ?
        ORDER BY o.discovered_at, o.observation_id
        """,
        (entity_id, entity_id),
    ).fetchall()


def build_inventory_record(entity_id, entity_type, rows):
    if not rows:
        return None

    first_seen = rows[0][3]
    last_seen = rows[-1][3]

    providers = set()
    ip_history = set()
    mac_history = set()
    hostname_history = set()

    latest_host_record = None

    for (
        _,
        provider,
        discovery_method,
        _,
        _,
        payload_json,
        _,
    ) in rows:
        providers.add(provider)
        record = json.loads(payload_json)

        for address in record.get("ip_addresses", []):
            ip_history.add(address)

        mac_address = record.get("mac_address")
        if mac_address is not None:
            mac_history.add(mac_address)

        hostname = record.get("hostname")
        if hostname is not None:
            hostname_history.add(hostname)

        if discovery_method == "host-discovery":
            latest_host_record = record

    current = {
        "ip_addresses": [],
        "mac_address": None,
        "hostname": None,
    }

    if latest_host_record is not None:
        current = {
            "ip_addresses": latest_host_record.get("ip_addresses", []),
            "mac_address": latest_host_record.get("mac_address"),
            "hostname": latest_host_record.get("hostname"),
        }

    return {
        "entity_id": entity_id,
        "entity_type": entity_type,
        "first_seen": first_seen,
        "last_seen": last_seen,
        "observation_count": len(rows),
        "current": current,
        "history": {
            "ip_addresses": sorted(ip_history),
            "mac_addresses": sorted(mac_history),
            "hostnames": sorted(hostname_history),
        },
        "providers": sorted(providers),
    }


def inventory_record(connection, entity_id):
    row = connection.execute(
        """
        SELECT entity_id, entity_type
        FROM entities
        WHERE entity_id = ?
        """,
        (entity_id,),
    ).fetchone()

    if row is None:
        raise ValueError(f"entity not found: {entity_id}")

    rows = entity_observations(connection, entity_id)
    record = build_inventory_record(row[0], row[1], rows)

    if record is None:
        raise ValueError(f"entity has no resolved observations: {entity_id}")

    return record


def inventory_records(connection):
    records = []

    for entity_id, entity_type in connection.execute(
        """
        SELECT entity_id, entity_type
        FROM entities
        ORDER BY entity_id
        """
    ):
        rows = entity_observations(connection, entity_id)
        record = build_inventory_record(entity_id, entity_type, rows)

        if record is not None:
            records.append(record)

    return records


def unresolved_records(connection):
    records = []

    rows = connection.execute(
        """
        SELECT
            c.observation_id,
            c.reason,
            c.decided_at,
            o.provider,
            o.discovery_method,
            o.discovered_at,
            o.received_at,
            o.payload_json
        FROM correlation_state AS c
        JOIN observations AS o
            ON o.observation_id = c.observation_id
        WHERE c.status = 'unresolved'
        ORDER BY o.discovered_at, c.observation_id
        """
    ).fetchall()

    for (
        observation_id,
        reason,
        decided_at,
        provider,
        discovery_method,
        discovered_at,
        received_at,
        payload_json,
    ) in rows:
        records.append(
            {
                "observation_id": observation_id,
                "status": "unresolved",
                "reason": reason,
                "decided_at": decided_at,
                "provider": provider,
                "discovery_method": discovery_method,
                "discovered_at": discovered_at,
                "received_at": received_at,
                "payload": json.loads(payload_json),
            }
        )

    return records


def history_records(connection, entity_id):
    entity = connection.execute(
        """
        SELECT entity_id
        FROM entities
        WHERE entity_id = ?
        """,
        (entity_id,),
    ).fetchone()

    if entity is None:
        raise ValueError(f"entity not found: {entity_id}")

    records = []

    for (
        observation_id,
        provider,
        discovery_method,
        discovered_at,
        received_at,
        payload_json,
        correlation_method,
    ) in entity_observations(connection, entity_id):
        records.append(
            {
                "entity_id": entity_id,
                "observation_id": observation_id,
                "provider": provider,
                "discovery_method": discovery_method,
                "discovered_at": discovered_at,
                "received_at": received_at,
                "correlation_method": correlation_method,
                "payload": json.loads(payload_json),
            }
        )

    return records


def emit_records(records):
    try:
        for record in records:
            print(json.dumps(record, separators=(",", ":"), sort_keys=True))
    except BrokenPipeError:
        return


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Living Inventory"
    )

    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help=f"SQLite database path (default: {DEFAULT_DATABASE})",
    )

    parser.add_argument(
        "command",
        nargs="?",
        default="list",
        choices=("list", "show", "unresolved", "history"),
        help="Inventory query command (default: list)",
    )

    parser.add_argument(
        "entity_id",
        nargs="?",
        help="Sentinel entity ID for show or history",
    )

    args = parser.parse_args()

    if args.command in {"show", "history"} and not args.entity_id:
        parser.error(f"{args.command} requires <entity-id>")

    if args.command in {"list", "unresolved"} and args.entity_id:
        parser.error(f"{args.command} does not accept <entity-id>")

    if not args.database.is_file():
        error(f"Inventory database not found: {args.database}")
        return 1

    try:
        connection = sqlite3.connect(args.database)

        try:
            version = current_schema_version(connection)

            if version < 2:
                raise ValueError(
                    f"inventory schema version {version} "
                    f"does not support Living Inventory"
                )

            if args.command == "list":
                records = inventory_records(connection)
                emit_records(records)

            elif args.command == "show":
                record = inventory_record(connection, args.entity_id)
                emit_records([record])

            elif args.command == "unresolved":
                records = unresolved_records(connection)
                emit_records(records)

            elif args.command == "history":
                records = history_records(connection, args.entity_id)
                emit_records(records)

        finally:
            connection.close()

    except (sqlite3.Error, ValueError, json.JSONDecodeError) as exc:
        error(f"Living Inventory failed: {exc}")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
