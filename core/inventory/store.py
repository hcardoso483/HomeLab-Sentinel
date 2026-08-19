#!/usr/bin/env python3

import argparse
import hashlib
import json
import sqlite3
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def info(message):
    print(f"[INFO] {message}", file=sys.stderr)


def utc_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def canonical_payload(record):
    return json.dumps(
        record,
        separators=(",", ":"),
        sort_keys=True,
    )


def initialize_database(connection, schema_file):
    schema = schema_file.read_text(encoding="utf-8")
    connection.executescript(schema)


def store_observation(connection, record):
    payload_json = canonical_payload(record)
    payload_hash = hashlib.sha256(
        payload_json.encode("utf-8")
    ).hexdigest()

    existing = connection.execute(
        """
        SELECT observation_id
        FROM observations
        WHERE payload_hash = ?
        """,
        (payload_hash,),
    ).fetchone()

    if existing is not None:
        return existing[0], False

    observation_id = f"obs-{uuid.uuid4().hex}"

    connection.execute(
        """
        INSERT INTO observations (
            observation_id,
            schema_version,
            provider,
            discovery_method,
            discovered_at,
            received_at,
            payload_json,
            payload_hash
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            observation_id,
            record["schema_version"],
            record["provider"],
            record["discovery_method"],
            record["discovered_at"],
            utc_now(),
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

        if not isinstance(record, dict):
            raise ValueError(
                f"line {line_number}: observation must be a JSON object"
            )

        required = (
            "schema_version",
            "provider",
            "discovery_method",
            "discovered_at",
        )

        missing = [
            field for field in required
            if field not in record
        ]

        if missing:
            raise ValueError(
                f"line {line_number}: missing required field(s): "
                + ", ".join(missing)
            )

        _, created = store_observation(connection, record)

        if created:
            stored += 1
        else:
            duplicates += 1

    connection.commit()

    return stored, duplicates


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Observation Store"
    )

    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help=f"SQLite database path (default: {DEFAULT_DATABASE})",
    )

    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    schema_file = script_dir / "schema.sql"

    if not schema_file.is_file():
        error(f"Inventory schema not found: {schema_file}")
        return 1

    try:
        args.database.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        connection = sqlite3.connect(args.database)

        try:
            connection.execute("PRAGMA foreign_keys = ON")
            initialize_database(connection, schema_file)

            stored, duplicates = process_stream(connection)

        finally:
            connection.close()

    except (OSError, sqlite3.Error, ValueError, KeyError) as exc:
        error(f"Observation store failed: {exc}")
        return 1

    info(
        f"Observation store complete. "
        f"Stored: {stored}, duplicates: {duplicates}"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
