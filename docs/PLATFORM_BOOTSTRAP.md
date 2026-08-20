# HomeLab Sentinel Platform Bootstrap

## Overview

The HomeLab Sentinel Platform Bootstrap prepares and validates the
system-level Sentinel Core runtime.

Its entry point is:

```text
installer/install.sh
```

The Platform Bootstrap is separate from the Module Deployment Engine.

The Platform Bootstrap establishes the Sentinel platform runtime.
The Deployment Engine manages the lifecycle of Sentinel modules.

---

## Bootstrap Version 1

Bootstrap v1 provides a reproducible and idempotent mechanism for deploying
the currently implemented Sentinel Core system services onto a prepared host.

Bootstrap v1 has been validated by repeated execution against an existing
HomeLab Sentinel installation.

Repeated execution must converge on the same desired platform state without
creating duplicate services or damaging the existing installation.

---

## Preconditions

Bootstrap v1 assumes:

- The HomeLab Sentinel application tree already exists.
- The application tree is located at `/opt/homelab-sentinel/app`.
- The Sentinel inventory database already exists.
- The host provides systemd.
- Python 3 is installed.
- curl is installed.
- Required Sentinel Core files are present.
- The bootstrap is executed with root privileges.

Bootstrap v1 validates the prerequisites it directly depends upon and fails
before platform deployment when a required prerequisite is unavailable.

---

## Responsibilities

Bootstrap v1:

1. Requires root privileges.
2. Validates required host commands.
3. Validates required Sentinel Core files.
4. Installs canonical Sentinel systemd unit files.
5. Reloads the systemd manager configuration.
6. Enables the HomeLab Sentinel Core API service.
7. Starts or restarts the Core API service.
8. Waits for the Core API health endpoint to become available.
9. Enables HomeLab Sentinel post-boot verification.
10. Executes the complete Sentinel verification suite.
11. Reports successful platform bootstrap only after verification passes.

---

## Core Services

Bootstrap v1 manages:

```text
homelab-sentinel-api.service
homelab-sentinel-verify.service
```

Canonical unit definitions are stored in:

```text
installer/systemd/
```

Installed unit files are deployed to:

```text
/etc/systemd/system/
```

---

## Core API

The initial Core API runtime is bound to:

```text
127.0.0.1:8000
```

The API remains local-only while the final authentication and authorization
boundary is not yet implemented.

Bootstrap verifies availability using:

```text
/api/v1/health
```

---

## Verification

Successful bootstrap requires the existing Sentinel verification system to
pass.

Verification includes:

- Application tree validation.
- Inventory database validation.
- Inventory schema validation.
- SQLite integrity validation.
- Core API regression testing.
- Temporary regression-process cleanup validation.

A bootstrap operation is not considered successful if Sentinel verification
fails.

---

## Idempotency

Platform Bootstrap operations must be safe to execute repeatedly.

Re-running Bootstrap v1 may:

- Reinstall canonical systemd unit files.
- Reload systemd.
- Restart the Core API.
- Re-enable required services.
- Re-run verification.

It must not create duplicate services or require manual cleanup between
successful runs.

---

## Relationship to the Deployment Engine

The Platform Bootstrap and Module Deployment Engine have separate
responsibilities.

```text
Platform Bootstrap
        |
        +-- Establish Sentinel Core runtime
        +-- Install Core system services
        +-- Verify platform state
        |
        +--> Module Deployment Engine
                 |
                 +-- Resolve modules/providers
                 +-- Validate module metadata
                 +-- Resolve module dependencies
                 +-- Install modules
                 +-- Run module health checks
                 +-- Manage module lifecycle
```

Module-specific installation logic must not be added to the Platform
Bootstrap.

---

## Outside Bootstrap v1 Scope

Bootstrap v1 does not yet:

- Clone or download the HomeLab Sentinel repository.
- Install or configure Git.
- Install Python.
- Install curl.
- Install Docker or Docker Compose.
- Create the Sentinel inventory database.
- Initialize the inventory schema.
- Deploy Sentinel modules.
- Configure host networking.
- Configure firewall rules.
- Configure external storage.
- Perform complete provisioning of a bare Debian installation.

These capabilities may be introduced incrementally in later bootstrap
versions where they belong within the platform installation boundary.

---

## Future Direction

The long-term installation objective is:

```text
Supported clean Debian installation
              |
              v
      Platform Bootstrap
              |
              +-- establish prerequisites
              +-- establish Sentinel Core
              +-- initialize required state
              |
              v
      Module Deployment Engine
              |
              +-- deploy selected/default modules
              |
              v
      Full Sentinel verification
              |
              v
      Operational HomeLab Sentinel
```

Future bootstrap development must preserve:

- Reproducibility.
- Idempotency.
- Clear failure reporting.
- Separation between platform and module responsibilities.
- Verification before installation is considered successful.
