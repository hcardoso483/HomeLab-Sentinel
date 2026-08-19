# HomeLab Sentinel Inventory Model

**Inventory Model Version:** 1.0
**Status:** Draft

---

## Overview

The HomeLab Sentinel Inventory is the authoritative Core representation of known infrastructure.

Discovery providers produce observations.

Observations are evidence about infrastructure at a particular point in time. They do not directly create permanent device identities.

The Sentinel Core is responsible for preserving observations, correlating them, maintaining persistent entities, and deriving current inventory state.

Conceptually:

```text
Discovery Providers
        |
        v
Validated Observations
        |
        v
Observation Store
        |
        v
Correlation
        |
        v
Living Inventory
        |
        +---- Core API
        |
        +---- Core Events
        |
        v
Sentinel UI
```

---

## Core Principles

The Inventory Model follows these principles:

- Observations are evidence, not identity.
- Providers never assign permanent Sentinel identities.
- No single observed attribute automatically defines permanent identity.
- Historical observations are preserved independently from current state.
- Correlation belongs to the Sentinel Core.
- Inventory state must be explainable from underlying observations.
- Unknown information must remain unknown rather than being guessed.
- Provider-specific data must not leak into Core identity rules.
- Identity must survive ordinary network changes where sufficient evidence exists.
- Ambiguous evidence must not silently merge unrelated entities.

---

## Observation

An observation is a validated statement produced by a provider about infrastructure at a particular time.

For example:

```json
{
  "schema_version": "1.0",
  "provider": "nmap",
  "discovery_method": "host-discovery",
  "discovered_at": "2026-08-19T09:29:24Z",
  "ip_addresses": ["192.168.1.20"],
  "mac_address": "BC:24:11:59:68:6A",
  "hostname": null
}
```

This means that the provider observed those attributes.

It does not mean that any individual attribute is the permanent identity of the device.

Observations are immutable historical evidence.

Once accepted into the Observation Store, an observation should not be rewritten to reflect later state.

---

## Observation Store

The Observation Store preserves validated observations received by the Sentinel Core.

Its responsibilities include:

- Preserving historical discovery evidence.
- Recording when observations occurred.
- Recording which provider produced each observation.
- Providing evidence to the correlation layer.
- Supporting historical queries.
- Supporting change detection.
- Supporting diagnostics and explainability.

The Observation Store is not the Living Inventory.

It represents what Sentinel observed over time rather than only what Sentinel currently believes to be true.

---

## Entity

An entity is a persistent Sentinel representation of a piece of infrastructure.

Initial entity types may include:

```text
device
```

Future entity types may include:

```text
host
virtual-machine
container
network-device
service
storage-system
network
```

Entity types may evolve as additional providers and infrastructure integrations are introduced.

Every entity receives a Sentinel-managed stable identifier.

For example:

```text
device_id: dev-7f8c2a...
```

The identifier is assigned by the Sentinel Core.

It must not be derived directly from:

- IP address
- MAC address
- Hostname
- Provider-specific identifier
- Network location

These attributes may contribute evidence to correlation, but they are not themselves the Sentinel identity.

---

## Identity

Permanent identity belongs to the Sentinel Core.

A device may change observable attributes during its lifetime.

Examples include:

- DHCP address changes.
- Static IP changes.
- Movement between VLANs.
- Replacement or addition of network interfaces.
- Hostname changes.
- Multiple IP addresses.
- IPv4 and IPv6 coexistence.
- Virtual machine migration.
- Container recreation.
- Wi-Fi MAC randomization.

Therefore:

```text
IP address != permanent identity
MAC address != permanent identity
hostname   != permanent identity
provider ID != permanent identity
```

A persistent Sentinel entity represents the Core's correlated understanding of infrastructure across observations.

---

## Correlation

Correlation is the process of determining whether an observation belongs to an existing entity or represents previously unknown infrastructure.

Conceptually:

```text
New Observation
       |
       v
Correlation Engine
       |
       +---- strong match ----> Existing Entity
       |
       +---- uncertain -------> Preserve as unresolved
       |
       +---- no match --------> New Entity
```

Correlation may use multiple pieces of evidence.

Potential evidence includes:

- MAC addresses.
- IP address history.
- Hostnames.
- Provider identifiers.
- Device serial numbers.
- Hardware UUIDs.
- Hypervisor identifiers.
- Switch forwarding information.
- DHCP information.
- ARP or neighbor information.
- Service fingerprints.
- User-confirmed relationships.

Not all evidence has equal reliability.

Correlation rules must therefore support confidence and precedence rather than treating every matching attribute as equivalent.

---

## Correlation Safety

Incorrectly merging two different devices is potentially more damaging than temporarily keeping one device as two unresolved entities.

When evidence is ambiguous, Sentinel should prefer preserving uncertainty.

The Core must not silently merge entities solely because they temporarily share:

- An IP address.
- A hostname.
- A service.
- A network location.

Strong identifiers may increase correlation confidence, but no provider is permitted to bypass Core correlation policy.

Future versions may introduce explicit correlation confidence levels and user-assisted reconciliation.

---

## Living Inventory

The Living Inventory represents Sentinel's current understanding of infrastructure.

It is derived from correlated observations and other authoritative Core information.

A device inventory record may conceptually contain:

```text
device_id
display_name
device_type
status

first_seen
last_seen

ip_addresses
mac_addresses
hostnames

services
network_relationships

monitoring_state
health_state

observation_count
```

This is a conceptual model.

The persistence implementation is intentionally not defined by Inventory Model 1.0.

---

## Current State and History

Current state and historical evidence are separate concepts.

For example:

```text
Observation History

09:00  192.168.1.20
09:10  192.168.1.20
09:20  192.168.1.20
10:30  192.168.20.20
            |
            v
      Correlation
            |
            v
Current Inventory

Device: dev-...
Current IP: 192.168.20.20
Previous IP: 192.168.1.20
First seen: 09:00
Last seen: 10:30
```

Historical evidence must not be destroyed merely because current state changes.

---

## Attribute Provenance

Inventory attributes should remain traceable to their evidence where practical.

For example, Sentinel may know a hostname because:

```text
Nmap observed it
```

while another attribute may originate from:

```text
Proxmox API
```

and another from:

```text
SNMP
```

The Core should preserve sufficient provenance to explain why it believes an inventory attribute is true.

This supports:

- Diagnostics.
- Conflict resolution.
- User trust.
- Correlation decisions.
- Future Sentinel UI detail views.

---

## Conflicting Observations

Different providers may report conflicting information.

For example:

```text
Provider A: hostname = server01
Provider B: hostname = proxmox01
```

The Core must not arbitrarily discard conflicting evidence.

Conflict resolution may consider:

- Provider authority.
- Observation freshness.
- Correlation confidence.
- User-defined values.
- Attribute-specific precedence rules.

User-defined authoritative values should take priority over automatically inferred presentation values where appropriate.

Historical observations remain unchanged even when the current inventory chooses one value as authoritative.

---

## Inventory and Providers

Providers interact with the Inventory only through Core-defined interfaces.

Providers may:

- Produce observations.
- Supply provider-specific identifiers as evidence.
- Request Core-supported inventory information where permitted.

Providers must not:

- Create permanent Sentinel device identities directly.
- Modify inventory persistence directly.
- Merge entities.
- Delete historical observations.
- Define global correlation policy.

---

## Inventory and Monitoring

Discovery establishes that infrastructure exists and provides identity evidence.

Monitoring provides continuing operational state.

These responsibilities are related but separate.

Conceptually:

```text
Discovery ---------+
                  |
                  v
            Inventory
                  ^
                  |
Monitoring --------+
```

Monitoring information may enrich an existing entity with:

- Health.
- Availability.
- CPU usage.
- Memory usage.
- Storage usage.
- Network traffic.
- Service state.
- Historical metrics.

Monitoring data must not redefine permanent identity independently of Core correlation.

---

## Inventory and Sentinel UI

The Sentinel UI consumes inventory state exposed by the Sentinel Core.

It does not reconstruct inventory from provider data.

For example:

```text
Homelab
  |
  +-- Devices: 37 online
        |
        v
     Devices
        |
        v
     Device
        |
        +-- Current state
        +-- Addresses
        +- Services
        +-- Health
        +- Metrics
        +-- Events
        +-- Observation history
```

This allows progressive disclosure from summary information to detailed evidence while keeping the Sentinel Core authoritative.

---

## Persistence Independence

Inventory Model 1.0 defines semantics rather than storage technology.

The architecture must not depend on a particular persistence implementation.

Possible implementations may include:

- SQLite.
- PostgreSQL.
- Other structured persistence systems.

Storage technology may evolve without changing provider contracts or Sentinel identity semantics.

---

## Design Rules

HomeLab Sentinel Inventory must follow these rules:

- Observations are immutable evidence.
- Observations do not directly equal devices.
- Permanent IDs are assigned by the Sentinel Core.
- IP addresses are not permanent identities.
- MAC addresses are not permanent identities.
- Hostnames are not permanent identities.
- Correlation uses evidence rather than assumptions.
- Ambiguous observations must not be silently merged.
- Historical observations must be preserved.
- Current state must remain distinguishable from history.
- Inventory attributes should retain provenance where practical.
- Providers must remain independent from inventory persistence.
- Sentinel UI must consume authoritative Core inventory state.
- Persistence technology must remain replaceable.

---

## Relationship to Discovery

The Discovery Scope model defines where discovery may occur.

The Discovery Contract defines how discovery observations are represented.

The Inventory Model defines how validated observations become persistent Core knowledge.

```text
Discovery Scope
      |
      v
Discovery Provider
      |
      v
Discovery Contract
      |
      v
Validated Observation
      |
      v
Inventory Model
```

---

## Status

Inventory Model Version: 1.0

Status: Draft
