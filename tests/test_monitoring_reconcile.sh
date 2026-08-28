#!/usr/bin/env bash

set -Eeuo pipefail

APP_ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

SUBJECT="${APP_ROOT}/core/monitoring/reconcile.sh"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

[[ -x "${SUBJECT}" ]] ||
    fail "Monitoring reconciliation runtime is not executable"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

FAKE_RESOLVER="${TMP_ROOT}/resolver.sh"
FAKE_REGISTRY="${TMP_ROOT}/registry.sh"
FAKE_RECONCILER="${TMP_ROOT}/reconciler.sh"
MARKER="${TMP_ROOT}/reconciled"

cat >"${FAKE_RESOLVER}" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${1:-}" == "provider-id" ]] || exit 10
[[ "${2:-}" == "monitoring" ]] || exit 11

printf '%s\n' "fake-provider"
SCRIPT

cat >"${FAKE_RECONCILER}" <<SCRIPT
#!/usr/bin/env bash
set -Eeuo pipefail

touch "${MARKER}"
echo "[PASS] Fake provider reconciliation complete."
SCRIPT

cat >"${FAKE_REGISTRY}" <<SCRIPT
#!/usr/bin/env bash
set -Eeuo pipefail

[[ "\${1:-}" == "entrypoint" ]] || exit 20
[[ "\${2:-}" == "fake-provider" ]] || exit 21
[[ "\${3:-}" == "monitoring-target-reconciler" ]] || exit 22

printf '%s\n' "${FAKE_RECONCILER}"
SCRIPT

chmod +x \
    "${FAKE_RESOLVER}" \
    "${FAKE_REGISTRY}" \
    "${FAKE_RECONCILER}"

OUTPUT="$(
    RESOLVER="${FAKE_RESOLVER}" \
    REGISTRY="${FAKE_REGISTRY}" \
    "${SUBJECT}"
)" || fail "Provider-neutral reconciliation failed"

[[ -f "${MARKER}" ]] ||
    fail "Resolved provider reconciler was not executed"

grep -Fq "Monitoring provider: fake-provider" <<<"${OUTPUT}" ||
    fail "Resolved provider was not reported"

grep -Fq "Monitoring target reconciliation completed." <<<"${OUTPUT}" ||
    fail "Successful reconciliation was not reported"

pass "Provider Resolver selected the Monitoring provider"
pass "Registry resolved monitoring-target-reconciler"
pass "Provider-owned reconciler was executed"
pass "Monitoring reconciliation boundary is provider-neutral"
