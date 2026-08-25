#!/usr/bin/env python3
import argparse, json, subprocess, sys
from pathlib import Path

APP_ROOT = Path("/opt/homelab-sentinel/app")
DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")
INVENTORY = APP_ROOT / "core" / "inventory" / "inventory.py"
RESOLVER = APP_ROOT / "core" / "resolver" / "resolver.sh"

def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)

def load_inventory_records(database):
    if not INVENTORY.is_file():
        raise RuntimeError(f"Living Inventory not found: {INVENTORY}")
    result = subprocess.run(
        [str(INVENTORY), "--database", str(database), "list"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, check=False,
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

def monitoring_target(record):
    entity_id = record.get("entity_id")
    entity_type = record.get("entity_type")
    if not isinstance(entity_id, str) or not entity_id:
        raise RuntimeError("Living Inventory record is missing a valid entity_id")
    if not isinstance(entity_type, str) or not entity_type:
        raise RuntimeError(f"Living Inventory entity {entity_id} is missing entity_type")
    current = record.get("current")
    if not isinstance(current, dict):
        raise RuntimeError(f"Living Inventory entity {entity_id} has invalid current state")
    raw_addresses = current.get("ip_addresses", [])
    if not isinstance(raw_addresses, list):
        raise RuntimeError(f"Living Inventory entity {entity_id} has invalid ip_addresses")
    ip_addresses = []
    for address in raw_addresses:
        if not isinstance(address, str) or not address:
            raise RuntimeError(
                f"Living Inventory entity {entity_id} contains an invalid current IP address"
            )
        ip_addresses.append(address)
    hostname = current.get("hostname")
    if hostname is not None and (not isinstance(hostname, str) or not hostname):
        raise RuntimeError(f"Living Inventory entity {entity_id} has invalid hostname")
    eligible = bool(ip_addresses or hostname)
    return {
        "schema_version": "1.0",
        "entity_id": entity_id,
        "entity_type": entity_type,
        "endpoints": {
            "ip_addresses": ip_addresses,
            "hostname": hostname,
        },
        "eligible": eligible,
        "state": "UNKNOWN",
    }

def monitoring_targets(database):
    return sorted(
        [monitoring_target(record) for record in load_inventory_records(database)],
        key=lambda item: item["entity_id"],
    )


def monitoring_provider():
    if not RESOLVER.is_file():
        raise RuntimeError(f"Provider Resolver not found: {RESOLVER}")

    result = subprocess.run(
        [str(RESOLVER), "resolve", "monitoring"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(
            detail or "Monitoring provider resolution failed"
        )

    fields = {
        "capability": "monitoring",
        "provider": None,
        "source": None,
        "status": None,
    }

    for line in result.stdout.splitlines():
        if line.startswith("Capability: "):
            fields["capability"] = line.split(":", 1)[1].strip()
        elif line.startswith("Selected provider: "):
            fields["provider"] = line.split(":", 1)[1].strip()
        elif line.startswith("Source: "):
            fields["source"] = line.split(":", 1)[1].strip()
        elif line.startswith("Status: "):
            fields["status"] = line.split(":", 1)[1].strip()

    for key in ("provider", "source", "status"):
        if not fields[key]:
            raise RuntimeError(
                "Provider Resolver returned incomplete Monitoring "
                f"provider data: missing {key}"
            )

    return fields


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
        return

def endpoint_text(target):
    addresses = target["endpoints"]["ip_addresses"]
    if addresses:
        return ",".join(addresses)
    hostname = target["endpoints"]["hostname"]
    return hostname if hostname else "-"

def hostname_text(target):
    hostname = target["endpoints"]["hostname"]
    return hostname if hostname else "-"

def emit_human(targets):
    print("HomeLab Sentinel Monitoring Targets")
    print()
    if not targets:
        print("No Living Inventory entities are available.")
        return
    print(f"{'ENTITY_ID':<38} {'ENDPOINT':<24} {'HOSTNAME':<24} {'STATE':<8}")
    for target in targets:
        print(
            f"{target['entity_id']:<38} "
            f"{endpoint_text(target):<24} "
            f"{hostname_text(target):<24} "
            f"{target['state']:<8}"
        )


def emit_provider_json(provider):
    print(
        json.dumps(
            provider,
            separators=(",", ":"),
            sort_keys=True,
        )
    )


def emit_provider_human(provider):
    print("HomeLab Sentinel Monitoring Provider")
    print()
    print(f"{'Capability':<18} {provider['capability']}")
    print(f"{'Provider':<18} {provider['provider']}")
    print(f"{'Source':<18} {provider['source']}")
    print(f"{'Status':<18} {provider['status']}")


def main():
    parser = argparse.ArgumentParser(description="HomeLab Sentinel Monitoring Core")
    parser.add_argument(
        "command",
        nargs="?",
        default="targets",
        choices=("targets", "provider"),
        help="Monitoring query command (default: targets)",
    )
    parser.add_argument(
        "--database", type=Path, default=DEFAULT_DATABASE,
        help=f"Inventory database path (default: {DEFAULT_DATABASE})",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Emit one canonical JSON target per line",
    )
    args = parser.parse_args()
    try:
        if args.command == "provider":
            provider = monitoring_provider()
            if args.json:
                emit_provider_json(provider)
            else:
                emit_provider_human(provider)
            return 0

        if not args.database.is_file():
            error(f"Inventory database not found: {args.database}")
            return 1

        targets = monitoring_targets(args.database)
    except RuntimeError as exc:
        error(str(exc))
        return 1

    emit_json(targets) if args.json else emit_human(targets)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
