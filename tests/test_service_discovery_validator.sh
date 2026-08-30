#!/usr/bin/env bash
set -euo pipefail
APP_ROOT="${APP_ROOT:-/opt/homelab-sentinel/app}"
VALIDATOR="$APP_ROOT/core/service_discovery/validate_observation.py"
[[ -f "$VALIDATOR" ]] || { echo "[FAIL] Service Discovery validator not found: $VALIDATOR"; exit 1; }

python3 - "$VALIDATOR" <<'PY'
import importlib.util, sys
from copy import deepcopy
from pathlib import Path

path=Path(sys.argv[1])
spec=importlib.util.spec_from_file_location("sd_validator", path)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
validate=m.validate_observation

BASE={"schema_version":"1.0","entity_id":"dev-c39a223bbd1d4362ade6e7c58a7c1a2c","provider":"nmap","observed_at":"2026-08-30T08:30:00+01:00","address":"192.168.1.58","protocol":"tcp","port":8006,"state":"open","service":None}
n=0

def good(name, change=None):
    global n
    r=deepcopy(BASE)
    if change: change(r)
    assert validate(r)==r
    n+=1; print("[PASS]",name)

def bad(name, change):
    global n
    r=deepcopy(BASE); change(r)
    try: validate(r)
    except ValueError: n+=1; print("[PASS]",name); return
    raise AssertionError(name+" should fail")

good("canonical observation")
good("identified service",lambda r:r.__setitem__("service","https"))
good("IPv6 address",lambda r:r.__setitem__("address","2001:db8::58"))
good("UTC Z timestamp",lambda r:r.__setitem__("observed_at","2026-08-30T07:30:00Z"))

try: validate([])
except ValueError: n+=1; print("[PASS] record must be object")
else: raise AssertionError("non-object should fail")

for f in BASE:
    bad("missing "+f,lambda r,f=f:r.pop(f))

bad("schema version",lambda r:r.__setitem__("schema_version","2.0"))
bad("entity ID",lambda r:r.__setitem__("entity_id","host-123"))
bad("short device entity ID",lambda r:r.__setitem__("entity_id","dev-"))
bad("uppercase device entity ID",lambda r:r.__setitem__("entity_id","dev-C39A223BBD1D4362ADE6E7C58A7C1A2C"))
bad("empty provider",lambda r:r.__setitem__("provider"," "))
bad("timestamp without timezone",lambda r:r.__setitem__("observed_at","2026-08-30T08:30:00"))
bad("invalid timestamp",lambda r:r.__setitem__("observed_at","not-a-time"))
bad("invalid address",lambda r:r.__setitem__("address","999.999.1.1"))
bad("unsupported protocol",lambda r:r.__setitem__("protocol","udp"))
bad("non-string protocol",lambda r:r.__setitem__("protocol",[]))
bad("port zero",lambda r:r.__setitem__("port",0))
bad("port above range",lambda r:r.__setitem__("port",65536))
bad("boolean port",lambda r:r.__setitem__("port",True))
bad("string port",lambda r:r.__setitem__("port","8006"))
bad("unsupported state",lambda r:r.__setitem__("state","closed"))
bad("non-string state",lambda r:r.__setitem__("state",[]))
bad("empty service",lambda r:r.__setitem__("service",""))
bad("blank service",lambda r:r.__setitem__("service"," "))
bad("non-string service",lambda r:r.__setitem__("service",443))

payload=m.canonical_payload(BASE)
assert payload=='{"address":"192.168.1.58","entity_id":"dev-c39a223bbd1d4362ade6e7c58a7c1a2c","observed_at":"2026-08-30T08:30:00+01:00","port":8006,"protocol":"tcp","provider":"nmap","schema_version":"1.0","service":null,"state":"open"}'
n+=1; print("[PASS] canonical payload")
print(f"[PASS] Service Discovery validator contract ({n} checks)")
PY
