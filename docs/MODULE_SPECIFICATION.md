# HomeLab Sentinel Module Specification

**Specification Version:** 1.2
**Status:** Approved

---

# Overview

A HomeLab Sentinel module is a self-contained component that provides a specific capability to the HomeLab Sentinel platform.

Modules are designed to be:

- Discoverable
- Deployable
- Maintainable
- Testable
- Replaceable
- Independently documented

The module system is the foundation of the HomeLab Sentinel modular architecture.

The core platform should interact with modules through well-defined contracts rather than module-specific implementation logic.

---

# Design Principles

Every module MUST be:

- Self-describing
- Independently identifiable
- Independently testable
- Independently maintainable
- Independently documented
- Discoverable by the Registry
- Deployable through the Deployment Engine

Modules should not require core platform code to contain module-specific implementation logic.

---

# Module Architecture

Every module follows a common structure.

Example:

```text
compose/
└── monitoring/
    └── prometheus/
        ├── compose.yml
        ├── metadata.yml
        ├── docs.md
        ├── config/
        │   └── prometheus.yml
        ├── assets/
        └── scripts/
            ├── install.sh
            ├── update.sh
            ├── uninstall.sh
            └── healthcheck.sh

Not every module requires every directory or file.

The required elements are defined below.

Module Identity

Every module MUST have a unique id.

Example:

id: prometheus

The module ID:

Must be unique.
Must be stable.
Must not change between installations.
Is used by the Registry.
Is used by the Deployment Engine.
Is used by automation and scripts.

Recommended format:

lowercase
lowercase-with-hyphens

Examples:

prometheus
node-exporter
home-assistant
docker-monitor
Metadata

Every module MUST contain:

metadata.yml

A module MUST provide compose.yml when Docker Compose is required for its deployment.

The metadata file is the authoritative definition of the module.

The Registry indexes module metadata.

The Deployment Engine consumes module metadata.

Other Sentinel components may consume metadata where appropriate.

## Specification Version

Every module SHOULD declare the version of the HomeLab Sentinel Module Specification it was written against.

Example:

spec_version: "1.2"

The specification version is independent from the module's own version.

This allows the Registry and Deployment Engine to identify compatibility requirements when the specification evolves.

Specification Versions

Specification 1.0 defines the original module metadata format.

Specification 1.1 introduces the structured capability format:

capabilities:
  provides:
    - metrics
    - monitoring

Modules using Specification 1.0 MAY use the legacy capability format:

capabilities:
  - metrics
  - monitoring

The Registry SHOULD support the legacy format during the Specification 1.1 transition period.

Modules written against Specification 1.1 SHOULD use the structured capability format.

Specification 1.2 introduces structured dependency declarations for platform and host-level requirements while preserving compatibility with legacy dependency lists.


Required Metadata

The following fields are required:

id:
name:
version:
category:
description:
status:

Example:

id: prometheus
name: Prometheus
version: "0.1.0"
category: monitoring
description: Time-series metrics collection and storage engine.
status: enabled
Optional Metadata

Modules MAY provide additional metadata.

Supported fields include:

spec_version:
display_name:
author:
license:
homepage:
documentation:
compose:
healthcheck:
install:
update:
uninstall:
dependencies:
capabilities:
ports:
volumes:
tags:

Modules do not need to declare optional fields that do not apply to them.

Metadata Field Definitions
id

Unique machine-readable module identifier.

Required.

name

Human-readable module name.

Required.

display_name

Optional user-facing name.

Useful when the technical module name differs from the name displayed in the dashboard.

version

Module version.

Required.

The version identifies the module definition and deployment package.

Semantic versioning is recommended.

Example:

0.1.0
1.0.0
2.1.3
category

Defines the module's functional category.

Required.

Initial categories:

core
monitoring
discovery
infrastructure
logging
optional

Additional categories may be introduced in future versions.

description

Short description of the module.

Required.

The description should explain the module's primary purpose.

status

Defines the module's availability state.

Required.

Supported values are:

enabled
disabled
experimental
deprecated

Module definition status and runtime health are separate concepts.

author

Optional module author or organization.

license

Software license associated with the module.

homepage

Official project homepage.

documentation

Path to module documentation.

Example:

documentation: docs.md
compose

Path to the Docker Compose definition.

Example:

compose: compose.yml

A module using Docker Compose should declare its Compose definition here.

healthcheck

Path to the module healthcheck script.

Example:

healthcheck: scripts/healthcheck.sh

A module that represents a continuously running service SHOULD provide a healthcheck.

Modules that do not represent a continuously running service MAY omit a healthcheck.

When a healthcheck is declared, the Registry and Deployment Engine should validate that the referenced file exists.

A healthcheck should verify actual service availability whenever practical.

The expected result is:

0 = healthy
non-zero = unhealthy
install

Optional module-specific installation script.

Example:

install: scripts/install.sh

The primary installation mechanism remains the HomeLab Sentinel Deployment Engine.

Module-specific scripts should only contain logic that cannot reasonably be handled by the core Deployment Engine.

update

Optional module-specific update script.

Example:

update: scripts/update.sh
uninstall

Optional module-specific uninstall script.

Example:

uninstall: scripts/uninstall.sh

Uninstall procedures must take persistent data into consideration.

Removing a module should not automatically destroy user data unless explicitly intended and documented.

Dependencies

Modules MAY declare dependencies.

Specification 1.0 and Specification 1.1 modules MAY use the legacy list format:

dependencies:

  - docker

Specification 1.2 introduces structured dependency declarations.

Example:

dependencies:

  platform:
    - docker

  host:
    - command: nmap
      packages:
        apt: nmap
      required: true

The structured dependency format separates platform requirements from host operating-system dependencies.

Platform Dependencies

Platform dependencies describe runtime, infrastructure, or host capabilities required by a module.

Initial platform dependency identifiers may include:

docker

network

storage

database

module


Platform dependencies are validated by the Deployment Engine.

Host Dependencies

Host dependencies describe executable commands that must be available on the HomeLab Sentinel host.

A host dependency MAY declare:

command

packages

required

The command field identifies the executable that Sentinel must verify.

Example:

command: nmap

The packages field maps supported package managers to the package that provides the required command.

Example:

packages:

  apt: nmap

Additional package managers may be supported in future implementations.

The required field determines whether failure to satisfy the dependency must stop deployment.

If required is omitted, it defaults to true.

Automatic Dependency Acquisition

Required host dependencies SHOULD be acquired automatically and non-interactively when all of the following conditions are true:

- The required command is not already available.
- The host uses a supported package manager.
- The dependency declares a package for that package manager.
- Sentinel has sufficient privileges to perform the installation safely.

After acquisition, the Deployment Engine MUST verify that the required command is available before continuing.

If automatic acquisition fails, or the dependency cannot be satisfied safely, deployment MUST stop and provide actionable diagnostics.

Module runtime scripts MUST NOT install their own operating-system dependencies.

Dependency acquisition and verification belong to the Deployment Engine.

Backward Compatibility

The Deployment Engine MUST continue to accept legacy dependency lists used by Specification 1.0 and Specification 1.1 modules.

For example:

dependencies:

  - docker

Legacy dependency declarations are interpreted according to their established platform dependency semantics.

Validation

Dependencies are validated before deployment.

The Deployment Engine is responsible for dependency validation and acquisition.

Circular module dependencies are not permitted.

The Deployment Engine must detect dependency cycles before deployment and report them as validation errors.

Dependency definitions should remain declarative.

Capabilities

Modules MAY declare capabilities.

Capabilities describe functionality that a module provides to the HomeLab Sentinel ecosystem.

Specification 1.1 uses the structured capability format:

capabilities:
  provides:
    - metrics
    - monitoring

The `provides` field contains a list of machine-readable capability identifiers.

Capability identifiers SHOULD use lowercase letters, numbers, and hyphens.

Multiple modules MAY provide the same capability.

This allows multiple implementations of the same functionality to coexist.

For example:

Prometheus:

capabilities:
  provides:
    - metrics
    - monitoring

VictoriaMetrics:

capabilities:
  provides:
    - metrics
    - monitoring

The Registry may use capability declarations to identify modules that can act as providers for a requested capability.

Capability declarations do not determine which provider is selected.

Provider selection and default providers are installation-level configuration and MUST NOT be declared by individual modules.

Initial capabilities include:

dashboard
metrics
monitoring
discovery
logging
alerting
storage
automation

Legacy Capability Format

Modules written against Specification 1.0 MAY use the legacy format:

capabilities:
  - metrics
  - monitoring

The Registry SHOULD continue to recognize the legacy format during the Specification 1.1 transition period.

Legacy capability declarations are treated as equivalent to the `provides` list for compatibility purposes.

New modules written against Specification 1.1 SHOULD use the structured `capabilities.provides` format.

Ports

Modules MAY declare network ports.

Example:

ports:
  - 9090

Ports describe ports exposed or required by the module.

The Compose configuration remains authoritative for actual container networking.

Volumes

Modules MAY declare persistent volumes.

Example:

volumes:
  - prometheus-data

The metadata declaration documents persistent storage requirements.

The actual Docker volume or bind-mount configuration remains defined by the Compose configuration.

Tags

Modules MAY provide tags.

Example:

tags:
  - monitoring
  - metrics
  - observability

Tags provide additional classification and search capabilities.

Module Compose Definition

A module using Docker MUST provide a Compose definition when Docker Compose is required for deployment.

Recommended filename:

compose.yml

Example:

prometheus/
└── compose.yml

The Compose definition should be self-contained within the module where practical.

External configuration may be referenced when required by the HomeLab Sentinel architecture.

Configuration

Persistent configuration should normally be stored outside the module definition when appropriate.

Example:

app/
├── compose/
│   └── monitoring/
│       └── prometheus/
│           └── compose.yml
│
└── config/
    └── prometheus/
        └── prometheus.yml

This separates:

Module definition

from:

User configuration

Module upgrades should therefore not overwrite user configuration.

Persistent Data

Persistent application data should be stored outside the module definition whenever practical.

Example:

/srv/homelab-sentinel/

or the appropriate configured data root.

Modules must clearly document persistent data requirements.

Lifecycle

The HomeLab Sentinel module lifecycle is:

Available
   │
   ▼
Installed
   │
   ▼
Running
   │
   ├── Update
   │
   ├── Healthcheck
   │
   └── Uninstall

Possible runtime states include:

available
installed
running
stopped
unhealthy
failed
updating
removing

Module definition status and runtime status are separate concepts.

Registry Integration

The Module Registry discovers modules by locating valid metadata.yml files.

The relationship is:

Module
   │
   └── metadata.yml
          │
          ▼
       Registry
          │
          ▼
    Module information

The Registry MUST NOT require module-specific hardcoded logic.

Adding a new compliant module should be sufficient for the Registry to discover it automatically.

The Registry is responsible for:

Discovering modules
Reading metadata
Identifying modules
Validating metadata
Reporting compliance
Providing module information to other Sentinel components
Deployment Engine Integration

The Deployment Engine uses Registry information to locate and manage modules.

Target architecture:

User
 │
 ▼
Deployment Engine
 │
 ▼
Registry
 │
 ▼
Module metadata
 │
 ├── dependencies
 ├── compose
 ├── healthcheck
 └── lifecycle scripts
 │
 ▼
Module deployment

The Deployment Engine should not contain module-specific installation logic whenever possible.

The Deployment Engine is responsible for:

Dependency validation
Module deployment
Module startup
Module health verification
Module updates
Module removal
Reporting deployment results
Validation

Module metadata MUST be validated before deployment.

Validation should check:

Valid YAML
Required fields
Valid module ID
Unique module ID
Valid category
Valid status
Referenced files
Dependencies
Compose configuration where applicable
Healthcheck availability where declared

Invalid modules must not be deployed automatically.

Compliance Levels

A module is evaluated against the HomeLab Sentinel Module Specification.

The Registry may classify a module using the following compliance levels.

Compliant

The module contains all required metadata fields and satisfies the structural requirements defined by this specification.

A compliant module may proceed through the normal deployment process.

Partially Compliant

The module satisfies all required fields and can potentially be deployed, but is missing optional metadata or recommended components.

The Registry should report missing optional information as a warning rather than treating it as a fatal error.

Example:

[WARNING] Module is partially compliant.
[DETAIL] Module: homepage
[DETAIL] Optional field missing: documentation
[SUGGESTION] Add documentation: docs.md to metadata.yml.
Non-Compliant

The module does not satisfy the required specification.

Examples include:

Missing metadata.yml
Invalid YAML
Missing required metadata fields
Invalid module ID
Invalid category
Invalid status
Referenced lifecycle files that do not exist

A non-compliant module must not be deployed automatically.

Example:

[ERROR] Module is non-compliant.
[DETAIL] Module: example
[DETAIL] Missing required field: version
[SUGGESTION] Add a version field to metadata.yml.

Compliance status should be determined by validation rather than manually declared by the module.

The Registry is responsible for module specification validation.

Diagnostics

Validation and deployment errors should provide actionable information.

Preferred format:

[ERROR] What went wrong
[DETAIL] Relevant context
[SUGGESTION] Recommended corrective action

Example:

[ERROR] Module metadata is invalid.
[DETAIL] Module: prometheus
[DETAIL] Missing required field: version
[SUGGESTION] Add a version field to metadata.yml.

Diagnostics should help both experienced administrators and beginners.

Future versions may introduce diagnostic codes and links to relevant documentation.

Security

Modules must not assume unrestricted host access.

Module definitions should request only the permissions required for their function.

Future module systems may include:

Signature verification
Trusted repositories
Dependency verification
Version integrity checks
Supply-chain protection
Versioning

The module specification itself is versioned independently from individual modules.

Current Specification Version: 1.2

Changes to the specification must consider backward compatibility.

A module should declare its own version independently.

Example:

version: "0.1.0"

Modules SHOULD declare the specification version they were written against:

spec_version: "1.2"

Future specification versions may introduce new required fields, validation rules, or capabilities.

Compatibility requirements should be documented when the specification changes.

Example: Prometheus

A compliant Prometheus module may look like:

prometheus/
├── compose.yml
├── metadata.yml
├── docs.md
├── config/
│   └── prometheus.yml
└── scripts/
    ├── install.sh
    ├── update.sh
    ├── uninstall.sh
    └── healthcheck.sh

Example metadata:

id: prometheus
name: Prometheus
display_name: Prometheus Metrics

spec_version: "1.1"
version: "0.1.0"

category: monitoring

description: Time-series metrics collection and storage engine.

author: HomeLab Sentinel
license: Apache-2.0

status: enabled

homepage: https://prometheus.io/
documentation: docs.md

compose: compose.yml
healthcheck: scripts/healthcheck.sh

install: scripts/install.sh
update: scripts/update.sh
uninstall: scripts/uninstall.sh

dependencies:
  - docker

capabilities:
  provides:
    - metrics
    - monitoring

ports:
  - 9090

volumes:
  - prometheus-data

tags:
  - monitoring
  - metrics
  - observability
Example: Homepage

A simpler module may provide only the fields required for its operation.

Example:

id: homepage
name: Homepage

spec_version: "1.1"
version: "1.0.0"

category: core

description: HomeLab Sentinel dashboard and unified infrastructure interface.

status: enabled

dependencies:
  - docker

capabilities:
  provides:
    - dashboard
    - docker-integration
    - service-overview

healthcheck: scripts/healthcheck.sh

Modules do not need to declare optional fields that do not apply to them.

Design Principles in Practice

The module system follows these principles:

Self-Description

Modules describe themselves through metadata.

No Hardcoded Modules

Core components should not contain special cases for individual modules.

Separation of Concerns
Metadata
   ↓
Identity and capabilities

Registry
   ↓
Discovery, indexing and validation

Deployment Engine
   ↓
Lifecycle management

Module
   ↓
Actual functionality
Minimal Manual Configuration

If a module can describe itself automatically, the user should not need to configure it manually.

Replaceability

Modules should be replaceable without requiring changes to unrelated Sentinel components.

Maintainability

Module structure should remain predictable so that troubleshooting and maintenance are straightforward.

Specification Status

Specification Version: 1.1

Status: Approved

This document represents the first formal HomeLab Sentinel module contract.

The specification may evolve as additional modules and platform capabilities are implemented.

Changes should be documented and tested against existing modules before adoption.
