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
  registry.sh refresh
EOF
}

find_modules() {
    find "${MODULE_ROOT}" \
        -type f \
        -name "metadata.yml" \
        -print
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
    metadata = yaml.safe_load(file)

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

case "${1:-}" in
    list)
        list_modules
        ;;

    refresh)
        log_info "Registry refresh is not implemented yet."
        ;;

    *)
        usage
        exit 1
        ;;
esac
