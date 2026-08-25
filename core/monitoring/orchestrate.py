#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from pathlib import Path

APP_ROOT = Path("/opt/homelab-sentinel/app")
DEFAULT_DATABASE = Path("/srv/homelab-sentinel/sentinel/inventory.db")
MONITORING = APP_ROOT / "core" / "monitoring" / "monitoring.py"
RESOLVER = APP_ROOT / "core" / "resolver" / "resolver.sh"
REGISTRY = APP_ROOT / "registry" / "registry.sh"
STORE = APP_ROOT / "core" / "monitoring" / "store.py"
ENTRYPOINT_ROLE = "monitoring-observer"

def error(message):
    print(f"[ERROR] {message}", file=sys.stderr)

def run_text(command, *, input_text=None):
    return subprocess.run(
        command,
        input=input_text,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )

def load_targets(database):
    result = run_text([
        str(MONITORING), "targets",
        "--database", str(database),
        "--json",
    ])
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(detail or "Monitoring target derivation failed")

    rows = []
    for number, line in enumerate(result.stdout.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"Monitoring targets returned invalid JSON on line {number}: {exc}"
            ) from exc
        if not isinstance(item, dict):
            raise RuntimeError(
                f"Monitoring target line {number} is not a JSON object"
            )
        rows.append(item)
    return rows

def resolve_provider():
    result = run_text([str(RESOLVER), "provider-id", "monitoring"])
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(detail or "Monitoring provider resolution failed")

    provider = result.stdout.strip()
    if not provider:
        raise RuntimeError("Monitoring provider resolution returned no provider")
    return provider

def resolve_adapter(provider):
    result = run_text([
        str(REGISTRY), "entrypoint",
        provider, ENTRYPOINT_ROLE,
    ])
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(
            detail or
            f"Monitoring provider {provider} does not expose {ENTRYPOINT_ROLE}"
        )

    path = Path(result.stdout.strip())
    if not path.is_file():
        raise RuntimeError(f"Monitoring adapter not found: {path}")
    if not path.stat().st_mode & 0o111:
        raise RuntimeError(f"Monitoring adapter is not executable: {path}")
    return path

def target_endpoint(target):
    endpoints = target.get("endpoints")
    if not isinstance(endpoints, dict):
        return None

    addresses = endpoints.get("ip_addresses")
    if isinstance(addresses, list):
        for address in addresses:
            if isinstance(address, str) and address:
                return address

    hostname = endpoints.get("hostname")
    if isinstance(hostname, str) and hostname:
        return hostname

    return None

def invoke_adapter(adapter, target, endpoint):
    result = run_text([
        str(adapter),
        "--entity-id", target["entity_id"],
        "--target", endpoint,
    ])

    if result.returncode != 0:
        return None, (
            result.stderr.strip()
            or result.stdout.strip()
            or f"adapter exited {result.returncode}"
        )

    lines = [line for line in result.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        return None, "adapter did not emit exactly one observation"

    try:
        observation = json.loads(lines[0])
    except json.JSONDecodeError as exc:
        return None, f"adapter returned invalid JSON: {exc}"

    if not isinstance(observation, dict):
        return None, "adapter observation is not a JSON object"

    return observation, None

def persist_observation(database, observation):
    payload = json.dumps(
        observation,
        separators=(",", ":"),
        sort_keys=True,
    ) + "\n"

    result = run_text(
        [str(STORE), "--database", str(database)],
        input_text=payload,
    )

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        if (
            "missing required field" in detail
            or "unsupported Monitoring" in detail
            or "must be " in detail
            or "must not be " in detail
        ):
            return "INVALID_EVIDENCE", detail
        return "STORE_ERROR", detail or "Monitoring persistence failed"

    return "SUCCESS", None

def collect(database):
    summary = {
        "provider": None,
        "targets_considered": 0,
        "targets_attempted": 0,
        "success": 0,
        "skipped": 0,
        "provider_error": 0,
        "adapter_error": 0,
        "invalid_evidence": 0,
        "store_error": 0,
        "outcomes": [],
    }

    try:
        provider = resolve_provider()
        summary["provider"] = provider
        adapter = resolve_adapter(provider)
    except RuntimeError as exc:
        summary["provider_error"] = 1
        summary["outcomes"].append({
            "entity_id": None,
            "outcome": "PROVIDER_ERROR",
            "detail": str(exc),
        })
        return summary

    targets = load_targets(database)
    summary["targets_considered"] = len(targets)

    for target in targets:
        entity_id = target.get("entity_id")

        if target.get("eligible") is not True:
            summary["skipped"] += 1
            summary["outcomes"].append({
                "entity_id": entity_id,
                "outcome": "SKIPPED",
                "detail": "target is not eligible",
            })
            continue

        endpoint = target_endpoint(target)
        if endpoint is None:
            summary["skipped"] += 1
            summary["outcomes"].append({
                "entity_id": entity_id,
                "outcome": "SKIPPED",
                "detail": "target has no usable current endpoint",
            })
            continue

        summary["targets_attempted"] += 1
        observation, detail = invoke_adapter(adapter, target, endpoint)

        if observation is None:
            summary["adapter_error"] += 1
            summary["outcomes"].append({
                "entity_id": entity_id,
                "outcome": "ADAPTER_ERROR",
                "detail": detail,
            })
            continue

        outcome, detail = persist_observation(database, observation)
        summary[outcome.lower()] += 1
        summary["outcomes"].append({
            "entity_id": entity_id,
            "outcome": outcome,
            "detail": detail,
        })

    return summary

def emit_json(summary):
    print(json.dumps(summary, separators=(",", ":"), sort_keys=True))

def emit_human(summary):
    print("HomeLab Sentinel Monitoring Collection")
    print()
    print(f"{'Provider':<22} {summary['provider'] or 'UNKNOWN'}")
    print(f"{'Targets considered':<22} {summary['targets_considered']}")
    print(f"{'Targets attempted':<22} {summary['targets_attempted']}")
    print(f"{'Success':<22} {summary['success']}")
    print(f"{'Skipped':<22} {summary['skipped']}")
    print(f"{'Provider errors':<22} {summary['provider_error']}")
    print(f"{'Adapter errors':<22} {summary['adapter_error']}")
    print(f"{'Invalid evidence':<22} {summary['invalid_evidence']}")
    print(f"{'Store errors':<22} {summary['store_error']}")

def main():
    parser = argparse.ArgumentParser(
        description="HomeLab Sentinel Monitoring Orchestrator"
    )
    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help=f"Inventory database path (default: {DEFAULT_DATABASE})",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit canonical collection summary JSON",
    )
    args = parser.parse_args()

    if not args.database.is_file():
        error(f"Inventory database not found: {args.database}")
        return 1

    try:
        summary = collect(args.database)
    except RuntimeError as exc:
        error(f"Monitoring orchestration failed: {exc}")
        return 1

    emit_json(summary) if args.json else emit_human(summary)

    failures = (
        summary["provider_error"]
        + summary["adapter_error"]
        + summary["invalid_evidence"]
        + summary["store_error"]
    )
    return 1 if failures else 0

if __name__ == "__main__":
    raise SystemExit(main())
