#!/usr/bin/env python3

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

DEFAULT_OUTPUT = Path(
    "/srv/homelab-sentinel/prometheus/targets/reachability.json"
)

PROVIDER = "prometheus"
CHECK_TYPE = "reachability"


def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)


def load_targets(stream):
    targets = []

    for line_number, line in enumerate(stream, start=1):
        if not line.strip():
            continue

        try:
            target = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(
                f"line {line_number}: invalid target JSON: {exc.msg}"
            ) from exc

        if not isinstance(target, dict):
            raise ValueError(
                f"line {line_number}: target must be a JSON object"
            )

        targets.append(target)

    return targets


def canonical_endpoint(target):
    endpoints = target.get("endpoints")

    if not isinstance(endpoints, dict):
        raise ValueError(
            f"{target.get('entity_id', '<unknown>')}: "
            "endpoints must be a mapping"
        )

    addresses = endpoints.get("ip_addresses", [])

    if not isinstance(addresses, list):
        raise ValueError(
            f"{target.get('entity_id', '<unknown>')}: "
            "ip_addresses must be a list"
        )

    for address in addresses:
        if not isinstance(address, str) or not address:
            raise ValueError(
                f"{target.get('entity_id', '<unknown>')}: "
                "invalid IP endpoint"
            )
        return address

    hostname = endpoints.get("hostname")

    if hostname is not None:
        if not isinstance(hostname, str) or not hostname:
            raise ValueError(
                f"{target.get('entity_id', '<unknown>')}: "
                "invalid hostname endpoint"
            )
        return hostname

    return None


def render_groups(targets):
    groups = []
    seen_entities = set()

    for target in sorted(
        targets,
        key=lambda item: item.get("entity_id") or "",
    ):
        entity_id = target.get("entity_id")

        if not isinstance(entity_id, str) or not entity_id.startswith("dev-"):
            raise ValueError(
                "Monitoring target is missing a canonical device entity_id"
            )

        if entity_id in seen_entities:
            raise ValueError(f"duplicate Monitoring target: {entity_id}")

        seen_entities.add(entity_id)

        if target.get("eligible") is not True:
            continue

        endpoint = canonical_endpoint(target)

        if endpoint is None:
            raise ValueError(
                f"{entity_id}: eligible target has no usable current endpoint"
            )

        groups.append(
            {
                "targets": [endpoint],
                "labels": {
                    "hls_entity_id": entity_id,
                    "hls_check_type": CHECK_TYPE,
                    "hls_provider": PROVIDER,
                },
            }
        )

    return groups


def atomic_write(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)

    descriptor, temporary = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
        text=True,
    )

    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())

        os.replace(temporary, path)

    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Prometheus target renderer"
    )

    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Generated file_sd JSON path (default: {DEFAULT_OUTPUT})",
    )

    parser.add_argument(
        "--stdout",
        action="store_true",
        help="Emit rendered file_sd JSON without writing a file",
    )

    args = parser.parse_args()

    try:
        targets = load_targets(sys.stdin)
        groups = render_groups(targets)

        payload = json.dumps(
            groups,
            indent=2,
            sort_keys=True,
        ) + "\n"

        if args.stdout:
            sys.stdout.write(payload)
        else:
            atomic_write(args.output, payload)
            print(
                f"[PASS] Prometheus targets rendered: "
                f"{len(groups)} -> {args.output}",
                file=sys.stderr,
            )

    except (OSError, ValueError) as exc:
        error(f"Prometheus target rendering failed: {exc}")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
