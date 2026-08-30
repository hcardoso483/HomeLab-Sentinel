#!/usr/bin/env python3

import argparse
import hashlib
import json
import sqlite3
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from validate_observation import canonical_payload, validate_observation


DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")
APP_ROOT = Path("/opt/homelab-sentinel/app")
MIGRATIONS_DIR = APP_ROOT / "core" / "inventory" / "migrations"


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def info(message):
    print(f"[INFO] {message}", file=sys.stderr)


def utc_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def current_schema_version(connection):
    return connection.execute("PRAGMA user_version").fetchone()[0]


def apply_migrations(connection):
    current = current_schema_version(connection)
    migrations = []

    for path in MIGRATIONS_DIR.glob("*.sql"):
        prefix, separator, _ = path.name.partition("_")
        if separator and prefix.isdigit():
            migrations.append((int(prefix), path))

    migrations.sort()

    for version, path in migrations:
        if version <= current:
            continue

        if version != current + 1:
            raise ValueError(
                f"missing migration between schema versions {current} and {version}"
            )

        info(
            f"Applying inventory migration {current} -> {version}: {path.name}"
        )
        connection.executescript(path.read_text(encoding="utf-8"))

        applied = current_schema_version(connection)
        if applied != version:
            raise ValueError(
                f"migration {path.name} did not set schema version to {version}"
            )

        current = applied

    return current


def store_observation(connection, record):
    validate_observation(record)

    payload_json = canonical_payload(record)
    payload_hash = hashlib.sha256(
        payload_json.encode("utf-8")
    ).hexdigest()

    existing = connection.execute(
        """
        SELECT service_observation_id
        FROM service_observations
        WHERE payload_hash = ?
        """,
        (payload_hash,),
    ).fetchone()

    if existing is not None:
        return existing[0], False

    entity = connection.execute(
        "SELECT entity_id FROM entities WHERE entity_id = ?",
        (record["entity_id"],),
    ).fetchone()

    if entity is None:
        raise ValueError(f"entity not found: {record['entity_id']}")

    observation_id = f"svc-{uuid.uuid4().hex}"

    connection.execute(
        """
        INSERT INTO service_observations (
            service_observation_id,
            entity_id,
            schema_version,
            provider,
            observed_at,
            received_at,
            address,
            protocol,
            port,
            state,
            service,
            payload_json,
            payload_hash
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            observation_id,
            record["entity_id"],
            record["schema_version"],
            record["provider"],
            record["observed_at"],
            utc_now(),
            record["address"],
            record["protocol"],
            record["port"],
            record["state"],
            record["service"],
            payload_json,
            payload_hash,
        ),
    )

    return observation_id, True


def process_stream(connection):
    stored = 0
    duplicates = 0

    for line_number, line in enumerate(sys.stdin, start=1):
        line = line.strip()
        if not line:
            continue

        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(
                f"line {line_number}: invalid JSON: {exc.msg}"
            ) from exc

        try:
            _, created = store_observation(connection, record)
        except ValueError as exc:
            raise ValueError(f"line {line_number}: {exc}") from exc

        if created:
            stored += 1
        else:
            duplicates += 1

    connection.commit()
    return stored, duplicates


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Service Discovery Observation Store"
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
            version = apply_migrations(connection)

            if version < 4:
                raise ValueError(
                    f"inventory schema version {version} "
                    "does not support Service Discovery observations"
                )

            stored, duplicates = process_stream(connection)
        finally:
            connection.close()

    except (OSError, sqlite3.Error, ValueError, KeyError) as exc:
        error(f"Service Discovery observation store failed: {exc}")
        return 1

    info(
        "Service Discovery observation store complete. "
        f"Stored: {stored}, duplicates: {duplicates}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
