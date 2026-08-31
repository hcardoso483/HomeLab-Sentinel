#!/usr/bin/env python3
import argparse
import os
import signal
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path


APP_ROOT = Path("/opt/homelab-sentinel/app")
DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")

PROVIDER_RESOLVER = APP_ROOT / "core" / "resolver" / "resolver.sh"
PROVIDER_REGISTRY = APP_ROOT / "registry" / "registry.sh"
STORE = APP_ROOT / "core" / "service_discovery" / "store.py"
ENTRYPOINT_ROLE = "service-discovery"
PROVIDER_TIMEOUT_SECONDS = 600


def utc_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def run_text(command, *, input_text=None, timeout=None):
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE if input_text is not None else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(input=input_text, timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
        raise RuntimeError(f"command timed out after {timeout} seconds")

    if process.returncode != 0:
        message = stderr.strip() or stdout.strip()
        raise RuntimeError(
            message or f"command failed with exit code {process.returncode}"
        )
    return stdout


def resolve_provider():
    output = run_text(
        [
            str(PROVIDER_RESOLVER),
            "provider-id",
            "service-discovery",
        ]
    ).strip()

    if not output:
        raise RuntimeError(
            "Service Discovery provider resolution returned no provider"
        )

    return output.splitlines()[-1].strip()


def resolve_entrypoint(provider):
    output = run_text(
        [
            str(PROVIDER_REGISTRY),
            "entrypoint",
            provider,
            ENTRYPOINT_ROLE,
        ]
    ).strip()

    if not output:
        raise RuntimeError(
            f"provider {provider!r} has no {ENTRYPOINT_ROLE} entrypoint"
        )

    path = Path(output.splitlines()[-1].strip())

    if not path.is_absolute():
        path = APP_ROOT / path

    if not path.is_file():
        raise RuntimeError(
            f"Service Discovery provider entrypoint not found: {path}"
        )

    return path

def invoke_provider(entrypoint, entity_id, address):
    return run_text(
        [
            str(entrypoint),
            "--entity-id",
            entity_id,
            "--address",
            address,
        ],
        timeout=PROVIDER_TIMEOUT_SECONDS,
    )


def persist_observations(
    database,
    output,
    *,
    run_id=None,
    entity_id=None,
    address=None,
    provider=None,
    started_at=None,
    completed_at=None,
    outcome="success",
    detail=None,
):
    command = [
        sys.executable,
        str(STORE),
        "--database",
        str(database),
    ]

    if run_id is not None:
        command.extend(
            [
                "--run-id",
                run_id,
                "--entity-id",
                entity_id,
                "--address",
                address,
                "--provider",
                provider,
                "--started-at",
                started_at,
                "--completed-at",
                completed_at,
                "--outcome",
                outcome,
            ]
        )

        if detail is not None:
            command.extend(["--detail", detail])

    try:
        run_text(
            command,
            input_text=output,
        )
    except RuntimeError as exc:
        if outcome == "success":
            raise RuntimeError(
                f"Service Discovery evidence persistence failed: {exc}"
            ) from exc

        raise RuntimeError(
            f"Service Discovery run persistence failed: {exc}"
        ) from exc


def build_parser():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Service Discovery Orchestrator"
    )

    parser.add_argument(
        "--entity-id",
        required=True,
        help="Canonical Sentinel entity identifier",
    )

    parser.add_argument(
        "--address",
        required=True,
        help="Current authoritative target address",
    )

    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help=f"SQLite database path (default: {DEFAULT_DATABASE})",
    )

    return parser


def main():
    args = build_parser().parse_args()

    if not args.database.is_file():
        print(
            f"[ERROR] Inventory database not found: {args.database}",
            file=sys.stderr,
        )
        return 1

    try:
        provider = resolve_provider()
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    run_id = f"run-{uuid.uuid4().hex}"
    started_at = utc_now()

    try:
        entrypoint = resolve_entrypoint(provider)
        output = invoke_provider(
            entrypoint,
            args.entity_id,
            args.address,
        )

    except RuntimeError as exc:
        completed_at = utc_now()

        try:
            persist_observations(
                args.database,
                "",
                run_id=run_id,
                entity_id=args.entity_id,
                address=args.address,
                provider=provider,
                started_at=started_at,
                completed_at=completed_at,
                outcome="provider_error",
                detail=str(exc),
            )
        except RuntimeError as persistence_exc:
            print(
                f"[ERROR] {exc}; additionally failed to persist "
                f"provider_error run: {persistence_exc}",
                file=sys.stderr,
            )
            return 1

        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    completed_at = utc_now()

    try:
        persist_observations(
            args.database,
            output,
            run_id=run_id,
            entity_id=args.entity_id,
            address=args.address,
            provider=provider,
            started_at=started_at,
            completed_at=completed_at,
            outcome="success",
        )
    except RuntimeError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
