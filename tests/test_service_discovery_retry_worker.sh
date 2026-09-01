#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RETRY_WORKER="${APP_ROOT}/core/service_discovery/retry.py"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

echo "HomeLab Sentinel Service Discovery Retry Worker regression"
echo

[[ -f "${RETRY_WORKER}" ]] \
    || fail "Service Discovery Retry Pool worker missing: ${RETRY_WORKER}"

python3 - "${RETRY_WORKER}" <<'PY'
import importlib.util
import pathlib
import sys

worker_path = pathlib.Path(sys.argv[1])

spec = importlib.util.spec_from_file_location(
    "service_discovery_retry_worker",
    worker_path,
)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class Result:
    def __init__(self, returncode, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


# ------------------------------------------------------------------
# A Retry Pool member receives exactly one 300 second attempt.
# ------------------------------------------------------------------

calls = []

def fake_run_text(command):
    calls.append(command)
    return Result(75)

worker.run_text = fake_run_text

rc = worker.run_target(
    pathlib.Path("/tmp/inventory.db"),
    "dev-a",
    "192.0.2.10",
)

if rc != 75:
    raise SystemExit(f"expected retry target rc 75, got {rc}")

if len(calls) != 1:
    raise SystemExit(
        f"retry target was executed {len(calls)} times instead of exactly once"
    )

command = calls[0]

expected_tail = [
    "--entity-id",
    "dev-a",
    "--address",
    "192.0.2.10",
    "--database",
    "/tmp/inventory.db",
    "--scan-budget-seconds",
    "300",
]

if command[1:] != expected_tail:
    raise SystemExit(
        "retry target command does not use one 300 second attempt: "
        f"{command!r}"
    )

print("[PASS] retry member receives exactly one 300 second attempt")


# ------------------------------------------------------------------
# Retry Pool membership is derived fresh for every worker invocation.
# ------------------------------------------------------------------

pool_snapshots = [
    [
        {
            "entity_id": "dev-a",
            "address": "192.0.2.10",
            "eligible": True,
        },
        {
            "entity_id": "dev-b",
            "address": "192.0.2.11",
            "eligible": True,
        },
    ],
    [
        {
            "entity_id": "dev-b",
            "address": "192.0.2.11",
            "eligible": True,
        },
    ],
]

load_calls = 0
processed = []

def fake_load_targets(database):
    global load_calls
    snapshot = pool_snapshots[load_calls]
    load_calls += 1
    return list(snapshot)

def fake_run_target(database, entity_id, address):
    processed.append((entity_id, address))
    return 0 if entity_id == "dev-a" else 75

worker.load_targets = fake_load_targets
worker.run_target = fake_run_target

first = worker.run_retry(pathlib.Path("/tmp/inventory.db"))
second = worker.run_retry(pathlib.Path("/tmp/inventory.db"))

if load_calls != 2:
    raise SystemExit(
        f"Retry Pool was not derived fresh per invocation: {load_calls}"
    )

if processed != [
    ("dev-a", "192.0.2.10"),
    ("dev-b", "192.0.2.11"),
    ("dev-b", "192.0.2.11"),
]:
    raise SystemExit(
        "successful Retry Pool member was processed again on next cycle: "
        f"{processed!r}"
    )

if first != {
    "failed": 0,
    "inconclusive": 1,
    "succeeded": 1,
    "targets": 2,
}:
    raise SystemExit(f"unexpected first retry summary: {first!r}")

if second != {
    "failed": 0,
    "inconclusive": 1,
    "succeeded": 0,
    "targets": 1,
}:
    raise SystemExit(f"unexpected second retry summary: {second!r}")

print("[PASS] Retry Pool membership is derived fresh on every cycle")
print("[PASS] successful member disappears from the next retry cycle")


# ------------------------------------------------------------------
# One target failure must not prevent later pooled targets.
# ------------------------------------------------------------------

worker.load_targets = lambda database: [
    {
        "entity_id": "dev-failure",
        "address": "192.0.2.20",
        "eligible": True,
    },
    {
        "entity_id": "dev-later",
        "address": "192.0.2.21",
        "eligible": True,
    },
]

seen = []

def mixed_run_target(database, entity_id, address):
    seen.append(entity_id)
    if entity_id == "dev-failure":
        return 1
    return 0

worker.run_target = mixed_run_target

summary = worker.run_retry(pathlib.Path("/tmp/inventory.db"))

if seen != ["dev-failure", "dev-later"]:
    raise SystemExit(
        f"target failure aborted Retry Pool processing: {seen!r}"
    )

if summary != {
    "failed": 1,
    "inconclusive": 0,
    "succeeded": 1,
    "targets": 2,
}:
    raise SystemExit(f"unexpected mixed retry summary: {summary!r}")

print("[PASS] one Retry Pool target failure does not abort later members")
PY

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery Retry Worker regression PASSED"
