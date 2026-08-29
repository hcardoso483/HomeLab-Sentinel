# HomeLab Sentinel Architecture

## Overview

HomeLab Sentinel is designed as a modular platform that automatically discovers, understands, monitors, and helps manage homelab infrastructure.

Rather than replacing existing open-source software, HomeLab Sentinel integrates proven technologies behind a Sentinel-owned Core.

The goal is to provide a unified experience with minimal manual configuration while preserving clear ownership of infrastructure identity, state, and health.

---

# Design Principles

1. Automatic discovery first
2. Understanding before monitoring
3. Sentinel-owned infrastructure identity
4. Provider-neutral Core architecture
5. One dashboard
6. Modular architecture
7. Easy installation
8. Intelligent defaults
9. Safe failure semantics
10. Open-source and community driven

---

# High Level Architecture

```text
                         HomeLab Sentinel
                                |
              +-----------------+-----------------+
              |                                   |
              v                                   v
       Discovery Engine                  Configuration / Registry
              |                                   |
              v                                   |
     Validated Observations                       |
              |                                   |
              +-----------------+-----------------+
                                |
                                v
                         Sentinel Core
                                |
                    +-----------+-----------+
                    |                       |
                    v                       v
             Identity Correlation     Provider Resolution
                    |
                    v
              Living Inventory
                    |
          +---------+---------+
          |                   |
          v                   v
     Monitoring          Future Core
      Targets            Capabilities
          |
          v
   Monitoring Provider
          |
          v
    Provider Evidence
          |
          v
    Provider Adapter
          |
          v
 Canonical Observations
          |
          v
  Health Evaluation
          |
          +-------------------+
                              |
                              v
                       Canonical Status
                              |
                     +--------+--------+
                     |                 |
                     v                 v
                   CLI             Core API
                                       |
                                       v
                              Presentation Layer
                                       |
                                       v
                                    Homepage
```

The Sentinel Core remains authoritative for infrastructure identity, Living Inventory state, canonical monitoring observations, health interpretation, and platform status.

Providers perform specialized work behind defined contracts. Provider-specific behavior must not become authoritative Sentinel meaning.

---

# Core Components

## Discovery Engine

Responsible for:

- Discovery scope orchestration
- Discovery provider execution
- Network and host observation collection
- Multi-pass discovery
- Discovery record validation
- Forwarding validated observations to the Sentinel Core
- Scheduled discovery execution
- Discovery runtime and freshness reporting

The Discovery Engine produces observations.

It does not assign permanent device identities or write provider-specific results directly into Living Inventory.

The current discovery provider is nmap.

---

## Identity Correlation

Identity Correlation converts validated discovery observations into stable Sentinel-owned infrastructure identities.

Responsibilities include:

- Correlating repeated observations
- Maintaining permanent `entity_id` values
- Using authoritative identity evidence where available
- Preserving identity across rediscovery
- Preserving identity across restart and reboot
- Preventing discovery providers from becoming identity authorities

Persistent identity is intentionally separate from provider-specific observations.

---

## Living Inventory

The Living Inventory is the Sentinel Core representation of discovered infrastructure.

Responsibilities include:

- Maintaining permanent device identities
- Tracking current device observations
- Associating IP addresses, MAC addresses, hostnames, services, and other discovered attributes
- Preserving infrastructure state
- Supporting monitoring target derivation
- Supporting future device classification and service understanding

Discovery observations do not become permanent infrastructure identities until processed through the Core correlation and inventory layers.

The Living Inventory is the authoritative source for infrastructure entities consumed by downstream Sentinel capabilities.

---

## Provider Registry and Resolver

The Registry exposes registered capabilities, providers, metadata, and provider entrypoints.

The Provider Resolver determines which provider should satisfy a requested capability.

Selection rules include:

- Explicit user configuration has priority
- Installation defaults provide predictable fallback behavior
- Providers are resolved by capability
- Core orchestration should remain independent of provider implementation

This allows providers to be replaced without redesigning Sentinel Core semantics.

---

## Monitoring

Monitoring v1 consumes canonical targets derived from the Living Inventory.

The current Monitoring architecture is:

```text
Living Inventory
       |
       v
Target Derivation
       |
       v
Provider Resolution
       |
       v
Target Reconciliation
       |
       v
Monitoring Provider
       |
       v
Provider Evidence
       |
       v
Provider Adapter
       |
       v
Canonical Monitoring Observation
       |
       v
Persistence / History
       |
       v
Health Evaluation
```

Monitoring v1 currently provides reachability health.

The Prometheus provider is the current default implementation.

Prometheus uses Blackbox Exporter for ICMP reachability probing.

Sentinel does not treat Prometheus or Blackbox Exporter state as authoritative device health directly. Provider evidence crosses the Monitoring adapter boundary and becomes a validated Sentinel-owned observation before health evaluation.

Canonical Monitoring health states are:

```text
UNKNOWN
HEALTHY
DEGRADED
DOWN
```

Monitoring also defines freshness semantics and protects against provider or adapter failures being incorrectly interpreted as device failure.

Monitoring v1 has been regression-tested, real-homelab tested, soak-tested, and reboot-proven.

Future infrastructure monitoring may extend this architecture to:

- CPU
- RAM
- Storage
- SMART health
- Docker containers
- Virtual machines
- Services
- Network performance
- Historical metrics

These extensions should reuse the established provider-neutral Monitoring architecture rather than bypass it.

---

## Monitoring Scheduling and Reconciliation

Monitoring execution is automatically scheduled.

The current architecture separates:

- Target reconciliation
- Provider collection
- Health evaluation
- Discovery
- Post-boot verification

Inventory-mutating and inventory-dependent operations use a shared runtime lock where required to prevent unsafe concurrent access.

Scheduling policy is owned by the platform while provider-specific reconciliation remains behind provider boundaries.

---

## Core API

The Core API exposes canonical Sentinel-owned state to presentation and integration layers.

The API is not intended to make presentation components reconstruct Sentinel meaning from internal implementation details.

Presentation components should not need to directly inspect:

- SQLite databases
- systemd state
- boot marker files
- Prometheus APIs
- Docker runtime state

when equivalent canonical state is available through Sentinel Core interfaces.

The current Core API is bound to loopback for isolation.

---

## Platform Status and Self-Verification

HomeLab Sentinel monitors its own operational readiness.

Current platform status includes:

- Installation readiness
- Service identity
- Core API health
- Discovery scheduler state
- Discovery freshness
- Inventory readiness and integrity
- Monitoring scheduler state
- Monitoring reconciliation
- Monitoring provider
- Monitoring collection
- Monitoring evidence freshness
- Post-boot verification
- Overall platform readiness

Boot readiness requires:

- Core API readiness
- Inventory readiness
- Stable discovery passes

Post-boot verification confirms that the platform recovered correctly after startup.

The platform should fail safely rather than report readiness before required conditions are satisfied.

---

## Dashboard and Presentation

Presentation is intentionally separated from authoritative Sentinel state.

The current presentation provider is Homepage.

Homepage currently provides:

- General homelab dashboard functionality
- Read-only Sentinel platform status
- Access to canonical status through a restricted API bridge

Homepage does not calculate authoritative Sentinel health.

It does not query Prometheus directly to determine Sentinel-owned health semantics.

The long-term native Sentinel UI remains a future goal.

Presentation layers should consume stable Sentinel Core interfaces so that they can evolve independently of Discovery, Inventory, Monitoring, and provider implementations.

---

## Alerts

Alerting remains planned.

Future notification providers may include:

- Email
- Discord
- Telegram
- Webhooks

Alerting should consume canonical Sentinel state and events rather than independently determining infrastructure health.

---

# Current Architecture Status

| Component | Current implementation | Status |
| --- | --- | :---: |
| Module Registry | Custom | ✅ Implemented |
| Provider Resolver | Custom | ✅ Implemented |
| Deployment Engine | Custom | ✅ Implemented |
| Dashboard Provider | Homepage | ✅ Operational |
| Discovery Engine | Custom + nmap provider | ✅ Operational |
| Persistent Identity | Sentinel Core | ✅ Operational |
| Living Inventory | Sentinel Core | ✅ Operational |
| Core API | Sentinel Core | ✅ Operational |
| Platform Status | Sentinel Core | ✅ Operational |
| Boot / Self Verification | Sentinel Core + systemd | ✅ Operational |
| Monitoring v1 | Sentinel Core | ✅ Complete |
| Monitoring Provider | Prometheus | ✅ Operational |
| Reachability Probe | Blackbox Exporter | ✅ Operational |
| Service Discovery | TBD | ⏳ Planned |
| Host Resource Monitoring | TBD | ⏳ Planned |
| Container Monitoring | TBD | ⏳ Planned |
| Virtual Machine Monitoring | TBD | ⏳ Planned |
| Alerting | TBD | ⏳ Planned |
| Historical Metrics | TBD | ⏳ Planned |
| Native Sentinel UI | Custom | 🔵 Future |

`Complete` is reserved for a capability that has satisfied its defined v1 completion criteria.

`Operational` means the capability is implemented and functioning in the current real deployment but has not necessarily been declared complete against a dedicated v1 completion contract.

`Implemented` means the platform foundation exists and is exercised by the current system.

---

# Current Operational Flow

The implemented end-to-end infrastructure flow is:

```text
Network
   |
   v
nmap
   |
   v
Discovery Observations
   |
   v
Validation
   |
   v
Identity Correlation
   |
   v
Living Inventory
   |
   v
Monitoring Target Derivation
   |
   v
Provider Resolver
   |
   v
Prometheus Target Reconciliation
   |
   v
Prometheus
   |
   v
Blackbox Exporter
   |
   v
Reachability Evidence
   |
   v
Prometheus Monitoring Adapter
   |
   v
Canonical Monitoring Observations
   |
   +------> Monitoring History
   |
   v
Health Evaluation
   |
   v
Canonical Platform Status
   |
   +------> hls CLI
   |
   +------> Core API
                 |
                 v
              Homepage
```

This flow has been exercised against the real homelab and has demonstrated autonomous recovery after reboot.

---

# Planned v1 Capability Areas

The original project direction still includes several capabilities that are not yet implemented.

## Service Discovery

Planned areas include:

- Open port detection
- Service identification
- Docker host detection
- Proxmox detection
- NAS detection
- Home Assistant detection
- Web application discovery

## Infrastructure Monitoring

The Monitoring v1 foundation exists.

Additional useful infrastructure evidence may include:

- CPU
- Memory
- Storage
- SMART disk health where practical
- Docker containers
- Virtual machines
- Services
- Network performance
- Historical metrics

## Alerts

Planned areas include:

- Infrastructure health notifications
- Email
- Discord
- Telegram
- Webhooks

## Unified Presentation

The current Homepage integration is the first presentation layer.

Future v1 presentation work may expose:

- Living Inventory
- Device health
- Service inventory
- Container and VM status
- Resource utilization
- Alerts
- Historical trends
- Recent infrastructure changes

UI refinement and a native Sentinel UI belong to later development unless required by a future v1 contract.

---

# Project Philosophy

If HomeLab Sentinel can safely detect something automatically, the user should not have to configure it manually.

Automatic discovery is the foundation of the platform.

Everything downstream should build upon Sentinel-owned infrastructure identity and Living Inventory rather than independently rediscovering authoritative state.

Providers collect evidence or perform specialized work.

Sentinel interprets that evidence and owns the meaning presented to users.

No component shall rely on hard-coded filesystem paths to locate providers or modules where Registry-based discovery is available.

Architecture should favor safe, explainable behavior over convenient shortcuts.
