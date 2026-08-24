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
    "initial_trigger_matches_policy": True,
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

run_json_case \
    "MISSING INITIAL TRIGGER" \
    1 \
    "missing-initial-trigger"

python3 - "${CASE_JSON}" <<'PY_CHECK'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
facts = data["facts"]

if facts.get("initial_trigger_matches_policy") is not False:
    raise SystemExit(
        "[FAIL] missing initial trigger was not detected"
    )

if facts.get("interval_matches_policy") is not True:
    raise SystemExit(
        "[FAIL] recurring interval should remain matched"
    )

if data.get("compliant") is not False:
    raise SystemExit(
        "[FAIL] missing initial trigger must be drift"
    )

print("[PASS] initial_trigger_matches_policy = False")
print("[PASS] interval_matches_policy = True")
print("[PASS] compliant = False")
PY_CHECK

rm -f "${CASE_JSON}"

echo
echo "=== REPAIR PLAN CONTRACTS ==="

run_plan_case() {
    local name="$1"
    local expected_exit="$2"
    local simulation="${3:-}"

    local json_file
    local result

    json_file="$(mktemp)"

    echo
    echo "--- ${name} ---"

    set +e

    if [[ -n "${simulation}" ]]; then
        "${RECONCILER}" plan \
            --json \
            --simulate "${simulation}" \
            >"${json_file}"
        result=$?
    else
        "${RECONCILER}" plan \
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


check_plan() {
    local expected_compliant="$1"
    local expected_repairable="$2"
    local expected_actions="$3"
    local expected_reason_mode="$4"

    python3 - \
        "${CASE_JSON}" \
        "${expected_compliant}" \
        "${expected_repairable}" \
        "${expected_actions}" \
        "${expected_reason_mode}" <<'PYPLAN'
import json
import sys
from pathlib import Path

(
    path,
    expected_compliant,
    expected_repairable,
    expected_actions,
    expected_reason_mode,
) = sys.argv[1:]

data = json.loads(Path(path).read_text(encoding="utf-8"))
repair = data.get("repair") or {}

wanted_compliant = expected_compliant == "true"
wanted_repairable = expected_repairable == "true"

if expected_actions:
    wanted_actions = expected_actions.split(",")
else:
    wanted_actions = []

checks = (
    ("compliant", data.get("compliant"), wanted_compliant),
    (
        "repairable",
        repair.get("repairable"),
        wanted_repairable,
    ),
    (
        "actions",
        repair.get("actions"),
        wanted_actions,
    ),
)

for name, actual, wanted in checks:
    if actual != wanted:
        raise SystemExit(
            f"[FAIL] {name}: expected {wanted!r}, got {actual!r}"
        )

    print(f"[PASS] {name} = {actual!r}")

reason = repair.get("reason")

if expected_reason_mode == "none":
    if reason is not None:
        raise SystemExit(
            f"[FAIL] reason: expected None, got {reason!r}"
        )
    print("[PASS] reason = None")

elif expected_reason_mode == "platform-repair":
    if not isinstance(reason, str) or "platform repair is required" not in reason:
        raise SystemExit(
            "[FAIL] refusal reason does not require platform repair"
        )
    print(f"[PASS] refusal reason = {reason}")

else:
    raise SystemExit(
        f"[FAIL] unknown reason contract: {expected_reason_mode}"
    )
PYPLAN

    rm -f "${CASE_JSON}"
}


run_plan_case "HEALTHY REPAIR PLAN" 0

check_plan \
    true \
    true \
    "" \
    none


run_plan_case \
    "DISABLED TIMER REPAIR PLAN" \
    1 \
    disabled

check_plan \
    false \
    true \
    "enable" \
    none


run_plan_case \
    "INACTIVE TIMER REPAIR PLAN" \
    1 \
    inactive

check_plan \
    false \
    true \
    "start" \
    none


run_plan_case \
    "MISSING DROP-IN REPAIR PLAN" \
    1 \
    missing-dropin

check_plan \
    false \
    true \
    "write-dropin,daemon-reload,restart" \
    none


run_plan_case \
    "WRONG DROP-IN REPAIR PLAN" \
    1 \
    wrong-dropin

check_plan \
    false \
    true \
    "write-dropin,daemon-reload,restart" \
    none


run_plan_case \
    "WRONG EFFECTIVE INTERVAL REPAIR PLAN" \
    1 \
    wrong-effective-interval

check_plan \
    false \
    true \
    "write-dropin,daemon-reload,restart" \
    none


run_plan_case \
    "MISSING INITIAL TRIGGER REPAIR PLAN" \
    1 \
    missing-initial-trigger

check_plan \
    false \
    true \
    "write-dropin,daemon-reload,restart" \
    none


run_plan_case \
    "MISSING FRAGMENT REPAIR REFUSAL" \
    2 \
    missing-fragment

check_plan \
    false \
    false \
    "" \
    platform-repair


run_plan_case \
    "WRONG FRAGMENT REPAIR REFUSAL" \
    2 \
    wrong-fragment

check_plan \
    false \
    false \
    "" \
    platform-repair


echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Discovery reconciliation regression PASSED"
