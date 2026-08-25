# HomeLab Sentinel Monitoring Orchestration Contract

## Status

Contract version: 1.0

HomeLab Sentinel Monitoring Orchestration v1 defines how Sentinel
coordinates canonical Monitoring targets, provider resolution, provider
adapters, observation validation, and Monitoring persistence without
transferring ownership between those components.

This contract defines Sentinel-owned orchestration behaviour.

Provider-specific collection details do not belong in this contract.

------------------------------------------------------------------------

## 1. Purpose

Monitoring Orchestration answers:

> How does Sentinel coordinate collection of Monitoring evidence for
> current Living Inventory entities through the selected Monitoring
> provider?

The orchestrator coordinates existing Monitoring components.

It MUST NOT replace them.

The orchestrator MUST preserve canonical Sentinel `entity_id` throughout
collection.

The orchestrator MUST remain independent of any specific Monitoring
provider.

------------------------------------------------------------------------

## 2. Architectural Boundary

The orchestration data path is:

``` text
Living Inventory
        |
        v
Monitoring target derivation
        |
        +--------------------+
        |                    |
        v                    v
canonical targets      Provider Resolver
        |                    |
        +---------+----------+
                  |
                  v
        Monitoring Orchestrator
                  |
                  v
        Selected Provider Adapter
                  |
                  v
       canonical observations
                  |
                  v
       validation / persistence
                  |
                  v
          health evaluation
```

The orchestrator coordinates this path but MUST NOT absorb the
responsibilities of the components it invokes.

In particular:

``` text
Orchestrator != Living Inventory
Orchestrator != Provider Resolver
Orchestrator != Provider Adapter
Orchestrator != Observation Store
Orchestrator != Health Evaluator
```

------------------------------------------------------------------------

## 3. Ownership

Monitoring Orchestration owns:

-   coordination of one Monitoring collection run
-   consumption of canonical Monitoring targets
-   consumption of the provider selected by Provider Resolver
-   invocation of the selected provider adapter
-   collection-run outcome accounting
-   isolation of independent target failures
-   forwarding canonical adapter output to Monitoring validation and
    persistence
-   operational reporting about the collection run

Monitoring Orchestration MUST NOT own:

-   Living Inventory identity
-   entity correlation
-   target identity derivation
-   provider-selection policy
-   provider-specific probe implementation
-   canonical observation semantics
-   Monitoring persistence schema
-   health-state semantics
-   health-state derivation
-   provider deployment lifecycle

------------------------------------------------------------------------

## 4. Canonical Inputs

The orchestrator MUST consume Monitoring targets produced by Monitoring
Core.

It MUST NOT independently reconstruct targets from raw Discovery data or
directly infer permanent identity from IP addresses.

A target's canonical identity is `entity_id`.

Current endpoints are collection endpoints, not permanent identity.

The orchestrator MUST consume the selected Monitoring provider through
the existing Provider Resolver.

It MUST NOT hardcode `prometheus` or silently substitute another
provider.

If provider resolution fails, the collection run MUST report a
provider-level failure.

Provider-resolution failure MUST NOT be converted into entity `DOWN`
states.

------------------------------------------------------------------------

## 5. Target Eligibility

Only targets marked eligible by Monitoring Core MAY be submitted for
collection.

An ineligible target MUST NOT cause the overall orchestration process to
invent an endpoint or provider result.

The orchestrator MAY record an ineligible target as:

``` text
SKIPPED
```

A skipped target is a collection outcome.

It is not a Monitoring health state.

Historical endpoints MUST NOT be promoted to current endpoints by the
orchestrator.

------------------------------------------------------------------------

## 6. Provider Adapter Invocation

The orchestrator MUST invoke the adapter belonging to the provider
selected by Provider Resolver.

Provider-specific arguments, queries, labels, configuration translation,
or collection mechanics MUST remain behind the provider boundary.

The orchestrator MAY supply canonical target identity and endpoint
information required by the adapter contract.

The orchestrator MUST NOT interpret provider-native evidence itself when
an adapter owns that translation.

An adapter invocation MUST preserve the canonical target `entity_id`.

The adapter MUST return canonical Monitoring observation evidence or
fail clearly.

------------------------------------------------------------------------

## 7. Observation Boundary

Provider adapter output is evidence, not health.

Canonical provider observation statuses remain:

``` text
success
failed
unknown
```

Canonical entity health states remain:

``` text
UNKNOWN
HEALTHY
DEGRADED
DOWN
```

The orchestrator MUST NOT translate an adapter or provider failure
directly into `UNKNOWN`, `HEALTHY`, `DEGRADED`, or `DOWN`.

Health conclusions remain exclusively owned by Monitoring Core health
evaluation.

------------------------------------------------------------------------

## 8. Validation and Persistence

Adapter output MUST pass canonical Monitoring observation validation
before persistence.

The orchestrator MUST use the Monitoring-owned validation and
persistence boundary.

It MUST NOT write directly to Monitoring database tables.

It MUST NOT write directly to Living Inventory tables.

Invalid adapter output MUST NOT be silently repaired into apparently
valid evidence.

Invalid evidence MUST be rejected and reported as an orchestration
outcome.

Persistence failure MUST be reported separately from provider or adapter
failure.

------------------------------------------------------------------------

## 9. Collection Outcomes

Monitoring Orchestration v1 distinguishes collection outcomes from
entity health.

Canonical orchestration outcome classes are:

``` text
SUCCESS
SKIPPED
PROVIDER_ERROR
ADAPTER_ERROR
INVALID_EVIDENCE
STORE_ERROR
```

### SUCCESS

The selected provider produced canonical evidence for the target and
Monitoring persistence accepted it.

### SKIPPED

The target was intentionally not collected, for example because
Monitoring Core marked it ineligible or no usable current endpoint
exists.

### PROVIDER_ERROR

Provider resolution or provider-wide collection capability failed.

A provider error MUST NOT imply that monitored entities are down.

### ADAPTER_ERROR

The selected provider adapter could not safely complete its
provider-specific translation or invocation.

### INVALID_EVIDENCE

Adapter output failed the canonical Monitoring observation contract.

Invalid evidence MUST NOT be persisted as valid evidence.

### STORE_ERROR

Canonical evidence was produced but Monitoring validation/persistence
could not accept or store it.

A store error is a Sentinel collection-path failure, not an entity
health conclusion.

------------------------------------------------------------------------

## 10. Failure Isolation

Failure of one target MUST NOT prevent independent eligible targets from
being attempted unless continuing would be unsafe because of a
provider-wide or platform-level failure.

A target-specific adapter failure SHOULD be isolated to that target.

Invalid evidence for one target SHOULD NOT invalidate valid evidence
already produced for another target.

A persistence failure MAY require the orchestrator to stop further
persistence when continuing could compromise correctness.

Provider-wide failure MAY terminate the run early when further target
attempts cannot produce trustworthy evidence.

The orchestrator MUST report enough information to distinguish
target-specific failure from provider-wide or platform-wide failure.

------------------------------------------------------------------------

## 11. Provider Failure Is Not Entity Failure

The following relationship is mandatory:

``` text
provider failure != entity DOWN
```

If the selected provider is unavailable, Sentinel lacks fresh evidence.

Monitoring freshness and health evaluation MAY eventually cause entity
health to become `UNKNOWN` according to Monitoring policy.

The orchestrator MUST NOT fabricate failed observations merely because
the provider could not be contacted.

------------------------------------------------------------------------

## 12. Idempotency and Evidence Integrity

Orchestration MAY retry safe collection operations according to
Monitoring policy.

Retries MUST preserve canonical `entity_id`.

The existing Monitoring persistence idempotency boundary MUST remain
authoritative for duplicate evidence.

The orchestrator MUST NOT create alternate identities or mutate
observation payloads merely to defeat duplicate detection.

A retry that produces the exact same canonical evidence MAY be accepted
as an idempotent duplicate by Monitoring persistence.

------------------------------------------------------------------------

## 13. Scheduling Boundary

Monitoring Orchestration defines execution of a collection run.

It does not, by itself, define when collection runs are scheduled.

Scheduling policy belongs to Sentinel Monitoring policy and platform
scheduling infrastructure.

Provider adapters MUST NOT own Sentinel collection scheduling.

The selected provider MAY have internal scheduling mechanisms, but
provider-native scheduling MUST NOT silently become the authoritative
Sentinel Monitoring policy.

Future scheduled Monitoring execution MUST invoke the same orchestration
contract used by manual or test execution.

------------------------------------------------------------------------

## 14. Operational State and Observability

The orchestrator SHOULD expose enough run information for HLS status,
troubleshooting, automation, and future API/UI consumers.

A collection-run record MAY include:

``` text
run identifier
provider
started_at
finished_at
targets considered
targets attempted
success count
skipped count
provider error count
adapter error count
invalid evidence count
store error count
overall run outcome
```

Operational collection state MUST remain distinct from entity health.

A healthy provider does not prove all entities are healthy.

A failed provider does not prove all entities are down.

------------------------------------------------------------------------

## 15. CLI Contract

Monitoring Orchestration SHOULD eventually be reachable through the
first-class HLS Monitoring CLI.

A future command surface MAY include:

``` text
hls monitoring collect
hls monitoring collect --json
```

The CLI MUST delegate to the same orchestration implementation used by
scheduled execution.

The CLI MUST NOT contain a second independent implementation of provider
selection, adapter translation, persistence, or health evaluation.

Exact CLI output and scheduling integration are implementation concerns
for later slices.

------------------------------------------------------------------------

## 16. Provider Independence

Monitoring Orchestration MUST depend on provider contracts, not
Prometheus-specific behaviour.

Prometheus MAY be the selected Monitoring v1 provider.

Prometheus MUST NOT become a hard dependency of the orchestrator.

Replacing one conforming Monitoring provider with another MUST NOT
require redesign of:

-   Living Inventory identity
-   Monitoring target derivation
-   Monitoring observation validation
-   Monitoring persistence
-   Monitoring health evaluation
-   orchestration outcome semantics

Provider-specific differences MUST remain isolated behind provider-owned
adapters and configuration.

------------------------------------------------------------------------

## 17. Security and Safety

The orchestrator MUST treat provider output as untrusted until validated
against the canonical Monitoring observation contract.

Provider adapter execution MUST NOT grant the provider ownership of
Sentinel persistence or health semantics.

The orchestrator SHOULD use least-privilege access to provider
interfaces.

Read-only provider queries SHOULD be preferred when sufficient for
collection.

Provider credentials, when required in future implementations, MUST
remain provider-owned configuration and MUST NOT be embedded in
canonical Monitoring targets or observations.

------------------------------------------------------------------------

## 18. Monitoring v1 Non-Goals

This contract does not define:

-   Prometheus scrape-target generation
-   exporter deployment
-   SNMP configuration
-   ICMP implementation details
-   service-specific checks
-   alert delivery
-   dashboard rendering
-   provider installation or upgrade
-   scheduler implementation
-   distributed orchestration
-   high-availability orchestration
-   automatic provider failover
-   final CLI formatting

Those concerns MAY be implemented by later slices while preserving this
contract.

------------------------------------------------------------------------

## 19. Required Invariants

Any Monitoring Orchestration v1 implementation MUST preserve all of the
following:

1.  `entity_id` remains the canonical monitored identity.
2.  Current endpoints come from Monitoring Core / Living Inventory
    state.
3.  Provider selection comes from Provider Resolver.
4.  Provider-specific evidence translation remains adapter-owned.
5.  Adapter output is validated before persistence.
6.  The orchestrator does not write directly to Monitoring or Inventory
    tables.
7.  Provider or adapter failure is not converted into entity `DOWN`.
8.  Health evaluation remains owned by Monitoring Core.
9.  Independent target failures are isolated where safe.
10. Prometheus is replaceable by another conforming Monitoring provider.
11. Manual and scheduled collection use the same orchestration boundary.
12. Collection outcomes remain distinct from entity health states.

------------------------------------------------------------------------

## 20. Slice Boundary

This document establishes the Monitoring Orchestration v1 architectural
contract.

The contract itself introduces no runtime behaviour.

Implementation MUST follow in later slices and MUST be regression-tested
against these boundaries before scheduled or broad live-device
collection is enabled.
