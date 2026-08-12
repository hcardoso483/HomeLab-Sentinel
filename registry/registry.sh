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
    cat <<EOF
HomeLab Sentinel Registry

Usage:
  registry.sh list
  registry.sh get <module>
  registry.sh refresh
EOF
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

    refresh)
        refresh_registry
        ;;

    *)
        usage
        exit 1
        ;;
esac
