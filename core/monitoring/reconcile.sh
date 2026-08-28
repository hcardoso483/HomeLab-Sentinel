#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="${APP_ROOT:-/opt/homelab-sentinel/app}"
RESOLVER="${RESOLVER:-${APP_ROOT}/core/resolver/resolver.sh}"
REGISTRY="${REGISTRY:-${APP_ROOT}/registry/registry.sh}"

CAPABILITY="${CAPABILITY:-monitoring}"
ENTRYPOINT_ROLE="${ENTRYPOINT_ROLE:-monitoring-target-reconciler}"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

[[ -x "${RESOLVER}" ]] ||
    fail "Provider Resolver unavailable: ${RESOLVER}"

[[ -x "${REGISTRY}" ]] ||
    fail "Registry unavailable: ${REGISTRY}"

provider="$(
    "${RESOLVER}" provider-id "${CAPABILITY}"
)" || fail "Unable to resolve ${CAPABILITY} provider"

[[ -n "${provider}" ]] ||
    fail "Provider Resolver returned no ${CAPABILITY} provider"

reconciler="$(
    "${REGISTRY}" entrypoint "${provider}" "${ENTRYPOINT_ROLE}"
)" || fail \
    "Monitoring provider ${provider} does not expose ${ENTRYPOINT_ROLE}"

[[ -n "${reconciler}" ]] ||
    fail \
    "Monitoring provider ${provider} returned no ${ENTRYPOINT_ROLE} entrypoint"

[[ -f "${reconciler}" ]] ||
    fail "Monitoring target reconciler not found: ${reconciler}"

[[ -x "${reconciler}" ]] ||
    fail "Monitoring target reconciler is not executable: ${reconciler}"

echo "[INFO] Monitoring provider: ${provider}"
echo "[INFO] Target reconciler  : ${reconciler}"

"${reconciler}"

echo "[PASS] Monitoring target reconciliation completed."
