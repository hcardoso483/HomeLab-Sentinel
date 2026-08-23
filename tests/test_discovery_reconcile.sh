#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RECONCILER="${APP_ROOT}/core/discovery/reconcile.py"

pass() {
    echo "[PASS] $*"
}

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

run_json_case() {
    local name="$1"
    local expected_exit="$2"
    local simulation="${3:-}"

    local output
    local result
    local json_file

    json_file="$(mktemp)"

    echo
    echo "=== ${name} ==="

    set +e

    if [[ -n "${simulation}" ]]; then
        "${RECONCILER}" audit \
            --json \
            --simulate "${simulation}" \
            >"${json_file}"
        result=$?
    else
        "${RECONCILER}" audit \
            --json \
            >"${json_file}"
        result=$?
    fi

    set -e

    cat "${json_file}"

    if [[ "${result}" -ne "${expected_exit}" ]]; then
        rm -f "${json_file}"
        fail \
            "${name}: expected exit ${expected_exit}, got ${result}"
    fi

    pass "${name} exit=${result}"

    CASE_JSON="${json_file}"
}


[[ -x "${RECONCILER}" ]] ||
    fail "Discovery reconciler not executable: ${RECONCILER}"

echo "HomeLab Sentinel Discovery reconciliation regression test"

run_json_case "HEALTHY AUDIT" 0

python3 - "${CASE_JSON}" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
facts = data["facts"]

expected = {
    "compliant": True,
}

for key, wanted in expected.items():
    actual = data.get(key)
    if actual != wanted:
        raise SystemExit(
            f"[FAIL] {key}: expected {wanted!r}, got {actual!r}"
        )
    print(f"[PASS] {key} = {actual!r}")

fact_expectations = {
    "policy_valid": True,
    "fragment_present": True,
    "fragment_matches": True,
    "dropin_present": True,
    "dropin_registered": True,
    "dropin_matches_policy": True,
    "interval_matches_policy": True,
    "loaded": True,
    "enabled": True,
    "active": True,
}

for key, wanted in fact_expectations.items():
    actual = facts.get(key)
    if actual != wanted:
        raise SystemExit(
            f"[FAIL] {key}: expected {wanted!r}, got {actual!r}"
        )
    print(f"[PASS] {key} = {actual!r}")
PY

rm -f "${CASE_JSON}"

run_json_case "DISABLED TIMER" 1 "disabled"

python3 - "${CASE_JSON}" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
facts = data["facts"]

checks = {
    "compliant": False,
    "enabled": False,
    "active": True,
    "dropin_matches_policy": True,
    "interval_matches_policy": True,
}

for key, wanted in checks.items():
    actual = data.get(key) if key == "compliant" else facts.get(key)

    if actual != wanted:
        raise SystemExit(
            f"[FAIL] {key}: expected {wanted!r}, got {actual!r}"
        )

    print(f"[PASS] {key} = {actual!r}")
PY

rm -f "${CASE_JSON}"

run_json_case "INACTIVE TIMER" 1 "inactive"

python3 - "${CASE_JSON}" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
facts = data["facts"]

checks = {
    "enabled": True,
    "active": False,
}

for key, wanted in checks.items():
    actual = facts.get(key)

    if actual != wanted:
        raise SystemExit(
            f"[FAIL] {key}: expected {wanted!r}, got {actual!r}"
        )

    print(f"[PASS] {key} = {actual!r}")

if data.get("compliant") is not False:
    raise SystemExit("[FAIL] inactive timer must be drift")

print("[PASS] compliant = False")
PY

rm -f "${CASE_JSON}"

run_json_case "MISSING DROP-IN" 1 "missing-dropin"

python3 - "${CASE_JSON}" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
facts = data["facts"]

checks = {
    "dropin_present": False,
    "dropin_registered": False,
    "dropin_matches_policy": False,
}

for key, wanted in checks.items():
    actual = facts.get(key)

    if actual != wanted:
        raise SystemExit(
            f"[FAIL] {key}: expected {wanted!r}, got {actual!r}"
        )

    print(f"[PASS] {key} = {actual!r}")

if data.get("compliant") is not False:
    raise SystemExit("[FAIL] missing drop-in must be drift")

print("[PASS] compliant = False")
PY

rm -f "${CASE_JSON}"

run_json_case "WRONG DROP-IN" 1 "wrong-dropin"

python3 - "${CASE_JSON}" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
facts = data["facts"]

if facts.get("dropin_matches_policy") is not False:
    raise SystemExit(
        "[FAIL] wrong drop-in was not detected"
    )

if facts.get("interval_matches_policy") is not True:
    raise SystemExit(
        "[FAIL] effective interval should remain independently matched"
    )

if data.get("compliant") is not False:
    raise SystemExit("[FAIL] wrong drop-in must be drift")

print("[PASS] dropin_matches_policy = False")
print("[PASS] interval_matches_policy = True")
print("[PASS] compliant = False")
PY

rm -f "${CASE_JSON}"

run_json_case \
    "WRONG EFFECTIVE INTERVAL" \
    1 \
    "wrong-effective-interval"

python3 - "${CASE_JSON}" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
facts = data["facts"]

desired = facts.get("desired_interval_minutes")
effective = facts.get("effective_interval_minutes")

if effective == desired:
    raise SystemExit(
        "[FAIL] simulated effective interval did not drift"
    )

if facts.get("interval_matches_policy") is not False:
    raise SystemExit(
        "[FAIL] effective interval drift was not detected"
    )

if facts.get("dropin_matches_policy") is not True:
    raise SystemExit(
        "[FAIL] drop-in policy should remain independently matched"
    )

if data.get("compliant") is not False:
    raise SystemExit(
        "[FAIL] wrong effective interval must be drift"
    )

print(f"[PASS] desired interval = {desired}")
print(f"[PASS] effective interval = {effective}")
print("[PASS] interval_matches_policy = False")
print("[PASS] dropin_matches_policy = True")
print("[PASS] compliant = False")
PY

rm -f "${CASE_JSON}"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Discovery reconciliation regression PASSED"
