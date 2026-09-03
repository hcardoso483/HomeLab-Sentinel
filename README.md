# HomeLab Sentinel

> **One dashboard. Complete visibility.**

HomeLab Sentinel is an open-source, self-hosted platform designed to discover, understand, monitor, and help manage homelab infrastructure through a unified and modular architecture.

Rather than replacing proven open-source monitoring and infrastructure tools, HomeLab Sentinel integrates them behind a Sentinel-owned core that maintains infrastructure identity and state, coordinates providers, and exposes a consistent view of the homelab.

The project is currently in **alpha development**. Core platform foundations, automatic network discovery, Living Inventory, persistent device identity, Monitoring v1, Service Discovery v1, boot verification, and read-only dashboard integration are operational and have been tested against a real homelab.

---

## Current Status

**Version:** 0.1.0-alpha

HomeLab Sentinel has progressed from architectural foundations into an operational platform.

The current implementation can automatically discover devices, correlate observations into persistent identities, maintain a Living Inventory, derive monitoring and Service Discovery targets, collect real reachability evidence through Prometheus and Blackbox Exporter, discover network endpoints through provider-neutral Service Discovery, evaluate canonical device health, preserve monitoring and Service Discovery history, recover automatically after reboot, and expose canonical platform status through the Sentinel CLI and Core API.

### Implemented Platform Foundations

The following foundations have been implemented and regression-tested:

- Module Registry
- Module metadata and specification validation
- Capability-based provider discovery
- Provider Resolver
- User-selectable providers
- Configurable installation defaults
- Provider acquisition
- Deployment orchestration
- Dependency validation
- Module installation
- Module health checking
- Healthcheck retry and startup handling
- Module update lifecycle
- Safe module uninstall
- Persistent Docker volume preservation during uninstall
- Docker Compose based module deployment

The deployment lifecycle has been exercised with Prometheus, including installation, health verification, update, uninstall, persistent data preservation, and reinstallation.

### Discovery and Living Inventory

The Discovery and Living Inventory foundations are operational.

Current capabilities include:

- Automatic network discovery using a provider-neutral Discovery contract
- Configurable discovery scope
- Multi-pass discovery
- Validated discovery observations
- Observation correlation
- Persistent Sentinel-owned device identities
- MAC-aware identity correlation
- Stable identity across rediscovery and reboot
- Living Inventory persistence
- Discovery scheduling
- Shared runtime locking for inventory-mutating operations
- Discovery freshness and runtime status
- Regression and real-network testing

Discovery produces observations. Permanent infrastructure identity remains owned by the Sentinel Core.

### Monitoring v1 — Complete

Monitoring v1 is implemented, contract-tested, real-homelab tested, soak-tested, and reboot-proven.

Current capabilities include:

- Monitoring targets derived from Living Inventory identities
- Provider-neutral target derivation
- Capability-based monitoring provider resolution
- Prometheus as the current default monitoring provider
- Prometheus file-based target reconciliation
- Blackbox Exporter ICMP reachability probing
- Provider adapter boundary
- Sentinel-owned normalized monitoring observations
- Persistent monitoring evidence and history
- Evidence freshness evaluation
- Canonical health states:
  - `UNKNOWN`
  - `HEALTHY`
  - `DEGRADED`
  - `DOWN`
- Protection against false device-down conclusions when a provider fails
- Automatic monitoring reconciliation
- Automatic monitoring collection
- Shared runtime serialization with Discovery and verification
- CLI surfaces for:
  - Monitoring status
  - Provider resolution
  - Targets
  - Health
  - History
- Real device offline/recovery validation
- Unattended soak testing
- Autonomous restart and reboot recovery

Monitoring v1 reached its completed project checkpoint at commit:

```text
15bd0a9 Add Monitoring history CLI
```

### Service Discovery v1 — Complete

Service Discovery v1 is implemented, regression-tested, real-homelab tested, and reboot-proven.

Current capabilities include:

- Canonical targets derived from Living Inventory
- Provider-neutral Service Discovery orchestration
- nmap as the current Service Discovery provider
- Endpoint and open-port observation
- Canonical observation validation
- Persistent current and historical Service Discovery state
- `OBSERVED` and `STALE` endpoint semantics
- Preservation of previous positive evidence when an inspection is inconclusive
- Bounded multi-stage inspection and retry processing
- Automatic normal-sweep and retry scheduling
- Shared runtime locking with inventory-sensitive Sentinel operations
- CLI surfaces for status, services, and history
- Canonical platform-status and read-only Core API integration
- Per-target Homepage presentation through the restricted server-side API bridge
- Autonomous restart and reboot recovery

Endpoint evidence remains distinct from higher-level service or infrastructure classification. An open port alone is not treated as proof of a particular application or device function.

Service Discovery v1 reached its implementation checkpoint at commit:

```text
aff7d0f complete service discovery status and orchestration integration
```

Subsequent real-homelab and reboot validation confirmed autonomous recovery, scheduling, persistence, fresh evidence, and post-boot verification without manual service or container restarts.

### Platform Status and Self-Verification

HomeLab Sentinel also provides operational self-status and boot verification.

Implemented capabilities include:

- Core API
- Canonical structured platform status
- CLI platform status
- Inventory integrity reporting
- Discovery scheduler and freshness status
- Monitoring scheduler and evidence status
- Boot readiness verification
- Stable discovery-pass requirement during startup
- Post-boot verification
- Automatic systemd scheduling
- Sentinel service identity
- Clean autonomous recovery after reboot

The platform does not report itself ready until its required boot-readiness conditions have been satisfied.

### Dashboard Integration

Homepage is currently used as the first presentation provider.

Implemented integration includes:

- Homepage module deployment
- Persistent configuration
- Container health checking
- Sentinel status presentation
- Read-only access to canonical Sentinel status
- Per-target Service Discovery presentation
- A restricted server-side API bridge between Homepage and the loopback-bound Sentinel Core API

Homepage is a presentation layer. It does not calculate authoritative Sentinel health and does not query monitoring providers directly for Sentinel-owned meaning.

The long-term native Sentinel UI remains a future development goal.

### Registered and Operational Providers

Current provider/module work includes:

- **Prometheus** — monitoring provider
- **Blackbox Exporter** — internal reachability probe dependency used by the Prometheus monitoring implementation
- **Homepage** — dashboard/presentation provider
- **nmap** — current network discovery and Service Discovery provider

Provider-specific implementation is kept behind Sentinel contracts wherever practical so that the Core remains responsible for orchestration and authoritative state rather than provider-specific behavior.

### Still Under Development

Major v1 areas that remain include:

- Deeper device understanding and classification
- Higher-level service understanding and classification
- Host and infrastructure resource monitoring
- Container and virtual-machine monitoring
- Broader historical metrics
- Alerting and notifications
- Richer dashboard presentation
- Installation and configuration experience
- Additional providers and integrations

HomeLab Sentinel should still be considered **alpha development software**, not a finished monitoring distribution.

---

## Vision

Modern homelabs often rely on several excellent tools for monitoring, logging, discovery, dashboards, and alerting. While each tool is powerful, deploying and integrating them into a cohesive solution can be challenging.

HomeLab Sentinel aims to provide the intelligent layer connecting those components.

The long-term goal is to:

- Automatically discover devices on the network.
- Build and maintain a Living Inventory of the homelab.
- Detect running services and open ports.
- Monitor CPU, memory, storage, containers, virtual machines, applications, and network health.
- Collect historical infrastructure state and metrics.
- Generate meaningful alerts.
- Present infrastructure through a single unified dashboard.

The platform should require as little manual configuration as reasonably possible while preserving user control.

---

## Core Principles

### Automatic Discovery

If HomeLab Sentinel can safely determine something automatically, the user should not have to configure it manually.

### Understanding Before Monitoring

Monitoring is more valuable when Sentinel understands the infrastructure being monitored.

Discovery observations are correlated into Sentinel-owned identities before they become authoritative infrastructure state.

### Single Dashboard

Infrastructure information should ultimately be accessible through one consistent interface.

### Modular Architecture

Monitoring engines, dashboards, discovery components, and other providers should be replaceable without redesigning the core platform.

### Sentinel-Owned Meaning

External providers collect or expose evidence.

HomeLab Sentinel remains authoritative for infrastructure identity, correlation, health interpretation, platform state, and the meaning presented to users.

### User Choice

User-selected providers take priority. Sensible installation defaults provide a predictable starting point and recovery mechanism.

### Separation of Responsibilities

Discovery, inventory, identity, provider resolution, acquisition, deployment, monitoring, and presentation remain separate concerns with defined interfaces between them.

### Safe Lifecycle Management

Deployment operations should validate their inputs, preserve persistent data by default, verify service health, and provide actionable diagnostics when something fails.

### Open Source

The project is developed openly and is intended to benefit from community feedback and contributions.

### Beginner Friendly

HomeLab Sentinel aims to provide powerful infrastructure monitoring without requiring every user to become an expert in every underlying component.

### Production Mindset

Even during alpha development, the project favors reproducible deployments, explicit validation, useful failure messages, predictable behavior, safe failure semantics, documented architecture, and real-world verification.

---

## Architecture

HomeLab Sentinel uses a capability-driven modular architecture built around a Sentinel-owned Core.

A simplified operational flow is:

```text
Infrastructure
      |
      v
Discovery Provider
      |
      v
Validated Observations
      |
      v
Sentinel Core
      |
      +----> Identity Correlation
      |
      +----> Living Inventory
               |
        +------+------+
        |             |
        v             v
 Monitoring Targets  Service Discovery Targets
        |             |
        v             v
 Provider Resolver   Provider Resolver
        |             |
        v             v
 Monitoring Provider Service Discovery Provider
        |             |
        v             v
 Provider Evidence   Endpoint Evidence
        |             |
        v             v
 Monitoring Adapter  Validation / Persistence
        |             |
        v             v
 Canonical Monitoring Current Service State
 Observations         + Service History
        |
        v
 Sentinel Health Evaluation
        |
        +------+------+
               |
               v
          Core API / CLI
               |
               v
       Presentation Layer
```

Provider selection and deployment remain capability-driven.

A simplified provider deployment flow is:

```text
Requested Capability
        |
        v
Provider Resolver
        |
        v
Selected Provider
        |
        v
Provider Acquisition
        |
        v
Deployment Engine
        |
        v
Metadata / Dependency Validation
        |
        v
Module Deployment
        |
        v
Health Verification
```

This separation allows HomeLab Sentinel to support multiple implementations of the same capability without making provider-specific behavior authoritative inside the Core.

---

## Core Components

### Sentinel Core

The Sentinel Core owns authoritative HomeLab Sentinel state and orchestration.

Current responsibilities include:

- Infrastructure identity
- Living Inventory
- Observation correlation
- Provider resolution
- Monitoring orchestration
- Monitoring health evaluation
- Service Discovery orchestration and state
- Platform status
- Boot readiness
- Core API
- CLI status surfaces

### Module Registry

The Registry discovers module metadata and provides a central view of registered modules, capabilities, provider information, and provider entrypoints.

### Provider Resolver

The Provider Resolver determines which registered provider should satisfy a requested capability.

Explicit user configuration has priority. Installation defaults can be used when an explicit selection is not available.

### Provider Acquisition

The acquisition layer determines how a selected provider can be obtained and ensures required provider resources are available before deployment.

Docker image acquisition is currently supported.

### Deployment Engine

The Deployment Engine manages the module lifecycle.

Current lifecycle operations include:

```text
deploy
install
healthcheck
update
uninstall
```

Deployment includes metadata validation, dependency validation, Docker Compose execution, and module health verification.

Healthchecks support retries so that services which require startup time are not immediately treated as failed.

Uninstall operations preserve persistent Docker volumes by default.

### Discovery

Discovery providers observe infrastructure and return validated observations.

Discovery itself does not own permanent device identity.

### Living Inventory and Identity

The Living Inventory is the Sentinel-owned representation of discovered infrastructure.

Correlation converts observations into persistent identities and maintains continuity as devices are rediscovered or their observations change.

### Monitoring

Monitoring consumes canonical Living Inventory targets and provider evidence.

Providers perform monitoring work, while Sentinel owns normalized observations, persistence, freshness rules, health evaluation, and canonical health state.

### Service Discovery

Service Discovery consumes canonical Living Inventory targets and provider observations.

Providers perform endpoint inspection, while Sentinel owns validation, persistence, current and historical state, retry semantics, scheduling, and the meaning exposed through CLI, Core API, and presentation layers.

### Core API and CLI

Canonical Sentinel state is exposed through stable Core interfaces rather than requiring presentation layers to inspect internal databases, systemd state, provider APIs, or runtime files directly.

### Presentation

Presentation providers consume Sentinel-owned state.

Homepage currently provides the first read-only Sentinel status integration.

---

## Planned v1 Capabilities

### Service Understanding and Classification

Service Discovery v1 already provides canonical endpoint and open-port evidence.

Remaining higher-level capabilities include:

- Trusted service identification beyond raw endpoint evidence
- Docker host detection
- Proxmox detection
- NAS detection
- Home Assistant detection
- Web application discovery
- Infrastructure role and function classification

These capabilities should build on canonical Service Discovery evidence and Living Inventory identity rather than treating an open port alone as proof of a particular application or device role.

### Infrastructure Monitoring

Monitoring v1 establishes the provider-neutral monitoring foundation and reachability health model.

Future v1 monitoring coverage is intended to expand toward useful infrastructure results such as:

- CPU
- Memory
- Storage
- SMART disk health where practical
- Docker containers
- Virtual machines
- Services
- Network performance
- Historical metrics

### Alerts

Planned notification and alert integrations include:

- Email
- Discord
- Telegram
- Webhooks
- Infrastructure health notifications

### Dashboard

The unified interface is intended to progressively provide:

- Device inventory
- Service inventory
- Container status
- Resource utilization
- Alerts
- Historical trends
- Recent infrastructure changes

The current Homepage integration provides an initial read-only presentation layer while these capabilities are developed.

---

## Repository Structure

A simplified view of the current repository is:

```text
HomeLab-Sentinel/
├── api/
├── compose/
│   ├── core/
│   ├── discovery/
│   ├── infrastructure/
│   ├── logging/
│   ├── monitoring/
│   └── optional/
├── config/
│   ├── homepage/
│   └── sentinel/
├── core/
│   ├── acquisition/
│   ├── deployment/
│   ├── discovery/
│   ├── identity/
│   ├── inventory/
│   ├── lib/
│   ├── logs/
│   ├── monitoring/
│   ├── pipeline/
│   ├── resolver/
│   ├── service_discovery/
│   └── status/
├── docs/
├── installer/
├── registry/
├── scripts/
├── services/
├── templates/
├── tests/
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## Documentation

The repository contains detailed design, contract, and implementation documentation.

Important documents include:

- `docs/VISION.md` — project goals and long-term direction
- `docs/ARCHITECTURE.md` — high-level architecture
- `docs/SOFTWARE_ARCHITECTURE.md` — software architecture and subsystem responsibilities
- `docs/MODULE_SPECIFICATION.md` — module format and requirements
- `docs/REGISTRY.md` — Module Registry design
- `docs/PROVIDER_ARCHITECTURE.md` — provider selection, defaults, acquisition, and resolution
- `docs/DEPLOYMENT_ENGINE.md` — module deployment and lifecycle management
- `docs/DISCOVERY_CONTRACT.md` — Discovery responsibility and observation contract
- `docs/LIVING_INVENTORY.md` — Living Inventory behavior
- `docs/PERSISTENT_IDENTITY_CONTRACT.md` — persistent infrastructure identity semantics
- `docs/SERVICE_DISCOVERY_CONTRACT.md` — canonical Service Discovery responsibility and state contract
- `docs/MONITORING_CONTRACT.md` — canonical Monitoring v1 contract
- `docs/MONITORING_ORCHESTRATION_CONTRACT.md` — provider-neutral Monitoring orchestration
- `docs/MONITORING_PROVIDER_ADAPTER.md` — monitoring provider adapter boundary
- `docs/MONITORING_PROVIDER_TARGETS.md` — provider target derivation contract
- `docs/PROMETHEUS_REACHABILITY_PROBE.md` — Prometheus/Blackbox reachability integration
- `docs/BOOT_READINESS_CONTRACT.md` — startup readiness semantics
- `docs/CORE_API.md` — Core API behavior
- `docs/ENGINEERING.md` — engineering principles
- `docs/DEVELOPMENT_LOG.md` — development history and implementation notes

These documents evolve alongside the implementation.

---

## Project Philosophy

HomeLab Sentinel is not intended to reinvent the excellent monitoring software that already exists.

Instead, it provides an intelligent integration and orchestration layer around proven open-source technologies.

The platform should determine what infrastructure exists, establish persistent Sentinel-owned identity, select appropriate providers, automate their deployment and configuration where possible, interpret provider evidence safely, and present the resulting information through a consistent experience.

The objective is to reduce complexity without removing flexibility or user control.

---

## Project Origins

HomeLab Sentinel began as an idea during a series of design sessions between the project creator and ChatGPT.

The project creator defined the vision, goals, priorities, testing environment, and desired user experience, with a strong emphasis on automatic discovery, simplicity, modularity, and creating a platform that homelab users can realistically deploy and understand.

The technical architecture, implementation guidance, deployment strategy, Linux and Docker design, and documentation have been developed collaboratively during those sessions with assistance from ChatGPT.

The repository documents that collaborative development process as the project evolves in public.

---

## Contributing

HomeLab Sentinel is still in alpha development, and contributions, suggestions, bug reports, testing, and architectural feedback are welcome.

When contributing, please keep the project's core principles in mind:

- Prefer modular solutions over provider-specific core logic.
- Preserve user choice.
- Avoid unnecessary configuration.
- Keep Sentinel authoritative for Sentinel-owned meaning.
- Fail safely and provide actionable diagnostics.
- Protect persistent user data.
- Keep implementation and documentation aligned.
- Validate behavior before declaring a capability complete.

---

## License

HomeLab Sentinel is released under the MIT License.

---

## Acknowledgements

HomeLab Sentinel is the result of a collaborative design and development process.

The project vision, direction, priorities, real-world testing, and long-term goals are driven by the repository owner.

The technical architecture, implementation guidance, software design, deployment strategy, troubleshooting, and much of the documentation have been developed collaboratively with assistance from OpenAI's ChatGPT.

The project is being developed transparently with the goal of eventually welcoming broader participation from the open-source and homelab communities.
