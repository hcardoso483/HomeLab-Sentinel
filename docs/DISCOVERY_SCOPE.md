# HomeLab Sentinel Discovery Scope

**Scope Model Version:** 1.0  
**Status:** Draft

---

## Overview

HomeLab Sentinel must not assume a specific network topology.

The platform must be able to operate across homelabs using different:

- IPv4 networks
- IPv6 networks
- Subnets
- VLANs
- Routed networks
- Gateways
- Service ports
- Network architectures

No discovery provider or Core component may hard-code a network such as:

```text
192.168.1.0/24
```

Discovery operates on explicit discovery scopes.

---

## Core Principle

A discovery scope defines a network target that HomeLab Sentinel may consider for discovery.

A scope is independent from any specific discovery provider.

For example:

```text
192.168.1.0/24
192.168.0.0/24
10.20.0.0/24
2001:db8:1234::/64
```

The same scope may be processed by different discovery providers.

---

## Scope Sources

Discovery scopes may originate from multiple sources.

Initial sources may include:

- User configuration
- Local network interfaces
- Local routing tables

Future sources may include:

- Routers
- Firewalls
- Managed switches
- VLAN configuration
- VPN integrations
- SDN controllers
- Cloud network integrations

Scope detection does not imply authorization to actively scan the scope.

---

## Detected and Authorized Scopes

HomeLab Sentinel distinguishes between:

```text
Detected Scope
```

and:

```text
Authorized Discovery Scope
```

A detected scope represents a network that Sentinel knows exists.

An authorized scope represents a network that Sentinel is permitted to actively discover.

This distinction prevents Sentinel from automatically scanning networks merely because they appear in a routing table.

Examples may include:

- Work VPN networks
- Guest networks
- Upstream provider networks
- Remote routed networks
- Networks intentionally isolated from active discovery

---

## Discovery Scope Record

Scope Model 1.0 defines the following conceptual record:

```yaml
id: lan-primary
target: 192.168.1.0/24
type: network
source: user
authorized: true
enabled: true
```

Future implementations may add additional fields.

---

## Scope Fields

### id

A stable machine-readable identifier for the discovery scope.

### target

The network target represented by the scope.

Examples:

```text
192.168.1.0/24
192.168.1.20
192.168.1.20-192.168.1.40
10.10.0.0/16
2001:db8::/64
```

### type

Describes the scope type.

Initial values may include:

```text
network
host
range
```

Future values may include:

```text
vlan
interface
provider-derived
```

### source

Identifies how Sentinel learned about the scope.

Initial values may include:

```text
user
interface
route
```

Future values may include:

```text
router
switch
firewall
vpn
integration
```

### authorized

Determines whether active discovery is permitted for the scope.

Detected scopes must not automatically become authorized.

### enabled

Determines whether the scope is currently eligible for discovery scheduling.

An authorized scope may still be temporarily disabled.

---

## Provider Independence

Discovery providers must not define network topology.

Providers receive targets from the Sentinel Core.

For example:

```text
Sentinel Core
    |
    | target: 10.20.0.0/24
    v
Nmap Provider
```

The Nmap provider does not need to know whether the target represents:

- A server VLAN
- A camera VLAN
- An IoT network
- A routed subnet
- A traditional flat LAN

It only performs discovery against the target it receives.

---

## VLANs and Routed Networks

VLAN segmentation must not require changes to the discovery contract.

If Sentinel has permitted network access to a VLAN or routed network, that network may be represented as a discovery scope.

Example:

```text
VLAN 10  Servers   10.10.10.0/24
VLAN 20  Cameras   10.10.20.0/24
VLAN 30  IoT        10.10.30.0/24
VLAN 40  Guests    10.10.40.0/24
```

Sentinel may discover each authorized scope independently.

Firewall and routing policy remain authoritative.

Sentinel must not attempt to bypass network isolation.

---

## Service Ports

Network discovery must not assume services use default ports.

Future service discovery may observe endpoints represented by:

```text
address
protocol
port
service
```

Example:

```text
192.168.10.50:8006  Proxmox
192.168.10.20:3000  Dashboard
192.168.20.15:554   RTSP
```

Service discovery is outside Discovery Contract 1.0 but must follow the same topology-independent principle.

---

## Discovery Flow

The intended architecture is:

```text
Network Environment
        |
        +-- Interfaces
        +-- Routes
        +-- User configuration
        +-- Router providers
        +-- Switch providers
        |
        v
Scope Detection
        |
        v
Discovery Scopes
        |
        +-- detected
        +-- authorized
        +-- enabled
        |
        v
Discovery Scheduler
        |
        v
Discovery Provider
        |
        v
Normalized Observation
        |
        v
Contract Validation
        |
        v
Observation Store
        |
        v
Correlation
        |
        v
Living Inventory
```

---

## Relationship to Discovery Contract

The Discovery Scope model defines where discovery may occur.

The Discovery Contract defines how discovery observations are represented.

These are separate responsibilities.

```text
Discovery Scope
      |
      v
Discovery Provider
      |
      v
Discovery Contract Record
```

---

## Design Rules

HomeLab Sentinel discovery must follow these rules:

- No hard-coded subnets.
- No hard-coded gateways.
- No hard-coded VLAN identifiers.
- No assumption of a single network.
- No assumption of default service ports.
- Scope detection must be separate from authorization.
- Providers must remain topology-independent.
- Network isolation must be respected.
- User-defined topology always takes priority over inferred topology.

---

## Status

Discovery Scope Model Version: 1.0

Status: Draft
