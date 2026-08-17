#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REGISTRY="${APP_ROOT}/registry/registry.sh"

log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

usage() {
    cat <<EOF_USAGE
HomeLab Sentinel Provider Acquisition

Usage:
  acquisition.sh discover <capability>
  acquisition.sh source <provider>
  acquisition.sh acquire <capability> <provider>
EOF_USAGE
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        {
            log_error "Required command not found: $1"
            return 1
        }
}

provider_exists() {
    local capability="$1"
    local provider="$2"

    "${REGISTRY}" provider-ids "${capability}" |
        grep -Fxq "${provider}"
}

provider_metadata() {
    local provider="$1"

    "${REGISTRY}" info "${provider}"
}

provider_source() {
    local provider="$1"

    python3 - "${APP_ROOT}" "${provider}" <<'PY_SOURCE'
import sys
import yaml
from pathlib import Path

app_root = Path(sys.argv[1])
provider = sys.argv[2]

metadata_files = list(app_root.glob(f"compose/**/{provider}/metadata.yml"))

if not metadata_files:
    print(
        f"[ERROR] Metadata not found for provider: {provider}",
        file=sys.stderr,
    )
    sys.exit(1)

metadata_file = metadata_files[0]

try:
    with metadata_file.open("r", encoding="utf-8") as file:
        metadata = yaml.safe_load(file) or {}
except (OSError, yaml.YAMLError) as error:
    print(
        f"[ERROR] Unable to read provider metadata: {error}",
        file=sys.stderr,
    )
    sys.exit(1)

source = metadata.get("source")

if not isinstance(source, dict):
    print(
        "[ERROR] Provider has no valid acquisition source.",
        file=sys.stderr,
    )
    sys.exit(1)

source_type = source.get("type")
image = source.get("image")

if source_type != "docker":
    print(
        f"[ERROR] Unsupported acquisition source type: {source_type}",
        file=sys.stderr,
    )
    sys.exit(1)

if not image:
    print(
        "[ERROR] Docker acquisition source has no image.",
        file=sys.stderr,
    )
    sys.exit(1)

print(f"source_type={source_type}")
print(f"image={image}")
PY_SOURCE
}

image_exists() {
    local image="$1"

    docker image inspect "${image}" >/dev/null 2>&1
}

acquire_docker_image() {
    local provider="$1"
    local image="$2"

    if image_exists "${image}"; then
        echo
        log_info "Provider image is already available."
        echo "[DETAIL] Provider: ${provider}"
        echo "[DETAIL] Image: ${image}"
        echo "[DETAIL] Status: available"
        return 0
    fi

    echo
    log_info "Provider image is not available locally."
    echo "[DETAIL] Provider: ${provider}"
    echo "[DETAIL] Image: ${image}"
    echo

    read -r -p "Download ${image}? [Y/n] " confirmation

    case "${confirmation}" in
        ""|y|Y|yes|YES|Yes)
            ;;
        *)
            echo
            log_warn "Provider acquisition cancelled."
            echo "[SUGGESTION] Provider configuration was not changed."
            return 1
            ;;
    esac

    echo
    log_info "Downloading provider image..."
    echo "[DETAIL] Image: ${image}"
    echo

    if ! docker pull "${image}"; then
        echo
        log_error "Provider acquisition failed."
        echo "[DETAIL] Provider: ${provider}"
        echo "[DETAIL] Source type: docker"
        echo "[DETAIL] Image: ${image}"
        echo
        echo "[SUGGESTION] Verify Docker connectivity and try again."
        echo "[SUGGESTION] Your provider configuration was not changed."
        return 1
    fi

    echo

    if ! image_exists "${image}"; then
        log_error "Provider image could not be verified after acquisition."
        echo "[DETAIL] Provider: ${provider}"
        echo "[DETAIL] Image: ${image}"
        echo
        echo "[SUGGESTION] Verify the Docker image and try again."
        echo "[SUGGESTION] Your provider configuration was not changed."
        return 1
    fi

    log_info "Provider acquired successfully."
    echo "[DETAIL] Provider: ${provider}"
    echo "[DETAIL] Image: ${image}"
    echo "[DETAIL] Status: available"

    return 0
}

discover_providers() {
    local capability="$1"
    local providers

    providers="$("${REGISTRY}" provider-sources "${capability}" || true)"

    echo
    log_info "Providers available for acquisition."
    echo "[DETAIL] Capability: ${capability}"
    echo

    if [[ -z "${providers}" ]]; then
        echo "[INFO] No obtainable providers were found."
        echo "[SUGGESTION] Install or register a provider that supports: ${capability}"
        return 1
    fi

    local count=0
    local provider
    local source_type
    local image

    while IFS='|' read -r provider source_type image; do
        [[ -z "${provider}" ]] && continue

        count=$((count + 1))

        echo "  ${count}. ${provider}"
        echo "     Source: ${source_type}"
        echo "     Image:  ${image}"
        echo
    done <<< "${providers}"

    echo "[INFO] ${count} obtainable provider(s) found."
}

case "${1:-}" in

    discover)
        if [[ -z "${2:-}" ]]; then
            log_error "Missing capability."
            echo "[SUGGESTION] Usage:"
            echo "  ${0} discover <capability>"
            exit 1
        fi

        discover_providers "${2}"
        ;;

    source)
        if [[ -z "${2:-}" ]]; then
            log_error "Missing provider."
            echo "[SUGGESTION] Usage:"
            echo "  ${0} source <provider>"
            exit 1
        fi

        provider_source "${2}"
        ;;

    acquire)
        if [[ -z "${2:-}" || -z "${3:-}" ]]; then
            log_error "Missing capability or provider."
            echo "[SUGGESTION] Usage:"
            echo "  ${0} acquire <capability> <provider>"
            exit 1
        fi

        require_command docker

        capability="${2}"
        provider="${3}"

        log_info "Preparing provider acquisition..."
        echo
        echo "Capability: ${capability}"
        echo "Provider: ${provider}"

        if ! provider_exists "${capability}" "${provider}"; then
            log_error "Provider is not registered for this capability."
            echo "[DETAIL] Capability: ${capability}"
            echo "[DETAIL] Provider: ${provider}"
            exit 1
        fi

        echo
        echo "[INFO] Provider is registered."

        source_info="$(provider_source "${provider}")"

        source_type="$(
            printf '%s\n' "${source_info}" |
                sed -n 's/^source_type=//p'
        )"

        image="$(
            printf '%s\n' "${source_info}" |
                sed -n 's/^image=//p'
        )"

        if [[ "${source_type}" != "docker" ]]; then
            log_error "Unsupported acquisition source type."
            echo "[DETAIL] Provider: ${provider}"
            echo "[DETAIL] Source type: ${source_type}"
            exit 1
        fi

        if [[ -z "${image}" ]]; then
            log_error "Provider acquisition image is empty."
            echo "[DETAIL] Provider: ${provider}"
            exit 1
        fi

        acquire_docker_image "${provider}" "${image}"
        ;;

    *)
        usage
        exit 1
        ;;

esac
