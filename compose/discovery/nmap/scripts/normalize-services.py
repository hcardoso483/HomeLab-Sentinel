#!/usr/bin/env python3

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone


def timestamp_for_host(host):
    value = host.get("endtime") or host.get("starttime")

    if value:
        try:
            return datetime.fromtimestamp(
                int(value),
                tz=timezone.utc,
            ).isoformat().replace("+00:00", "Z")
        except (TypeError, ValueError, OSError):
            pass

    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def normalize_service_name(port):
    service = port.find("service")

    if service is None:
        return None

    name = service.get("name")

    if not name or name == "unknown":
        return None

    return name


def normalize_host(host, entity_id, target_address, suppress_services=False):
    status = host.find("status")

    if status is not None and status.get("state") != "up":
        return []

    observed_at = timestamp_for_host(host)
    records = []

    for port in host.findall("./ports/port"):
        protocol = port.get("protocol")
        port_id = port.get("portid")

        if protocol != "tcp":
            continue

        try:
            port_number = int(port_id)
        except (TypeError, ValueError):
            continue

        if not 1 <= port_number <= 65535:
            continue

        state = port.find("state")

        if state is None or state.get("state") != "open":
            continue

        records.append(
            {
                "schema_version": "1.0",
                "entity_id": entity_id,
                "provider": "nmap",
                "observed_at": observed_at,
                "address": target_address,
                "protocol": "tcp",
                "port": port_number,
                "state": "open",
                "service": (
                    None
                    if suppress_services
                    else normalize_service_name(port)
                ),
            }
        )

    return records


def parse_args():
    parser = argparse.ArgumentParser(
        description="Normalize Nmap XML into HomeLab Sentinel Service Discovery observations"
    )

    parser.add_argument(
        "--entity-id",
        required=True,
        help="Existing HomeLab Sentinel entity identifier",
    )

    parser.add_argument(
        "--address",
        required=True,
        help="Canonical Living Inventory target address",
    )

    parser.add_argument(
        "--suppress-services",
        action="store_true",
        help="Emit endpoint evidence without service-identification labels",
    )

    return parser.parse_args()


def main():
    args = parse_args()

    try:
        tree = ET.parse(sys.stdin)
    except ET.ParseError as error:
        print(
            f"[ERROR] Invalid Nmap XML: {error}",
            file=sys.stderr,
        )
        return 1

    records = []

    for host in tree.getroot().findall("host"):
        records.extend(
            normalize_host(
                host,
                args.entity_id,
                args.address,
                suppress_services=args.suppress_services,
            )
        )

    records.sort(
        key=lambda record: (
            record["address"],
            record["protocol"],
            record["port"],
        )
    )

    for record in records:
        print(
            json.dumps(
                record,
                separators=(",", ":"),
                sort_keys=True,
            )
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
