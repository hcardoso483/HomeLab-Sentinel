#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SERVICE_USER="${SERVICE_USER:-homelab-sentinel}"
DATABASE="${DATABASE:-/srv/homelab-sentinel/sentinel/inventory.db}"
STATE_DIR="${STATE_DIR:-/srv/homelab-sentinel/sentinel/runtime}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/discovery.json}"
PIPELINE="${PIPELINE:-${APP_ROOT}/core/pipeline/run.sh}"
SCOPE_CONFIG="${SCOPE_CONFIG:-${APP_ROOT}/config/sentinel/discovery-scopes.yml}"

usage() {
    echo "Usage: ${0} {run|status}"
    echo
    echo "Manage HomeLab Sentinel Discovery Runtime state."
}

utc_now() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

new_run_id() {
    python3 - <<'PY'
import uuid
print(f"run-{uuid.uuid4().hex}")
PY
}

require_run_identity() {
    local current_user

    current_user="$(id -un)"

    if [[ "${current_user}" != "${SERVICE_USER}" ]]; then
        echo \
            "[ERROR] Discovery runtime must run as ${SERVICE_USER}; " \
            "current user is ${current_user}." >&2
        exit 1
    fi
}

require_runtime_inputs() {
    [[ -x "${PIPELINE}" ]] || {
        echo "[ERROR] Discovery pipeline missing or not executable: ${PIPELINE}" >&2
        exit 1
    }

    [[ -f "${DATABASE}" ]] || {
        echo "[ERROR] Inventory database missing: ${DATABASE}" >&2
        exit 1
    }

    [[ -f "${SCOPE_CONFIG}" ]] || {
        echo "[ERROR] Discovery scope configuration missing: ${SCOPE_CONFIG}" >&2
        exit 1
    }
}

write_state() {
    local transition="$1"
    local run_id="$2"
    local started_at="$3"
    local finished_at="$4"
    local result_state="$5"
    local provider="$6"
    local scope_count="$7"
    local stored="$8"
    local duplicates="$9"
    local processed="${10}"
    local created="${11}"
    local resolved="${12}"
    local unresolved="${13}"
    local failure_reason="${14}"

    python3 - \
        "${STATE_FILE}" \
        "${transition}" \
        "${run_id}" \
        "${started_at}" \
        "${finished_at}" \
        "${result_state}" \
        "${provider}" \
        "${scope_count}" \
        "${stored}" \
        "${duplicates}" \
        "${processed}" \
        "${created}" \
        "${resolved}" \
        "${unresolved}" \
        "${failure_reason}" <<'PY'
import json
import os
import sys
import tempfile
from pathlib import Path

(
    state_path,
    transition,
    run_id,
    started_at,
    finished_at,
    result_state,
    provider,
    scope_count,
    stored,
    duplicates,
    processed,
    created,
    resolved,
    unresolved,
    failure_reason,
) = sys.argv[1:]

path = Path(state_path)
path.parent.mkdir(parents=True, exist_ok=True)

previous = {}

if path.is_file():
    try:
        previous = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(
            f"[ERROR] Unable to read existing discovery runtime state: {exc}"
        )

if not isinstance(previous, dict):
    raise SystemExit("[ERROR] Existing discovery runtime state is not a JSON object.")

last_success_at = previous.get("last_success_at")
last_failure_at = previous.get("last_failure_at")
last_failure_reason = previous.get("last_failure_reason")

if transition == "success":
    last_success_at = finished_at
elif transition == "failure":
    last_failure_at = finished_at
    last_failure_reason = failure_reason

if result_state == "SUCCESS":
    freshness = "FRESH"
elif result_state == "FAILED" and last_success_at:
    freshness = "STALE"
else:
    freshness = "UNKNOWN"

def number(value):
    if value == "":
        return None
    return int(value)

state = {
    "version": 1,
    "run_id": run_id,
    "state": result_state,
    "provider": provider or None,
    "started_at": started_at or None,
    "finished_at": finished_at or None,
    "last_success_at": last_success_at,
    "last_failure_at": last_failure_at,
    "last_failure_reason": last_failure_reason,
    "observations": number(stored),
    "duplicates": number(duplicates),
    "scope_count": number(scope_count),
    "correlation": {
        "processed": number(processed),
        "created": number(created),
        "resolved": number(resolved),
        "unresolved": number(unresolved),
    },
    "attempt": 1,
    "max_attempts": 1,
    "recovery_action": "none",
    "recovery_result": "not-attempted",
    "freshness": freshness,
}

fd, temporary_name = tempfile.mkstemp(
    prefix=".discovery-state.",
    suffix=".tmp",
    dir=path.parent,
    text=True,
)

try:
    with os.fdopen(fd, "w", encoding="utf-8") as file:
        json.dump(state, file, indent=2, sort_keys=True)
        file.write("\n")
        file.flush()
        os.fsync(file.fileno())

    os.chmod(temporary_name, 0o644)
    os.replace(temporary_name, path)

    directory_fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
finally:
    if os.path.exists(temporary_name):
        os.unlink(temporary_name)
PY
}

status_runtime() {
    if [[ ! -f "${STATE_FILE}" ]]; then
        echo "HomeLab Sentinel Discovery Runtime"
        echo
        echo "State           NEVER RUN"
        echo "State file      ${STATE_FILE}"
        return 2
    fi

    python3 - "${STATE_FILE}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

try:
    state = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    print(f"[ERROR] Unable to read discovery runtime state: {exc}", file=sys.stderr)
    raise SystemExit(1)

if not isinstance(state, dict):
    print("[ERROR] Discovery runtime state is not a JSON object.", file=sys.stderr)
    raise SystemExit(1)

correlation = state.get("correlation") or {}

def value(name, default="N/A"):
    current = state.get(name)
    return default if current is None else current

def correlation_value(name):
    current = correlation.get(name)
    return "N/A" if current is None else current

print("HomeLab Sentinel Discovery Runtime")
print()
print(f"State           {value('state')}")
print(f"Run ID          {value('run_id')}")
print(f"Provider        {value('provider')}")
print(f"Started         {value('started_at')}")
print(f"Finished        {value('finished_at')}")
print(f"Last success    {value('last_success_at')}")
print(f"Last failure    {value('last_failure_at')}")
print(f"Failure reason  {value('last_failure_reason')}")
print(f"Freshness       {value('freshness')}")
print(f"Scopes          {value('scope_count')}")
print(f"Observations    {value('observations')}")
print(f"Duplicates      {value('duplicates')}")
print(
    "Correlation     "
    f"processed={correlation_value('processed')} "
    f"created={correlation_value('created')} "
    f"resolved={correlation_value('resolved')} "
    f"unresolved={correlation_value('unresolved')}"
)
print(f"Recovery        {value('recovery_result')}")
PY
}

run_runtime() {
    local run_id
    local started_at
    local finished_at
    local run_log
    local pipeline_exit
    local provider=""
    local scope_count=""
    local stored=""
    local duplicates=""
    local processed=""
    local created=""
    local resolved=""
    local unresolved=""
    local failure_reason=""

    require_run_identity
    require_runtime_inputs

    mkdir -p "${STATE_DIR}"

    run_id="$(new_run_id)"
    started_at="$(utc_now)"

    write_state \
        "running" \
        "${run_id}" \
        "${started_at}" \
        "" \
        "RUNNING" \
        "" \
        "" \
        "" \
        "" \
        "" \
        "" \
        "" \
        "" \
        ""

    echo "[INFO] Discovery runtime started: ${run_id}"

    run_log="$(mktemp "${STATE_DIR}/.discovery-run.XXXXXX.log")"

    set +e
    "${PIPELINE}" \
        --database "${DATABASE}" \
        "${SCOPE_CONFIG}" >"${run_log}" 2>&1
    pipeline_exit=$?
    set -e

    cat "${run_log}"

    provider="$(
        sed -n 's/^\[INFO\] Discovery provider: //p' "${run_log}" |
            tail -n 1
    )"

    scope_count="$(
        grep -c '^\[INFO\] Discovering scope:' "${run_log}" || true
    )"

    if store_line="$(
        grep '^\[INFO\] Observation store complete\.' "${run_log}" |
            tail -n 1
    )"; then
        stored="$(
            sed -n 's/.*Stored: \([0-9][0-9]*\), duplicates: \([0-9][0-9]*\).*/\1/p' \
                <<< "${store_line}"
        )"
        duplicates="$(
            sed -n 's/.*Stored: \([0-9][0-9]*\), duplicates: \([0-9][0-9]*\).*/\2/p' \
                <<< "${store_line}"
        )"
    fi

    if correlation_line="$(
        grep '^\[INFO\] Correlation complete\.' "${run_log}" |
            tail -n 1
    )"; then
        processed="$(
            sed -n 's/.*Processed: \([0-9][0-9]*\), created: \([0-9][0-9]*\), resolved: \([0-9][0-9]*\), unresolved: \([0-9][0-9]*\).*/\1/p' \
                <<< "${correlation_line}"
        )"
        created="$(
            sed -n 's/.*Processed: \([0-9][0-9]*\), created: \([0-9][0-9]*\), resolved: \([0-9][0-9]*\), unresolved: \([0-9][0-9]*\).*/\2/p' \
                <<< "${correlation_line}"
        )"
        resolved="$(
            sed -n 's/.*Processed: \([0-9][0-9]*\), created: \([0-9][0-9]*\), resolved: \([0-9][0-9]*\), unresolved: \([0-9][0-9]*\).*/\3/p' \
                <<< "${correlation_line}"
        )"
        unresolved="$(
            sed -n 's/.*Processed: \([0-9][0-9]*\), created: \([0-9][0-9]*\), resolved: \([0-9][0-9]*\), unresolved: \([0-9][0-9]*\).*/\4/p' \
                <<< "${correlation_line}"
        )"
    fi

    finished_at="$(utc_now)"

    if (( pipeline_exit == 0 )); then
        write_state \
            "success" \
            "${run_id}" \
            "${started_at}" \
            "${finished_at}" \
            "SUCCESS" \
            "${provider}" \
            "${scope_count}" \
            "${stored}" \
            "${duplicates}" \
            "${processed}" \
            "${created}" \
            "${resolved}" \
            "${unresolved}" \
            ""

        rm -f "${run_log}"

        echo "[PASS] Discovery runtime completed successfully: ${run_id}"
        return 0
    fi

    failure_reason="$(
        grep -E '^\[(ERROR|FAIL)\]' "${run_log}" |
            tail -n 1
    )"

    if [[ -z "${failure_reason}" ]]; then
        failure_reason="$(
            grep -v '^[[:space:]]*$' "${run_log}" |
                tail -n 1
        )"
    fi

    if [[ -z "${failure_reason}" ]]; then
        failure_reason="discovery pipeline exited with status ${pipeline_exit}"
    fi

    write_state \
        "failure" \
        "${run_id}" \
        "${started_at}" \
        "${finished_at}" \
        "FAILED" \
        "${provider}" \
        "${scope_count}" \
        "${stored}" \
        "${duplicates}" \
        "${processed}" \
        "${created}" \
        "${resolved}" \
        "${unresolved}" \
        "${failure_reason}"

    rm -f "${run_log}"

    echo \
        "[FAIL] Discovery runtime failed: ${run_id} " \
        "(pipeline exit ${pipeline_exit})" >&2
    return "${pipeline_exit}"
}

main() {
    case "${1:-}" in
        run)
            shift
            [[ $# -eq 0 ]] || {
                usage >&2
                return 2
            }
            run_runtime
            ;;
        status)
            shift
            [[ $# -eq 0 ]] || {
                usage >&2
                return 2
            }
            status_runtime
            ;;
        --help|-h|help)
            usage
            ;;
        *)
            usage >&2
            return 2
            ;;
    esac
}

main "$@"
