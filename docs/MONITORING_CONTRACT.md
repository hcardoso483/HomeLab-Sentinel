# HomeLab Sentinel Monitoring Contract

## Status

Contract version: 1.0

HomeLab Sentinel Monitoring v1 defines how Sentinel turns Living
Inventory entities into provider-neutral monitoring targets, collects
monitoring evidence through the selected monitoring provider, derives
current health, stores historical monitoring evidence, and exposes
monitoring state through the HLS CLI.

This contract defines Sentinel-owned behaviour.

Provider-specific implementation details do not belong in this contract.

------------------------------------------------------------------------

## 1. Purpose

Discovery answers:

> What exists?

Living Inventory answers:

> What persistent entity does Sentinel believe this is?

Monitoring answers:

> Is that entity working, and what evidence supports that conclusion?

Monitoring MUST consume stable Sentinel entity identity from Living
Inventory.

Monitoring MUST NOT redefine device identity.

Monitoring MUST NOT use an IP address as the permanent identity of a
monitored device.

------------------------------------------------------------------------

## 2. Architectural Boundary

The Monitoring data path is:

``` text
Living Inventory
      |
      v
Monitoring target derivation
      |
      v
Monitoring policy
      |
      v
Selected monitoring provider
      |
      v
Normalized monitoring observations
      |
      v
Monitoring persistence
      |
      v
Health-state evaluation
      |
      v
Current health + history
      |
      v
HLS CLI / API / UI consumers
```

Monitoring Core owns:

-   monitoring target identity
-   monitoring target derivation
-   monitoring policy
-   provider-neutral monitoring contracts
-   monitoring observation validation
-   monitoring persistence
-   health-state semantics
-   health-state derivation
-   monitoring history
-   HLS monitoring CLI behaviour

Monitoring providers own:

-   provider-specific deployment
-   provider-specific configuration
-   provider-specific probe execution
-   provider-specific collection mechanisms
-   conversion of provider results into the Sentinel Monitoring Contract

Providers MUST NOT redefine Sentinel entity identity.

Providers MUST NOT directly assign permanent device identity.

Providers MUST NOT decide Sentinel's final health semantics
independently of Monitoring Core.

------------------------------------------------------------------------

## 3. Provider Model

Monitoring is a Sentinel capability.

The selected provider is an implementation of that capability.

The default installation recommendation is:

``` text
capability: monitoring
default provider: prometheus
```

Prometheus is the recommended/default provider for Monitoring v1.

Prometheus MUST NOT become a hard dependency of Monitoring Core.

Alternative providers are allowed when:

-   they are registered in the Sentinel module registry
-   their metadata advertises the `monitoring` capability
-   they satisfy the Monitoring provider contract

Provider selection MUST continue to use the existing Provider Resolver.

If the user explicitly selects a valid provider, Sentinel MUST respect
that selection.

If no explicit provider is selected, Sentinel MAY use the installation
default.

If the configured provider is invalid or unavailable, Sentinel MUST fail
clearly rather than silently substituting another provider.

------------------------------------------------------------------------

## 4. Monitoring Identity

The canonical monitored identity is:

``` text
entity_id
```

Example:

``` text
dev-1234567890abcdef
```

An IP address is an endpoint.

A hostname is an endpoint label.

A MAC address is identity evidence used by Inventory/Correlation.

Monitoring MUST associate historical monitoring evidence with
`entity_id`.

If an entity changes IP address, its monitoring history MUST remain
attached to the same `entity_id`.

Monitoring MUST NOT create a new monitoring identity merely because an
IP address changes.

------------------------------------------------------------------------

## 5. Monitoring Targets

Automatic Monitoring targets MUST be derived from resolved Living
Inventory entities.

A Monitoring target minimally contains:

``` json
{
  "schema_version": "1.0",
  "entity_id": "dev-example",
  "entity_type": "device",
  "endpoints": {
    "ip_addresses": [
      "192.168.1.20"
    ],
    "hostname": "example-host"
  }
}
```

Target derivation MUST use current Living Inventory state.

Historical addresses MAY be retained for context but MUST NOT
automatically be treated as current Monitoring endpoints.

An entity with no usable current endpoint MAY remain a known entity with
Monitoring state `UNKNOWN`.

Monitoring MUST NOT invent an endpoint when Living Inventory does not
provide one.

------------------------------------------------------------------------

## 6. Monitoring Policy

Monitoring policy describes what Sentinel intends to monitor.

Policy MUST remain provider-neutral.

Policy MAY define:

-   enabled or disabled Monitoring
-   Monitoring interval
-   target eligibility
-   desired check classes
-   evaluation thresholds
-   freshness expectations
-   retry behaviour

Policy MUST NOT contain provider-specific implementation details unless
those details are explicitly isolated inside provider-owned
configuration.

A provider translates Sentinel Monitoring policy into its own execution
mechanism.

------------------------------------------------------------------------

## 7. Monitoring Check Types

Monitoring v1 begins with a small set of provider-neutral check
concepts.

The first supported conceptual check is:

``` text
reachability
```

A provider MAY implement reachability using ICMP, TCP, HTTP, exporter
state, or another mechanism appropriate to the provider.

Sentinel MUST NOT assume that ICMP failure alone proves an entity is
down.

Future check types MAY include:

``` text
service
port
http
dns
snmp
resource
metric
```

Adding a new check type MUST preserve backwards compatibility with
existing Monitoring observations whenever practical.

------------------------------------------------------------------------

## 8. Monitoring Observation Contract

A Monitoring observation is evidence collected at a specific point in
time.

A Monitoring observation is NOT the permanent health identity of an
entity.

A normalized Monitoring v1 observation has this shape:

``` json
{
  "schema_version": "1.0",
  "entity_id": "dev-example",
  "provider": "prometheus",
  "check_type": "reachability",
  "target": "192.168.1.20",
  "checked_at": "2026-08-24T15:00:00Z",
  "status": "success",
  "latency_ms": 0.84
}
```

Required fields:

``` text
schema_version
entity_id
provider
check_type
target
checked_at
status
latency_ms
```

Allowed `status` values for Monitoring Contract 1.0:

``` text
success
failed
unknown
```

`latency_ms` MAY be null when latency is unavailable or not meaningful.

Example failed observation:

``` json
{
  "schema_version": "1.0",
  "entity_id": "dev-example",
  "provider": "prometheus",
  "check_type": "reachability",
  "target": "192.168.1.20",
  "checked_at": "2026-08-24T15:00:00Z",
  "status": "failed",
  "latency_ms": null
}
```

Provider-specific raw information MAY be retained in an optional payload
in a future contract revision.

Monitoring Core MUST validate normalized observations before
persistence.

------------------------------------------------------------------------

## 9. Monitoring Evidence

Monitoring observations are historical evidence.

They SHOULD be immutable after successful ingestion.

Monitoring evidence MUST be stored separately from Discovery
observations.

The existing Discovery `observations` table MUST NOT be overloaded with
Monitoring records.

Discovery evidence describes what Sentinel observed about network
existence and identity.

Monitoring evidence describes what Sentinel observed about operational
behaviour and health.

------------------------------------------------------------------------

## 10. Monitoring Persistence

Monitoring v1 SHOULD introduce dedicated persistent storage for
Monitoring observations.

A conceptual record includes:

``` text
monitoring_observation_id
entity_id
schema_version
provider
check_type
target
checked_at
received_at
status
latency_ms
payload_json
payload_hash
```

Monitoring observations SHOULD reference:

``` text
entities.entity_id
```

through a foreign key.

Exact duplicate Monitoring evidence SHOULD be safe to ingest repeatedly.

Persistence SHOULD therefore support idempotent ingestion where
practical.

Monitoring history MUST survive process restarts.

Monitoring history MUST survive provider restarts.

Monitoring history MUST remain associated with the Sentinel entity
rather than the endpoint used for a particular check.

------------------------------------------------------------------------

## 11. Current Health State

Monitoring Core derives current health from Monitoring evidence.

Canonical Monitoring v1 health states are:

``` text
UNKNOWN
HEALTHY
DEGRADED
DOWN
```

### UNKNOWN

Sentinel does not currently have enough valid or fresh Monitoring
evidence to make a health determination.

Examples:

-   entity has no usable endpoint
-   provider has not collected evidence yet
-   latest evidence is too old
-   provider result cannot be interpreted safely

### HEALTHY

Available Monitoring evidence indicates expected operation.

HEALTHY means that required Monitoring evidence is currently
satisfactory.

### DEGRADED

Sentinel has evidence of partial failure or reduced operation, but
available evidence does not justify declaring the entity DOWN.

Examples:

-   one check fails while another proves the entity is reachable
-   an expected service fails but the device remains reachable
-   Monitoring evidence is incomplete but still meaningful

### DOWN

Available Monitoring evidence strongly indicates that the entity is not
operational according to Monitoring policy.

DOWN MUST require stronger evidence than a single isolated failed probe.

------------------------------------------------------------------------

## 12. Health Evaluation Principles

Health is a conclusion derived from evidence.

A single failed Monitoring observation MUST NOT automatically mean DOWN.

Monitoring Core SHOULD consider:

-   number of recent observations
-   freshness
-   consistency of failure
-   available check types
-   contradictory evidence
-   Monitoring policy
-   provider confidence where applicable

A successful check MAY immediately provide strong positive evidence.

Repeated failures MAY increase confidence that an entity is unavailable.

Conflicting evidence SHOULD generally produce DEGRADED rather than DOWN.

Insufficient evidence SHOULD produce UNKNOWN rather than an invented
result.

------------------------------------------------------------------------

## 13. Provider Failure

Provider health and monitored-entity health are separate concepts.

If the Monitoring provider fails:

``` text
provider failure != all monitored entities are DOWN
```

When Monitoring evidence cannot be refreshed because the provider is
unavailable, entity health SHOULD eventually become UNKNOWN or STALE
according to policy.

Sentinel MUST NOT convert provider failure into false device outages.

------------------------------------------------------------------------

## 14. Freshness

Monitoring evidence has a useful lifetime.

Monitoring v1 MUST distinguish current evidence from stale evidence.

A previously HEALTHY entity MUST NOT remain permanently HEALTHY when no
new Monitoring evidence is received.

Likewise, old failure evidence MUST NOT permanently force an entity to
remain DOWN after evidence becomes stale.

Freshness policy MAY be configurable.

------------------------------------------------------------------------

## 15. HLS CLI Contract

Monitoring v1 includes a first-class HLS CLI interface.

The CLI exists for:

-   operational inspection
-   development
-   troubleshooting
-   automation
-   future UI/API consumption patterns

The initial command surface SHOULD be:

``` text
hls monitoring status
hls monitoring provider
hls monitoring targets
hls monitoring health
hls monitoring history <entity-id>
```

------------------------------------------------------------------------

## 16. `hls monitoring status`

This command reports Monitoring subsystem health.

Example:

``` text
HomeLab Sentinel Monitoring

Provider          prometheus
Provider status   HEALTHY
Targets           60
Healthy           52
Degraded           4
Down               2
Unknown            2
Last evaluation   2026-08-24T15:00:00Z
```

The command SHOULD expose enough information to quickly determine
whether the Monitoring subsystem itself is operational.

------------------------------------------------------------------------

## 17. `hls monitoring provider`

This command reports provider resolution.

Example:

``` text
Capability         monitoring
Provider           prometheus
Source             user configuration
Status             valid
```

The command SHOULD use the existing Provider Resolver rather than
duplicating provider-selection logic.

------------------------------------------------------------------------

## 18. `hls monitoring targets`

This command reports current Monitoring targets.

Example:

``` text
ENTITY_ID                  ENDPOINT         STATE
dev-example-1              192.168.1.20     HEALTHY
dev-example-2              192.168.1.34     DEGRADED
dev-example-3              192.168.1.58     DOWN
```

Target output MUST identify entities by `entity_id`.

Endpoint output is secondary operational information.

------------------------------------------------------------------------

## 19. `hls monitoring health`

This command reports current derived entity health.

It SHOULD support both concise human-readable output and future
machine-readable output.

The health command MUST NOT expose raw provider-specific semantics as
the canonical Sentinel health model.

------------------------------------------------------------------------

## 20. `hls monitoring history <entity-id>`

This command reports recent normalized Monitoring evidence for one
entity.

Example conceptual output:

``` text
2026-08-24T15:00:00Z  reachability  success  0.84 ms
2026-08-24T14:45:00Z  reachability  success  0.91 ms
2026-08-24T14:30:00Z  reachability  failed   -
```

History MUST remain attached to `entity_id`.

------------------------------------------------------------------------

## 21. Integration with `hls status`

Once Monitoring v1 is sufficiently mature, the general:

``` text
hls status
```

command SHOULD gain a Monitoring section.

Conceptual example:

``` text
Monitoring
  Provider             prometheus
  Runtime              HEALTHY
  Targets              60
  Health evaluation    CURRENT
```

Monitoring failure SHOULD affect overall Sentinel status only according
to explicit status policy.

Monitoring provider failure MUST remain distinguishable from monitored
entity failure.

------------------------------------------------------------------------

## 22. Homepage and Native UI

Homepage remains a temporary development and integration dashboard.

Monitoring Core MUST NOT depend on Homepage.

Homepage MAY consume Monitoring information where useful during
development.

A future native Sentinel UI SHOULD consume Sentinel-owned Monitoring
contracts and APIs rather than provider-specific data directly.

------------------------------------------------------------------------

## 23. Alerting Boundary

Alerting is NOT part of Monitoring v1.

Monitoring determines:

``` text
What is the current health state?
```

Alerting determines:

``` text
Does a health transition require notification?
```

Monitoring MUST NOT directly encode user-notification behaviour into
health evaluation.

A future Alerting module MAY consume Monitoring state transitions and
Monitoring observations.

------------------------------------------------------------------------

## 24. Metrics Boundary

Monitoring and metrics are related but distinct Sentinel capabilities.

A provider such as Prometheus MAY provide both:

``` text
metrics
monitoring
```

Sentinel MUST preserve the conceptual distinction.

Metrics answer questions such as:

``` text
What value was measured?
How did it change over time?
```

Monitoring answers:

``` text
Is this entity or service currently operating as expected?
```

A single provider MAY implement both capabilities without merging the
Sentinel contracts.

------------------------------------------------------------------------

## 25. Monitoring v1 Non-Goals

Monitoring v1 does NOT attempt to provide:

-   alert notifications
-   full Prometheus rule management
-   Grafana integration
-   SNMP polling
-   advanced service dependency graphs
-   automatic root-cause analysis
-   predictive failure detection
-   anomaly detection
-   native Sentinel UI
-   complete infrastructure observability
-   every possible Monitoring provider

These MAY be considered in later versions after v1 is proven in real
use.

------------------------------------------------------------------------

## 26. Monitoring v1 Completion Criteria

Monitoring v1 is considered complete when:

-   Monitoring target identity is based on Living Inventory `entity_id`
-   target derivation is deterministic
-   provider resolution works through the existing registry/resolver
-   Prometheus functions as the default Monitoring provider
-   provider-neutral Monitoring observations are defined and validated
-   Monitoring evidence is persisted separately from Discovery evidence
-   current health can be derived as UNKNOWN, HEALTHY, DEGRADED, or DOWN
-   stale evidence is handled safely
-   provider failure does not falsely mark entities DOWN
-   HLS CLI exposes Monitoring status, provider, targets, health, and
    history
-   deterministic regression tests cover the Monitoring contract
-   Monitoring survives restart/reboot testing
-   production behaviour has been observed on the real homelab
-   the working implementation is committed and checkpointed

------------------------------------------------------------------------

## 27. Versioning Mindset

Monitoring v1 exists to establish and prove the Monitoring architecture.

It is not intended to predict every future Monitoring requirement.

HomeLab Sentinel v2 MAY evolve this contract using evidence gathered
from real v1 operation.

Changes SHOULD preserve proven behaviour where practical.

Regression tests SHOULD act as the behavioural record of v1 guarantees.

The development cycle is:

``` text
contract
   |
implementation
   |
regression tests
   |
real-world validation
   |
stable checkpoint
   |
operational experience
   |
future evidence-driven improvement
```
