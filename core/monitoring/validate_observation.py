#!/usr/bin/env python3
import json
from datetime import datetime

SCHEMA_VERSION = "1.0"
STATUSES = {"success", "failed", "unknown"}
REQUIRED_FIELDS = (
    "schema_version",
    "entity_id",
    "provider",
    "check_type",
    "target",
    "checked_at",
    "status",
    "latency_ms",
)

def validate_observation(record):
    if not isinstance(record, dict):
        raise ValueError("Monitoring observation must be a JSON object")

    missing = [field for field in REQUIRED_FIELDS if field not in record]
    if missing:
        raise ValueError("missing required field(s): " + ", ".join(missing))

    if record["schema_version"] != SCHEMA_VERSION:
        raise ValueError(
            f"unsupported Monitoring schema_version: {record['schema_version']}"
        )

    for field in ("entity_id", "provider", "check_type", "target"):
        value = record[field]
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{field} must be a non-empty string")

    if not record["entity_id"].startswith("dev-"):
        raise ValueError("entity_id must be a Sentinel device entity ID")

    checked_at = record["checked_at"]
    if not isinstance(checked_at, str) or not checked_at.endswith("Z"):
        raise ValueError("checked_at must be a UTC timestamp ending in Z")
    try:
        datetime.fromisoformat(checked_at[:-1] + "+00:00")
    except ValueError as exc:
        raise ValueError("checked_at must be a valid UTC timestamp") from exc

    if record["status"] not in STATUSES:
        raise ValueError(
            "status must be one of: " + ", ".join(sorted(STATUSES))
        )

    latency = record["latency_ms"]
    if latency is not None:
        if isinstance(latency, bool) or not isinstance(latency, (int, float)):
            raise ValueError("latency_ms must be numeric or null")
        if latency < 0:
            raise ValueError("latency_ms must not be negative")

    return record

def canonical_payload(record):
    return json.dumps(record, separators=(",", ":"), sort_keys=True)
