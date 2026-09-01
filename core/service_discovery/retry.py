#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
from pathlib import Path

MODULE_DIR = Path(__file__).resolve().parent

if str(MODULE_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_DIR))

from service_discovery import (
    connect_read_only,
    require_schema,
    service_discovery_retry_pool,
    service_discovery_targets,
)

DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")

APP_ROOT = Path("/opt/homelab-sentinel/app")
ORCHESTRATOR = APP_ROOT / "core" / "service_discovery" / "orchestrate.py"

RETRY_SCAN_BUDGET_SECONDS = 300


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def run_text(command):
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )


def load_targets(database):
    targets = service_discovery_targets(database)

    connection = connect_read_only(database)
    try:
        require_schema(connection)
        retry_pool = service_discovery_retry_pool(
            connection,
            targets,
        )
    finally:
        connection.close()

    return sorted(
        retry_pool,
        key=lambda target: (
            target["entity_id"],
            target["address"],
        ),
    )


def run_target(database, entity_id, address):
    result = run_text(
        [
            str(ORCHESTRATOR),
            "--entity-id",
            entity_id,
            "--address",
            address,
            "--database",
            str(database),
            "--scan-budget-seconds",
            str(RETRY_SCAN_BUDGET_SECONDS),
        ]
    )

    if result.returncode not in (0, 75):
        detail = result.stderr.strip() or result.stdout.strip()

        if detail:
            print(
                f"[ERROR] Service Discovery Retry Pool target "
                f"{entity_id} {address}: {detail}",
                file=sys.stderr,
            )

    return result.returncode


def run_retry(database):
    targets = sorted(
        load_targets(database),
        key=lambda target: (
            target["entity_id"],
            target["address"],
        ),
    )

    summary = {
        "failed": 0,
        "inconclusive": 0,
        "succeeded": 0,
        "targets": len(targets),
    }

    for target in targets:
        returncode = run_target(
            database,
            target["entity_id"],
            target["address"],
        )

        if returncode == 0:
            summary["succeeded"] += 1
        elif returncode == 75:
            summary["inconclusive"] += 1
        else:
            summary["failed"] += 1

    return summary


def emit_json(summary):
    print(
        json.dumps(
            summary,
            separators=(",", ":"),
            sort_keys=True,
        )
    )


def emit_human(summary):
    print("HomeLab Sentinel Service Discovery Retry Pool")
    print()
    print(f"{'Targets':<14} {summary['targets']}")
    print(f"{'Succeeded':<14} {summary['succeeded']}")
    print(f"{'Inconclusive':<14} {summary['inconclusive']}")
    print(f"{'Failed':<14} {summary['failed']}")


def main():
    parser = argparse.ArgumentParser(
        description=(
            "HomeLab Sentinel Service Discovery Retry Pool Worker"
        )
    )

    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help=f"Inventory database path (default: {DEFAULT_DATABASE})",
    )

    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit canonical Retry Pool summary JSON",
    )

    args = parser.parse_args()

    if not args.database.is_file():
        error(f"Inventory database not found: {args.database}")
        return 1

    try:
        summary = run_retry(args.database)
    except RuntimeError as exc:
        error(f"Service Discovery Retry Pool failed: {exc}")
        return 1

    emit_json(summary) if args.json else emit_human(summary)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
