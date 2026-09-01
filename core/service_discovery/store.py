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

RUN_OUTCOMES = {
    "success",
    "inconclusive",
    "provider_error",
    "invalid_evidence",
    "store_error",
}


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


def read_stream(stream):
    records = []

    for line_number, line in enumerate(stream, start=1):
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
            validate_observation(record)
        except (ValueError, KeyError, TypeError) as exc:
            raise ValueError(f"line {line_number}: {exc}") from exc

        records.append(record)

    return records


def validate_run_context(records, *, entity_id, address, provider):
    for line_number, record in enumerate(records, start=1):
        if record["entity_id"] != entity_id:
            raise ValueError(
                f"line {line_number}: entity_id does not match run context"
            )

        if record["address"] != address:
            raise ValueError(
                f"line {line_number}: address does not match run context"
            )

        if record["provider"] != provider:
            raise ValueError(
                f"line {line_number}: provider does not match run context"
            )


def store_run(
    connection,
    *,
    run_id,
    entity_id,
    address,
    provider,
    started_at,
    completed_at,
    outcome,
    detail=None,
):
    if outcome not in RUN_OUTCOMES:
        raise ValueError(f"unsupported Service Discovery run outcome: {outcome}")

    entity = connection.execute(
        "SELECT entity_id FROM entities WHERE entity_id = ?",
        (entity_id,),
    ).fetchone()

    if entity is None:
        raise ValueError(f"entity not found: {entity_id}")

    if not run_id or not run_id.strip():
        raise ValueError("run_id must be non-empty")

    if not address or not address.strip():
        raise ValueError("address must be non-empty")

    if not provider or not provider.strip():
        raise ValueError("provider must be non-empty")

    if not started_at or not started_at.strip():
        raise ValueError("started_at must be non-empty")

    if not completed_at or not completed_at.strip():
        raise ValueError("completed_at must be non-empty")

    if detail is not None and not detail.strip():
        raise ValueError("detail must be non-empty when provided")

    connection.execute(
        """
        INSERT INTO service_discovery_runs (
            service_discovery_run_id,
            entity_id,
            address,
            provider,
            started_at,
            completed_at,
            outcome,
            detail
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            run_id,
            entity_id,
            address,
            provider,
            started_at,
            completed_at,
            outcome,
            detail,
        ),
    )


def store_run_with_observations(
    connection,
    *,
    records,
    run_id,
    entity_id,
    address,
    provider,
    started_at,
    completed_at,
):
    validate_run_context(
        records,
        entity_id=entity_id,
        address=address,
        provider=provider,
    )

    stored = 0
    duplicates = 0
    observation_ids = []

    for record in records:
        observation_id, created = store_observation(connection, record)
        observation_ids.append(observation_id)

        if created:
            stored += 1
        else:
            duplicates += 1

    store_run(
        connection,
        run_id=run_id,
        entity_id=entity_id,
        address=address,
        provider=provider,
        started_at=started_at,
        completed_at=completed_at,
        outcome="success",
    )

    for observation_id in observation_ids:
        connection.execute(
            """
            INSERT INTO service_discovery_run_observations (
                service_discovery_run_id,
                service_observation_id
            )
            VALUES (?, ?)
            """,
            (run_id, observation_id),
        )

    return stored, duplicates


def process_stream(connection):
    records = read_stream(sys.stdin)
    stored = 0
    duplicates = 0

    for record in records:
        _, created = store_observation(connection, record)

        if created:
            stored += 1
        else:
            duplicates += 1

    connection.commit()
    return stored, duplicates


def persist_failure_run(
    connection,
    *,
    run_id,
    entity_id,
    address,
    provider,
    started_at,
    completed_at,
    outcome,
    detail,
):
    connection.rollback()

    store_run(
        connection,
        run_id=run_id,
        entity_id=entity_id,
        address=address,
        provider=provider,
        started_at=started_at,
        completed_at=completed_at,
        outcome=outcome,
        detail=detail,
    )
    connection.commit()


def build_parser():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Service Discovery Observation Store"
    )

    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help=f"SQLite database path (default: {DEFAULT_DATABASE})",
    )

    parser.add_argument("--run-id")
    parser.add_argument("--entity-id")
    parser.add_argument("--address")
    parser.add_argument("--provider")
    parser.add_argument("--started-at")
    parser.add_argument("--completed-at")
    parser.add_argument(
        "--outcome",
        choices=sorted(RUN_OUTCOMES),
    )
    parser.add_argument("--detail")

    return parser


def run_mode_requested(args):
    values = (
        args.run_id,
        args.entity_id,
        args.address,
        args.provider,
        args.started_at,
        args.completed_at,
        args.outcome,
        args.detail,
    )
    return any(value is not None for value in values)


def require_run_arguments(args):
    required = {
        "--run-id": args.run_id,
        "--entity-id": args.entity_id,
        "--address": args.address,
        "--provider": args.provider,
        "--started-at": args.started_at,
        "--completed-at": args.completed_at,
        "--outcome": args.outcome,
    }

    missing = [
        name
        for name, value in required.items()
        if value is None
    ]

    if missing:
        raise ValueError(
            "run persistence requires: " + ", ".join(missing)
        )


def main():
    parser = build_parser()
    args = parser.parse_args()

    if not args.database.is_file():
        error(f"Inventory database not found: {args.database}")
        return 1

    try:
        connection = sqlite3.connect(args.database)

        try:
            connection.execute("PRAGMA foreign_keys = ON")
            version = apply_migrations(connection)

            if version < 5:
                raise ValueError(
                    f"inventory schema version {version} "
                    "does not support Service Discovery run evidence"
                )

            if not run_mode_requested(args):
                stored, duplicates = process_stream(connection)
                info(
                    "Service Discovery observation store complete. "
                    f"Stored: {stored}, duplicates: {duplicates}"
                )
                return 0

            require_run_arguments(args)

            if args.outcome == "success":
                try:
                    records = read_stream(sys.stdin)

                    stored, duplicates = store_run_with_observations(
                        connection,
                        records=records,
                        run_id=args.run_id,
                        entity_id=args.entity_id,
                        address=args.address,
                        provider=args.provider,
                        started_at=args.started_at,
                        completed_at=args.completed_at,
                    )

                    connection.commit()

                except (ValueError, KeyError, TypeError) as exc:
                    persist_failure_run(
                        connection,
                        run_id=args.run_id,
                        entity_id=args.entity_id,
                        address=args.address,
                        provider=args.provider,
                        started_at=args.started_at,
                        completed_at=args.completed_at,
                        outcome="invalid_evidence",
                        detail=str(exc),
                    )

                    error(
                        "Service Discovery observation store failed: "
                        f"{exc}"
                    )
                    return 1

                info(
                    "Service Discovery run store complete. "
                    f"Stored: {stored}, duplicates: {duplicates}"
                )
                return 0

            # Failure runs are authoritative operation history with
            # no positive endpoint evidence.
            records = read_stream(sys.stdin)

            if records:
                raise ValueError(
                    f"{args.outcome} run must not include observations"
                )

            store_run(
                connection,
                run_id=args.run_id,
                entity_id=args.entity_id,
                address=args.address,
                provider=args.provider,
                started_at=args.started_at,
                completed_at=args.completed_at,
                outcome=args.outcome,
                detail=args.detail,
            )
            connection.commit()

            info(
                f"Service Discovery run store complete. Outcome: {args.outcome}"
            )
            return 0

        finally:
            connection.close()

    except (OSError, sqlite3.Error, ValueError, KeyError, TypeError) as exc:
        error(f"Service Discovery observation store failed: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
