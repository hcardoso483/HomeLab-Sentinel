# HomeLab Sentinel Monitoring Provider Target Contract

## Status

Contract version: 1.0

This contract defines the boundary between provider-neutral HomeLab Sentinel
Monitoring targets and provider-owned runtime target configuration.

## Purpose

Monitoring Core owns the canonical target set.

A provider target renderer converts canonical Monitoring targets into
provider-specific runtime configuration.

Provider runtime configuration is derived state.

It is not a source of Sentinel identity or endpoint truth.

## Direction

```text
Living Inventory
        |
        v
Monitoring target derivation
        |
        v
canonical Monitoring targets
        |
        v
provider target renderer
        |
        v
provider-owned runtime target configuration
```

## Identity

The canonical identity is always `entity_id`.

Provider configuration MUST preserve `entity_id` explicitly when the provider
supports labels or metadata.

A provider MUST NOT reconstruct permanent identity from an IP address.

An IP address or hostname is an endpoint.

## Ownership

Monitoring Core owns:

- canonical `entity_id`
- current endpoint state
- eligibility
- provider-neutral check intent

The provider target renderer owns:

- provider-specific target-file syntax
- provider-specific labels required for later collection
- atomic replacement of generated provider target state

The provider target renderer MUST NOT:

- modify Living Inventory
- correlate entities
- derive health
- persist Monitoring observations
- redefine eligibility
- promote historical endpoints to current endpoints

## Runtime State

Generated provider configuration MUST live outside the Git repository.

Prometheus v1 uses:

```text
/srv/homelab-sentinel/prometheus/targets/reachability.json
```

Generated target state MAY be replaced whenever canonical Monitoring targets
change.

An identical canonical target set SHOULD produce deterministic provider output.

## Prometheus v1 Target Representation

The Prometheus provider uses file-service-discovery-compatible JSON.

Each eligible Sentinel entity is represented independently.

Example:

```json
[
  {
    "targets": [
      "192.168.1.20"
    ],
    "labels": {
      "hls_entity_id": "dev-example",
      "hls_check_type": "reachability",
      "hls_provider": "prometheus"
    }
  }
]
```

The `hls_entity_id` label preserves Sentinel identity through provider-specific
collection.

## Eligibility

Only targets marked eligible by Monitoring Core MAY be rendered.

An ineligible target is omitted from provider target configuration.

The renderer MUST NOT invent an endpoint for an ineligible target.

If Monitoring Core marks a target eligible but provides no usable current
endpoint, rendering MUST fail clearly instead of silently inventing provider
state.

## Endpoint Selection

For Monitoring v1, the renderer uses the first current IP address when one is
available.

If no current IP address is available, the current hostname MAY be used.

Historical addresses MUST NOT be rendered as current targets.

Future policy MAY define richer endpoint selection without changing canonical
identity.

## Determinism and Safety

Rendering MUST be deterministic for an identical canonical target set.

The renderer MUST reject duplicate canonical `entity_id` records in one render
operation.

Runtime target files SHOULD be replaced atomically so providers do not observe
partially written configuration.

## Prometheus Probe Boundary

This contract does not define how Prometheus probes a rendered target.

Generic device reachability MUST NOT be implemented by assuming every device
exposes a Prometheus metrics endpoint.

A later provider-owned slice MAY use a probing mechanism such as Blackbox
Exporter.

Monitoring Core MUST remain unaware of that provider-specific implementation.

## Slice Boundary

This slice establishes deterministic provider target rendering.

It does not:

- enable Prometheus scraping of rendered targets
- deploy Blackbox Exporter
- modify the active Prometheus scrape configuration
- schedule target reconciliation
- create live Monitoring observations
