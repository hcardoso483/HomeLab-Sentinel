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

python3 - "${BATCH}" "${DATABASE}" <<'PY'
import importlib.util
import subprocess
import sys
from pathlib import Path

batch_path = Path(sys.argv[1])
database = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "hls_sd_batch_staged_target",
    batch_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

calls = []
returncodes = iter((75, 75, 0))

def fake_run_text(command):
    calls.append(list(command))
    return subprocess.CompletedProcess(
        command,
        next(returncodes),
        stdout="",
        stderr="",
    )

module.run_text = fake_run_text

result = module.run_target(
    database,
    "dev-0123456789abcdef0123456789abcdef",
    "192.0.2.58",
)

if result != 0:
    raise SystemExit(
        f"[FAIL] staged target did not succeed after Stage 3: {result}"
    )

budgets = []

for command in calls:
    try:
        index = command.index("--scan-budget-seconds")
    except ValueError:
        raise SystemExit(
            "[FAIL] staged target invocation omitted scan budget: "
            f"{command!r}"
        )

    budgets.append(command[index + 1])

if budgets != ["60", "180", "300"]:
    raise SystemExit(
        "[FAIL] staged target budgets were not 60 -> 180 -> 300: "
        f"{budgets!r}"
    )

if len(calls) != 3:
    raise SystemExit(
        f"[FAIL] staged target invoked orchestrator {len(calls)} times"
    )
PY

pass "target retries inconclusive attempts through 60 180 300 second stages"

python3 - "${BATCH}" "${DATABASE}" <<'PY'
import importlib.util
import subprocess
import sys
from pathlib import Path

batch_path = Path(sys.argv[1])
database = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "hls_sd_batch_staged_success_stop",
    batch_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

calls = []

def fake_run_text(command):
    calls.append(list(command))
    return subprocess.CompletedProcess(
        command,
        0,
        stdout="",
        stderr="",
    )

module.run_text = fake_run_text

result = module.run_target(
    database,
    "dev-success",
    "192.0.2.60",
)

if result != 0:
    raise SystemExit(
        f"[FAIL] successful Stage 1 returned unexpected code {result}"
    )

if len(calls) != 1:
    raise SystemExit(
        "[FAIL] successful Stage 1 advanced to later stages: "
        f"{len(calls)} invocations"
    )

command = calls[0]

try:
    index = command.index("--scan-budget-seconds")
except ValueError:
    raise SystemExit("[FAIL] successful Stage 1 omitted scan budget")

if command[index + 1] != "60":
    raise SystemExit(
        "[FAIL] successful first attempt did not use 60-second budget: "
        f"{command[index + 1]!r}"
    )
PY

pass "target stops after authoritative Stage 1 success"

python3 - "${BATCH}" "${DATABASE}" <<'PY'
import importlib.util
import subprocess
import sys
from pathlib import Path

batch_path = Path(sys.argv[1])
database = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "hls_sd_batch_staged_failure_stop",
    batch_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

calls = []

def fake_run_text(command):
    calls.append(list(command))
    return subprocess.CompletedProcess(
        command,
        42,
        stdout="",
        stderr="synthetic provider failure",
    )

module.run_text = fake_run_text

result = module.run_target(
    database,
    "dev-failure",
    "192.0.2.61",
)

if result != 42:
    raise SystemExit(
        f"[FAIL] real provider failure returned unexpected code {result}"
    )

if len(calls) != 1:
    raise SystemExit(
        "[FAIL] real provider failure incorrectly advanced stages: "
        f"{len(calls)} invocations"
    )

command = calls[0]

try:
    index = command.index("--scan-budget-seconds")
except ValueError:
    raise SystemExit("[FAIL] failed Stage 1 omitted scan budget")

if command[index + 1] != "60":
    raise SystemExit(
        "[FAIL] failed first attempt did not use 60-second budget: "
        f"{command[index + 1]!r}"
    )
PY

pass "target does not retry genuine provider failure"

python3 - "${BATCH}" "${DATABASE}" <<'PY'
import importlib.util
import sys
from pathlib import Path

batch_path = Path(sys.argv[1])
database = Path(sys.argv[2])

spec = importlib.util.spec_from_file_location(
    "hls_sd_batch_inconclusive_summary",
    batch_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

module.load_targets = lambda database_path: [
    {
        "entity_id": "dev-inconclusive",
        "address": "192.0.2.75",
        "eligible": True,
    }
]

module.run_target = (
    lambda database_path, entity_id, address: 75
)

summary = module.run_batch(database)

expected = {
    "failed": 0,
    "inconclusive": 1,
    "succeeded": 0,
    "targets": 1,
}

if summary != expected:
    raise SystemExit(
        "[FAIL] fully staged inconclusive target was not separated "
        f"from failures: {summary!r}"
    )
PY

pass "fully staged inconclusive target is separated from failures"

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
    "inconclusive": 0,
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
    "inconclusive": 0,
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

if run_main({"failed": 0, "inconclusive": 0, "succeeded": 3, "targets": 3}) != 0:
    raise SystemExit("fully successful completed batch did not return 0")
rc = run_main({"failed": 1, "inconclusive": 0, "succeeded": 2, "targets": 3})
if rc != 0:
    raise SystemExit(f"completed batch with target-level failures returned {rc}, expected 0")
if run_main({"failed": 0, "inconclusive": 0, "succeeded": 0, "targets": 0}) != 0:
    raise SystemExit("successful zero-target batch did not return 0")
if run_main(error="fixture target derivation failed") != 1:
    raise SystemExit("batch-level RuntimeError did not return 1")
PY

pass "completed batch exit status is independent of target-level failures"
pass "batch-level infrastructure failure still returns nonzero"

echo

python3 - "${BATCH}" <<'PY'
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

batch_path = Path(sys.argv[1])

spec = importlib.util.spec_from_file_location(
    "service_discovery_batch_retry_exclusion",
    batch_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

calls = []

def fake_run_text(command):
    calls.append(command)
    return subprocess.CompletedProcess(
        command,
        0,
        stdout=json.dumps(
            {
                "schema_version": "1.0",
                "entity_id": "dev-a",
                "entity_type": "device",
                "address": "192.0.2.10",
                "eligible": True,
                "state": "UNKNOWN",
            }
        ) + "\n",
        stderr="",
    )

module.run_text = fake_run_text

targets = module.load_targets("/tmp/inventory.db")

if len(targets) != 1:
    raise SystemExit(
        f"unexpected target result while testing Retry Pool exclusion: {targets!r}"
    )

if len(calls) != 1:
    raise SystemExit(
        f"normal target derivation invoked unexpected command count: {calls!r}"
    )

command = calls[0]

if "--exclude-retry-pool" not in command:
    raise SystemExit(
        "normal Service Discovery sweep did not request Retry Pool exclusion"
    )

if command.count("--exclude-retry-pool") != 1:
    raise SystemExit(
        f"Retry Pool exclusion flag was not passed exactly once: {command!r}"
    )
PY

pass "normal sweep excludes Retry Pool members during target derivation"

echo

echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery batch regression PASSED"
