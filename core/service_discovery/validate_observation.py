#!/usr/bin/env python3

import ipaddress
import json
import re
from datetime import datetime

SCHEMA_VERSION = "1.0"
PROTOCOLS = {"tcp"}
STATES = {"open"}
ENTITY_ID_RE = re.compile(r"^dev-[0-9a-f]{32}$")

REQUIRED_FIELDS = (
    "schema_version",
    "entity_id",
    "provider",
    "observed_at",
    "address",
    "protocol",
    "port",
    "state",
    "service",
)


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


def validate_observation(record):
    if not isinstance(record, dict):
        raise ValueError("Service Discovery observation must be a JSON object")

    missing = [field for field in REQUIRED_FIELDS if field not in record]
    if missing:
        raise ValueError("missing required field(s): " + ", ".join(missing))

    if record["schema_version"] != SCHEMA_VERSION:
        raise ValueError(
            f"unsupported Service Discovery schema_version: "
            f"{record['schema_version']}"
        )

    entity_id = record["entity_id"]
    if not isinstance(entity_id, str) or not ENTITY_ID_RE.fullmatch(entity_id):
        raise ValueError("entity_id must be a canonical Sentinel device entity ID")

    provider = record["provider"]
    if not isinstance(provider, str) or not provider.strip():
        raise ValueError("provider must be a non-empty string")

    if not valid_timestamp(record["observed_at"]):
        raise ValueError(
            "observed_at must be an ISO 8601 timestamp with timezone"
        )

    address = record["address"]
    if not isinstance(address, str) or not address:
        raise ValueError("address must be a valid IP address")

    try:
        ipaddress.ip_address(address)
    except ValueError as exc:
        raise ValueError("address must be a valid IP address") from exc

    protocol = record["protocol"]
    if not isinstance(protocol, str) or protocol not in PROTOCOLS:
        raise ValueError(
            "protocol must be one of: " + ", ".join(sorted(PROTOCOLS))
        )

    port = record["port"]
    if isinstance(port, bool) or not isinstance(port, int):
        raise ValueError("port must be an integer")
    if port < 1 or port > 65535:
        raise ValueError("port must be between 1 and 65535")

    state = record["state"]
    if not isinstance(state, str) or state not in STATES:
        raise ValueError(
            "state must be one of: " + ", ".join(sorted(STATES))
        )

    service = record["service"]
    if service is not None:
        if not isinstance(service, str) or not service.strip():
            raise ValueError(
                "service must be null or a non-empty string"
            )

    return record


def canonical_payload(record):
    return json.dumps(record, separators=(",", ":"), sort_keys=True)
