#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCHESTRATOR="${APP_ROOT}/core/service_discovery/orchestrate.py"
BATCH="${APP_ROOT}/core/service_discovery/batch.py"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

[[ -x "${ORCHESTRATOR}" ]] || fail "Service Discovery orchestrator missing or not executable"
[[ -f "${BATCH}" ]] || fail "Service Discovery batch orchestrator missing"

TMP_ROOT="$(mktemp -d /tmp/hls-service-discovery-timeout-test.XXXXXX)"
trap 'rm -rf "${TMP_ROOT}"' EXIT
DB="${TMP_ROOT}/inventory.db"
FIXTURE_PROVIDER="${TMP_ROOT}/fixture-provider.sh"
CHILD_PID_FILE="${TMP_ROOT}/child.pid"

python3 - "${DB}" "${APP_ROOT}" <<'PY'
import sqlite3, sys
from pathlib import Path

db = Path(sys.argv[1])
root = Path(sys.argv[2])
conn = sqlite3.connect(db)
conn.execute("PRAGMA foreign_keys = ON")
conn.executescript((root / "core/inventory/schema.sql").read_text())

migrations = root / "core/inventory/migrations"
for version, path in sorted(
    (int(p.name.split("_", 1)[0]), p) for p in migrations.glob("*.sql")
):
    current = conn.execute("PRAGMA user_version").fetchone()[0]
    if version == current + 1:
        conn.executescript(path.read_text())

entity = "dev-0123456789abcdef0123456789abcdef"
conn.execute(
    "INSERT INTO entities(entity_id, entity_type, created_at, updated_at) VALUES (?, 'device', ?, ?)",
    (entity, "2026-08-31T12:00:00Z", "2026-08-31T12:00:00Z"),
)
conn.commit()
conn.close()
PY

cat >"${FIXTURE_PROVIDER}" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail

ENTITY_ID=""
ADDRESS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --entity-id) ENTITY_ID="$2"; shift 2 ;;
        --address) ADDRESS="$2"; shift 2 ;;
        *) exit 2 ;;
    esac
done

printf '%s\n' "{\"address\":\"${ADDRESS}\",\"entity_id\":\"${ENTITY_ID}\",\"observed_at\":\"2026-08-31T12:00:05Z\",\"port\":443,\"protocol\":\"tcp\",\"provider\":\"fixture-provider\",\"schema_version\":\"1.0\",\"service\":\"https\",\"state\":\"open\"}"

sleep 120 &
child_pid=$!
printf '%s\n' "${child_pid}" >"${HLS_TEST_CHILD_PID_FILE}"
wait "${child_pid}"
SH
chmod +x "${FIXTURE_PROVIDER}"

python3 - "${ORCHESTRATOR}" "${BATCH}" "${DB}" "${FIXTURE_PROVIDER}" "${CHILD_PID_FILE}" <<'PY'
import importlib.util, os, sqlite3, sys, time
from pathlib import Path

orchestrator_path = Path(sys.argv[1])
batch_path = Path(sys.argv[2])
db = Path(sys.argv[3])
fixture = Path(sys.argv[4])
child_pid_file = Path(sys.argv[5])

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

o = load("hls_sd_timeout", orchestrator_path)

# RED gate: implementation must define one explicit whole-provider ceiling.
if not hasattr(o, "PROVIDER_TIMEOUT_SECONDS"):
    raise SystemExit("[FAIL] orchestrator has no bounded provider execution timeout policy")

if o.PROVIDER_TIMEOUT_SECONDS != 600:
    raise SystemExit(
        f"[FAIL] expected production target timeout 600 seconds, got {o.PROVIDER_TIMEOUT_SECONDS!r}"
    )

# Keep the regression fast.
o.PROVIDER_TIMEOUT_SECONDS = 1
o.resolve_provider = lambda: "fixture-provider"
o.resolve_entrypoint = lambda provider: fixture
os.environ["HLS_TEST_CHILD_PID_FILE"] = str(child_pid_file)

entity = "dev-0123456789abcdef0123456789abcdef"
address = "192.0.2.111"
sys.argv = [
    str(orchestrator_path),
    "--entity-id", entity,
    "--address", address,
    "--database", str(db),
]

started = time.monotonic()
result = o.main()
elapsed = time.monotonic() - started

if result == 0:
    raise SystemExit("[FAIL] timed-out provider invocation unexpectedly succeeded")
if elapsed > 8:
    raise SystemExit(f"[FAIL] one-second timeout took too long: {elapsed:.2f}s")

conn = sqlite3.connect(db)
run = conn.execute(
    "SELECT outcome, detail FROM service_discovery_runs WHERE entity_id=? AND address=? ORDER BY completed_at DESC, service_discovery_run_id DESC LIMIT 1",
    (entity, address),
).fetchone()
obs = conn.execute(
    "SELECT COUNT(*) FROM service_observations WHERE entity_id=? AND address=?",
    (entity, address),
).fetchone()[0]
links = conn.execute(
    "SELECT COUNT(*) FROM service_discovery_run_observations l JOIN service_discovery_runs r ON r.service_discovery_run_id=l.service_discovery_run_id WHERE r.entity_id=? AND r.address=?",
    (entity, address),
).fetchone()[0]
conn.close()

if run is None:
    raise SystemExit("[FAIL] timeout did not persist an inspection run")
if run[0] != "provider_error":
    raise SystemExit(f"[FAIL] timeout must persist provider_error, got {run!r}")

detail = (run[1] or "").lower()
if "timeout" not in detail and "timed out" not in detail:
    raise SystemExit(f"[FAIL] timeout detail is not explicit: {run!r}")

if obs != 0:
    raise SystemExit(f"[FAIL] partial stdout became evidence after timeout: {obs}")
if links != 0:
    raise SystemExit(f"[FAIL] timed-out inspection created authoritative links: {links}")

deadline = time.monotonic() + 3
while not child_pid_file.exists() and time.monotonic() < deadline:
    time.sleep(0.05)
if not child_pid_file.exists():
    raise SystemExit("[FAIL] fixture child PID was not captured")

pid = int(child_pid_file.read_text().strip())

def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True

deadline = time.monotonic() + 3
while alive(pid) and time.monotonic() < deadline:
    time.sleep(0.05)
if alive(pid):
    raise SystemExit(f"[FAIL] provider descendant survived timeout: pid={pid}")

b = load("hls_sd_timeout_batch", batch_path)
targets = [
    {"entity_id": "dev-a", "address": "192.0.2.10", "eligible": True},
    {"entity_id": "dev-b", "address": "192.0.2.20", "eligible": True},
]
calls = []
b.load_targets = lambda database: list(targets)

def fake_run_target(database, entity_id, address):
    calls.append((entity_id, address))
    return 1 if entity_id == "dev-a" else 0

b.run_target = fake_run_target
summary = b.run_batch(db)

if calls != [("dev-a", "192.0.2.10"), ("dev-b", "192.0.2.20")]:
    raise SystemExit(f"[FAIL] batch did not continue after bounded failure: {calls!r}")
if summary != {"failed": 1, "inconclusive": 0, "succeeded": 1, "targets": 2}:
    raise SystemExit(f"[FAIL] unexpected batch summary: {summary!r}")

print("[PASS] timed-out provider invocation is bounded")
print("[PASS] timeout is persisted as non-authoritative provider_error")
print("[PASS] partial provider stdout is discarded after timeout")
print("[PASS] provider descendants are terminated on timeout")
print("[PASS] batch continues with the next target after bounded failure")
PY

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Service Discovery timeout regression PASSED"
