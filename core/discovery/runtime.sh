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
    local failure_class="${15:-}"
    local failure_component="${16:-}"
    local failure_retryable="${17:-}"
    local failure_detail="${18:-}"
    local attempt="${19:-1}"
    local max_attempts="${20:-2}"
    local recovery_action="${21:-none}"
    local recovery_result="${22:-not-attempted}"

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
        "${failure_reason}" \
        "${failure_class}" \
        "${failure_component}" \
        "${failure_retryable}" \
        "${failure_detail}" \
        "${attempt}" \
        "${max_attempts}" \
        "${recovery_action}" \
        "${recovery_result}" <<'PY'
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
    failure_class,
    failure_component,
    failure_retryable,
    failure_detail,
    attempt,
    max_attempts,
    recovery_action,
    recovery_result,
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
last_failure_class = previous.get("last_failure_class")
last_failure_component = previous.get("last_failure_component")
last_failure_retryable = previous.get("last_failure_retryable")
last_failure_detail = previous.get("last_failure_detail")

if transition == "success":
    last_success_at = finished_at
elif transition == "failure":
    last_failure_at = finished_at
    last_failure_reason = failure_reason
    last_failure_class = failure_class or None
    last_failure_component = failure_component or None

    if failure_retryable == "true":
        last_failure_retryable = True
    elif failure_retryable == "false":
        last_failure_retryable = False
    else:
        last_failure_retryable = None

    last_failure_detail = failure_detail or None

if result_state == "SUCCESS":
    freshness = "FRESH"
elif result_state in {"FAILED", "RECOVERING"} and last_success_at:
    freshness = "STALE"
else:
    freshness = "UNKNOWN"

def number(value):
    if value == "":
        return None
    return int(value)

state = {
    "version": 3,
    "run_id": run_id,
    "state": result_state,
    "provider": provider or None,
    "started_at": started_at or None,
    "finished_at": finished_at or None,
    "last_success_at": last_success_at,
    "last_failure_at": last_failure_at,
    "last_failure_reason": last_failure_reason,
    "last_failure_class": last_failure_class,
    "last_failure_component": last_failure_component,
    "last_failure_retryable": last_failure_retryable,
    "last_failure_detail": last_failure_detail,
    "observations": number(stored),
    "duplicates": number(duplicates),
    "scope_count": number(scope_count),
    "correlation": {
        "processed": number(processed),
        "created": number(created),
        "resolved": number(resolved),
        "unresolved": number(unresolved),
    },
    "attempt": int(attempt),
    "max_attempts": int(max_attempts),
    "recovery_action": recovery_action,
    "recovery_result": recovery_result,
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
print(f"Failure class   {value('last_failure_class')}")
print(f"Failure comp.   {value('last_failure_component')}")
print(f"Retryable       {value('last_failure_retryable')}")
print(f"Failure detail  {value('last_failure_detail')}")
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
print(
    f"Attempt         {value('attempt')}/"
    f"{value('max_attempts')}"
)
print(f"Recovery action {value('recovery_action')}")
print(f"Recovery        {value('recovery_result')}")
PY
}

classify_failure() {
    local log_file="$1"

    python3 - "${log_file}" <<'PY_CLASSIFY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])

try:
    lines = path.read_text(
        encoding="utf-8",
        errors="replace",
    ).splitlines()
except OSError as exc:
    print("platform")
    print("runtime")
    print("false")
    print(f"Unable to inspect discovery failure log: {exc}")
    raise SystemExit(0)

error_lines = [
    line.strip()
    for line in lines
    if line.startswith("[ERROR]") or line.startswith("[FAIL]")
]


def find(pattern):
    regex = re.compile(pattern, re.IGNORECASE)

    for line in error_lines:
        if regex.search(line):
            return line

    for line in lines:
        if regex.search(line):
            return line.strip()

    return None


rules = [
    (
        r"Invalid discovery scope configuration:",
        "configuration",
        "scopes",
        "false",
    ),
    (
        r"Discovery scope configuration not found:",
        "configuration",
        "scopes",
        "false",
    ),
    (
        r"Invalid provider configuration:|"
        r"Configured provider is unavailable|"
        r"Unable to resolve discovery provider|"
        r"Discovery provider resolved to an empty ID",
        "configuration",
        "resolver",
        "false",
    ),
    (
        r"Required command not found:|"
        r"Nmap normalizer is missing or not executable:|"
        r"Discovery provider entry point not found or not executable:",
        "dependency",
        "provider",
        "false",
    ),
    (
        r"Required discovery component not found:|"
        r"Required pipeline component not found or not executable:",
        "dependency",
        "pipeline",
        "false",
    ),
    (
        r"Discovery record validation failed for scope:",
        "data",
        "validation",
        "false",
    ),
    (
        r"Observation store failed:|"
        r"Correlation failed:|"
        r"Inventory schema not found:",
        "data",
        "inventory",
        "false",
    ),
    (
        r"network is unreachable|"
        r"no route to host|"
        r"temporary failure|"
        r"timed out|"
        r"timeout",
        "transient",
        "provider",
        "true",
    ),
]

for pattern, failure_class, component, retryable in rules:
    detail = find(pattern)

    if detail is not None:
        print(failure_class)
        print(component)
        print(retryable)
        print(detail)
        raise SystemExit(0)

detail = find(r"Discovery provider failed for scope:")

if detail is not None:
    print("unknown")
    print("provider")
    print("false")
    print(detail)
    raise SystemExit(0)

detail = error_lines[0] if error_lines else None

if detail is None:
    nonempty = [
        line.strip()
        for line in lines
        if line.strip()
    ]
    detail = (
        nonempty[-1]
        if nonempty
        else "Unknown discovery failure"
    )

print("unknown")
print("pipeline")
print("false")
print(detail)
PY_CLASSIFY
}


run_pipeline_attempt() {
    local run_log="$1"

    local -n result_exit="$2"
    local -n result_provider="$3"
    local -n result_scope_count="$4"
    local -n result_stored="$5"
    local -n result_duplicates="$6"
    local -n result_processed="$7"
    local -n result_created="$8"
    local -n result_resolved="$9"
    local -n result_unresolved="${10}"

    local store_line=""
    local correlation_line=""

    result_exit=0
    result_provider=""
    result_scope_count=""
    result_stored=""
    result_duplicates=""
    result_processed=""
    result_created=""
    result_resolved=""
    result_unresolved=""

    if "${PIPELINE}" \
        --database "${DATABASE}" \
        "${SCOPE_CONFIG}" >"${run_log}" 2>&1
    then
        result_exit=0
    else
        result_exit=$?
    fi

    cat "${run_log}"

    result_provider="$(
        sed -n 's/^\[INFO\] Discovery provider: //p' "${run_log}" |
            tail -n 1
    )"

    result_scope_count="$(
        grep -c '^\[INFO\] Discovering scope:' "${run_log}" || true
    )"

    if store_line="$(
        grep '^\[INFO\] Observation store complete\.' "${run_log}" |
            tail -n 1
    )"; then
        result_stored="$(
            sed -n \
                's/.*Stored: \([0-9][0-9]*\), duplicates: \([0-9][0-9]*\).*/\1/p' \
                <<< "${store_line}"
        )"

        result_duplicates="$(
            sed -n \
                's/.*Stored: \([0-9][0-9]*\), duplicates: \([0-9][0-9]*\).*/\2/p' \
                <<< "${store_line}"
        )"
    fi

    if correlation_line="$(
        grep '^\[INFO\] Correlation complete\.' "${run_log}" |
            tail -n 1
    )"; then
        result_processed="$(
            sed -n \
                's/.*Processed: \([0-9][0-9]*\), created: \([0-9][0-9]*\), resolved: \([0-9][0-9]*\), unresolved: \([0-9][0-9]*\).*/\1/p' \
                <<< "${correlation_line}"
        )"

        result_created="$(
            sed -n \
                's/.*Processed: \([0-9][0-9]*\), created: \([0-9][0-9]*\), resolved: \([0-9][0-9]*\), unresolved: \([0-9][0-9]*\).*/\2/p' \
                <<< "${correlation_line}"
        )"

        result_resolved="$(
            sed -n \
                's/.*Processed: \([0-9][0-9]*\), created: \([0-9][0-9]*\), resolved: \([0-9][0-9]*\), unresolved: \([0-9][0-9]*\).*/\3/p' \
                <<< "${correlation_line}"
        )"

        result_unresolved="$(
            sed -n \
                's/.*Processed: \([0-9][0-9]*\), created: \([0-9][0-9]*\), resolved: \([0-9][0-9]*\), unresolved: \([0-9][0-9]*\).*/\4/p' \
                <<< "${correlation_line}"
        )"
    fi
}


extract_failure_reason() {
    local log_file="$1"
    local exit_code="$2"
    local reason=""

    reason="$(
        grep -E '^\[(ERROR|FAIL)\]' "${log_file}" |
            tail -n 1
    )"

    if [[ -z "${reason}" ]]; then
        reason="$(
            grep -v '^[[:space:]]*$' "${log_file}" |
                tail -n 1
        )"
    fi

    if [[ -z "${reason}" ]]; then
        reason="discovery pipeline exited with status ${exit_code}"
    fi

    printf '%s\n' "${reason}"
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
    local failure_class=""
    local failure_component=""
    local failure_retryable=""
    local failure_detail=""
    local -a failure_metadata=()

    local attempt=1
    local max_attempts=2
    local retry_delay=5

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
        "" \
        "" \
        "" \
        "" \
        "" \
        "${attempt}" \
        "${max_attempts}" \
        "none" \
        "not-attempted"

    echo "[INFO] Discovery runtime started: ${run_id}"
    echo "[INFO] Discovery attempt ${attempt}/${max_attempts}"

    run_log="$(
        mktemp "${STATE_DIR}/.discovery-run.XXXXXX.log"
    )"

    run_pipeline_attempt \
        "${run_log}" \
        pipeline_exit \
        provider \
        scope_count \
        stored \
        duplicates \
        processed \
        created \
        resolved \
        unresolved

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
            "" \
            "" \
            "" \
            "" \
            "" \
            "${attempt}" \
            "${max_attempts}" \
            "none" \
            "not-attempted"

        rm -f "${run_log}"

        echo \
            "[PASS] Discovery runtime completed successfully: " \
            "${run_id}"

        return 0
    fi

    failure_reason="$(
        extract_failure_reason \
            "${run_log}" \
            "${pipeline_exit}"
    )"

    mapfile -t failure_metadata < <(
        classify_failure "${run_log}"
    )

    failure_class="${failure_metadata[0]:-unknown}"
    failure_component="${failure_metadata[1]:-pipeline}"
    failure_retryable="${failure_metadata[2]:-false}"
    failure_detail="${failure_metadata[3]:-${failure_reason}}"

    if [[ "${failure_retryable}" != "true" ]]; then
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
            "${failure_reason}" \
            "${failure_class}" \
            "${failure_component}" \
            "${failure_retryable}" \
            "${failure_detail}" \
            "${attempt}" \
            "${max_attempts}" \
            "none" \
            "not-attempted"

        rm -f "${run_log}"

        echo \
            "[FAIL] Discovery runtime failed: ${run_id} " \
            "(non-retryable ${failure_class} failure)" >&2

        return "${pipeline_exit}"
    fi

    write_state \
        "failure" \
        "${run_id}" \
        "${started_at}" \
        "${finished_at}" \
        "RECOVERING" \
        "${provider}" \
        "${scope_count}" \
        "${stored}" \
        "${duplicates}" \
        "${processed}" \
        "${created}" \
        "${resolved}" \
        "${unresolved}" \
        "${failure_reason}" \
        "${failure_class}" \
        "${failure_component}" \
        "${failure_retryable}" \
        "${failure_detail}" \
        "${attempt}" \
        "${max_attempts}" \
        "retry" \
        "in-progress"

    rm -f "${run_log}"

    echo \
        "[RECOVER] Retryable ${failure_class} failure detected; " \
        "retrying in ${retry_delay} seconds."

    sleep "${retry_delay}"

    attempt=2

    echo "[INFO] Discovery attempt ${attempt}/${max_attempts}"

    run_log="$(
        mktemp "${STATE_DIR}/.discovery-run.XXXXXX.log"
    )"

    run_pipeline_attempt \
        "${run_log}" \
        pipeline_exit \
        provider \
        scope_count \
        stored \
        duplicates \
        processed \
        created \
        resolved \
        unresolved

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
            "" \
            "" \
            "" \
            "" \
            "" \
            "${attempt}" \
            "${max_attempts}" \
            "retry" \
            "recovered"

        rm -f "${run_log}"

        echo \
            "[PASS] Discovery runtime recovered successfully: " \
            "${run_id}"

        return 0
    fi

    failure_reason="$(
        extract_failure_reason \
            "${run_log}" \
            "${pipeline_exit}"
    )"

    mapfile -t failure_metadata < <(
        classify_failure "${run_log}"
    )

    failure_class="${failure_metadata[0]:-unknown}"
    failure_component="${failure_metadata[1]:-pipeline}"
    failure_retryable="${failure_metadata[2]:-false}"
    failure_detail="${failure_metadata[3]:-${failure_reason}}"

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
        "${failure_reason}" \
        "${failure_class}" \
        "${failure_component}" \
        "${failure_retryable}" \
        "${failure_detail}" \
        "${attempt}" \
        "${max_attempts}" \
        "retry" \
        "failed"

    rm -f "${run_log}"

    echo \
        "[FAIL] Discovery recovery exhausted after " \
        "${max_attempts} attempts: ${run_id}" >&2

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
