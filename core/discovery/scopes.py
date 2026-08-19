#!/usr/bin/env python3

import ipaddress
import re
import sys
from pathlib import Path

import yaml


ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")

ALLOWED_TYPES = {"network", "host", "range"}
ALLOWED_SOURCES = {"user", "interface", "route"}


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def validate_target(target, scope_type):
    if not isinstance(target, str) or not target:
        return False, "target must be a non-empty string"

    try:
        if scope_type == "network":
            ipaddress.ip_network(target, strict=True)
        elif scope_type == "host":
            ipaddress.ip_address(target)
        elif scope_type == "range":
            if "-" not in target:
                return False, "range target must contain '-'"

            start, end = target.split("-", 1)
            start_ip = ipaddress.ip_address(start)
            end_ip = ipaddress.ip_address(end)

            if start_ip.version != end_ip.version:
                return False, "range endpoints must use the same IP version"

            if int(start_ip) > int(end_ip):
                return False, "range start must not be greater than range end"
    except ValueError as exc:
        return False, str(exc)

    return True, None


def validate_scope(scope, index):
    errors = []

    if not isinstance(scope, dict):
        return [f"scope #{index} must be a mapping"]

    required_fields = {"id", "target", "type", "source", "authorized", "enabled"}

    missing = sorted(required_fields - set(scope))
    if missing:
        errors.append(
            f"scope #{index} missing required field(s): {', '.join(missing)}"
        )
        return errors

    scope_id = scope["id"]
    if not isinstance(scope_id, str) or not ID_RE.fullmatch(scope_id):
        errors.append(
            f"scope #{index} id must use lowercase letters, numbers, and hyphens"
        )

    scope_type = scope["type"]
    if scope_type not in ALLOWED_TYPES:
        errors.append(
            f"scope #{index} has unsupported type: {scope_type}"
        )
    else:
        ok, message = validate_target(scope["target"], scope_type)
        if not ok:
            errors.append(f"scope #{index} invalid target: {message}")

    source = scope["source"]
    if source not in ALLOWED_SOURCES:
        errors.append(
            f"scope #{index} has unsupported source: {source}"
        )

    for field in ("authorized", "enabled"):
        if not isinstance(scope[field], bool):
            errors.append(
                f"scope #{index} field '{field}' must be true or false"
            )

    return errors


def load_scopes(config_file):
    with config_file.open("r", encoding="utf-8") as file:
        data = yaml.safe_load(file) or {}

    if not isinstance(data, dict):
        raise ValueError("discovery scope configuration must be a YAML mapping")

    if "scopes" not in data:
        raise ValueError("missing required top-level field: scopes")

    scopes = data["scopes"]

    if not isinstance(scopes, list):
        raise ValueError("'scopes' must be a list")

    errors = []

    seen_ids = set()

    for index, scope in enumerate(scopes, start=1):
        errors.extend(validate_scope(scope, index))

        if isinstance(scope, dict):
            scope_id = scope.get("id")
            if isinstance(scope_id, str):
                if scope_id in seen_ids:
                    errors.append(f"duplicate scope id: {scope_id}")
                seen_ids.add(scope_id)

    if errors:
        raise ValueError("; ".join(errors))

    return scopes


def main():
    if len(sys.argv) != 3:
        error(
            "Usage: scopes.py <validate|active> <discovery-scopes.yml>"
        )
        return 1

    action = sys.argv[1]
    config_file = Path(sys.argv[2])

    if action not in {"validate", "active"}:
        error(f"Unsupported action: {action}")
        return 1

    if not config_file.is_file():
        error(f"Discovery scope configuration not found: {config_file}")
        return 1

    try:
        scopes = load_scopes(config_file)
    except (OSError, yaml.YAMLError, ValueError) as exc:
        error(f"Invalid discovery scope configuration: {exc}")
        return 1

    if action == "validate":
        print(
            f"[INFO] Discovery scope validation successful. "
            f"Scopes: {len(scopes)}"
        )
        return 0

    active_scopes = [
        scope
        for scope in scopes
        if scope["authorized"] and scope["enabled"]
    ]

    for scope in active_scopes:
        print(
            f"{scope["id"]}|{scope["type"]}|"
            f"{scope["target"]}|{scope["source"]}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
