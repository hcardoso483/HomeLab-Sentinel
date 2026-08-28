#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="${APP_ROOT:-/opt/homelab-sentinel/app}"
LEGACY="${APP_ROOT}/core/status/status.py"
READ_MODEL="${APP_ROOT}/core/status/read_model.py"
RENDERER="${APP_ROOT}/core/status/render.py"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

for path in "${LEGACY}" "${READ_MODEL}" "${RENDERER}"; do
    [[ -f "${path}" ]] || fail "Required status component missing: ${path}"
done

echo "HomeLab Sentinel status renderer equivalence"
echo

normalize_output() {
    local simulation="$1"

    python3 - "${simulation}" <<'PY'
import sys

simulation = sys.argv[1]

# These fields come from live platform state and can legitimately change
# between the legacy evaluation and the canonical evaluation.
always_volatile = {
    "Last success",
    "Reconciliation",
    "Collection",
}

# Monitoring entity counts are live unless the simulation explicitly
# defines the expected Monitoring entity state.
count_fields = {
    "Targets",
    "Healthy",
    "Degraded",
    "Down",
    "Unknown",
}

preserve_counts = simulation == "monitoring-entities-down"

for raw in sys.stdin:
    line = raw.rstrip("\n")

    replaced = False

    for label in always_volatile:
        prefix = f"  {label:<20} "
        if line.startswith(prefix):
            print(f"{prefix}<VOLATILE>")
            replaced = True
            break

    if replaced:
        continue

    if not preserve_counts:
        for label in count_fields:
            prefix = f"  {label:<20} "
            if line.startswith(prefix):
                print(f"{prefix}<VOLATILE>")
                replaced = True
                break

    if replaced:
        continue

    print(line)
PY
}

compare_case() {
    local simulation="$1"
    local expected_rc="$2"
    local ignore_verification="${3:-1}"

    local legacy_output
    local legacy_rc
    local canonical_output
    local canonical_rc
    local legacy_normalized
    local canonical_normalized

    local legacy_args=(
        --simulate "${simulation}"
    )

    if [[ "${ignore_verification}" == "1" ]]; then
        legacy_args+=(--ignore-verification-result)
    fi

    set +e
    legacy_output="$(
        python3 "${LEGACY}" "${legacy_args[@]}"
    )"
    legacy_rc=$?
    set -e

    set +e
    canonical_output="$(
        python3 - \
            "${READ_MODEL}" \
            "${RENDERER}" \
            "${simulation}" \
            "${ignore_verification}" <<'PY'
import importlib.util
import sys
from pathlib import Path


read_model_path = Path(sys.argv[1])
renderer_path = Path(sys.argv[2])
simulation = sys.argv[3]
ignore_verification = sys.argv[4] == "1"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


read_model = load(
    "homelab_sentinel_status_read_model",
    read_model_path,
)

renderer = load(
    "homelab_sentinel_status_renderer",
    renderer_path,
)

payload = read_model.build_status(
    simulation=simulation,
    ignore_verification_result=ignore_verification,
)

text, exit_code = renderer.render_status(payload)

sys.stdout.write(
    f"[TEST] Status simulation enabled: {simulation}\n\n"
)
sys.stdout.write(text)

raise SystemExit(exit_code)
PY
    )"
    canonical_rc=$?
    set -e

    if [[ "${legacy_rc}" -ne "${expected_rc}" ]]; then
        fail \
            "${simulation}: legacy rc=${legacy_rc}, expected=${expected_rc}"
    fi

    if [[ "${canonical_rc}" -ne "${expected_rc}" ]]; then
        fail \
            "${simulation}: canonical rc=${canonical_rc}, expected=${expected_rc}"
    fi

    legacy_normalized="$(
        printf '%s\n' "${legacy_output}" |
            normalize_output "${simulation}"
    )"

    canonical_normalized="$(
        printf '%s\n' "${canonical_output}" |
            normalize_output "${simulation}"
    )"

    if [[ "${legacy_normalized}" != "${canonical_normalized}" ]]; then
        echo "--- LEGACY (NORMALIZED) ---" >&2
        printf '%s\n' "${legacy_normalized}" >&2

        echo "--- CANONICAL (NORMALIZED) ---" >&2
        printf '%s\n' "${canonical_normalized}" >&2

        echo "--- DIFF ---" >&2
        diff -u \
            <(printf '%s\n' "${legacy_normalized}") \
            <(printf '%s\n' "${canonical_normalized}") \
            >&2 || true

        fail "${simulation}: stable renderer contract differs"
    fi

    pass "${simulation}: stable output and exit code equivalent"
}


compare_case "not-installed" 2
compare_case "wrong-runtime-identity" 1
compare_case "missing-database" 1
compare_case "unsupported-schema" 1

compare_case "discovery-failed" 1
compare_case "discovery-running" 0
compare_case "discovery-recovering" 1
compare_case "discovery-scheduler-disabled" 1
compare_case "discovery-schedule-drift" 1
compare_case "discovery-state-unreadable" 1

compare_case "verification-running" 0 0
compare_case "failed-verification" 1 0
compare_case "failed-verification" 0 1

compare_case "monitoring-collection-failed" 1
compare_case "monitoring-evidence-stale" 1
compare_case "monitoring-entities-down" 0

echo
pass "canonical renderer matches legacy stable status contract"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel status renderer equivalence PASSED"
