#!/usr/bin/env bash
set -Eeuo pipefail
APP_ROOT="${APP_ROOT:-/opt/homelab-sentinel/app}"
IDENTITY="${APP_ROOT}/core/identity/identity.py"
TMP_ROOT="$(mktemp -d /tmp/hls-persistent-identity-test.XXXXXX)"
DB="${TMP_ROOT}/identity.db"
trap 'rm -rf "${TMP_ROOT}"' EXIT
fail(){ echo "[FAIL] $*" >&2; exit 1; }
pass(){ echo "[PASS] $*"; }
A=dev-11111111111111111111111111111111
B=dev-22222222222222222222222222222222
G=00:11:22:33:44:55
L=02:AA:BB:CC:DD:EE
T1=2026-08-25T18:00:00Z
T2=2026-08-25T19:00:00Z

echo 'HomeLab Sentinel Persistent Identity regression test'; echo
"${IDENTITY}" --database "${DB}" init >/dev/null
[[ -f "${DB}" ]] || fail 'database not created'
pass 'Persistent Identity database initialized'

V="$(python3 -c 'import sqlite3,sys;c=sqlite3.connect(sys.argv[1]);print(c.execute("PRAGMA user_version").fetchone()[0]);c.close()' "${DB}")"
[[ "${V}" == 1 ]] || fail "schema=${V}"
pass 'Persistent Identity schema version 1'

"${IDENTITY}" --database "${DB}" register --entity-id "${A}" --mac "${G}" --seen-at "${T1}" >/dev/null
pass 'global MAC identity registered'
[[ "$("${IDENTITY}" --database "${DB}" lookup --mac "${G}")" == "${A}" ]] || fail 'global lookup mismatch'
pass 'global MAC resolves canonical entity_id'

"${IDENTITY}" --database "${DB}" register --entity-id "${A}" --mac "${G}" --seen-at "${T2}" >/dev/null
LAST="$("${IDENTITY}" --database "${DB}" lookup --mac "${G}" --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["last_confirmed"])')"
[[ "${LAST}" == "${T2}" ]] || fail 'last_confirmed not updated'
pass 'same identity confirmation is idempotent'

if "${IDENTITY}" --database "${DB}" register --entity-id "${B}" --mac "${G}" --seen-at "${T2}" >/dev/null 2>&1; then fail 'identity conflict accepted'; fi
pass 'identity reassignment conflict rejected'

"${IDENTITY}" --database "${DB}" register --entity-id "${B}" --mac "${L}" --seen-at "${T1}" >/dev/null
pass 'local MAC evidence recorded'
set +e
"${IDENTITY}" --database "${DB}" lookup --mac "${L}" >/dev/null 2>&1
RC=$?
set -e
[[ "${RC}" == 1 ]] || fail "local MAC authoritative rc=${RC}"
pass 'local MAC excluded from authoritative lookup'

J="$("${IDENTITY}" --database "${DB}" lookup --mac "${L}" --include-non-authoritative --json)"
python3 -c 'import json,sys;p=json.loads(sys.argv[1]);assert p["identity_class"]=="local-mac" and p["authoritative"] is False and p["confidence"]==0.60' "${J}"
pass 'local MAC retained as non-authoritative evidence'

echo; echo '=== RESULT ==='; echo 'HomeLab Sentinel Persistent Identity regression PASSED'
