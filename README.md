# HomeLab Sentinel

> **One dashboard. Complete visibility.**

HomeLab Sentinel is an open-source, self-hosted platform designed to discover, monitor, and help manage homelab infrastructure through a unified and modular architecture.

Rather than replacing proven open-source monitoring and infrastructure tools, HomeLab Sentinel aims to integrate them into a cohesive platform that is easier to deploy, configure, maintain, and understand.

The project is currently in **early alpha development**. Its core architecture and module lifecycle are functional, while network discovery, deeper monitoring integrations, alerting, and the unified dashboard experience continue to be developed.

---

## Current Status

**Version:** 0.1.0-alpha

HomeLab Sentinel has progressed beyond the initial architecture and design phase. A functional core platform is now being built and tested against real modules.

### Implemented

The current foundation includes:

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

### Registered Modules

The repository currently includes module definitions for:

- **Prometheus** — metrics collection and monitoring provider
- **Homepage** — dashboard provider

Additional providers and modules can be added through the modular architecture as development progresses.

### Under Development

Major areas still being developed include:

- Network discovery
- Device inventory
- Service discovery
- Host and infrastructure monitoring
- Automated monitoring configuration
- Alerting
- Historical infrastructure state
- Dashboard integration
- Installation and configuration experience

HomeLab Sentinel should currently be considered **development software**, not a finished monitoring distribution.

---

## Vision

Modern homelabs often rely on several excellent tools for monitoring, logging, discovery, dashboards, and alerting. While each tool is powerful, deploying and integrating them into a cohesive solution can be challenging.

HomeLab Sentinel aims to provide the intelligent layer connecting those components.

The long-term goal is to:

- Automatically discover devices on the network.
- Build and maintain a living inventory of the homelab.
- Detect running services and open ports.
- Monitor CPU, memory, storage, containers, virtual machines, and applications.
- Collect historical metrics.
- Generate meaningful alerts.
- Present infrastructure through a single unified dashboard.

The platform should require as little manual configuration as reasonably possible while preserving user control.

---

## Core Principles

### Automatic Discovery

If HomeLab Sentinel can safely determine something automatically, the user should not have to configure it manually.

### Single Dashboard

Infrastructure information should ultimately be accessible through one consistent interface.

### Modular Architecture

Monitoring engines, dashboards, discovery components, and other providers should be replaceable without redesigning the core platform.

### User Choice

User-selected providers take priority. Sensible installation defaults provide a predictable starting point and recovery mechanism.

### Separation of Responsibilities

Discovery, provider resolution, acquisition, deployment, monitoring, and presentation remain separate concerns with defined interfaces between them.

### Safe Lifecycle Management

Deployment operations should validate their inputs, preserve persistent data by default, verify service health, and provide actionable diagnostics when something fails.

### Open Source

The project is developed openly and is intended to benefit from community feedback and contributions.

### Beginner Friendly

HomeLab Sentinel aims to provide powerful infrastructure monitoring without requiring every user to become an expert in every underlying component.

### Production Mindset

Even during early development, the project favors reproducible deployments, explicit validation, useful failure messages, predictable behavior, and documented architecture.

---

## Architecture

HomeLab Sentinel uses a capability-driven modular architecture.

Modules declare what they provide through metadata. Core components determine which provider should satisfy a requested capability and how that provider should be acquired and deployed.

A simplified deployment flow is:

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

This separation allows the platform to support multiple implementations of the same capability without embedding provider-specific decisions into the core engine.

---

## Core Components

### Module Registry

The Registry discovers module metadata and provides a central view of registered modules, capabilities, and provider information.

### Provider Resolver

The Provider Resolver determines which registered module should provide a requested capability.

Explicit user configuration has priority. Installation defaults can be used when an explicit selection is not available.

### Provider Acquisition

The acquisition layer determines how a selected provider can be obtained and ensures required provider resources are available before deployment.

Docker image acquisition is currently supported.

### Deployment Engine

The Deployment Engine manages the basic module lifecycle.

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

---

## Module System

Modules live beneath the `compose/` hierarchy and describe themselves through `metadata.yml`.

Current modules include:

```text
compose/
├── core/
│   └── homepage/
│       └── metadata.yml
│
└── monitoring/
    └── prometheus/
        └── metadata.yml
```

Module metadata describes information such as:

- Module identity
- Version
- Category
- Capabilities
- Dependencies
- Acquisition source
- Compose definition
- Healthcheck
- Lifecycle scripts

The core platform should avoid module-specific deployment logic whenever a behavior can be expressed through the module specification.

---

## Planned Capabilities

### Network Discovery

Planned capabilities include:

- Automatic IP discovery
- Device identification
- Hostname resolution
- MAC vendor detection
- Operating system detection where practical

### Service Discovery

Planned capabilities include:

- Open port detection
- Service identification
- Docker host detection
- Proxmox detection
- NAS detection
- Home Assistant detection
- Web application discovery

### Monitoring

The long-term monitoring layer is intended to cover:

- CPU
- Memory
- Storage
- SMART disk health
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

The unified interface is intended to eventually provide:

- Device inventory
- Service inventory
- Container status
- Resource utilization
- Alerts
- Historical trends
- Recent infrastructure changes

---

## Repository Structure

A simplified view of the current repository is:

```text
HomeLab-Sentinel/
├── compose/
│   ├── core/
│   └── monitoring/
│
├── config/
│   └── sentinel/
│
├── core/
│   ├── acquisition/
│   ├── deployment/
│   ├── lib/
│   └── resolver/
│
├── docs/
├── registry/
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## Documentation

The repository contains detailed design and implementation documentation.

Important documents include:

- `docs/VISION.md` — project goals and long-term direction
- `docs/ARCHITECTURE.md` — high-level architecture
- `docs/SOFTWARE_ARCHITECTURE.md` — software architecture and subsystem responsibilities
- `docs/MODULE_SPECIFICATION.md` — module format and requirements
- `docs/REGISTRY.md` — Module Registry design
- `docs/PROVIDER_ARCHITECTURE.md` — provider selection, defaults, acquisition, and resolution
- `docs/DEPLOYMENT_ENGINE.md` — module deployment and lifecycle management
- `docs/ENGINEERING.md` — engineering principles
- `docs/DEVELOPMENT_LOG.md` — development history and implementation notes

These documents evolve alongside the implementation.

---

## Project Philosophy

HomeLab Sentinel is not intended to reinvent the excellent monitoring software that already exists.

Instead, it provides an intelligent integration and orchestration layer around proven open-source technologies.

The platform should determine what infrastructure exists, select appropriate monitoring components, automate their deployment and configuration where possible, and present the resulting information through a consistent experience.

The objective is to reduce complexity without removing flexibility or user control.

---

## Project Origins

HomeLab Sentinel began as an idea during a series of design sessions between the project creator and ChatGPT.

The project creator defined the vision, goals, priorities, testing environment, and desired user experience, with a strong emphasis on automatic discovery, simplicity, modularity, and creating a platform that homelab users can realistically deploy and understand.

The technical architecture, implementation guidance, deployment strategy, Linux and Docker design, and documentation have been developed collaboratively during those sessions with assistance from ChatGPT.

The repository documents that collaborative development process as the project evolves in public.

---

## Contributing

HomeLab Sentinel is still in early development, and contributions, suggestions, bug reports, testing, and architectural feedback are welcome.

When contributing, please keep the project's core principles in mind:

- Prefer modular solutions over provider-specific core logic.
- Preserve user choice.
- Avoid unnecessary configuration.
- Fail safely and provide actionable diagnostics.
- Protect persistent user data.
- Keep implementation and documentation aligned.

---

## License

HomeLab Sentinel is released under the MIT License.

---

## Acknowledgements

HomeLab Sentinel is the result of a collaborative design and development process.

The project vision, direction, priorities, real-world testing, and long-term goals are driven by the repository owner.

The technical architecture, implementation guidance, software design, deployment strategy, troubleshooting, and much of the documentation have been developed collaboratively with assistance from OpenAI's ChatGPT.

The project is being developed transparently with the goal of eventually welcoming broader participation from the open-source and homelab communities.
