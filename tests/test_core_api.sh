#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="${APP_ROOT:-/opt/homelab-sentinel/app}"
API_HOST="${API_HOST:-127.0.0.1}"
API_PORT="${API_PORT:-18000}"
DATABASE="${DATABASE:-/srv/homelab-sentinel/sentinel/inventory.db}"

SERVER="${APP_ROOT}/api/server.py"
INVENTORY="${APP_ROOT}/core/inventory/inventory.py"
BASE_URL="http://${API_HOST}:${API_PORT}"

API_PID=""
TMP_DIR=""

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

pass() {
    echo "[PASS] $*"
}

cleanup() {
    local rc=$?

    if [[ -n "${API_PID}" ]] && kill -0 "${API_PID}" 2>/dev/null; then
        kill "${API_PID}" 2>/dev/null || true
        wait "${API_PID}" 2>/dev/null || true
    fi

    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
    fi

    exit "${rc}"
}
trap cleanup EXIT INT TERM

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

json_assert() {
    local file="$1"
    local expression="$2"
    local description="$3"

    python3 - "${file}" "${expression}" "${description}" <<'PY'
import json
import sys

path, expression, description = sys.argv[1:4]

with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

namespace = {"data": data}
if not eval(expression, {"__builtins__": {"isinstance": isinstance, "int": int, "list": list}}, namespace):
    raise SystemExit(f"[FAIL] {description}")
PY
}

http_request() {
    local method="$1"
    local url="$2"
    local body_file="$3"

    curl         --silent         --show-error         --output "${body_file}"         --write-out "%{http_code}"         --request "${method}"         "${url}"
}

echo "HomeLab Sentinel Core API regression test"
echo "App root : ${APP_ROOT}"
echo "Database : ${DATABASE}"
echo "API      : ${BASE_URL}"
echo

require_command python3
require_command curl

[[ -f "${SERVER}" ]] || fail "Core API server not found: ${SERVER}"
[[ -x "${SERVER}" ]] || fail "Core API server is not executable: ${SERVER}"
[[ -f "${INVENTORY}" ]] || fail "Inventory CLI not found: ${INVENTORY}"
[[ -x "${INVENTORY}" ]] || fail "Inventory CLI is not executable: ${INVENTORY}"
[[ -f "${DATABASE}" ]] || fail "Inventory database not found: ${DATABASE}"

python3 -m py_compile "${SERVER}" "${INVENTORY}"
pass "Python syntax"

TMP_DIR="$(mktemp -d)"
SERVER_OUT="${TMP_DIR}/server.out"
SERVER_ERR="${TMP_DIR}/server.err"

"${SERVER}"     --host "${API_HOST}"     --port "${API_PORT}"     --database "${DATABASE}"     >"${SERVER_OUT}" 2>"${SERVER_ERR}" &
API_PID=$!

for _ in $(seq 1 50); do
    if ! kill -0 "${API_PID}" 2>/dev/null; then
        echo "=== Core API stderr ===" >&2
        cat "${SERVER_ERR}" >&2 || true
        fail "Core API process exited before becoming ready"
    fi

    if curl --silent --fail "${BASE_URL}/api/v1/health" >/dev/null 2>&1; then
        break
    fi

    sleep 0.1
done

curl --silent --fail "${BASE_URL}/api/v1/health" >/dev/null 2>&1     || fail "Core API did not become ready"
pass "Core API started"

HEALTH="${TMP_DIR}/health.json"
STATUS="$(http_request GET "${BASE_URL}/api/v1/health" "${HEALTH}")"
[[ "${STATUS}" == "200" ]] || fail "Health endpoint returned HTTP ${STATUS}"
json_assert "${HEALTH}"     'data.get("status") == "ok" and isinstance(data.get("inventory_schema_version"), int) and data["inventory_schema_version"] >= 2'     "Health response contract"
pass "GET /api/v1/health"

LIST="${TMP_DIR}/inventory.json"
STATUS="$(http_request GET "${BASE_URL}/api/v1/inventory" "${LIST}")"
[[ "${STATUS}" == "200" ]] || fail "Inventory list returned HTTP ${STATUS}"
json_assert "${LIST}"     'isinstance(data.get("items"), list)'     "Inventory list response contract"

ENTITY_ID="$(
    python3 - "${LIST}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

items = data.get("items", [])
if not items:
    raise SystemExit(1)

entity_id = items[0].get("entity_id")
if not isinstance(entity_id, str) or not entity_id:
    raise SystemExit(1)

print(entity_id)
PY
)" || fail "Inventory contains no usable entity for entity/history tests"
pass "GET /api/v1/inventory"

SHOW="${TMP_DIR}/show.json"
STATUS="$(http_request GET "${BASE_URL}/api/v1/inventory/${ENTITY_ID}" "${SHOW}")"
[[ "${STATUS}" == "200" ]] || fail "Entity endpoint returned HTTP ${STATUS}"
python3 - "${SHOW}" "${ENTITY_ID}" <<'PY'
import json
import sys

path, expected = sys.argv[1:3]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

if data.get("entity_id") != expected:
    raise SystemExit("[FAIL] Entity response returned the wrong entity_id")
PY
pass "GET /api/v1/inventory/{entity_id}"

HISTORY="${TMP_DIR}/history.json"
STATUS="$(http_request GET "${BASE_URL}/api/v1/inventory/${ENTITY_ID}/history" "${HISTORY}")"
[[ "${STATUS}" == "200" ]] || fail "History endpoint returned HTTP ${STATUS}"
python3 - "${HISTORY}" "${ENTITY_ID}" <<'PY'
import json
import sys

path, expected = sys.argv[1:3]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

if data.get("entity_id") != expected:
    raise SystemExit("[FAIL] History response returned the wrong entity_id")
if not isinstance(data.get("items"), list):
    raise SystemExit("[FAIL] History response does not contain an items array")
PY
pass "GET /api/v1/inventory/{entity_id}/history"

UNRESOLVED="${TMP_DIR}/unresolved.json"
STATUS="$(http_request GET "${BASE_URL}/api/v1/inventory/unresolved" "${UNRESOLVED}")"
[[ "${STATUS}" == "200" ]] || fail "Unresolved endpoint returned HTTP ${STATUS}"
json_assert "${UNRESOLVED}"     'isinstance(data.get("items"), list)'     "Unresolved response contract"
pass "GET /api/v1/inventory/unresolved"

NOT_FOUND="${TMP_DIR}/not-found.json"
STATUS="$(http_request GET "${BASE_URL}/api/v1/inventory/dev-does-not-exist" "${NOT_FOUND}")"
[[ "${STATUS}" == "404" ]] || fail "Missing entity returned HTTP ${STATUS}, expected 404"
json_assert "${NOT_FOUND}"     'data.get("error", {}).get("code") == "entity_not_found"'     "Missing entity error contract"
pass "404 entity_not_found"

METHOD="${TMP_DIR}/method.json"
STATUS="$(http_request POST "${BASE_URL}/api/v1/health" "${METHOD}")"
[[ "${STATUS}" == "405" ]] || fail "POST returned HTTP ${STATUS}, expected 405"
json_assert "${METHOD}"     'data.get("error", {}).get("code") == "method_not_allowed"'     "Unsupported method error contract"
pass "405 method_not_allowed JSON"

UNKNOWN="${TMP_DIR}/unknown.json"
STATUS="$(http_request GET "${BASE_URL}/api/v1/does-not-exist" "${UNKNOWN}")"
[[ "${STATUS}" == "404" ]] || fail "Unknown resource returned HTTP ${STATUS}, expected 404"
json_assert "${UNKNOWN}"     'data.get("error", {}).get("code") == "not_found"'     "Unknown resource error contract"
pass "404 not_found"

echo
echo "All Core API regression tests passed."
