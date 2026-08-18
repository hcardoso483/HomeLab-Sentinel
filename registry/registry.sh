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
  registry.sh info <module>
  registry.sh providers <capability>
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

info_module() {
    local requested_id="$1"
    local metadata_file

    if ! metadata_file="$(find_module_metadata "${requested_id}")"; then
        log_error "Module not found: ${requested_id}"
        echo "[SUGGESTION] Run:"
        echo "  ${0} list"
        echo "[SUGGESTION] Verify the module ID and try again."
        return 1
    fi

    local module_dir
    module_dir="$(dirname "${metadata_file}")"

    python3 - "${metadata_file}" "${module_dir}" <<'PY_INFO'
import sys
import yaml

metadata_file = sys.argv[1]
module_dir = sys.argv[2]

with open(metadata_file, "r", encoding="utf-8") as file:
    metadata = yaml.safe_load(file) or {}

def value(field, default=None):
    result = metadata.get(field)
    if result in (None, ""):
        return default
    return result

def print_field(label, field):
    result = value(field)
    if result is not None:
        print(f"{label:<15} {result}")

print("Module Information")
print("------------------")
print_field("ID:", "id")
print_field("Name:", "name")
print_field("Display Name:", "display_name")
print_field("Version:", "version")
print_field("Spec Version:", "spec_version")
print_field("Category:", "category")
print_field("Status:", "status")
print()

description = value("description")
if description is not None:
    print("Description:")
    print(f"  {description}")
    print()

for field, title in [
    ("author", "Author"),
    ("license", "License"),
    ("homepage", "Homepage"),
    ("documentation", "Documentation"),
    ("compose", "Compose"),
    ("healthcheck", "Healthcheck"),
]:
    result = value(field)
    if result is not None:
        print(f"{title}:")
        print(f"  {result}")
        print()

for field, title in [
    ("dependencies", "Dependencies"),
    ("capabilities", "Capabilities"),
    ("ports", "Ports"),
    ("volumes", "Volumes"),
    ("tags", "Tags"),
]:
    items = value(field)
    if not items:
        continue

    print(f"{title}:")

    if isinstance(items, list):
        for item in items:
            print(f"  - {item}")
    elif isinstance(items, dict):
        for key, item in items.items():
            print(f"  - {key}: {item}")
    else:
        print(f"  - {items}")

    print()

print("Location:")
print(f"  {module_dir}")
PY_INFO
}


providers_module() {
    local requested_capability="$1"

    log_info "Searching for providers..."
    echo
    echo "Capability: ${requested_capability}"
    echo
    echo "Providers:"

    local found=0

    while IFS= read -r metadata_file; do
        local result

        result="$(
            python3 - "${metadata_file}" "${requested_capability}" <<'PY_PROVIDER'
import sys
import yaml

metadata_file = sys.argv[1]
requested_capability = sys.argv[2]

with open(metadata_file, "r", encoding="utf-8") as file:
    metadata = yaml.safe_load(file) or {}

capabilities = metadata.get("capabilities", {})

if isinstance(capabilities, list):
    capability_list = capabilities
elif isinstance(capabilities, dict):
    capability_list = capabilities.get("provides", [])
else:
    capability_list = []

if requested_capability in capability_list:
    module_id = metadata.get("id", "unknown")
    name = metadata.get("name", "unknown")
    print(f"  - {module_id}")
    print(f"    Name: {name}")
PY_PROVIDER
        )"

        if [[ -n "${result}" ]]; then
            echo "${result}"
            found=1
        fi

    done < <(find_modules)

    echo

    if [[ "${found}" -eq 0 ]]; then
        log_error "No providers found for capability: ${requested_capability}"
        echo "[SUGGESTION] Install a module that provides this capability."
        return 1
    fi
}


provider_ids() {
    local requested_capability="$1"

    while IFS= read -r metadata_file; do
        python3 - "${metadata_file}" "${requested_capability}" <<'PY_PROVIDER_IDS'
import sys
import yaml

metadata_file = sys.argv[1]
requested_capability = sys.argv[2]

with open(metadata_file, "r", encoding="utf-8") as file:
    metadata = yaml.safe_load(file) or {}

capabilities = metadata.get("capabilities", {})

if isinstance(capabilities, list):
    capability_list = capabilities
elif isinstance(capabilities, dict):
    capability_list = capabilities.get("provides", [])
else:
    capability_list = []

if requested_capability in capability_list:
    module_id = metadata.get("id")

    if module_id:
        print(module_id)
PY_PROVIDER_IDS
    done < <(find_modules)
}

provider_sources() {
    local requested_capability="$1"

    while IFS= read -r metadata_file; do
        python3 - "${metadata_file}" "${requested_capability}" <<'PY_PROVIDER_SOURCES'
import sys
import yaml

metadata_file = sys.argv[1]
requested_capability = sys.argv[2]

try:
    with open(metadata_file, "r", encoding="utf-8") as file:
        metadata = yaml.safe_load(file) or {}
except (OSError, yaml.YAMLError):
    sys.exit(0)

capabilities = metadata.get("capabilities", {})

if isinstance(capabilities, list):
    capability_list = capabilities
elif isinstance(capabilities, dict):
    capability_list = capabilities.get("provides", [])
else:
    capability_list = []

if requested_capability not in capability_list:
    sys.exit(0)

provider = metadata.get("id")
source = metadata.get("source")

if not provider or not isinstance(source, dict):
    sys.exit(0)

source_type = source.get("type")
image = source.get("image")

if source_type == "docker" and image:
    print(f"{provider}|{source_type}|{image}")
PY_PROVIDER_SOURCES
    done < <(find_modules)
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

dependencies = metadata.get("dependencies")

if dependencies is not None:
    if isinstance(dependencies, list):
        # Legacy Specification 1.0 / 1.1 dependency format.
        for dependency in dependencies:
            if not isinstance(dependency, str) or not dependency:
                errors.append(
                    f"Invalid dependency: {dependency}. "
                    "Legacy dependencies must be non-empty strings."
                )

    elif isinstance(dependencies, dict):
        # Specification 1.2 structured dependency format.
        if spec_version in (None, ""):
            errors.append(
                "Structured dependencies require spec_version 1.2 or newer."
            )
        elif re.fullmatch(r"[0-9]+\.[0-9]+", str(spec_version)):
            major, minor = map(int, str(spec_version).split("."))

            if (major, minor) < (1, 2):
                errors.append(
                    "Structured dependencies require spec_version 1.2 or newer."
                )

        allowed_dependency_keys = {"platform", "host"}

        for key in dependencies:
            if key not in allowed_dependency_keys:
                errors.append(
                    f"Unsupported dependency section: {key}"
                )

        platform_dependencies = dependencies.get("platform", [])

        if not isinstance(platform_dependencies, list):
            errors.append(
                "Invalid dependencies.platform: expected a list."
            )
        else:
            for dependency in platform_dependencies:
                if not isinstance(dependency, str) or not dependency:
                    errors.append(
                        f"Invalid platform dependency: {dependency}. "
                        "Platform dependencies must be non-empty strings."
                    )

        host_dependencies = dependencies.get("host", [])

        if not isinstance(host_dependencies, list):
            errors.append(
                "Invalid dependencies.host: expected a list."
            )
        else:
            for index, dependency in enumerate(host_dependencies, start=1):
                if not isinstance(dependency, dict):
                    errors.append(
                        f"Invalid host dependency #{index}: expected a mapping."
                    )
                    continue

                command = dependency.get("command")

                if not isinstance(command, str) or not command:
                    errors.append(
                        f"Invalid host dependency #{index}: "
                        "missing non-empty command."
                    )

                packages = dependency.get("packages")

                if packages is not None:
                    if not isinstance(packages, dict):
                        errors.append(
                            f"Invalid host dependency #{index}: "
                            "packages must be a mapping."
                        )
                    else:
                        for manager, package in packages.items():
                            if not isinstance(manager, str) or not manager:
                                errors.append(
                                    f"Invalid host dependency #{index}: "
                                    "package manager name must be a non-empty string."
                                )

                            if not isinstance(package, str) or not package:
                                errors.append(
                                    f"Invalid host dependency #{index}: "
                                    f"package for {manager} must be a non-empty string."
                                )

                required = dependency.get("required", True)

                if not isinstance(required, bool):
                    errors.append(
                        f"Invalid host dependency #{index}: "
                        "required must be true or false."
                    )

    else:
        errors.append(
            "Invalid dependencies: expected a list or mapping."
        )


capabilities = metadata.get("capabilities")

if capabilities is not None:
    if isinstance(capabilities, list):
        # Legacy Specification 1.0 capability format.
        capability_list = capabilities

    elif isinstance(capabilities, dict):
        # Specification 1.1 structured capability format.
        if "provides" not in capabilities:
            errors.append(
                "Invalid capabilities: missing required 'provides' field."
            )
            capability_list = []
        else:
            capability_list = capabilities["provides"]

            if not isinstance(capability_list, list):
                errors.append(
                    "Invalid capabilities.provides: expected a list."
                )
                capability_list = []

    else:
        errors.append(
            "Invalid capabilities: expected a list or mapping."
        )
        capability_list = []

    for capability in capability_list:
        if not isinstance(capability, str) or not capability:
            errors.append(
                f"Invalid capability: {capability}. "
                "Capabilities must be non-empty strings."
            )
        elif not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", capability):
            errors.append(
                f"Invalid capability: {capability}. "
                "Use lowercase letters, numbers, and hyphens."
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

    info)
        if [[ -z "${2:-}" ]]; then
            log_error "Missing module ID."
            echo "[SUGGESTION] Usage:"
            echo "  ${0} info <module>"
            exit 1
        fi

        info_module "${2}"
        ;;

    providers)
        if [[ -z "${2:-}" ]]; then
            log_error "Missing capability."
            echo "[SUGGESTION] Usage:"
            echo "  ${0} providers <capability>"
            exit 1
        fi

        providers_module "${2}"
        ;;

    provider-ids)
        if [[ -z "${2:-}" ]]; then
            log_error "Missing capability."
            echo "[SUGGESTION] Usage:"
            echo "  ${0} provider-ids <capability>"
            exit 1
        fi

        provider_ids "${2}"
        ;;

    provider-sources)
        if [[ -z "${2:-}" ]]; then
            log_error "Missing capability."
            echo "[SUGGESTION] Usage:"
            echo "  ${0} provider-sources <capability>"
            exit 1
        fi

        provider_sources "${2}"
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
