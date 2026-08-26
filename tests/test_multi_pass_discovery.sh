#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MULTI_PASS="${APP_ROOT}/core/discovery/multi_pass.py"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

pass() {
    echo "[PASS] $*"
}

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

[[ -x "${MULTI_PASS}" ]] ||
    fail "Multi-Pass engine not executable: ${MULTI_PASS}"

PROVIDER="${TMP_DIR}/provider.sh"
COUNTER="${TMP_DIR}/counter"

printf '0\n' > "${COUNTER}"

cat > "${PROVIDER}" <<'PROVIDER'
#!/usr/bin/env bash
set -Eeuo pipefail

counter_file="${TEST_COUNTER:?}"
count="$(cat "${counter_file}")"
count=$((count + 1))
printf '%s\n' "${count}" > "${counter_file}"

timestamp="2026-08-26T07:00:0${count}Z"

emit() {
    local ip="$1"
    local mac="$2"
    local hostname="$3"

    printf \
        '{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"%s","ip_addresses":["%s"],"mac_address":"%s","hostname":"%s"}\n' \
        "${timestamp}" \
        "${ip}" \
        "${mac}" \
        "${hostname}"
}

# Present in all three passes.
emit \
    "192.0.2.10" \
    "00:11:22:33:44:10" \
    "always-present"

# Present in passes 1 and 3.
if [[ "${count}" -eq 1 || "${count}" -eq 3 ]]; then
    emit \
        "192.0.2.20" \
        "00:11:22:33:44:20" \
        "two-of-three"
fi

# Present only in pass 2.
if [[ "${count}" -eq 2 ]]; then
    emit \
        "192.0.2.30" \
        "00:11:22:33:44:30" \
        "one-of-three"
fi
PROVIDER

chmod +x "${PROVIDER}"

echo "HomeLab Sentinel Multi-Pass Discovery regression"

echo
echo "=== THREE-PASS CONSOLIDATION ==="

set +e
OUTPUT="$(
    TEST_COUNTER="${COUNTER}" \
    "${MULTI_PASS}" \
        --provider "${PROVIDER}" \
        --target "192.0.2.0/24" \
        --passes 3 \
        --interval 0 \
        2>&1
)"
RESULT=$?
set -e

echo "${OUTPUT}"

[[ "${RESULT}" -eq 0 ]] ||
    fail "three-pass consolidation exit=${RESULT}"

[[ "$(cat "${COUNTER}")" -eq 3 ]] ||
    fail "provider was not executed exactly three times"

pass "provider executed exactly three normal passes"

python3 - "${OUTPUT}" <<'PY'
import json
import sys

lines = [
    line
    for line in sys.argv[1].splitlines()
    if line.startswith("{")
]

records = [json.loads(line) for line in lines]

by_mac = {
    record["mac_address"]: record
    for record in records
}

expected = {
    "00:11:22:33:44:10": 3,
    "00:11:22:33:44:20": 2,
    "00:11:22:33:44:30": 1,
}

if set(by_mac) != set(expected):
    raise SystemExit(
        f"unexpected consolidated MAC set: {sorted(by_mac)}"
    )

for mac, expected_count in expected.items():
    record = by_mac[mac]

    if record.get("passes_observed") != expected_count:
        raise SystemExit(
            f"{mac}: expected passes_observed={expected_count}, "
            f"got {record.get('passes_observed')}"
        )

    if record.get("passes_total") != 3:
        raise SystemExit(
            f"{mac}: expected passes_total=3, "
            f"got {record.get('passes_total')}"
        )

print("[PASS] 3/3 evidence preserved")
print("[PASS] 2/3 evidence preserved")
print("[PASS] 1/3 evidence retained")
PY

echo
echo "=== PROVIDER FAILURE IS NOT ABSENCE ==="

FAIL_PROVIDER="${TMP_DIR}/provider-fail.sh"
FAIL_COUNTER="${TMP_DIR}/fail-counter"

printf '0\n' > "${FAIL_COUNTER}"

cat > "${FAIL_PROVIDER}" <<'PROVIDER'
#!/usr/bin/env bash
set -Eeuo pipefail

counter_file="${TEST_COUNTER:?}"
count="$(cat "${counter_file}")"
count=$((count + 1))
printf '%s\n' "${count}" > "${counter_file}"

if [[ "${count}" -eq 2 ]]; then
    exit 42
fi

printf '%s\n' \
    '{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-26T07:10:00Z","ip_addresses":["192.0.2.40"],"mac_address":"00:11:22:33:44:40","hostname":"provider-test"}'
PROVIDER

chmod +x "${FAIL_PROVIDER}"

set +e
FAIL_OUTPUT="$(
    TEST_COUNTER="${FAIL_COUNTER}" \
    "${MULTI_PASS}" \
        --provider "${FAIL_PROVIDER}" \
        --target "192.0.2.0/24" \
        --passes 3 \
        --interval 0 \
        2>&1
)"
FAIL_RESULT=$?
set -e

echo "${FAIL_OUTPUT}"

[[ "${FAIL_RESULT}" -ne 0 ]] ||
    fail "provider execution failure was treated as successful absence"

pass "provider execution failure remains distinct from host absence"

[[ "$(cat "${FAIL_COUNTER}")" -eq 2 ]] ||
    fail "multi-pass engine continued after provider execution failure"

pass "failed cycle stops without inventing additional normal passes"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Multi-Pass Discovery regression PASSED"

echo
echo "=== EMPTY SUCCESSFUL PASS ==="

EMPTY_PROVIDER="${TMP_DIR}/provider-empty.sh"
EMPTY_COUNTER="${TMP_DIR}/empty-counter"

printf '0\n' > "${EMPTY_COUNTER}"

cat > "${EMPTY_PROVIDER}" <<'PROVIDER'
#!/usr/bin/env bash
set -Eeuo pipefail

counter_file="${TEST_COUNTER:?}"
count="$(cat "${counter_file}")"
count=$((count + 1))
printf '%s\n' "${count}" > "${counter_file}"

if [[ "${count}" -eq 2 ]]; then
    exit 0
fi

printf '%s\n' \
    '{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-26T07:20:00Z","ip_addresses":["192.0.2.50"],"mac_address":"00:11:22:33:44:50","hostname":"empty-pass-test"}'
PROVIDER

chmod +x "${EMPTY_PROVIDER}"

EMPTY_OUTPUT="$(
    TEST_COUNTER="${EMPTY_COUNTER}" \
    "${MULTI_PASS}" \
        --provider "${EMPTY_PROVIDER}" \
        --target "192.0.2.0/24" \
        --passes 3 \
        --interval 0 \
        2>&1
)"

echo "${EMPTY_OUTPUT}"

python3 - "${EMPTY_OUTPUT}" <<'PY'
import json
import sys

records = [
    json.loads(line)
    for line in sys.argv[1].splitlines()
    if line.startswith("{")
]

if len(records) != 1:
    raise SystemExit(
        f"expected 1 consolidated record, got {len(records)}"
    )

record = records[0]

if record["passes_observed"] != 2:
    raise SystemExit(
        f"expected passes_observed=2, got "
        f"{record['passes_observed']}"
    )

if record["observed_passes"] != [1, 3]:
    raise SystemExit(
        f"expected observed_passes [1, 3], got "
        f"{record['observed_passes']}"
    )
PY

pass "empty successful pass preserved as absence evidence"

echo
echo "=== DUPLICATE OUTPUT WITHIN ONE PASS ==="

DUP_PROVIDER="${TMP_DIR}/provider-duplicate.sh"

cat > "${DUP_PROVIDER}" <<'PROVIDER'
#!/usr/bin/env bash
set -Eeuo pipefail

record='{"schema_version":"1.0","provider":"test","discovery_method":"host-discovery","discovered_at":"2026-08-26T07:30:00Z","ip_addresses":["192.0.2.60"],"mac_address":"00:11:22:33:44:60","hostname":"duplicate-test"}'

printf '%s\n' "${record}"
printf '%s\n' "${record}"
PROVIDER

chmod +x "${DUP_PROVIDER}"

DUP_OUTPUT="$(
    "${MULTI_PASS}" \
        --provider "${DUP_PROVIDER}" \
        --target "192.0.2.0/24" \
        --passes 1 \
        --interval 0 \
        2>&1
)"

echo "${DUP_OUTPUT}"

python3 - "${DUP_OUTPUT}" <<'PY'
import json
import sys

records = [
    json.loads(line)
    for line in sys.argv[1].splitlines()
    if line.startswith("{")
]

if len(records) != 1:
    raise SystemExit(
        f"expected 1 consolidated record, got {len(records)}"
    )

record = records[0]

if record["passes_observed"] != 1:
    raise SystemExit(
        f"duplicate provider output inflated presence evidence: "
        f"{record['passes_observed']}"
    )
PY

pass "duplicate output within one pass does not inflate presence"

echo
echo "=== HARDENED RESULT ==="
echo "HomeLab Sentinel Multi-Pass Discovery edge cases PASSED"
