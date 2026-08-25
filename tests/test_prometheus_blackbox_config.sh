#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="/opt/homelab-sentinel/app"
PROM_ROOT="${APP_ROOT}/compose/monitoring/prometheus"

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; }

echo "HomeLab Sentinel Prometheus Blackbox configuration regression test"
echo

python3 - "${PROM_ROOT}" <<'PY'
import sys
from pathlib import Path
import yaml

root = Path(sys.argv[1])
compose = yaml.safe_load((root / "compose.yml").read_text()) or {}
prom = yaml.safe_load((root / "config/prometheus.yml").read_text()) or {}
blackbox = yaml.safe_load((root / "config/blackbox.yml").read_text()) or {}

services = compose.get("services", {})
assert "prometheus" in services
assert "blackbox" in services

bb = services["blackbox"]
assert bb["image"] == "prom/blackbox-exporter:v0.28.0"
assert "NET_RAW" in bb.get("cap_add", [])
assert "no-new-privileges:true" in bb.get("security_opt", [])
assert "ports" not in bb

prom_volumes = services["prometheus"].get("volumes", [])
assert "/srv/homelab-sentinel/prometheus/targets:/etc/prometheus/hls-targets:ro" in prom_volumes

icmp = blackbox["modules"]["icmp_ipv4"]
assert icmp["prober"] == "icmp"
assert icmp["icmp"]["preferred_ip_protocol"] == "ip4"
assert icmp["icmp"]["ip_protocol_fallback"] is False

jobs = {j.get("job_name"): j for j in prom.get("scrape_configs", [])}
reach = jobs["hls-reachability"]
assert reach["metrics_path"] == "/probe"
assert reach["params"]["module"] == ["icmp_ipv4"]
assert reach["file_sd_configs"][0]["files"] == ["/etc/prometheus/hls-targets/*.json"]

relabels = reach["relabel_configs"]
assert relabels[0]["source_labels"] == ["__address__"]
assert relabels[0]["target_label"] == "__param_target"
assert relabels[1]["source_labels"] == ["__param_target"]
assert relabels[1]["target_label"] == "instance"
assert relabels[2]["target_label"] == "__address__"
assert relabels[2]["replacement"] == "blackbox:9115"
PY

pass "Blackbox service is internal-only"
pass "Blackbox ICMP receives only NET_RAW capability"
pass "Prometheus target runtime is mounted read-only"
pass "IPv4 ICMP probe module configured"
pass "file_sd reachability scrape job configured"
pass "Prometheus relabeling forwards targets through Blackbox"

echo
echo "=== RESULT ==="
echo "HomeLab Sentinel Prometheus Blackbox configuration regression PASSED"
