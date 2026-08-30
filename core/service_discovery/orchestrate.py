#!/usr/bin/env python3

import argparse
import subprocess
import sys
from pathlib import Path


APP_ROOT = Path("/opt/homelab-sentinel/app")
DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")
RESOLVER = APP_ROOT / "core" / "resolver" / "resolver.sh"
REGISTRY = APP_ROOT / "registry" / "registry.sh"
STORE = APP_ROOT / "core" / "service_discovery" / "store.py"
ENTRYPOINT_ROLE = "service-discovery"


def run_text(command, *, input_text=None):
    return subprocess.run(
        command,
        input=input_text,
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


def persist_observations(database, output):
    result = run_text(
        [
            str(STORE),
            "--database",
            str(database),
        ],
        input_text=output,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(
            detail or "Service Discovery persistence failed"
        )


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
    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help=f"Inventory database path (default: {DEFAULT_DATABASE})",
    )
    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    if not args.database.is_file():
        print(
            f"[ERROR] Inventory database not found: {args.database}",
            file=sys.stderr,
        )
        return 1

    try:
        provider = resolve_provider()
        entrypoint = resolve_entrypoint(provider)
        output = invoke_provider(
            entrypoint,
            args.entity_id,
            args.address,
        )
        persist_observations(args.database, output)
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
