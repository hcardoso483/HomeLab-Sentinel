#!/usr/bin/env python3

import ipaddress
import json
import re
import sys
from datetime import datetime


MAC_RE = re.compile(r"^[0-9A-F]{2}(?::[0-9A-F]{2}){5}$")


def fail(message, line_number=None):
    if line_number is None:
        print(f"[ERROR] {message}", file=sys.stderr)
    else:
        print(
            f"[ERROR] Discovery record line {line_number}: {message}",
            file=sys.stderr,
        )
    return False


def valid_timestamp(value):
    if not isinstance(value, str) or not value:
        return False

    candidate = value

    if candidate.endswith("Z"):
        candidate = candidate[:-1] + "+00:00"

    try:
        parsed = datetime.fromisoformat(candidate)
    except ValueError:
        return False

    return parsed.tzinfo is not None


def validate_record(record, line_number):
    required_fields = {
        "schema_version",
        "provider",
        "discovery_method",
        "discovered_at",
        "ip_addresses",
        "mac_address",
        "hostname",
    }

    if not isinstance(record, dict):
        return fail("record must be a JSON object.", line_number)

    missing = sorted(required_fields - set(record))

    if missing:
        return fail(
            "missing required field(s): " + ", ".join(missing),
            line_number,
        )

    if record["schema_version"] != "1.0":
        return fail(
            f"unsupported schema_version: {record[schema_version]}",
            line_number,
        )

    provider = record["provider"]

    if not isinstance(provider, str) or not provider:
        return fail("provider must be a non-empty string.", line_number)

    if record["discovery_method"] != "host-discovery":
        return fail(
            f"unsupported discovery_method: {record[discovery_method]}",
            line_number,
        )

    if not valid_timestamp(record["discovered_at"]):
        return fail(
            "discovered_at must be an ISO 8601 timestamp with timezone.",
            line_number,
        )

    addresses = record["ip_addresses"]

    if not isinstance(addresses, list) or not addresses:
        return fail(
            "ip_addresses must be a non-empty list.",
            line_number,
        )

    if len(addresses) != len(set(addresses)):
        return fail(
            "ip_addresses must contain unique values.",
            line_number,
        )

    for address in addresses:
        if not isinstance(address, str):
            return fail(
                "each ip_addresses entry must be a string.",
                line_number,
            )

        try:
            ipaddress.ip_address(address)
        except ValueError:
            return fail(
                f"invalid IP address: {address}",
                line_number,
            )

    mac_address = record["mac_address"]

    if mac_address is not None:
        if not isinstance(mac_address, str) or not MAC_RE.fullmatch(mac_address):
            return fail(
                "mac_address must be null or uppercase colon-separated MAC.",
                line_number,
            )

    hostname = record["hostname"]

    if hostname is not None:
        if not isinstance(hostname, str) or not hostname:
            return fail(
                "hostname must be null or a non-empty string.",
                line_number,
            )

    return True


def main():
    valid_records = 0

    for line_number, raw_line in enumerate(sys.stdin, start=1):
        line = raw_line.strip()

        if not line:
            continue

        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            fail(f"invalid JSON: {error}", line_number)
            return 1

        if not validate_record(record, line_number):
            return 1

        print(
            json.dumps(
                record,
                separators=(",", ":"),
                sort_keys=True,
            )
        )

        valid_records += 1

    if valid_records == 0:
        print(
            "[ERROR] No discovery records were provided.",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
