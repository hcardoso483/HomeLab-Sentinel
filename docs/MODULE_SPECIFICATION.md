# HomeLab Sentinel Module Specification

**Version:** 1.0 (Draft)

---

# Purpose

This document defines the standard that every HomeLab Sentinel module must follow.

The objective is to ensure consistency across the platform, simplify maintenance, improve troubleshooting, and allow the Sentinel Core and Deployment Engine to manage all modules through a common interface.

If a component does not follow this specification, it is **not considered a HomeLab Sentinel module**.

---

# Design Goals

Every module must be:

* Self-contained
* Independently installable
* Independently removable
* Independently testable
* Independently updateable
* Independently documented

Modules should never depend on implementation details of other modules.

---

# Standard Directory Layout

Every module must follow the same structure.

```text
module-name/
├── metadata.yml
├── compose.yml
├── docs.md
├── config/
├── scripts/
│   ├── install.sh
│   ├── update.sh
│   ├── uninstall.sh
│   └── healthcheck.sh
└── assets/
```

---

# Required Files

## metadata.yml

Defines the module identity and capabilities.

Required fields include:

* id
* name
* version
* category
* description
* author
* license
* dependencies
* capabilities
* ports
* volumes
* status

---

## compose.yml

Defines how the module is deployed.

Modules that do not require containers may omit this file.

---

## docs.md

Explains:

* Purpose
* Configuration
* Ports
* Dependencies
* Troubleshooting
* Upgrade notes

---

## config/

Contains configuration files used by the module.

The installer may generate or modify these files during deployment.

---

## scripts/

Contains lifecycle scripts.

### install.sh

Installs or prepares the module.

---

### update.sh

Safely updates the module.

---

### uninstall.sh

Removes the module while preserving data unless explicitly instructed otherwise.

---

### healthcheck.sh

Returns the operational state of the module.

Possible results:

* Healthy
* Warning
* Critical

---

## assets/

Optional directory containing:

* Icons
* Dashboards
* Templates
* Static resources

---

# Metadata Standard

Every module must provide a metadata file similar to:

```yaml
id: prometheus

name: Prometheus

version: 0.1.0

category: monitoring

description: Metrics collection engine.

author: HomeLab Sentinel

license: Apache-2.0

status: enabled

dependencies:
  - docker

capabilities:
  - metrics

ports:
  - 9090

volumes:
  - prometheus-data
```

---

# Module Categories

Current categories include:

* monitoring
* discovery
* logging
* infrastructure
* integrations
* notifications
* optional

Additional categories may be introduced as the project evolves.

---

# Capabilities

Capabilities describe what a module provides rather than how it is implemented.

Examples:

* metrics
* dashboards
* discovery
* inventory
* alerts
* logging
* visualization
* integration
* backup
* security

The Sentinel Core interacts with capabilities instead of module names whenever possible.

---

# Module Lifecycle

Every module follows the same lifecycle.

```text
Install
    ↓
Configure
    ↓
Start
    ↓
Health Check
    ↓
Register
    ↓
Running
    ↓
Update
    ↓
Restart
    ↓
Remove
```

The Deployment Engine is responsible for executing lifecycle stages.

---

# Dependency Management

Modules declare their dependencies through `metadata.yml`.

The Deployment Engine resolves dependencies before installation.

Circular dependencies are not permitted.

---

# Health Monitoring

Every module must expose a health status.

Health checks should verify:

* Service availability
* Configuration validity
* Required resources
* Connectivity to dependent services

Health information is reported to the Sentinel Core.

---

# Configuration Principles

Configuration should favour:

* Automatic detection
* Sensible defaults
* Minimal user interaction

Manual configuration should only be required when automatic configuration is impossible.

---

# Logging

Modules should:

* Produce meaningful logs
* Avoid excessive verbosity
* Clearly identify errors
* Support troubleshooting

---

# Security

Modules should:

* Use the minimum required privileges
* Avoid privileged containers whenever possible
* Validate configuration before startup
* Never expose secrets through logs

---

# Versioning

Modules follow Semantic Versioning.

Example:

* 1.0.0
* 1.2.1
* 2.0.0

The module version is independent of the HomeLab Sentinel platform version.

---

# Future Compatibility

This specification is intended to support future module types, including:

* Native services
* Docker containers
* External integrations
* Community plugins
* Dashboard packs
* Rule packs

The specification should evolve without breaking existing modules whenever possible.

---

# Final Principle

A HomeLab Sentinel module is a self-contained component that provides one or more capabilities through a standardized structure and lifecycle.

Consistency across modules is considered more important than individual implementation preferences.
