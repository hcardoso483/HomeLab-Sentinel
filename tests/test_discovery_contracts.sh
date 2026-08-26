#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SCOPES="${APP_ROOT}/core/discovery/scopes.py"
VALIDATOR="${APP_ROOT}/core/discovery/validate_record.py"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

pass() {
    echo "[PASS] $*"
}

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

run_expect() {
    local name="$1"
    local expected="$2"
    shift 2

    local output
    local result

    echo
    echo "=== ${name} ==="

    set +e
    output="$("$@" 2>&1)"
    result=$?
    set -e

    echo "${output}"

    if [[ "${result}" -eq "${expected}" ]]; then
        pass "${name} exit=${result}"
    else
        fail "${name}: expected exit ${expected}, got ${result}"
    fi

    CASE_OUTPUT="${output}"
}

require_contains() {
    local expected="$1"
    local description="$2"

    if grep -Fq "${expected}" <<< "${CASE_OUTPUT}"; then
        pass "${description}"
    else
        fail "${description}: missing ${expected}"
    fi
}

printf '%s\n' \
'scopes:' \
'  - id: test-lan' \
'    target: 192.0.2.0/24' \
'    type: network' \
'    source: user' \
'    authorized: true' \
'    enabled: true' \
> "${TMP_DIR}/valid.yml"

run_expect \
    "VALID SCOPE CONFIGURATION" \
    0 \
    "${SCOPES}" validate "${TMP_DIR}/valid.yml"

require_contains \
    "Discovery scope validation successful. Scopes: 1" \
    "valid scope accepted"

printf '%s\n' \
'not_scopes: []' \
> "${TMP_DIR}/missing-scopes.yml"

run_expect \
    "MISSING SCOPES" \
    1 \
    "${SCOPES}" validate "${TMP_DIR}/missing-scopes.yml"

require_contains \
    "missing required top-level field: scopes" \
    "missing scopes rejected"

printf '%s\n' \
'scopes:' \
'  - id: disabled' \
'    target: 192.0.2.1' \
'    type: host' \
'    source: user' \
'    authorized: true' \
'    enabled: false' \
'  - id: unauthorized' \
'    target: 192.0.2.2' \
'    type: host' \
'    source: user' \
'    authorized: false' \
'    enabled: true' \
> "${TMP_DIR}/inactive.yml"

run_expect \
    "INACTIVE SCOPES" \
    0 \
    "${SCOPES}" active "${TMP_DIR}/inactive.yml"

[[ -z "${CASE_OUTPUT}" ]] ||
    fail "inactive scopes must not be emitted"

pass "disabled and unauthorized scopes excluded"

printf '%s\n' \
'scopes:' \
'  - id: duplicate' \
'    target: 192.0.2.1' \
'    type: host' \
'    source: user' \
'    authorized: true' \
'    enabled: true' \
'  - id: duplicate' \
'    target: 192.0.2.2' \
'    type: host' \
'    source: user' \
'    authorized: true' \
'    enabled: true' \
> "${TMP_DIR}/duplicate.yml"

run_expect \
    "DUPLICATE SCOPE ID" \
    1 \
    "${SCOPES}" validate "${TMP_DIR}/duplicate.yml"

require_contains \
    "duplicate scope id: duplicate" \
    "duplicate scope ID rejected"

printf '%s\n' \
'scopes:' \
'  - id: bad-target' \
'    target: 192.0.2.999' \
'    type: host' \
'    source: user' \
'    authorized: true' \
'    enabled: true' \
> "${TMP_DIR}/bad-target.yml"

run_expect \
    "INVALID SCOPE TARGET" \
    1 \
    "${SCOPES}" validate "${TMP_DIR}/bad-target.yml"

require_contains \
    "invalid target" \
    "invalid scope target rejected"

VALID_RECORD='{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-23T18:00:00Z","ip_addresses":["192.0.2.10"],"mac_address":"02:00:00:00:00:01","hostname":"test-host"}'

run_expect \
    "VALID DISCOVERY RECORD" \
    0 \
    bash -c \
    'printf "%s\n" "$1" | "$2"' \
    _ "${VALID_RECORD}" "${VALIDATOR}"

require_contains \
    '"schema_version":"1.0"' \
    "valid record canonicalized"

run_expect \
    "MALFORMED JSON" \
    1 \
    bash -c \
    'printf "%s\n" "{bad-json" | "$1"' \
    _ "${VALIDATOR}"

require_contains \
    "invalid JSON" \
    "malformed JSON rejected"

run_expect \
    "MISSING RECORD FIELD" \
    1 \
    bash -c \
    'printf "%s\n" "$1" | "$2"' \
    _ \
    '{"schema_version":"1.0","provider":"test"}' \
    "${VALIDATOR}"

require_contains \
    "missing required field(s)" \
    "missing record fields rejected"

run_expect \
    "UNSUPPORTED RECORD SCHEMA" \
    1 \
    bash -c \
    'printf "%s\n" "$1" | "$2"' \
    _ \
    '{"schema_version":"2.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-23T18:00:00Z","ip_addresses":["192.0.2.10"],"mac_address":null,"hostname":null}' \
    "${VALIDATOR}"

require_contains \
    "unsupported schema_version: 2.0" \
    "unsupported record schema rejected"

run_expect \
    "INVALID RECORD IP" \
    1 \
    bash -c \
    'printf "%s\n" "$1" | "$2"' \
    _ \
    '{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-23T18:00:00Z","ip_addresses":["192.0.2.999"],"mac_address":null,"hostname":null}' \
    "${VALIDATOR}"

require_contains \
    "invalid IP address: 192.0.2.999" \
    "invalid record IP rejected"

run_expect \
    "DUPLICATE RECORD IPS" \
    1 \
    bash -c \
    'printf "%s\n" "$1" | "$2"' \
    _ \
    '{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-23T18:00:00Z","ip_addresses":["192.0.2.10","192.0.2.10"],"mac_address":null,"hostname":null}' \
    "${VALIDATOR}"

require_contains \
    "ip_addresses must contain unique values" \
    "duplicate record IPs rejected"

run_expect \
    "INVALID RECORD MAC" \
    1 \
    bash -c \
    'printf "%s\n" "$1" | "$2"' \
    _ \
    '{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-23T18:00:00Z","ip_addresses":["192.0.2.10"],"mac_address":"02:00:00:00:00:zz","hostname":null}' \
    "${VALIDATOR}"

require_contains \
    "mac_address must be null or uppercase colon-separated MAC" \
    "invalid record MAC rejected"

run_expect \
    "TIMESTAMP WITHOUT TIMEZONE" \
    1 \
    bash -c \
    'printf "%s\n" "$1" | "$2"' \
    _ \
    '{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-23T18:00:00","ip_addresses":["192.0.2.10"],"mac_address":null,"hostname":null}' \
    "${VALIDATOR}"

require_contains \
    "discovered_at must be an ISO 8601 timestamp with timezone" \
    "timezone-less timestamp rejected"

run_expect \
    "EMPTY RECORD STREAM" \
    1 \
    bash -c \
    'printf "\n" | "$1"' \
    _ "${VALIDATOR}"

require_contains \
    "No discovery records were provided" \
    "empty discovery stream rejected"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Discovery contract regression PASSED"

echo
echo "=== MULTI-PASS RECORD CONTRACT ==="

MULTI_PASS_VALID='{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-26T08:00:00Z","ip_addresses":["192.0.2.50"],"mac_address":"02:00:00:00:00:50","hostname":"multi-pass-test","passes_observed":2,"passes_total":3,"observed_passes":[1,3]}'

if ! printf '%s\n' "${MULTI_PASS_VALID}" \
    | "${VALIDATOR}" >/dev/null; then
    fail "valid Multi-Pass observation rejected"
fi

pass "valid Multi-Pass observation accepted"

LEGACY_VALID='{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-26T08:00:00Z","ip_addresses":["192.0.2.51"],"mac_address":null,"hostname":null}'

if ! printf '%s\n' "${LEGACY_VALID}" \
    | "${VALIDATOR}" >/dev/null; then
    fail "legacy schema 1.0 observation rejected"
fi

pass "legacy schema 1.0 observation remains valid"

PARTIAL_MULTI_PASS='{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-26T08:00:00Z","ip_addresses":["192.0.2.52"],"mac_address":null,"hostname":null,"passes_observed":2,"passes_total":3}'

if printf '%s\n' "${PARTIAL_MULTI_PASS}" \
    | "${VALIDATOR}" >/dev/null 2>&1; then
    fail "partial Multi-Pass evidence accepted"
fi

pass "partial Multi-Pass evidence rejected"

BAD_COUNT='{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-26T08:00:00Z","ip_addresses":["192.0.2.53"],"mac_address":null,"hostname":null,"passes_observed":4,"passes_total":3,"observed_passes":[1,2,3]}'

if printf '%s\n' "${BAD_COUNT}" \
    | "${VALIDATOR}" >/dev/null 2>&1; then
    fail "passes_observed greater than passes_total accepted"
fi

pass "impossible Multi-Pass count rejected"

BAD_DUPLICATE='{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-26T08:00:00Z","ip_addresses":["192.0.2.54"],"mac_address":null,"hostname":null,"passes_observed":2,"passes_total":3,"observed_passes":[1,1]}'

if printf '%s\n' "${BAD_DUPLICATE}" \
    | "${VALIDATOR}" >/dev/null 2>&1; then
    fail "duplicate observed pass numbers accepted"
fi

pass "duplicate observed pass numbers rejected"

BAD_RANGE='{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-26T08:00:00Z","ip_addresses":["192.0.2.55"],"mac_address":null,"hostname":null,"passes_observed":2,"passes_total":3,"observed_passes":[1,4]}'

if printf '%s\n' "${BAD_RANGE}" \
    | "${VALIDATOR}" >/dev/null 2>&1; then
    fail "out-of-range observed pass accepted"
fi

pass "out-of-range observed pass rejected"

BAD_LENGTH='{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-26T08:00:00Z","ip_addresses":["192.0.2.56"],"mac_address":null,"hostname":null,"passes_observed":2,"passes_total":3,"observed_passes":[1]}'

if printf '%s\n' "${BAD_LENGTH}" \
    | "${VALIDATOR}" >/dev/null 2>&1; then
    fail "inconsistent Multi-Pass evidence length accepted"
fi

pass "Multi-Pass evidence count consistency enforced"

echo
echo "=== MULTI-PASS CONTRACT RESULT ==="
echo "HomeLab Sentinel Multi-Pass record contract PASSED"
