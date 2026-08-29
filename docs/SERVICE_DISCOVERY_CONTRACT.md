# HomeLab Sentinel Service Discovery Contract

## Status

Contract version: 1.0

Service Discovery v1 defines how HomeLab Sentinel discovers network
endpoints and identifies services associated with existing Living
Inventory entities.

This contract is provider-neutral.

A provider such as Nmap may implement Service Discovery, but
provider-specific behavior must not define Sentinel Core semantics.

---

# Purpose

Host Discovery answers:

> What devices are present?

Persistent Identity and Living Inventory answer:

> Which Sentinel entity represents each device?

Service Discovery answers:

> What network endpoints and services are observable on those devices?

Service Discovery therefore operates on existing Sentinel entities.
It does not create or determine permanent device identity.

---

# Architectural Boundary

The intended flow is:

```text
Living Inventory
        |
        | entity_id
        | current.ip_addresses[]
        v
Service Discovery Core
        |
        | canonical targets
        v
Provider Resolver
        |
        v
Service Discovery Provider
        |
        | provider-specific evidence
        v
Provider Normalization
        |
        v
Canonical Service Observations
        |
        v
Validation
        |
        v
Persistence
        |
        +--> Current Service State
        |
        +--> Service History
```

Service Discovery consumes Sentinel-owned Living Inventory state.

It must not independently reconstruct device identity from network
addresses, MAC addresses, hostnames, or provider-specific evidence.

---

# Relationship to Discovery Contract 1.0

Discovery Contract 1.0 defines basic host discovery only.

Service Discovery is a separate capability.

The existing host-discovery contract and validator must not be expanded
or weakened merely to accept Service Discovery observations.

Host Discovery remains responsible for observing hosts.

Service Discovery remains responsible for observing endpoints and
services associated with already-known hosts.

---

# Service Discovery Targets

A Service Discovery target originates from the Living Inventory.

At minimum, target derivation requires:

```text
schema_version
entity_id
entity_type
current addresses
eligibility
```

Current addresses must come from the canonical Living Inventory current
state.

Historical addresses must not be reused as current Service Discovery
targets merely because they appeared in previous observations.

An entity without a usable current address is not eligible for active
network Service Discovery.

Such an entity must remain represented in Sentinel state rather than
having an address invented from historical context.

---

# Multiple Current Addresses

A Living Inventory entity may have more than one current network
address.

Service Discovery must not assume that inspecting one address is
equivalent to inspecting every current address.

Where authorized and reachable, each current address may represent a
distinct Service Discovery target.

This allows Sentinel to correctly represent devices with multiple
interfaces, networks, address families, or service-binding behavior.

---

# Endpoint Model

A network endpoint is identified by the tuple:

```text
entity_id
address
protocol
port
```

The Sentinel entity remains the stable device identity.

The network address describes where the endpoint was observed.

The protocol and port describe the network endpoint.

The service field describes evidence about what appears to be listening
on that endpoint.

An address must not become a substitute for Sentinel entity identity.

---

# Non-Default Ports

Service Discovery must never assume that a service uses its conventional
or default port.

Examples include:

```text
tcp/22    -> SSH
tcp/2222  -> SSH

tcp/80    -> HTTP
tcp/8080  -> HTTP
tcp/3000  -> HTTP-like application
```

The observed protocol and port are factual endpoint evidence.

Service identification is separate evidence describing the service
believed to be associated with that endpoint.

A service may therefore be identified on any valid observed port.

---

# Service Identification

An open endpoint does not require successful service identification.

Sentinel must be able to represent:

```text
open endpoint
service unknown
```

without discarding the endpoint.

Service identification may be derived from provider evidence such as:

- protocol negotiation
- banners
- fingerprints
- application responses
- provider-specific service detection

Provider-specific evidence must be normalized before becoming canonical
Sentinel state.

Service identification must not be treated as permanent device identity.

---

# Canonical Service Observation

A normalized Service Discovery observation must contain enough
information to associate the evidence with an existing Sentinel entity
and network endpoint.

The minimum canonical fields are:

```text
schema_version
entity_id
provider
observed_at
address
protocol
port
state
service
```

Additional normalized fields may be introduced where they provide
provider-independent value.

Provider-specific details may be retained as raw evidence but must not
be required for Sentinel Core to understand the canonical observation.

---

# Field Semantics

## schema_version

Version of the canonical Service Discovery observation contract.

Service Discovery v1 uses:

```text
1.0
```

## entity_id

Existing Sentinel Living Inventory entity associated with the target.

The provider must not assign this value independently.

## provider

Provider that produced the observation.

Example:

```text
nmap
```

## observed_at

Timezone-aware timestamp representing when the endpoint evidence was
observed.

## address

Current network address inspected for the entity.

IPv4 and IPv6 must be representable by the contract.

## protocol

Transport protocol associated with the endpoint.

Initial implementations may support TCP only.

The contract must not prevent future protocol support.

## port

Observed network port.

The port must be an integer in the valid transport-port range.

## state

Observed endpoint state.

Service Discovery v1 must at minimum represent:

```text
open
```

Additional states may be introduced when their semantics are explicitly
defined.

## service

Normalized service identification when available.

The value may be null or unknown when an endpoint is open but the
service cannot be identified reliably.

---

# Provider Responsibilities

A Service Discovery provider is responsible for:

- inspecting authorized Service Discovery targets
- producing provider-specific endpoint evidence
- reporting observed protocol and port information
- reporting service-identification evidence where available
- exposing its functionality through the provider framework

A provider may use any suitable implementation technology.

The first provider may use Nmap.

---

# Provider Prohibitions

A Service Discovery provider must not:

- create Sentinel device entities
- assign permanent Sentinel device identities
- write directly to Sentinel persistence
- modify Living Inventory state
- reconstruct identity from historical addresses
- assume default service ports
- contain Sentinel Core persistence policy
- contain Sentinel Core lifecycle policy
- require Sentinel Core to parse provider-native output directly

Provider-native output must cross a normalization boundary.

---

# Sentinel Core Responsibilities

Sentinel Core is responsible for:

- deriving targets from Living Inventory
- validating target structure
- resolving the selected Service Discovery provider
- consuming normalized provider observations
- validating canonical observations
- associating observations with existing entity IDs
- persistence
- current-state derivation
- historical queries
- lifecycle semantics
- scheduling
- safe failure behavior
- exposing canonical results to CLI and API consumers

---

# Persistence

Service Discovery observations are Sentinel-owned evidence.

They must not be stored as if they were Host Discovery observations.

Service Discovery persistence must preserve:

- entity association
- endpoint evidence
- observation time
- provider
- service-identification evidence
- sufficient history to explain current state

Historical evidence must remain distinguishable from current endpoint
state.

The persistence model must not require IP addresses to become permanent
device identities.

---

# Current State and History

Sentinel must distinguish:

```text
current service state
```

from:

```text
historical service observations
```

Historical endpoints may remain queryable after an address, port, or
service is no longer current.

Historical evidence must not automatically become current state.

---

# Absence Semantics

Failure to observe a previously known endpoint once must not
automatically mean that the service has disappeared.

Possible causes include:

- packet loss
- temporary device load
- provider failure
- scan interruption
- firewall behavior
- network isolation
- target unreachability
- transient service restart

Service lifecycle decisions must therefore distinguish:

```text
observed open
not observed
provider failure
target unavailable
stale evidence
```

before declaring that a previously observed service is no longer
current.

The exact lifecycle policy may be implemented incrementally, but a
single missed observation must not silently delete historical service
evidence.

---

# Failure Semantics

Provider or orchestration failure must not be converted into false
service disappearance.

If the provider fails, Sentinel must preserve the distinction between:

```text
service not observed
```

and:

```text
service discovery did not complete successfully
```

Sentinel must prefer UNKNOWN or stale state over an unsupported negative
conclusion.

---

# Topology Independence

Service Discovery must remain topology-independent.

It must not assume:

- a single subnet
- a specific gateway
- a particular VLAN layout
- direct Layer-2 access to every device
- a specific private address range
- a specific router or switch vendor

Service Discovery operates only against addresses and scopes Sentinel is
authorized and technically able to inspect.

Firewall and routing policy remain authoritative.

Sentinel must not attempt to bypass network isolation.

---

# Provider Independence

The Service Discovery contract must not depend on Nmap semantics.

Nmap may be the first provider because it is already available in the
HomeLab Sentinel platform and is suitable for network endpoint
discovery.

Future providers must be able to produce equivalent canonical Service
Discovery observations without changing Sentinel Core semantics.

---

# Relationship to Device Classification

Service Discovery observes endpoints and service evidence.

Higher-level understanding may later infer device or application roles
such as:

- Docker host
- Proxmox host
- NAS
- Home Assistant
- web application
- media server
- database server

Those classifications must consume canonical Sentinel evidence rather
than being hard-coded into a Service Discovery provider.

For example:

```text
Service Discovery
        |
        +--> tcp/8006 open
        +--> HTTPS-like service evidence
        |
        v
Understanding / Classification
        |
        +--> possible Proxmox host
```

Classification is therefore downstream of endpoint observation.

---

# Relationship to Monitoring

Service Discovery and Monitoring answer different questions.

Service Discovery asks:

> What endpoints and services are observable?

Monitoring asks:

> What is the health of a known target?

Service Discovery may later provide service targets to Monitoring.

Monitoring must not be required to perform Service Discovery itself.

Likewise, Service Discovery must not determine health using Monitoring
semantics.

---

# Initial v1 Scope

Service Discovery v1 initially targets useful network service results.

The first implementation should provide:

- target derivation from Living Inventory
- open TCP port discovery
- basic service identification where evidence is available
- provider-neutral normalized observations
- canonical validation
- persistence
- current service visibility
- service observation history
- CLI visibility
- automatic scheduling
- safe provider-failure behavior
- restart and reboot recovery

UDP discovery may be added later because its observation semantics and
scan cost differ significantly from TCP.

Advanced application classification is not required for the first
Service Discovery v1 implementation.

---

# CLI Direction

Service Discovery v1 should eventually expose canonical CLI surfaces
similar in spirit to:

```text
hls service-discovery targets
hls service-discovery status
hls service-discovery services
hls service-discovery history <entity-id>
```

Exact command names may be finalized during implementation.

The CLI must expose Sentinel-owned canonical state rather than raw
provider output.

---

# Completion Criteria

Service Discovery v1 is complete when all of the following have been
demonstrated:

1. Targets are derived from canonical Living Inventory current state.
2. Historical addresses are not reused as current targets.
3. Existing Sentinel entity IDs remain authoritative.
4. Multiple current addresses can be represented safely.
5. A provider can inspect eligible targets.
6. Open TCP endpoints can be discovered.
7. Non-default service ports are represented correctly.
8. Open endpoints remain valid observations even when service
   identification is unknown.
9. Provider output is normalized before entering Sentinel Core.
10. Canonical observations are validated.
11. Service evidence is persisted against existing Sentinel entities.
12. Current state can be distinguished from historical evidence.
13. A single missed observation does not automatically erase a
    previously observed service.
14. Provider failure does not become false service disappearance.
15. Canonical service state is queryable through Sentinel-owned CLI
    surfaces.
16. Service Discovery can run automatically without conflicting with
    Discovery, Monitoring, or Verification.
17. Restart and reboot behavior have been demonstrated on the real
    HomeLab Sentinel deployment.
18. Regression tests cover the defined contract invariants.

---

# v1 Philosophy

Service Discovery v1 is intended to establish a useful, reliable
service-understanding capability.

It does not need to solve every possible application fingerprint,
protocol, device classification, or network topology.

The v1 goal is:

> Reliably discover what network endpoints are present on known Sentinel
> entities, preserve that evidence, and make it useful to the rest of
> HomeLab Sentinel.

Further classification, richer fingerprints, additional protocols,
performance optimization, and presentation refinements may evolve in
later versions.
