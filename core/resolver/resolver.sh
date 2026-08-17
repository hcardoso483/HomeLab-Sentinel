#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REGISTRY="${APP_ROOT}/registry/registry.sh"
PROVIDER_CONFIG="${APP_ROOT}/config/sentinel/providers.yml"
DEFAULT_CONFIG="${APP_ROOT}/config/sentinel/defaults.yml"

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
HomeLab Sentinel Provider Resolver

Usage:
  resolver.sh resolve <capability>
EOF_USAGE
}

require_configuration() {
    if [[ ! -f "${PROVIDER_CONFIG}" ]]; then
        log_warn "Provider configuration not found."
        echo "[DETAIL] ${PROVIDER_CONFIG}"
        echo "[INFO] Installation defaults may be used."
    fi

    if [[ ! -f "${DEFAULT_CONFIG}" ]]; then
        log_error "Default provider configuration not found."
        echo "[DETAIL] ${DEFAULT_CONFIG}"
        echo
        echo "[SUGGESTION] Create the default provider configuration."
        return 1
    fi
}

configured_provider() {
    local capability="$1"

    if [[ ! -f "${PROVIDER_CONFIG}" ]]; then
        return 0
    fi

    python3 - "${PROVIDER_CONFIG}" "${capability}" <<'PY_CONFIG'
import sys
import yaml

config_file = sys.argv[1]
capability = sys.argv[2]

try:
    with open(config_file, "r", encoding="utf-8") as file:
        config = yaml.safe_load(file) or {}

    providers = config.get("providers", {})

    if not isinstance(providers, dict):
        print(
            "[ERROR] Invalid provider configuration: "
            "'providers' must be a mapping.",
            file=sys.stderr,
        )
        sys.exit(2)

    provider = providers.get(capability)

    if provider is not None:
        print(provider)

except yaml.YAMLError as error:
    print(
        f"[ERROR] Invalid provider configuration: {error}",
        file=sys.stderr,
    )
    sys.exit(2)

except OSError as error:
    print(
        f"[ERROR] Unable to read provider configuration: {error}",
        file=sys.stderr,
    )
    sys.exit(2)
PY_CONFIG
}

provider_exists() {
    local capability="$1"
    local provider="$2"

    "${REGISTRY}" provider-ids "${capability}" |
        grep -Fxq "${provider}"
}

available_providers() {
    local capability="$1"

    "${REGISTRY}" provider-ids "${capability}"
}

installation_recommendation() {
    local capability="$1"

    if [[ ! -f "${DEFAULT_CONFIG}" ]]; then
        return 1
    fi

    python3 - "${DEFAULT_CONFIG}" "${capability}" <<'PY_DEFAULT'
import sys
import yaml

config_file = sys.argv[1]
capability = sys.argv[2]

try:
    with open(config_file, "r", encoding="utf-8") as file:
        config = yaml.safe_load(file) or {}

    defaults = config.get("default_providers", {})

    if not isinstance(defaults, dict):
        print(
            "[ERROR] Invalid default provider configuration: "
            "'default_providers' must be a mapping.",
            file=sys.stderr,
        )
        sys.exit(2)

    provider = defaults.get(capability)

    if provider is not None:
        print(provider)

except yaml.YAMLError as error:
    print(
        f"[ERROR] Invalid default provider configuration: {error}",
        file=sys.stderr,
    )
    sys.exit(2)

except OSError as error:
    print(
        f"[ERROR] Unable to read default provider configuration: {error}",
        file=sys.stderr,
    )
    sys.exit(2)
PY_DEFAULT
}

resolve_provider() {
    local capability="$1"

    log_info "Resolving provider..."
    echo
    echo "Capability: ${capability}"
    echo

    require_configuration || return 1

    local provider
    provider="$(configured_provider "${capability}")" || {
        return 1
    }

    if [[ -n "${provider}" ]]; then

        if provider_exists "${capability}" "${provider}"; then
            echo "Selected provider: ${provider}"
            echo "Source: user configuration"
            echo "Status: valid"
            return 0
        fi

        log_error "Configured provider is unavailable."
        echo "[DETAIL] Capability: ${capability}"
        echo "[DETAIL] Requested provider: ${provider}"
        echo
        echo "[SUGGESTION] Available providers:"

        local available
        available="$(available_providers "${capability}" || true)"

        if [[ -n "${available}" ]]; then
            while IFS= read -r candidate; do
                echo "  - ${candidate}"
            done <<< "${available}"
        else
            echo "  - none"
        fi

        local recommendation
        recommendation="$(installation_recommendation "${capability}" || true)"

        if [[ -n "${recommendation}" ]]; then
            echo
            echo "[SUGGESTION] Recommended provider: ${recommendation}"
        fi

        echo "[SUGGESTION] Your provider configuration was not changed."
        echo "[SUGGESTION] Installation cannot continue until a valid provider is selected."

        return 1
    fi

    local recommendation
    recommendation="$(installation_recommendation "${capability}" || true)"

    if [[ -n "${recommendation}" ]] &&
       provider_exists "${capability}" "${recommendation}"; then
        echo "Selected provider: ${recommendation}"
        echo "Source: installation default"
        echo "Status: valid"
        return 0
    fi

    log_error "No valid provider is available."
    echo "[DETAIL] Capability: ${capability}"

    local available
    available="$(available_providers "${capability}" || true)"

    echo
    echo "[SUGGESTION] Available providers:"

    if [[ -n "${available}" ]]; then
        while IFS= read -r candidate; do
            echo "  - ${candidate}"
        done <<< "${available}"
    else
        echo "  - none"
        echo
        echo "[SUGGESTION] Install a provider that supports: ${capability}"
    fi

    if [[ -n "${recommendation}" ]]; then
        echo "[SUGGESTION] Recommended provider: ${recommendation}"
    fi

    echo "[SUGGESTION] Installation cannot continue until a provider is available."

    return 1
}

case "${1:-}" in
    resolve)
        if [[ -z "${2:-}" ]]; then
            log_error "Missing capability."
            echo "[SUGGESTION] Usage:"
            echo "  ${0} resolve <capability>"
            exit 1
        fi

        resolve_provider "${2}"
        ;;

    *)
        usage
        exit 1
        ;;
esac
