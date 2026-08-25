# HomeLab Sentinel Prometheus Reachability Probe

## Status

Provider implementation slice for Monitoring v1.

## Purpose

The Prometheus Monitoring provider needs a provider-owned mechanism capable of
probing ordinary network devices that do not expose Prometheus metrics.

HomeLab Sentinel Monitoring Core remains unaware of the implementation.

## Provider Boundary

```text
canonical Sentinel target
        |
        v
Prometheus file_sd target
        |
        v
Prometheus reachability scrape job
        |
        v
Blackbox Exporter
        |
        v
ICMP probe result
        |
        v
Prometheus metrics
```

Blackbox Exporter is an internal implementation dependency of the Prometheus
Monitoring provider. It is not a separate Sentinel Monitoring provider.

## Initial Probe

The initial provider-owned reachability mechanism uses an IPv4 ICMP module
named `icmp_ipv4`.

ICMP probe success is provider evidence. It is not a Sentinel entity health
conclusion. A single failed ICMP probe MUST NOT directly imply Sentinel `DOWN`.

## Privilege Boundary

ICMP raw sockets require additional Linux privilege. The Blackbox container
receives only `NET_RAW`; it is not run in broad privileged mode.

The Blackbox HTTP endpoint is not published to the host in this slice. It is
reachable only on the provider Compose network.

## Runtime Targets

Prometheus consumes generated targets from:

```text
/etc/prometheus/hls-targets/*.json
```

The host runtime source is:

```text
/srv/homelab-sentinel/prometheus/targets/
```

The directory is mounted read-only into the Prometheus container.

## Prometheus Relabeling

The provider uses:

```text
__address__ -> __param_target
__param_target -> instance
blackbox:9115 -> __address__
```

Sentinel labels from file-based service discovery remain attached to resulting
Prometheus series.

## Slice Boundary

This slice proves the provider probe engine and a direct live ICMP probe.

It does not yet:

- render the full live Living Inventory target set
- reload/recreate the active Prometheus service
- ingest `probe_success` as Sentinel observations
- schedule reconciliation or collection
- convert an ICMP failure directly into Sentinel `DOWN`
