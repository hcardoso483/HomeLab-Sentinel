#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="${APP_ROOT}/compose/discovery/nmap/scripts/discover-services.sh"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

[[ -x "${PROVIDER}" ]] ||
    fail "Nmap Service Discovery provider missing or not executable"

TMP_ROOT="$(mktemp -d /tmp/hls-nmap-budget-test.XXXXXX)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

BIN="${TMP_ROOT}/bin"
mkdir -p "${BIN}"

cat > "${BIN}/nmap" <<'SH'
#!/usr/bin/env bash
cat <<'XML'
<?xml version="1.0"?>
<nmaprun>
  <host timedout="true"/>
</nmaprun>
XML
exit 0
SH

chmod +x "${BIN}/nmap"

STDOUT_FILE="${TMP_ROOT}/stdout"
STDERR_FILE="${TMP_ROOT}/stderr"

set +e
PATH="${BIN}:${PATH}" \
"${PROVIDER}" \
    --entity-id dev-budget-fixture \
    --address 192.0.2.111 \
    --scan-budget-seconds 1 \
    > "${STDOUT_FILE}" \
    2> "${STDERR_FILE}"
rc=$?
set -e

[[ "${rc}" -eq 75 ]] ||
    fail "Stage 1 bounded exhaustion returned ${rc}, expected 75"

pass "Stage 1 bounded exhaustion returns retryable exit 75"

[[ ! -s "${STDOUT_FILE}" ]] ||
    fail "Stage 1 bounded exhaustion emitted partial endpoint evidence"

pass "Stage 1 bounded exhaustion emits no endpoint evidence"

grep -qi "exhausted the attempt budget" "${STDERR_FILE}" ||
    fail "Stage 1 bounded exhaustion did not report the reason"

pass "Stage 1 bounded exhaustion reports explicit budget exhaustion"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Nmap Service Discovery budget regression PASSED"
