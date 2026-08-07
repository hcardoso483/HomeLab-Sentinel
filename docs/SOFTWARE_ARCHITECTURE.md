# HomeLab Sentinel Software Architecture

**Version:** 1.0 (Draft)

---

# Purpose

This document defines the software architecture of HomeLab Sentinel.

Unlike the project vision or high-level architecture documents, this specification describes how HomeLab Sentinel is built internally and establishes the engineering principles that guide every implementation decision.

This document is considered the architectural contract of the project.

Whenever a new feature is proposed, it should comply with the principles defined here rather than introducing exceptions or special cases.

---

# Architectural Principles

The following principles are considered non-negotiable.

## 1. Modularity First

Every feature in HomeLab Sentinel shall exist as an independent module.

Modules must be self-contained and independently installable, maintainable, testable and removable.

No module should require modifications to the Sentinel Core.

---

## 2. Core Orchestrates, Modules Implement

The Sentinel Core is responsible for orchestration.

Modules are responsible for implementation.

The Core shall never contain module-specific logic.

The Core should not know what Prometheus, Grafana, Loki, Home Assistant or any other module is.

Instead, it communicates with modules through a common contract.

---

## 3. Automation Before Configuration

If HomeLab Sentinel can detect or configure something automatically, the user should never be required to perform that step manually.

Automation is preferred over documentation.

Good defaults are preferred over complex configuration.

---

## 4. Convention Over Complexity

Every module follows the same directory layout, lifecycle and metadata format.

Consistency is more valuable than flexibility.

---

## 5. Installer Is Part of the Platform

The installer is not a utility script.

It is a core subsystem responsible for deploying, configuring, validating and updating HomeLab Sentinel.

Every architectural decision must consider how the installer interacts with it.

---

## 6. Technology Independence

The architecture describes responsibilities, not technologies.

Prometheus, Grafana, Docker and other technologies are implementation choices.

They may change in future without changing the architecture.

---

# System Layers

HomeLab Sentinel is organised into five logical layers.

```
User Interface
        │
Sentinel Core
        │
Module Framework
        │
Modules
        │
Infrastructure
```

Each layer has clearly defined responsibilities.

---

# Layer Responsibilities

## User Interface

Responsible for presenting information to users.

Examples include:

* Web dashboard
* Device inventory
* Alerts
* Reports
* Administration

The User Interface never communicates directly with infrastructure components.

All communication occurs through the Sentinel Core.

---

## Sentinel Core

The Sentinel Core is the central orchestration engine.

Responsibilities include:

* REST API
* Authentication
* Inventory management
* Rules engine
* Scheduling
* Event processing
* Module management
* Health monitoring

The Core coordinates modules but never implements their functionality.

---

## Module Framework

The Module Framework provides common services used by every module.

Responsibilities include:

* Module discovery
* Registry
* Dependency resolution
* Lifecycle management
* Configuration loading
* Health monitoring
* Version management

This layer allows modules to remain independent.

---

## Modules

Modules provide functionality.

Examples:

* Monitoring
* Discovery
* Logging
* Notifications
* Integrations
* Backup
* Security

Every module follows the Module Specification.

---

## Infrastructure

Infrastructure includes the operating system and runtime environment.

Examples:

* Linux
* Docker
* Networking
* Storage
* Hardware

Infrastructure details should never leak into higher architectural layers.

---

# Module Architecture

Every module is an independent software package.

A module may provide:

* Services
* Dashboards
* Discovery engines
* Rules
* APIs
* Documentation
* Configuration
* Scripts

Modules communicate through the Sentinel Core and never directly depend on one another unless explicitly declared.

---

# Module Contract

Every module must provide:

* Metadata
* Configuration
* Documentation
* Health checks
* Lifecycle scripts
* Optional deployment definition

Modules may also expose capabilities.

Examples:

* metrics
* dashboards
* discovery
* logging
* alerts
* integrations

Capabilities allow the Core to discover what a module provides without knowing its implementation.

---

# Module Lifecycle

Every module follows the same lifecycle.

```
Install
Configure
Start
Health Check
Register
Running
Update
Restart
Remove
```

Every lifecycle stage should be repeatable and recoverable.

---

# Registry

The registry is the authoritative source of installed modules.

The Sentinel Core never scans arbitrary directories looking for functionality.

Instead, it queries the registry.

The registry stores:

* Module identity
* Version
* Dependencies
* Status
* Capabilities
* Health information

---

# Deployment Engine

The Deployment Engine is responsible for:

* Detecting supported operating systems
* Installing prerequisites
* Resolving dependencies
* Deploying modules
* Running health checks
* Performing upgrades
* Removing modules safely

The Deployment Engine should be idempotent.

Running the installer multiple times should never damage an existing installation.

---

# Communication

Modules communicate through well-defined interfaces.

Direct coupling between modules should be avoided.

The preferred communication methods are:

* REST API
* Internal events
* Shared inventory
* Registry services

---

# Security

Security is considered part of the architecture.

Every module should:

* Run with minimum required privileges.
* Avoid privileged containers whenever possible.
* Validate configuration before startup.
* Expose health information.
* Fail safely.

---

# Extensibility

HomeLab Sentinel is designed to support future expansion.

Future extensions may include:

* Plugin SDK
* Community module repository
* Native services
* AI-assisted diagnostics
* Mobile applications
* Multi-node deployments

These features should integrate through the existing module framework rather than introducing architectural exceptions.

---

# Directory Structure

```
app/
├── core/
├── modules/
├── registry/
├── installer/
├── services/
├── api/
├── config/
├── docs/
└── scripts/
```

Every component has a single responsibility.

---

# Final Principle

The architecture of HomeLab Sentinel is intentionally conservative.

New features should be added by extending the platform rather than modifying existing architectural rules.

Long-term maintainability is considered more important than short-term implementation speed.

If a proposed feature requires breaking these architectural principles, the feature should be redesigned rather than the architecture.
