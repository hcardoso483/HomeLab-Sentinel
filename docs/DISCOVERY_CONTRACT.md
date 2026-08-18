# HomeLab Sentinel Discovery Contract

**Contract Version:** 1.0  
**Status:** Draft

---

## Overview

The HomeLab Sentinel Discovery Contract defines the normalized interface between discovery providers and the Sentinel Core.

Discovery providers may use different tools, protocols, and techniques internally.

Provider-specific output must not leak into the Sentinel Core.

Instead, every discovery provider translates its results into the common HomeLab Sentinel discovery format defined by this contract.

The relationship is:

```text
Network / Environment
        |
        v
Discovery Provider
        |
        | provider-specific discovery
        v
Normalization Boundary
        |
        v
Sentinel Discovery Records
        |
        v
Sentinel Core
        |
        v
Inventory
```

---

## Design Principles

### Provider Independence

The Sentinel Core must not depend on Nmap, SNMP, ARP, or any other specific discovery implementation.

Discovery providers are replaceable.

### Observation Before Identification

A discovery result represents an observation of a host.

It does not by itself establish a permanent device identity.

Device correlation and identity management belong to the Sentinel Core inventory layer.

### Transparency

Discovery results must identify which provider produced the observation and how it was discovered.

### No Invented Data

Providers must not guess missing values.

Unknown information must be represented explicitly as `null` or an empty collection where appropriate.

### Extensibility

The contract must allow future discovery methods and additional fields without requiring provider-specific logic in the Sentinel Core.

---

## Discovery Record

Contract version 1.0 defines the following normalized host discovery record:

```json
{
  "schema_version": "1.0",
  "provider": "nmap",
  "discovery_method": "host-discovery",
  "discovered_at": "2026-08-18T15:30:00Z",
  "ip_addresses": [
    "192.168.1.20"
  ],
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "hostname": "pihole"
}
```

---

## Fields

### schema_version

Required.

Identifies the version of the HomeLab Sentinel Discovery Contract used by the record.

Example:

```text
1.0
```

### provider

Required.

Identifies the module that produced the discovery record.

Example:

```text
nmap
```

### discovery_method

Required.

Describes the general discovery technique represented by the observation.

Initial value:

```text
host-discovery
```

Additional methods may be introduced in future contract versions.

### discovered_at

Required.

UTC timestamp describing when the host observation was made by the discovery provider.

Timestamps must use ISO 8601 format.

### ip_addresses

Required.

A collection of IP addresses observed for the host.

The collection may contain IPv4 or IPv6 addresses.

Addresses must be unique. Array order must not be treated as significant.

At least one address must be present for Contract 1.0 network host observations.

### mac_address

Optional.

MAC address observed for the host.

If unavailable, the value must be:

```json
null
```

### hostname

Optional.

Hostname reported or resolved during discovery.

If unavailable, the value must be:

```json
null
```

---

## Provider Responsibilities

A discovery provider is responsible for:

- Performing discovery using its own implementation.
- Parsing provider-specific results.
- Normalizing results into this contract.
- Producing valid discovery records.
- Preserving unknown values rather than guessing them.
- Reporting discovery failures clearly.

A discovery provider must not:

- Write directly to the Sentinel inventory.
- Assign permanent device identities.
- Contain Sentinel Core inventory logic.
- Require the Sentinel Core to understand provider-specific output.

---

## Core Responsibilities

The Sentinel Core is responsible for consuming normalized discovery records.

Future Core responsibilities may include:

- Validation.
- Correlation.
- Device identity.
- Inventory persistence.
- Change detection.
- Historical observations.
- Scheduling discovery.
- Triggering additional discovery or monitoring strategies.

These responsibilities are outside the discovery provider.

---

## Contract 1.0 Scope

Discovery Contract 1.0 intentionally covers only basic host discovery.

It does not define:

- Port discovery.
- Service detection.
- Operating system detection.
- Device classification.
- Monitoring configuration.
- Permanent device identity.
- Inventory persistence.

These capabilities will be added through later contracts or higher architectural layers.

---

## Initial Provider

The first planned provider for the `discovery` capability is Nmap.

The initial Nmap implementation will perform host discovery only.

Provider-specific Nmap output will be normalized into Discovery Contract 1.0 records before being exposed to the Sentinel Core.

---

## Future Compatibility

Future versions may introduce additional observation types and fields.

Consumers should use `schema_version` to determine compatibility.

New fields should be introduced in a way that preserves provider independence and avoids implementation-specific assumptions.

---

## Status

Discovery Contract Version: 1.0

Status: Draft
