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
    return connection.execute("""
        SELECT o.observation_id, o.provider, o.discovery_method,
               o.discovered_at, o.payload_json
        FROM observations AS o
        JOIN entity_observations AS eo
            ON eo.observation_id = o.observation_id
        JOIN correlation_state AS c
            ON c.observation_id = o.observation_id
        WHERE eo.entity_id = ?
          AND c.status = 'resolved'
          AND c.entity_id = ?
        ORDER BY o.discovered_at, o.observation_id
    """, (entity_id, entity_id)).fetchall()


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

    for _, provider, discovery_method, discovered_at, payload_json in rows:
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


def inventory_records(connection):
    records = []

    for entity_id, entity_type in connection.execute("""
        SELECT entity_id, entity_type
        FROM entities
        ORDER BY entity_id
    """):
        rows = entity_observations(connection, entity_id)
        record = build_inventory_record(entity_id, entity_type, rows)

        if record is not None:
            records.append(record)

    return records


def main():
    parser = argparse.ArgumentParser(description="HomeLab Sentinel Living Inventory")
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE, help=f"SQLite database path (default: {DEFAULT_DATABASE})")
    args = parser.parse_args()

    if not args.database.is_file():
        error(f"Inventory database not found: {args.database}")
        return 1

    try:
        connection = sqlite3.connect(args.database)

        try:
            version = current_schema_version(connection)

            if version < 2:
                raise ValueError(f"inventory schema version {version} does not support Living Inventory")

            records = inventory_records(connection)

        finally:
            connection.close()

    except (sqlite3.Error, ValueError, json.JSONDecodeError) as exc:
        error(f"Living Inventory failed: {exc}")
        return 1

    for record in records:
        print(json.dumps(record, separators=(",", ":"), sort_keys=True))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
