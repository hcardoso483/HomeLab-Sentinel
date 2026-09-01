#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BATCH="${APP_ROOT}/core/service_discovery/batch.py"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

[[ -f "${BATCH}" ]] || fail "Service Discovery batch orchestrator missing: ${BATCH}"
[[ -x "${BATCH}" ]] || fail "Service Discovery batch orchestrator is not executable"

TMP_DIR="$(mktemp -d /tmp/hls-service-discovery-batch-test.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

TARGETS_FILE="${TMP_DIR}/targets.jsonl"
CALLS_FILE="${TMP_DIR}/calls.log"
RESULT_FILE="${TMP_DIR}/result.json"
DATABASE="${TMP_DIR}/inventory.db"
: >"${DATABASE}"

cat >"${TARGETS_FILE}" <<'JSONL'
{"address":"198.51.100.11","eligible":true,"entity_id":"dev-b","entity_type":"device","schema_version":"1.0","state":"UNKNOWN"}
{"address":"192.0.2.20","eligible":true,"entity_id":"dev-c","entity_type":"device","schema_version":"1.0","state":"UNKNOWN"}
{"address":"192.0.2.11","eligible":true,"entity_id":"dev-a","entity_type":"device","schema_version":"1.0","state":"UNKNOWN"}
JSONL

python3 - "${BATCH}" "${DATABASE}" "${TARGETS_FILE}" "${CALLS_FILE}" "${RESULT_FILE}" <<'PY'
import contextlib
import importlib.util
import io
import json
import sys
from pathlib import Path

batch_path = Path(sys.argv[1])
database = Path(sys.argv[2])
targets_file = Path(sys.argv[3])
calls_file = Path(sys.argv[4])
result_file = Path(sys.argv[5])

spec = importlib.util.spec_from_file_location("service_discovery_batch", batch_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

targets = [
    json.loads(line)
    for line in targets_file.read_text(encoding="utf-8").splitlines()
    if line.strip()
]

load_count = 0

def fake_load_targets(database_path):
    global load_count
    load_count += 1
    if load_count != 1:
        raise AssertionError("target derivation was called more than once")
    return list(targets)

calls = []

def fake_run_target(database_path, entity_id, address):
    calls.append((entity_id, address))
    with calls_file.open("a", encoding="utf-8") as handle:
        handle.write(f"{entity_id} {address}\n")
    if entity_id == "dev-b":
        return 1
    return 0

module.load_targets = fake_load_targets
module.run_target = fake_run_target

summary = module.run_batch(database)

expected_calls = [
    ("dev-a", "192.0.2.11"),
    ("dev-b", "198.51.100.11"),
    ("dev-c", "192.0.2.20"),
]
if calls != expected_calls:
    raise SystemExit(f"targets were not processed deterministically: {calls!r}")

expected_summary = {
    "failed": 1,
    "succeeded": 2,
    "targets": 3,
}
if summary != expected_summary:
    raise SystemExit(f"unexpected batch summary: {summary!r}")

result_file.write_text(
    json.dumps(summary, separators=(",", ":"), sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

pass "target set is derived exactly once"
pass "targets are processed sequentially in deterministic entity/address order"
pass "one target failure does not abort later targets"
pass "batch summary separates succeeded and failed targets"

python3 - "${BATCH}" "${DATABASE}" <<'PY'
import importlib.util
import sys
from pathlib import Path

batch_path = Path(sys.argv[1])
database = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location("service_discovery_batch_zero", batch_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

calls = []

module.load_targets = lambda database_path: []
module.run_target = lambda database_path, entity_id, address: calls.append(
    (entity_id, address)
) or 0

summary = module.run_batch(database)

if calls:
    raise SystemExit(f"zero-target batch invoked target orchestrator: {calls!r}")

expected = {
    "failed": 0,
    "succeeded": 0,
    "targets": 0,
}
if summary != expected:
    raise SystemExit(f"unexpected zero-target batch summary: {summary!r}")
PY

pass "zero targets is a successful empty batch"

python3 - "${BATCH}" "${DATABASE}" <<'PY'
import importlib.util
import sys
from pathlib import Path

batch_path = Path(sys.argv[1])
database = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location("service_discovery_batch_error", batch_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def fail_load(database_path):
    raise RuntimeError("fixture target derivation failed")

module.load_targets = fail_load

try:
    module.run_batch(database)
except RuntimeError as exc:
    if "fixture target derivation failed" not in str(exc):
        raise SystemExit(f"unexpected target derivation error: {exc}")
else:
    raise SystemExit("batch swallowed target derivation failure")
PY

pass "target derivation failure aborts before any target execution"

python3 - "${BATCH}" "${DATABASE}" <<'PY'
import contextlib
import importlib.util
import io
import sys
from pathlib import Path

batch_path = Path(sys.argv[1])
database = Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("service_discovery_batch_exit_contract", batch_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original_argv = list(sys.argv)

def run_main(summary=None, error=None):
    def fake_run_batch(database_path):
        if error is not None:
            raise RuntimeError(error)
        return dict(summary)
    module.run_batch = fake_run_batch
    sys.argv = [str(batch_path), "--database", str(database), "--json"]
    stdout = io.StringIO()
    stderr = io.StringIO()
    try:
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            returncode = module.main()
    finally:
        sys.argv = original_argv
    return returncode

if run_main({"failed": 0, "succeeded": 3, "targets": 3}) != 0:
    raise SystemExit("fully successful completed batch did not return 0")
rc = run_main({"failed": 1, "succeeded": 2, "targets": 3})
if rc != 0:
    raise SystemExit(f"completed batch with target-level failures returned {rc}, expected 0")
if run_main({"failed": 0, "succeeded": 0, "targets": 0}) != 0:
    raise SystemExit("successful zero-target batch did not return 0")
if run_main(error="fixture target derivation failed") != 1:
    raise SystemExit("batch-level RuntimeError did not return 1")
PY

pass "completed batch exit status is independent of target-level failures"
pass "batch-level infrastructure failure still returns nonzero"

echo

echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery batch regression PASSED"
