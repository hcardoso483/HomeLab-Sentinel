#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${APP_ROOT}/core/lib/common.sh"

SCOPE_CONFIG="${1:-${APP_ROOT}/config/sentinel/discovery-scopes.yml}"
SCOPE_HELPER="${APP_ROOT}/core/discovery/scopes.py"
RESOLVER="${APP_ROOT}/core/resolver/resolver.sh"
RECORD_VALIDATOR="${APP_ROOT}/core/discovery/validate_record.py"

for required_file in \
    "${SCOPE_CONFIG}" \
    "${SCOPE_HELPER}" \
    "${RESOLVER}" \
    "${RECORD_VALIDATOR}"
do
    [[ -f "${required_file}" ]] ||
        die "Required discovery component not found: ${required_file}"
done

PROVIDER="$("${RESOLVER}" provider-id discovery)" ||
    die "Unable to resolve discovery provider."

[[ -n "${PROVIDER}" ]] || die "Discovery provider resolved to an empty ID."

PROVIDER_DIR="$(require_module "${PROVIDER}")"
PROVIDER_DISCOVER="${PROVIDER_DIR}/scripts/discover.sh"

[[ -x "${PROVIDER_DISCOVER}" ]] ||
    die "Discovery provider entry point not found or not executable: ${PROVIDER_DISCOVER}"

log_info "Discovery provider: ${PROVIDER}" >&2

active_scopes="$("${SCOPE_HELPER}" active "${SCOPE_CONFIG}")" ||
    die "Unable to load active discovery scopes."

if [[ -z "${active_scopes}" ]]; then
    log_info "No active discovery scopes." >&2
    exit 0
fi

while IFS='|' read -r scope_id scope_type target scope_source; do
    [[ -n "${target}" ]] || continue

    log_info "Discovering scope: ${scope_id} (${target})" >&2

    provider_output="$("${PROVIDER_DISCOVER}" "${target}")" ||
        die "Discovery provider failed for scope: ${scope_id}"

    if [[ -z "${provider_output}" ]]; then
        log_info "Discovery completed with 0 observations: ${scope_id}" >&2
        continue
    fi

    printf "%s\n" "${provider_output}" |
        "${RECORD_VALIDATOR}" ||
        die "Discovery record validation failed for scope: ${scope_id}"
done <<< "${active_scopes}"
