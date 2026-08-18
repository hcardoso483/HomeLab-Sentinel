#!/usr/bin/env python3

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


def normalize_host(host):
    status = host.find("status")

    if status is None or status.get("state") != "up":
        return None

    ip_addresses = []
    mac_address = None

    for address in host.findall("address"):
        value = address.get("addr")
        address_type = address.get("addrtype")

        if not value:
            continue

        if address_type in ("ipv4", "ipv6"):
            if value not in ip_addresses:
                ip_addresses.append(value)

        elif address_type == "mac" and mac_address is None:
            mac_address = value.upper()

    if not ip_addresses:
        return None

    hostname = None
    hostname_element = host.find("./hostnames/hostname")

    if hostname_element is not None:
        value = hostname_element.get("name")

        if value:
            hostname = value

    return {
        "schema_version": "1.0",
        "provider": "nmap",
        "discovery_method": "host-discovery",
        "discovered_at": timestamp_for_host(host),
        "ip_addresses": ip_addresses,
        "mac_address": mac_address,
        "hostname": hostname,
    }


def main():
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
        record = normalize_host(host)

        if record is not None:
            records.append(record)

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
