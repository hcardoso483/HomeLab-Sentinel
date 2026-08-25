# Monitoring Provider Observation Adapter Contract

## Status

Monitoring v1 provider adapter contract.

## Purpose

A Monitoring provider adapter converts provider-specific evidence into the
canonical HomeLab Sentinel Monitoring observation contract.

The adapter is the provider-specific boundary. Monitoring Core remains
provider-independent.

## Direction

```text
provider-specific evidence
        |
        v
provider adapter
        |
        v
canonical Monitoring observation
        |
        v
Monitoring Core validation and persistence
```

## Responsibilities

A provider adapter MUST:

- understand its provider-specific result format
- retain canonical Living Inventory `entity_id`
- identify itself using the provider ID selected by Provider Resolver
- emit Monitoring schema version `1.0`
- map provider evidence to canonical observation status
- emit a UTC `checked_at` timestamp
- emit exactly one canonical observation for one evaluated target/result

A provider adapter MUST NOT:

- write directly to the Living Inventory database
- write directly to `monitoring_observations`
- derive `UNKNOWN`, `HEALTHY`, `DEGRADED`, or `DOWN`
- own Monitoring freshness policy
- own Monitoring persistence policy
- change Living Inventory identity
- make Prometheus a dependency of Monitoring Core

## Prometheus v1 mapping

The first Prometheus adapter uses the Prometheus `up` metric as
provider-specific reachability evidence.

```text
Prometheus up == 1  -> observation status success
Prometheus up == 0  -> observation status failed
missing/unsafe result -> observation status unknown
```

The resulting canonical observation uses:

```text
provider   = prometheus
check_type = reachability
latency_ms = null
```

`latency_ms` remains null because the Prometheus `up` metric does not itself
represent probe latency.

## Health boundary

Observation status is evidence, not entity health.

```text
success / failed / unknown
```

are provider observation states.

```text
UNKNOWN / HEALTHY / DEGRADED / DOWN
```

remain conclusions owned exclusively by Monitoring Core health evaluation.

## Live provider input

The Prometheus adapter supports two provider-input modes:

```text
--fixture PATH
```

loads a deterministic Prometheus HTTP API response from disk for regression
testing.

```text
--live
```

performs a read-only Prometheus instant query against `/api/v1/query`.

Live mode MUST preserve the same canonical observation output contract as
fixture mode.

When a Prometheus query returns multiple vector results, the adapter MUST NOT
guess which result belongs to a Sentinel entity. The caller MAY constrain the
result with provider labels such as `instance` and `job`. If selection does not
resolve to exactly one result, observation status is `unknown`.

Failure to contact the Prometheus API is a provider-query failure. The adapter
MUST fail rather than inventing an entity observation.

Live input does not authorize the adapter to:

- modify Prometheus configuration
- write Monitoring evidence directly
- schedule collection
- derive Monitoring Core health

## Initial integration scope

Slice 5 proves the adapter contract using deterministic Prometheus HTTP API
fixtures.

It does not:

- modify live Prometheus scrape configuration
- query the live Prometheus HTTP API
- create real device observations
- schedule Monitoring collection
- configure exporters or probes

Those operational concerns belong to later slices after the adapter boundary
has been regression-proven.
