#!/usr/bin/env bash

set -euo pipefail

# HomeLab Sentinel shared library

SENTINEL_ROOT="/opt/homelab-sentinel/app"
LOG_DIR="${SENTINEL_ROOT}/core/logs"

mkdir -p "${LOG_DIR}"

log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

die() {
    log_error "$*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

module_path() {
    local module_id="$1"

    find "${SENTINEL_ROOT}/compose" \
        -type f \
        -name "metadata.yml" \
        -exec grep -l "^id: ${module_id}$" {} \; \
        | head -n 1 \
        | xargs -r dirname
}

require_module() {
    local module_id="$1"
    local path

    path="$(module_path "${module_id}")"

    [[ -n "${path}" ]] || die "Module not found: ${module_id}"

    echo "${path}"
}

validate_metadata() {
    local module_dir="$1"
    local metadata_file="${module_dir}/metadata.yml"

    [[ -f "${metadata_file}" ]] || die "Metadata file not found: ${metadata_file}"

    python3 - "${metadata_file}" <<'PY'
import sys
import yaml

metadata_file = sys.argv[1]

required_fields = [
    "id",
    "name",
    "version",
    "category",
    "description",
    "status",
    "dependencies",
    "capabilities",
]

try:
    with open(metadata_file, "r", encoding="utf-8") as file:
        metadata = yaml.safe_load(file)

    if not isinstance(metadata, dict):
        print("[ERROR] metadata.yml must contain a YAML mapping.")
        sys.exit(1)

    missing = [
        field for field in required_fields
        if field not in metadata
    ]

    if missing:
        print(
            "[ERROR] Missing required metadata fields: "
            + ", ".join(missing)
        )
        sys.exit(1)

    if not isinstance(metadata["dependencies"], list):
        print("[ERROR] 'dependencies' must be a list.")
        sys.exit(1)

    capabilities = metadata["capabilities"]

    if isinstance(capabilities, list):
        # Specification 1.0 legacy format.
        capability_list = capabilities

    elif isinstance(capabilities, dict):
        # Specification 1.1 structured format.
        if "provides" not in capabilities:
            print(
                "[ERROR] Invalid capabilities: "
                "missing 'provides' field."
            )
            sys.exit(1)

        capability_list = capabilities["provides"]

        if not isinstance(capability_list, list):
            print(
                "[ERROR] Invalid capabilities.provides: "
                "expected a list."
            )
            sys.exit(1)

    else:
        print(
            "[ERROR] Invalid capabilities: "
            "expected a list or mapping."
        )
        sys.exit(1)

    for capability in capability_list:
        if not isinstance(capability, str) or not capability:
            print(
                f"[ERROR] Invalid capability: {capability}. "
                "Capabilities must be non-empty strings."
            )
            sys.exit(1)

    print("[INFO] Metadata validation successful.")

except yaml.YAMLError as error:
    print(f"[ERROR] Invalid YAML: {error}")
    sys.exit(1)

except OSError as error:
    print(f"[ERROR] Unable to read metadata: {error}")
    sys.exit(1)
PY
}

check_dependencies() {
    local module_dir="$1"
    local metadata_file="${module_dir}/metadata.yml"

    [[ -f "${metadata_file}" ]] || die "Metadata file not found: ${metadata_file}"

    python3 - "${metadata_file}" <<'PY'
import sys
import shutil
import yaml

metadata_file = sys.argv[1]

try:
    with open(metadata_file, "r", encoding="utf-8") as file:
        metadata = yaml.safe_load(file)

    dependencies = metadata.get("dependencies", [])

    if not isinstance(dependencies, list):
        print("[ERROR] 'dependencies' must be a list.")
        sys.exit(1)

    if not dependencies:
        print("[INFO] No dependencies declared.")
        sys.exit(0)

    failed = False

    for dependency in dependencies:
        if dependency == "docker":
            if shutil.which("docker"):
                print("[INFO] Dependency available: docker")
            else:
                print("[ERROR] Dependency missing: docker")
                failed = True

        else:
            print(f"[WARN] Dependency check not implemented: {dependency}")

    if failed:
        sys.exit(1)

    print("[INFO] Dependency validation successful.")

except yaml.YAMLError as error:
    print(f"[ERROR] Invalid YAML: {error}")
    sys.exit(1)

except OSError as error:
    print(f"[ERROR] Unable to read metadata: {error}")
    sys.exit(1)
PY
}

run_healthcheck() {
    local module_dir="$1"
    local metadata_file="${module_dir}/metadata.yml"
    local healthcheck

    [[ -f "${metadata_file}" ]] || die "Metadata file not found: ${metadata_file}"

    healthcheck="$(python3 - "${metadata_file}" <<'PY'
import sys
import yaml

metadata_file = sys.argv[1]

with open(metadata_file, "r", encoding="utf-8") as file:
    metadata = yaml.safe_load(file)

healthcheck = metadata.get("healthcheck", "")

if healthcheck:
    print(healthcheck)
PY
)"

    if [[ -z "${healthcheck}" ]]; then
        log_warn "No healthcheck defined for module."
        return 0
    fi

    local healthcheck_path="${module_dir}/${healthcheck}"

    [[ -f "${healthcheck_path}" ]] || \
        die "Healthcheck script not found: ${healthcheck_path}"

    [[ -x "${healthcheck_path}" ]] || \
        die "Healthcheck script is not executable: ${healthcheck_path}"

    log_info "Running module healthcheck..."

    if "${healthcheck_path}"; then
        log_info "Module healthcheck passed."
    else
        die "Module healthcheck failed."
    fi
}
