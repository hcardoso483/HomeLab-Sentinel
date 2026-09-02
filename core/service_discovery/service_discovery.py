#!/usr/bin/env python3

import argparse
import json
import sqlite3
import subprocess
import sys
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[2]
INVENTORY = APP_ROOT / "core" / "inventory" / "inventory.py"
CURRENT = APP_ROOT / "core" / "service_discovery" / "current.py"

# Allow direct execution of this file while still importing the canonical
# Service Discovery provider resolver from the repository root namespace.
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from core.service_discovery.current import derive_current_services


def load_inventory_records(database):
    if not INVENTORY.is_file():
        raise RuntimeError(f"Living Inventory Core not found: {INVENTORY}")

    result = subprocess.run(
        [str(INVENTORY), "--database", str(database), "list"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(detail or "Living Inventory query failed")

    records = []
    for line_number, line in enumerate(result.stdout.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"Living Inventory returned invalid JSON on line {line_number}: {exc}"
            ) from exc
        if not isinstance(record, dict):
            raise RuntimeError(
                f"Living Inventory returned a non-object record on line {line_number}"
            )
        records.append(record)

    return records


def service_discovery_targets(database):
    targets = []

    for record in load_inventory_records(database):
        entity_id = record.get("entity_id")
        entity_type = record.get("entity_type")

        if not isinstance(entity_id, str) or not entity_id:
            raise RuntimeError("Living Inventory record is missing a valid entity_id")

        if not isinstance(entity_type, str) or not entity_type:
            raise RuntimeError(
                f"Living Inventory entity {entity_id} is missing entity_type"
            )

        current = record.get("current")
        if not isinstance(current, dict):
            raise RuntimeError(
                f"Living Inventory entity {entity_id} has invalid current state"
            )

        raw_addresses = current.get("ip_addresses", [])
        if not isinstance(raw_addresses, list):
            raise RuntimeError(
                f"Living Inventory entity {entity_id} has invalid ip_addresses"
            )

        for address in raw_addresses:
            if not isinstance(address, str) or not address:
                raise RuntimeError(
                    f"Living Inventory entity {entity_id} contains an invalid current IP address"
                )

            targets.append(
                {
                    "schema_version": "1.0",
                    "entity_id": entity_id,
                    "entity_type": entity_type,
                    "address": address,
                    "eligible": True,
                    "state": "UNKNOWN",
                }
            )

    return sorted(targets, key=lambda item: (item["entity_id"], item["address"]))


def service_discovery_retry_pool(connection, targets):
    pooled = []

    for target in targets:
        entity_id = target["entity_id"]
        address = target["address"]

        row = connection.execute(
            """
            SELECT outcome
            FROM service_discovery_runs
            WHERE entity_id = ?
              AND address = ?
            ORDER BY completed_at DESC, service_discovery_run_id DESC
            LIMIT 1
            """,
            (entity_id, address),
        ).fetchone()

        if row is not None and row[0] == "inconclusive":
            pooled.append(target)

    return sorted(
        pooled,
        key=lambda item: (item["entity_id"], item["address"]),
    )


def service_discovery_results(database):
    """Return canonical current Service Discovery results grouped by target."""

    targets = service_discovery_targets(database)

    conn = connect_read_only(database)
    try:
        require_schema(conn)

        entity_endpoints = {}
        for entity_id in sorted(
            {target["entity_id"] for target in targets}
        ):
            entity_endpoints[entity_id] = derive_current_services(
                conn,
                entity_id,
            )

        items = []

        for target in targets:
            entity_id = target["entity_id"]
            address = target["address"]

            endpoints = [
                record
                for record in entity_endpoints.get(entity_id, [])
                if record.get("address") == address
            ]

            observed = sum(
                1
                for record in endpoints
                if record.get("endpoint_state") == "OBSERVED"
            )
            stale = sum(
                1
                for record in endpoints
                if record.get("endpoint_state") == "STALE"
            )

            latest_row = conn.execute(
                """
                SELECT outcome, completed_at
                FROM service_discovery_runs
                WHERE entity_id = ?
                  AND address = ?
                ORDER BY completed_at DESC,
                         service_discovery_run_id DESC
                LIMIT 1
                """,
                (entity_id, address),
            ).fetchone()

            latest_inspection = None
            if latest_row is not None:
                latest_inspection = {
                    "outcome": latest_row["outcome"],
                    "completed_at": latest_row["completed_at"],
                }

            items.append(
                {
                    "entity_id": entity_id,
                    "entity_type": target["entity_type"],
                    "address": address,
                    "observed": observed,
                    "stale": stale,
                    "latest_inspection": latest_inspection,
                    "endpoints": endpoints,
                }
            )

        return {
            "targets": len(targets),
            "items": items,
        }
    finally:
        conn.close()


def emit_json(records):
    try:
        for record in records:
            print(
                json.dumps(
                    record,
                    separators=(",", ":"),
                    sort_keys=True,
                )
            )
            sys.stdout.flush()
    except BrokenPipeError:
        try:
            sys.stdout.close()
        except BrokenPipeError:
            pass


def emit_human(targets):
    print("HomeLab Sentinel Service Discovery Targets")
    print()

    if not targets:
        print("No eligible Living Inventory addresses are available.")
        return

    print(f"{'ENTITY_ID':<38} {'ADDRESS':<39} {'TYPE':<12} {'STATE':<8}")
    for target in targets:
        print(
            f"{target['entity_id']:<38} "
            f"{target['address']:<39} "
            f"{target['entity_type']:<12} "
            f"{target['state']:<8}"
        )


def connect_read_only(database):
    path = Path(database).resolve()
    if not path.is_file():
        raise RuntimeError(f"Inventory database not found: {path}")

    uri = f"{path.as_uri()}?mode=ro"
    try:
        conn = sqlite3.connect(uri, uri=True)
    except sqlite3.Error as exc:
        raise RuntimeError(f"Service Discovery database query failed: {exc}") from exc

    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def require_schema(conn, minimum=5):
    version = int(conn.execute("PRAGMA user_version").fetchone()[0])
    if version < minimum:
        raise RuntimeError(
            f"Service Discovery requires schema version {minimum} or newer; got {version}"
        )


def require_entity(conn, entity_id):
    row = conn.execute(
        "SELECT 1 FROM entities WHERE entity_id = ?",
        (entity_id,),
    ).fetchone()
    if row is None:
        raise RuntimeError(f"Living Inventory entity not found: {entity_id}")


def service_discovery_services(database, entity_id):
    # Entity existence is a public CLI concern: the #16 read model correctly
    # returns an empty collection when no endpoint history exists, which is
    # distinct from asking for a nonexistent canonical entity.
    conn = connect_read_only(database)
    try:
        require_schema(conn)
        require_entity(conn, entity_id)
    finally:
        conn.close()

    if not CURRENT.is_file():
        raise RuntimeError(
            f"Service Discovery current-state read model not found: {CURRENT}"
        )

    result = subprocess.run(
        [
            str(CURRENT),
            "--database",
            str(database),
            "--entity-id",
            entity_id,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(detail or "Service Discovery current-state query failed")

    try:
        records = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"Service Discovery current-state returned invalid JSON: {exc}"
        ) from exc

    if not isinstance(records, list) or not all(
        isinstance(record, dict) for record in records
    ):
        raise RuntimeError(
            "Service Discovery current-state returned an invalid record collection"
        )

    return records


def emit_services_human(entity_id, records):
    try:
        print("HomeLab Sentinel Current Services")
        print()
        print(f"Entity             {entity_id}")
        print()

        if not records:
            print("No Service Discovery endpoint evidence is available for this entity.")
            return

        print(
            f"{'ADDRESS':<39} "
            f"{'PROTO':<6} "
            f"{'PORT':<6} "
            f"{'SERVICE':<16} "
            f"{'STATE':<10} "
            f"{'LAST_OBSERVED':<30} "
            f"{'LATEST_INSPECTION':<18} "
            "INSPECTED_AT"
        )

        for record in records:
            service = record["service"] if record["service"] is not None else "UNKNOWN"
            inspection = record.get("latest_inspection")
            inspection_outcome = "-"
            inspection_completed = "-"
            if inspection is not None:
                inspection_outcome = inspection["outcome"]
                inspection_completed = inspection["completed_at"]

            print(
                f"{record['address']:<39} "
                f"{record['protocol']:<6} "
                f"{record['port']:<6} "
                f"{service:<16} "
                f"{record['endpoint_state']:<10} "
                f"{record['last_observed_at']:<30} "
                f"{inspection_outcome:<18} "
                f"{inspection_completed}"
            )
    except BrokenPipeError:
        try:
            sys.stdout.close()
        except BrokenPipeError:
            pass


def service_discovery_history(database, entity_id):
    conn = connect_read_only(database)
    try:
        require_schema(conn)
        require_entity(conn, entity_id)

        observation_rows = conn.execute(
            """
            SELECT
                entity_id,
                provider,
                observed_at,
                received_at,
                address,
                protocol,
                port,
                state,
                service
            FROM service_observations
            WHERE entity_id = ?
            """,
            (entity_id,),
        ).fetchall()

        run_rows = conn.execute(
            """
            SELECT
                entity_id,
                address,
                provider,
                started_at,
                completed_at,
                outcome,
                detail
            FROM service_discovery_runs
            WHERE entity_id = ?
            """,
            (entity_id,),
        ).fetchall()
    except sqlite3.Error as exc:
        raise RuntimeError(f"Service Discovery history query failed: {exc}") from exc
    finally:
        conn.close()

    records = []

    for row in observation_rows:
        records.append(
            {
                "type": "observation",
                "entity_id": row["entity_id"],
                "provider": row["provider"],
                "observed_at": row["observed_at"],
                "received_at": row["received_at"],
                "address": row["address"],
                "protocol": row["protocol"],
                "port": int(row["port"]),
                "state": row["state"],
                "service": row["service"],
            }
        )

    for row in run_rows:
        records.append(
            {
                "type": "inspection",
                "entity_id": row["entity_id"],
                "address": row["address"],
                "provider": row["provider"],
                "started_at": row["started_at"],
                "completed_at": row["completed_at"],
                "outcome": row["outcome"],
                "detail": row["detail"],
            }
        )

    def event_time(record):
        if record["type"] == "inspection":
            return record["completed_at"]
        return record["observed_at"]

    return sorted(
        records,
        key=lambda record: (
            event_time(record),
            record["type"],
            record["address"],
        ),
        reverse=True,
    )


def emit_history_human(entity_id, records):
    try:
        print("HomeLab Sentinel Service Discovery History")
        print()
        print(f"Entity             {entity_id}")
        print()

        if not records:
            print("No Service Discovery evidence is available for this entity.")
            return

        print(
            f"{'TIME':<30} "
            f"{'TYPE':<12} "
            f"{'ADDRESS':<39} "
            f"{'PROVIDER':<12} "
            "EVIDENCE"
        )

        for record in records:
            if record["type"] == "inspection":
                evidence = record["outcome"]
                if record["detail"]:
                    evidence = f"{evidence}: {record['detail']}"
                timestamp = record["completed_at"]
            else:
                service = (
                    record["service"] if record["service"] is not None else "UNKNOWN"
                )
                evidence = (
                    f"{record['protocol']}/{record['port']} "
                    f"{record['state']} {service}"
                )
                timestamp = record["observed_at"]

            print(
                f"{timestamp:<30} "
                f"{record['type']:<12} "
                f"{record['address']:<39} "
                f"{record['provider']:<12} "
                f"{evidence}"
            )
    except BrokenPipeError:
        try:
            sys.stdout.close()
        except BrokenPipeError:
            pass


def resolve_service_discovery_provider():
    resolver = APP_ROOT / "core" / "resolver" / "resolver.sh"

    if not resolver.is_file():
        raise RuntimeError(
            f"Service Discovery provider resolver not found: {resolver}"
        )

    result = subprocess.run(
        [
            str(resolver),
            "provider-id",
            "service-discovery",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(
            detail or "Service Discovery provider resolution failed"
        )

    provider = result.stdout.strip()
    if not provider:
        raise RuntimeError(
            "Service Discovery provider resolution returned no provider"
        )

    return provider


def service_discovery_status(database):
    provider = resolve_service_discovery_provider()
    targets = service_discovery_targets(database)

    conn = connect_read_only(database)
    try:
        require_schema(conn)

        entity_rows = conn.execute(
            """
            SELECT DISTINCT entity_id
            FROM service_observations
            ORDER BY entity_id
            """
        ).fetchall()

        last_inspection = conn.execute(
            """
            SELECT MAX(completed_at)
            FROM service_discovery_runs
            """
        ).fetchone()[0]
    except sqlite3.Error as exc:
        raise RuntimeError(f"Service Discovery status query failed: {exc}") from exc
    finally:
        conn.close()

    counts = {
        "observed": 0,
        "stale": 0,
    }

    for row in entity_rows:
        records = service_discovery_services(database, row["entity_id"])
        for record in records:
            state = record.get("endpoint_state")
            if state == "OBSERVED":
                counts["observed"] += 1
            elif state == "STALE":
                counts["stale"] += 1
            else:
                raise RuntimeError(
                    f"Service Discovery current-state returned invalid endpoint state: {state!r}"
                )

    return {
        "provider": provider,
        "targets": len(targets),
        "endpoints": counts,
        "last_inspection": last_inspection,
    }


def emit_status_json(status):
    print(
        json.dumps(
            status,
            separators=(",", ":"),
            sort_keys=True,
        )
    )


def emit_status_human(status):
    print("HomeLab Sentinel Service Discovery")
    print()
    print(f"{'Provider':<18} {status['provider']}")
    print(f"{'Targets':<18} {status['targets']}")
    print(f"{'Observed endpoints':<18} {status['endpoints']['observed']}")
    print(f"{'Stale endpoints':<18} {status['endpoints']['stale']}")
    print(f"{'Last inspection':<18} {status['last_inspection'] or '-'}")


def build_parser():
    parser = argparse.ArgumentParser(
        prog="service_discovery.py",
        description="HomeLab Sentinel Service Discovery Core",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    targets = subparsers.add_parser(
        "targets",
        help="Derive canonical Service Discovery targets from Living Inventory",
    )
    targets.add_argument(
        "--database",
        required=True,
        help="Path to the Living Inventory SQLite database",
    )
    targets.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON lines",
    )

    targets.add_argument(
        "--exclude-retry-pool",
        action="store_true",
        help="Exclude targets whose latest Service Discovery run is inconclusive",
    )

    status = subparsers.add_parser(
        "status",
        help="Show canonical Service Discovery subsystem summary",
    )
    status.add_argument(
        "--database",
        required=True,
        help="Path to the Living Inventory SQLite database",
    )
    status.add_argument(
        "--json",
        action="store_true",
        help="Emit canonical JSON output",
    )

    services = subparsers.add_parser(
        "services",
        help="Show derived current Service Discovery endpoints for one entity",
    )
    services.add_argument(
        "entity_id",
        help="Canonical Living Inventory entity_id",
    )
    services.add_argument(
        "--database",
        required=True,
        help="Path to the Living Inventory SQLite database",
    )
    services.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON lines",
    )

    history = subparsers.add_parser(
        "history",
        help="Show Service Discovery observation and inspection history for one entity",
    )
    history.add_argument(
        "entity_id",
        help="Canonical Living Inventory entity_id",
    )
    history.add_argument(
        "--database",
        required=True,
        help="Path to the Living Inventory SQLite database",
    )
    history.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON lines",
    )

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    try:
        if args.command == "targets":
            targets = service_discovery_targets(args.database)

            if args.exclude_retry_pool:
                conn = connect_read_only(args.database)
                try:
                    require_schema(conn)
                    retry_pool = service_discovery_retry_pool(conn, targets)
                finally:
                    conn.close()

                retry_keys = {
                    (target["entity_id"], target["address"])
                    for target in retry_pool
                }

                targets = [
                    target
                    for target in targets
                    if (target["entity_id"], target["address"]) not in retry_keys
                ]

            if args.json:
                emit_json(targets)
            else:
                emit_human(targets)
            return 0

        if args.command == "status":
            status = service_discovery_status(args.database)
            if args.json:
                emit_status_json(status)
            else:
                emit_status_human(status)
            return 0

        if args.command == "services":
            records = service_discovery_services(args.database, args.entity_id)
            if args.json:
                emit_json(records)
            else:
                emit_services_human(args.entity_id, records)
            return 0

        if args.command == "history":
            records = service_discovery_history(args.database, args.entity_id)
            if args.json:
                emit_json(records)
            else:
                emit_history_human(args.entity_id, records)
            return 0

        parser.error(f"unknown command: {args.command}")
        return 2

    except (OSError, sqlite3.Error, RuntimeError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
