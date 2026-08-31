#!/bin/bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/homelab-sentinel/app}"
PROVIDER="$APP_ROOT/compose/discovery/nmap/scripts/discover-services.sh"

fail() { echo "[FAIL] $*" >&2; exit 1; }

[[ -f "$PROVIDER" ]] || fail "Nmap Service Discovery provider not found: $PROVIDER"

python3 - "$PROVIDER" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")

def section(start_marker, end_marker=None):
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f"[FAIL] missing provider section: {start_marker}")
    if end_marker is None:
        return text[start:]
    end = text.find(end_marker, start + len(start_marker))
    if end < 0:
        raise SystemExit(f"[FAIL] missing provider section boundary: {end_marker}")
    return text[start:end]

stage1 = section("# Stage 1:", "# Derive the exact set of open TCP ports")
stage2 = section("# Stage 2:")

# Match policy tokens inside their explicit provider stages rather than trying
# to parse shell command prefixes such as `if nmap`.
if not re.search(r'(?m)^\s*nmap\s*\\', stage1):
    raise SystemExit("[FAIL] Stage 1 Nmap invocation not found")
if not re.search(r'(?m)^\s*if\s+nmap\s*\\', stage2):
    raise SystemExit("[FAIL] Stage 2 Nmap invocation not found")

if not re.search(r'(?m)^\s*-p-\s*\\', stage1):
    raise SystemExit("[FAIL] Stage 1 no longer scans the full TCP port range")
print("[PASS] Stage 1 retains full-range TCP endpoint discovery")

if "--defeat-rst-ratelimit" not in stage1:
    raise SystemExit("[FAIL] Stage 1 lacks --defeat-rst-ratelimit")
print("[PASS] Stage 1 mitigates closed-port RST rate limiting")

if "--defeat-rst-ratelimit" in stage2:
    raise SystemExit("[FAIL] Stage 2 unexpectedly uses --defeat-rst-ratelimit")
print("[PASS] Stage 2 remains separate from RST-rate-limit tuning")

if not re.search(r'(?m)^\s*-sV\s*\\', stage2):
    raise SystemExit("[FAIL] Stage 2 no longer performs service detection")
if not re.search(r'(?m)^\s*--version-light\s*\\', stage2):
    raise SystemExit("[FAIL] Stage 2 no longer uses version-light")
if not re.search(r'(?m)^\s*-p\s+"\$\{OPEN_PORTS\}"\s*\\', stage2):
    raise SystemExit("[FAIL] Stage 2 no longer probes only Stage 1 open ports")
print("[PASS] Stage 2 retains version-light probing of Stage 1 open ports")
PY

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Nmap Service Discovery scan-policy regression PASSED"
