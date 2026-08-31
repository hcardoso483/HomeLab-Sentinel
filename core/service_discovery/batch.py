#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from pathlib import Path

APP_ROOT = Path("/opt/homelab-sentinel/app")
DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")
SERVICE_DISCOVERY = APP_ROOT / "core" / "service_discovery" / "service_discovery.py"
ORCHESTRATOR = APP_ROOT / "core" / "service_discovery" / "orchestrate.py"


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
    result = run_text(
        [
            str(SERVICE_DISCOVERY),
            "targets",
            "--database",
            str(database),
            "--json",
        ]
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(
            detail or "Service Discovery target derivation failed"
        )

    targets = []
    for line_number, line in enumerate(result.stdout.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            target = json.loads(line)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                "Service Discovery targets returned invalid JSON "
                f"on line {line_number}: {exc}"
            ) from exc

        if not isinstance(target, dict):
            raise RuntimeError(
                f"Service Discovery target line {line_number} is not a JSON object"
            )

        entity_id = target.get("entity_id")
        address = target.get("address")
        if not isinstance(entity_id, str) or not entity_id:
            raise RuntimeError(
                f"Service Discovery target line {line_number} has invalid entity_id"
            )
        if not isinstance(address, str) or not address:
            raise RuntimeError(
                f"Service Discovery target line {line_number} has invalid address"
            )
        if target.get("eligible") is not True:
            raise RuntimeError(
                f"Service Discovery target line {line_number} is not eligible"
            )

        targets.append(target)

    return sorted(
        targets,
        key=lambda target: (target["entity_id"], target["address"]),
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
        ]
    )

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        if detail:
            print(
                f"[ERROR] Service Discovery target {entity_id} "
                f"{address}: {detail}",
                file=sys.stderr,
            )

    return result.returncode


def run_batch(database):
    targets = sorted(
        load_targets(database),
        key=lambda target: (target["entity_id"], target["address"]),
    )

    summary = {
        "failed": 0,
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
    print("HomeLab Sentinel Service Discovery Batch")
    print()
    print(f"{'Targets':<12} {summary['targets']}")
    print(f"{'Succeeded':<12} {summary['succeeded']}")
    print(f"{'Failed':<12} {summary['failed']}")


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Service Discovery Batch Orchestrator"
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
        help="Emit canonical batch summary JSON",
    )
    args = parser.parse_args()

    if not args.database.is_file():
        error(f"Inventory database not found: {args.database}")
        return 1

    try:
        summary = run_batch(args.database)
    except RuntimeError as exc:
        error(f"Service Discovery batch failed: {exc}")
        return 1

    emit_json(summary) if args.json else emit_human(summary)
    return 1 if summary["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
