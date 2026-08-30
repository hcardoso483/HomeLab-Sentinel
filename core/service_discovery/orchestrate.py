#!/usr/bin/env python3

import argparse
import subprocess
import sys
from pathlib import Path


APP_ROOT = Path("/opt/homelab-sentinel/app")
RESOLVER = APP_ROOT / "core" / "resolver" / "resolver.sh"
REGISTRY = APP_ROOT / "registry" / "registry.sh"

ENTRYPOINT_ROLE = "service-discovery"


def run_text(command):
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )


def resolve_provider():
    result = run_text([
        str(RESOLVER),
        "provider-id",
        "service-discovery",
    ])

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(
            detail or "Service Discovery provider resolution failed"
        )

    provider = result.stdout.strip()

    if not provider:
        raise RuntimeError(
            "Service Discovery provider resolution returned no provider"
        )

    return provider


def resolve_entrypoint(provider):
    result = run_text([
        str(REGISTRY),
        "entrypoint",
        provider,
        ENTRYPOINT_ROLE,
    ])

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(
            detail
            or (
                f"Service Discovery provider {provider} "
                f"does not expose {ENTRYPOINT_ROLE}"
            )
        )

    path = Path(result.stdout.strip())

    if not path.is_file():
        raise RuntimeError(
            f"Service Discovery provider entrypoint not found: {path}"
        )

    if not path.stat().st_mode & 0o111:
        raise RuntimeError(
            f"Service Discovery provider entrypoint is not executable: {path}"
        )

    return path


def invoke_provider(entrypoint, entity_id, address):
    result = run_text([
        str(entrypoint),
        "--entity-id",
        entity_id,
        "--address",
        address,
    ])

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(
            detail
            or f"Service Discovery provider exited {result.returncode}"
        )

    return result.stdout


def build_parser():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Service Discovery Orchestrator"
    )

    parser.add_argument(
        "--entity-id",
        required=True,
        help="Canonical Living Inventory entity ID",
    )

    parser.add_argument(
        "--address",
        required=True,
        help="Canonical current target address",
    )

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    try:
        provider = resolve_provider()
        entrypoint = resolve_entrypoint(provider)
        output = invoke_provider(
            entrypoint,
            args.entity_id,
            args.address,
        )
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    try:
        sys.stdout.write(output)
        sys.stdout.flush()
    except BrokenPipeError:
        try:
            sys.stdout.close()
        except BrokenPipeError:
            pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
