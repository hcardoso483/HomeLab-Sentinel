#!/usr/bin/env bash

set -euo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
MODULE_ROOT="${APP_ROOT}/compose"

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

usage() {
    cat <<EOF_USAGE
HomeLab Sentinel Registry

Usage:
  registry.sh list
  registry.sh get <module>
  registry.sh validate
  registry.sh refresh
EOF_USAGE
}

find_modules() {
    find "${MODULE_ROOT}" \
        -type f \
        -name "metadata.yml" \
        -print
}

find_module_metadata() {
    local requested_id="$1"

    while IFS= read -r metadata_file; do
        local module_id

        module_id="$(
            python3 - "${metadata_file}" <<'PY'
import sys
import yaml

metadata_file = sys.argv[1]

with open(metadata_file, "r", encoding="utf-8") as file:
    metadata = yaml.safe_load(file) or {}

print(metadata.get("id", ""))
PY
        )"

        if [[ "${module_id}" == "${requested_id}" ]]; then
            echo "${metadata_file}"
            return 0
        fi
    done < <(find_modules)

    return 1
}

list_modules() {
    log_info "Scanning for modules..."

    local found=0

    while IFS= read -r metadata_file; do
        found=1

        local module_dir
        module_dir="$(dirname "${metadata_file}")"

        python3 - "${metadata_file}" "${module_dir}" <<'PY'
import sys
import yaml

metadata_file = sys.argv[1]
module_dir = sys.argv[2]

with open(metadata_file, "r", encoding="utf-8") as file:
    metadata = yaml.safe_load(file) or {}

module_id = metadata.get("id", "unknown")
name = metadata.get("name", "unknown")
version = metadata.get("version", "unknown")
category = metadata.get("category", "unknown")

print(
    f"{module_id}\t"
    f"{name}\t"
    f"{version}\t"
    f"{category}\t"
    f"{module_dir}"
)
PY

    done < <(find_modules)

    if [[ "${found}" -eq 0 ]]; then
        log_info "No modules found."
    fi
}

get_module() {
    local requested_id="$1"

    local metadata_file

    if ! metadata_file="$(find_module_metadata "${requested_id}")"; then
        log_error "Module not found: ${requested_id}"
        echo "[SUGGESTION] Run:"
        echo "  ${0} list"
        echo "[SUGGESTION] Verify the module ID and try again."
        return 1
    fi

    log_info "Module found: ${requested_id}"
    echo

    cat "${metadata_file}"
}

validate_modules() {
    log_info "Validating modules..."
    echo

    local module_count=0
    local compliant_count=0
    local partial_count=0
    local noncompliant_count=0

    declare -A module_ids

    while IFS= read -r metadata_file; do
        module_count=$((module_count + 1))

        local module_dir
        module_dir="$(dirname "${metadata_file}")"

        local result
        result="$(
            python3 - "${metadata_file}" "${module_dir}" <<'PY'
import os
import re
import sys
import yaml

metadata_file = sys.argv[1]
module_dir = sys.argv[2]

required_fields = [
    "id",
    "name",
    "version",
    "category",
    "description",
    "status",
]

valid_categories = {
    "core",
    "monitoring",
    "discovery",
    "infrastructure",
    "logging",
    "optional",
}

valid_statuses = {
    "enabled",
    "disabled",
    "experimental",
    "deprecated",
}

errors = []
warnings = []

try:
    with open(metadata_file, "r", encoding="utf-8") as file:
        metadata = yaml.safe_load(file)
except Exception as exc:
    print("NON_COMPLIANT")
    print(f"ERROR|Unable to parse metadata.yml: {exc}")
    sys.exit(0)

if not isinstance(metadata, dict):
    print("NON_COMPLIANT")
    print("ERROR|metadata.yml must contain a YAML mapping.")
    sys.exit(0)

for field in required_fields:
    if field not in metadata or metadata[field] in (None, ""):
        errors.append(f"Missing required field: {field}")

spec_version = metadata.get("spec_version")

if spec_version in (None, ""):
    warnings.append("Missing recommended field: spec_version")
elif not re.fullmatch(r"[0-9]+\.[0-9]+", str(spec_version)):
    errors.append(
        f"Invalid spec_version: {spec_version}. "
        "Expected format: major.minor"
    )

module_id = metadata.get("id")

if module_id:
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", str(module_id)):
        errors.append(
            f"Invalid module ID: {module_id}. "
            "Use lowercase letters, numbers, and hyphens."
        )

category = metadata.get("category")

if category and category not in valid_categories:
    errors.append(
        f"Invalid category: {category}. "
        f"Supported categories: {', '.join(sorted(valid_categories))}"
    )

status = metadata.get("status")

if status and status not in valid_statuses:
    errors.append(
        f"Invalid status: {status}. "
        f"Supported statuses: {', '.join(sorted(valid_statuses))}"
    )

for field in [
    "compose",
    "healthcheck",
    "install",
    "update",
    "uninstall",
]:
    reference = metadata.get(field)

    if reference:
        referenced_path = os.path.join(module_dir, reference)

        if not os.path.isfile(referenced_path):
            errors.append(
                f"Referenced file does not exist: {reference}"
            )

if metadata.get("compose") and not os.path.isfile(
    os.path.join(module_dir, metadata["compose"])
):
    errors.append(
        f"Compose definition is missing: {metadata['compose']}"
    )

if metadata.get("healthcheck"):
    healthcheck_path = os.path.join(module_dir, metadata["healthcheck"])

    if os.path.isfile(healthcheck_path) and not os.access(
        healthcheck_path, os.X_OK
    ):
        warnings.append(
            f"Healthcheck is not executable: {metadata['healthcheck']}"
        )

if errors:
    print("NON_COMPLIANT")

    for error in errors:
        print(f"ERROR|{error}")

    for warning in warnings:
        print(f"WARNING|{warning}")

elif warnings:
    print("PARTIALLY_COMPLIANT")

    for warning in warnings:
        print(f"WARNING|{warning}")

else:
    print("COMPLIANT")
PY
        )"

        local status
        status="$(echo "${result}" | head -n 1)"

        local module_id
        module_id="$(
            python3 - "${metadata_file}" <<'PY'
import sys
import yaml

with open(sys.argv[1], "r", encoding="utf-8") as file:
    metadata = yaml.safe_load(file) or {}

print(metadata.get("id", "unknown"))
PY
        )"

        echo "Module: ${module_id}"

        if [[ "${status}" == "COMPLIANT" ]]; then
            echo "[OK] Module is compliant."
            compliant_count=$((compliant_count + 1))

        elif [[ "${status}" == "PARTIALLY_COMPLIANT" ]]; then
            echo "[WARNING] Module is partially compliant."
            partial_count=$((partial_count + 1))

        else
            echo "[ERROR] Module is non-compliant."
            noncompliant_count=$((noncompliant_count + 1))
        fi

        while IFS='|' read -r level message; do
            [[ -z "${level}" ]] && continue

            case "${level}" in
                ERROR)
                    echo "[ERROR] ${message}"
                    ;;
                WARNING)
                    echo "[WARNING] ${message}"
                    ;;
            esac
        done < <(echo "${result}" | tail -n +2)

        echo

    done < <(find_modules)

    if [[ "${module_count}" -eq 0 ]]; then
        log_info "No modules found."
        return 0
    fi

    echo "Validation Summary"
    echo "------------------"
    echo "Modules checked: ${module_count}"
    echo "Compliant: ${compliant_count}"
    echo "Partially compliant: ${partial_count}"
    echo "Non-compliant: ${noncompliant_count}"

    if [[ "${noncompliant_count}" -gt 0 ]]; then
        return 1
    fi
}

refresh_registry() {
    log_info "Registry refresh is not implemented yet."
}

case "${1:-}" in
    list)
        list_modules
        ;;

    get)
        if [[ -z "${2:-}" ]]; then
            log_error "Missing module ID."
            echo "[SUGGESTION] Usage:"
            echo "  ${0} get <module>"
            exit 1
        fi

        get_module "${2}"
        ;;

    validate)
        validate_modules
        ;;

    refresh)
        refresh_registry
        ;;

    *)
        usage
        exit 1
        ;;
esac
