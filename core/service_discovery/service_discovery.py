#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[2]
INVENTORY = APP_ROOT / "core" / "inventory" / "inventory.py"


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


def emit_json(targets):
    try:
        for target in targets:
            print(
                json.dumps(
                    target,
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

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    try:
        if args.command == "targets":
            targets = service_discovery_targets(args.database)
            if args.json:
                emit_json(targets)
            else:
                emit_human(targets)
            return 0

        parser.error(f"unknown command: {args.command}")
        return 2
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
