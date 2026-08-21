# HomeLab Sentinel Platform Bootstrap

## Overview

The HomeLab Sentinel Platform Bootstrap prepares and validates the
system-level Sentinel Core runtime.

Its entry point is:

``` text
installer/install.sh
```

The Platform Bootstrap is separate from the Module Deployment Engine.

The Platform Bootstrap establishes the Sentinel platform runtime. The
Deployment Engine manages the lifecycle of Sentinel modules.

------------------------------------------------------------------------

## Bootstrap Version 1

Bootstrap v1 provides a reproducible and idempotent mechanism for
deploying the currently implemented Sentinel Core system services onto a
prepared host.

Bootstrap v1 has been validated by repeated execution against an
existing HomeLab Sentinel installation.

Repeated execution must converge on the same desired platform state
without creating duplicate services or damaging the existing
installation.

------------------------------------------------------------------------

## Bootstrap Version 2

Bootstrap v2 extends the platform bootstrap with mandatory Sentinel
dependency management.

Before deploying Core services, Bootstrap v2 validates the supported
host and the capabilities required by HomeLab Sentinel. When a mandatory
dependency is missing and a supported, deterministic recovery path is
known, the bootstrap attempts automatic recovery and verifies the actual
capability again before continuing.

The dependency-management principle is:

``` text
Detect
  |
  v
Diagnose
  |
  v
Recover when safe and supported
  |
  v
Verify the actual capability
  |
  +-- PASS --> Continue
  |
  +-- FAIL --> Stop safely with a clear error
```

Successful package-manager execution alone is not considered proof that
a dependency is healthy. The required Sentinel capability must pass its
own post-recovery verification.

------------------------------------------------------------------------

## Supported Host

Bootstrap v2 currently supports:

``` text
Operating system: Debian GNU/Linux
Version:          13 (trixie)
Init system:      systemd
Package manager:  APT
```

Host identity is determined from `/etc/os-release`.

Automatic package recovery must not be attempted using Debian 13 package
mappings when the host does not match the supported operating-system
contract.

------------------------------------------------------------------------

## Preconditions

The current bootstrap assumes:

-   Existing-install mode uses the application tree at `/opt/homelab-sentinel/app`.
-   First-install mode acquires the application tree before Platform Bootstrap runs.
-   The Sentinel inventory database already exists.
-   The host is a supported Debian 13 system.
-   The host provides systemd.
-   APT is available for supported automatic dependency recovery.
-   Required Sentinel Core files are present.
-   The bootstrap is executed with root privileges.

Bootstrap validates the prerequisites it directly depends upon and fails
safely when a required prerequisite cannot be provided or recovered.

------------------------------------------------------------------------

## Host Prerequisites

Host prerequisites define the operating-system foundation on which
HomeLab Sentinel is supported.

They are distinct from Sentinel-managed dependencies.

Current host prerequisites include:

``` text
systemd
apt-get
install
```

These capabilities describe the supported host environment. Bootstrap
must not attempt arbitrary host conversion when they are unavailable.

------------------------------------------------------------------------

## Mandatory Sentinel Dependencies

Mandatory Sentinel dependencies are capabilities required by the
Sentinel platform itself.

They are distinct from module-specific dependencies.

Bootstrap v2 currently manages:

  -----------------------------------------------------------------------
  Sentinel capability    Debian 13 recovery       Purpose
                         package
  ---------------------- ------------------------ -----------------------
  `python3` command      `python3`                Sentinel Core and
                                                  platform Python runtime

  `curl` command         `curl`                   Bootstrap and health
                                                  endpoint verification

  Python `yaml` import   `python3-yaml`           Module metadata and
                                                  deployment processing

  Python `sqlite3`       `libpython3.13-stdlib`   Living Inventory and
  import                                          Core API database
                                                  access
  -----------------------------------------------------------------------

The SQLite requirement is the Python SQLite capability used by Sentinel.
The standalone `sqlite3` command-line package is not currently a
mandatory Core dependency.

The dependency manager is:

``` text
installer/dependencies.py
```

Normal capability validation can be run directly with:

``` text
./installer/dependencies.py
```

------------------------------------------------------------------------

## Automatic Dependency Recovery

The platform bootstrap invokes the dependency manager with automatic
recovery enabled:

``` text
./installer/dependencies.py --recover
```

For each mandatory dependency, the manager:

1.  Tests the actual capability required by Sentinel.
2.  Reports the dependency as available when the capability passes.
3.  Identifies the known Debian package when the capability is missing.
4.  Uses APT to attempt recovery when recovery is authorized.
5.  Verifies the actual Sentinel capability again after recovery.
6.  Continues only when post-recovery verification succeeds.

Recovery is intentionally limited to known mappings on supported hosts.

If recovery cannot be performed safely, package installation fails, or
the capability remains unavailable after recovery, dependency management
fails and the bootstrap stops.

------------------------------------------------------------------------

## Recovery Verification

Dependency recovery follows the rule:

> Package installation is an action. Capability verification is the
> proof.

For example, recovery of the YAML dependency is not considered
successful merely because APT reports success. Sentinel subsequently
verifies that Python can actually import `yaml`.

The same principle applies to all managed capabilities.

Representative output is:

``` text
[RECOVER] Dependency missing: python-yaml (package: python3-yaml)
[INFO] Installing mandatory Sentinel package(s): python3-yaml
[PASS] Dependency recovered and verified: python-yaml
```

A failed post-recovery capability check must produce a failure and
prevent the bootstrap from continuing.

------------------------------------------------------------------------

## Dependency Recovery Simulation

The dependency manager provides an explicit test-only simulation
interface for validating missing-dependency and recovery behavior
without uninstalling or damaging dependencies on a working Sentinel
host.

Simulation is exposed only through the command-line option:

``` text
--simulate-missing
```

Supported dependency identifiers are discoverable through:

``` text
./installer/dependencies.py --help
```

A missing dependency can be simulated without authorizing recovery:

``` text
./installer/dependencies.py --simulate-missing python-yaml
```

This must report the simulated dependency as missing and exit
unsuccessfully without attempting package recovery.

The complete recovery path can be exercised with:

``` text
./installer/dependencies.py --recover --simulate-missing python-yaml
```

When simulation mode is active, output must explicitly identify the test
condition:

``` text
[TEST] Dependency simulation enabled: python-yaml will be reported as missing.
```

Simulation affects initial dependency detection only. Post-recovery
verification bypasses the simulation and tests the real capability.

This ensures the test proves the complete recovery chain:

``` text
Simulated missing capability
        |
        v
Recovery provider selected
        |
        v
Recovery attempted
        |
        v
Real capability independently verified
        |
        +-- PASS
        |
        +-- FAIL
```

The Platform Bootstrap does not enable or forward simulation mode during
normal installation.

Simulation exists as a deliberate regression and recovery-testing
facility, not as hidden production behavior.

------------------------------------------------------------------------

## Inventory State Management

Platform Bootstrap prepares the authoritative Sentinel inventory state
before the Core API is started.

The platform-level inventory state manager is:

``` text
installer/inventory.py
```

The inventory manager does not implement Sentinel database schemas or
migrations itself. Schema ownership remains with the Inventory
subsystem.

The authoritative initialization and migration path is:

``` text
core/inventory/store.py
```

This preserves the architectural boundary:

> Platform Bootstrap determines that required Sentinel state is ready.
> The Inventory subsystem determines how inventory state is created and
> migrated.

### Missing Inventory Database

When the configured inventory database does not exist, the inventory
manager:

1.  Reports the missing state as recoverable.
2.  Invokes `core/inventory/store.py` with an empty input stream.
3.  Allows the Inventory Store to create the required parent directory.
4.  Initializes the base inventory schema.
5.  Applies all required sequential inventory migrations.
6.  Confirms that the database file was created.
7.  Verifies the resulting schema version.
8.  Runs SQLite integrity verification.
9.  Allows Bootstrap to continue only when verification passes.

The default inventory database is:

``` text
/srv/homelab-sentinel/sentinel/inventory.db
```

The currently verified clean initialization path is:

``` text
No inventory database
        |
        v
Inventory Store creates database
        |
        v
Base schema initialized
user_version = 1
        |
        v
Migration 002 applied
user_version = 2
        |
        v
SQLite integrity_check
        |
        +-- PASS --> Inventory state ready
        |
        +-- FAIL --> Bootstrap stops
```

Clean initialization has been tested against a temporary empty path and
produces schema version 2 with the expected inventory tables and an
`integrity_check` result of `ok`.

### Existing Inventory Database

When the inventory database already exists, the inventory manager does
not reinitialize it.

Instead it:

1.  Opens the database in read-only mode for verification.
2.  Reads `PRAGMA user_version`.
3.  Confirms that the schema version is supported.
4.  Runs `PRAGMA integrity_check`.
5.  Reports the inventory state as ready only when verification
    succeeds.

Repeated Platform Bootstrap execution has been verified against the
existing live inventory without changing its inventory counts or
reinitializing its contents.

This establishes idempotent inventory-state behavior:

``` text
missing database
    -> initialize
    -> migrate
    -> verify
    -> ready

existing database
    -> verify only
    -> preserve data
    -> ready
```

### Failure Boundary

Inventory state must be valid before the Core API service is installed,
started, or restarted as part of the bootstrap sequence.

If initialization fails, the database is not created as expected, the
schema version is unsupported, or SQLite integrity verification fails,
the inventory manager exits unsuccessfully and Platform Bootstrap stops.

The Core API must not be treated as successfully deployed on top of
invalid Sentinel inventory state.

------------------------------------------------------------------------


## Platform Service Identity

HomeLab Sentinel separates installation privileges from runtime privileges.

Platform installation is performed with root privileges because Bootstrap
must be able to install packages, prepare platform state, install systemd
units, create system identities, and enable services.

Long-running Sentinel services must not depend on the identity of the human
administrator who installed the platform.

The canonical runtime service identity is:

```text
homelab-sentinel
```

The account is declared by:

```text
installer/sysusers.d/homelab-sentinel.conf
```

Bootstrap installs the declaration to:

```text
/etc/sysusers.d/homelab-sentinel.conf
```

and ensures the identity exists using `systemd-sysusers`.

The account is intentionally non-interactive:

```text
home:  /nonexistent
shell: /usr/sbin/nologin
```

Bootstrap creates `/etc/sysusers.d` when necessary before installing the
declaration.

The service identity has been validated running both:

- HomeLab Sentinel Core API.
- HomeLab Sentinel post-boot verification.

The canonical systemd units therefore use:

```text
User=homelab-sentinel
Group=homelab-sentinel
```

Application code remains administrator-owned under:

```text
/opt/homelab-sentinel/app
```

Runtime services require only the permissions necessary to read and execute
the current Core implementation.

Persistent Sentinel state remains under:

```text
/srv/homelab-sentinel
```

The platform must not require a human account such as the original installer
user to exist after installation.

---

## Responsibilities

The current Platform Bootstrap:

In addition to dependency and inventory-state management, the platform now
establishes the dedicated `homelab-sentinel` runtime identity and installs the
canonical `hls` administrative CLI.

1.  Requires root privileges.
2.  Validates the supported host.
3.  Validates mandatory Sentinel dependencies.
4.  Automatically attempts safe recovery of missing mandatory
    dependencies.
5.  Verifies recovered capabilities before continuing.
6.  Validates required host commands.
7.  Validates required Sentinel Core files.
8.  Installs canonical Sentinel systemd unit files.
9.  Reloads the systemd manager configuration.
10. Enables the HomeLab Sentinel Core API service.
11. Starts or restarts the Core API service.
12. Waits for the Core API health endpoint to become available.
13. Enables HomeLab Sentinel post-boot verification.
14. Executes the complete Sentinel verification suite.
15. Reports successful platform bootstrap only after verification
    passes.

------------------------------------------------------------------------

## Core Services

The Platform Bootstrap manages:

``` text
homelab-sentinel-api.service
homelab-sentinel-verify.service
```

Canonical unit definitions are stored in:

``` text
installer/systemd/
```

Installed unit files are deployed to:

``` text
/etc/systemd/system/
```

------------------------------------------------------------------------


## HLS Command-Line Interface

The canonical administrative interface for HomeLab Sentinel is:

```text
hls
```

Bootstrap installs the version-controlled CLI from:

```text
installer/hls
```

to:

```text
/usr/local/bin/hls
```

Users should interact with HomeLab Sentinel through `hls` rather than needing
to know internal repository script paths.

The currently implemented commands are:

```text
hls help
hls status
hls verify
hls inventory [arguments...]
sudo hls install
```

### Install / Reconciliation

On an existing HomeLab Sentinel installation:

```text
sudo hls install
```

invokes the Platform Bootstrap and converges the system toward the desired
Sentinel platform state.

The verified flow includes:

```text
mandatory dependency validation/recovery
        |
        v
inventory state preparation
        |
        v
service identity enforcement
        |
        v
HLS CLI installation
        |
        v
systemd unit deployment
        |
        v
Core API startup
        |
        v
health verification
        |
        v
full Sentinel verification
```

Repeated execution through `sudo hls install` has been verified to remain
idempotent.

### Status

```text
hls status
```

delegates platform status evaluation to the dedicated read-only status engine:

```text
core/status/status.py
```

The status engine observes the installed Sentinel platform and reports its
current operational state. It does not install packages, initialize inventory
state, start or restart services, change permissions, repair configuration, or
otherwise reconcile the platform.

This preserves the command boundary:

```text
hls status
    -> observe and classify current platform state

sudo hls install
    -> reconcile the platform toward desired state

hls verify
    -> execute the complete Sentinel verification suite
```

The current status report evaluates:

-   Application installation state.
-   Canonical `homelab-sentinel` service identity.
-   Core API systemd service state.
-   Core API runtime identity.
-   Core API health endpoint.
-   Inventory database presence and readability.
-   Inventory schema version.
-   SQLite integrity.
-   Post-boot verification unit enablement.

The status engine uses three overall states with stable process exit codes:

```text
READY          exit 0
DEGRADED       exit 1
NOT INSTALLED  exit 2
```

`READY` means the observed platform checks required by the current status
contract are healthy.

`DEGRADED` means Sentinel is present, or platform remnants indicate that it
should be present, but one or more observed components are missing, unhealthy,
incorrect, or unsupported.

`NOT INSTALLED` represents clean platform absence. Components that do not apply
to a clean uninstalled system are reported as `N/A` rather than being presented
as failures.

This distinction is intentional:

```text
clean platform absence
        -> NOT INSTALLED

installed, partial, inconsistent, or unhealthy platform
        -> DEGRADED
```

Status evaluation is deliberately read-only. In particular, inventory
inspection opens the database read-only and must not invoke the inventory state
manager, because `installer/inventory.py` is allowed to initialize missing state
during platform reconciliation.

#### Status Failure-State Testing

The status engine provides an explicit test-only simulation interface:

```text
--simulate CONDITION
```

The currently supported simulated conditions are:

```text
wrong-runtime-identity
missing-database
unsupported-schema
not-installed
```

Simulation allows status classification and exit-code behavior to be exercised
without damaging the live Sentinel installation.

The verified simulation matrix is:

```text
normal                   -> READY          -> exit 0
wrong-runtime-identity   -> DEGRADED       -> exit 1
missing-database         -> DEGRADED       -> exit 1
unsupported-schema       -> DEGRADED       -> exit 1
not-installed            -> NOT INSTALLED  -> exit 2
```

Live degraded-state testing has also verified that stopping the Core API reports
the service as `INACTIVE`, health as `UNHEALTHY`, overall state as `DEGRADED`,
and exit code 1. Disabling the post-boot verification unit reports it as
`DISABLED`, overall state as `DEGRADED`, and exit code 1. Restoring each live
condition returns the platform to `READY`.

The simulation interface exists only for controlled regression testing. It does
not alter production state and is not used by normal `hls status` execution.

### Verification

```text
hls verify
```

executes the complete Sentinel verification suite.

### Inventory

```text
hls inventory
```

delegates to the authoritative Living Inventory CLI.

### First-Install Acquisition

The same `hls install` interface now supports two installation states.

When `/opt/homelab-sentinel/app` already contains HomeLab Sentinel, `hls
install` enters existing-install mode and invokes the Platform Bootstrap to
reconcile and verify the installed platform.

When HomeLab Sentinel is not yet installed, the standalone bootstrap form of
`hls` enters first-install acquisition mode.

The first-install flow is:

```text
standalone bootstrap hls
        |
        v
sudo ./hls install
        |
        v
ensure Git is available
        |
        v
acquire canonical repository over HTTPS
        |
        v
clone main branch into temporary staging
        |
        v
validate required Sentinel tree
        |
        +-- FAIL --> remove staging --> stop
        |
        v
activate /opt/homelab-sentinel/app
        |
        v
remove staging
        |
        v
run Platform Bootstrap
        |
        v
install permanent /usr/local/bin/hls
```

The canonical acquisition source is:

```text
https://github.com/hcardoso483/HomeLab-Sentinel.git
```

and the currently selected acquisition branch is:

```text
main
```

HTTPS is deliberately used for first installation so acquisition does not
depend on a preconfigured SSH key or GitHub SSH credentials.

#### Acquisition Staging and Validation

Repository contents are not cloned directly into the final application path.
First-install acquisition creates a temporary `.bootstrap-*` staging directory
under the selected installation root and clones the repository there.

Before activation, `hls` validates that the acquired tree contains the
required platform components, including the installer, dependency manager,
inventory state manager, HLS CLI, systemd units, service identity declaration,
Core API server, and Sentinel verification script.

Only a tree that passes validation may be moved into the final application
path.

The final application path must not already exist when first-install
acquisition attempts activation. An existing installation is handled through
the existing-install reconciliation path instead.

#### Transactional Failure Boundary

Acquisition is treated as a transactional operation.

The verified successful path is:

```text
clone
  |
  v
validate
  |
  v
activate
  |
  v
cleanup staging
  |
  v
acquisition complete
```

The clone-failure path has been explicitly tested:

```text
clone fails
  |
  v
report acquisition failure
  |
  v
cleanup staging
  |
  v
no application installed
```

The validation-failure path has also been explicitly tested:

```text
clone succeeds
  |
  v
acquired tree fails validation
  |
  v
cleanup staging
  |
  v
no application installed
```

In both tested failure paths, no final `app` tree is created and no
`.bootstrap-*` staging directory remains.

#### First-Install Test Mode

First-install acquisition provides an explicit test-only root override:

```text
--test-root PATH
```

The test root must be under `/tmp`.

Test mode performs acquisition, staging, validation, activation, and cleanup
under the temporary root but deliberately does not execute Platform Bootstrap.
This allows acquisition behavior to be exercised without replacing or
reconfiguring the live Sentinel installation.

A successful acquisition test has been verified to produce a checkout with:

```text
remote: https://github.com/hcardoso483/HomeLab-Sentinel.git
branch: main
```

while leaving the live application tree unchanged.

#### Invalid-Tree Simulation

Validation rollback can be exercised through the explicit test-only option:

```text
--simulate-invalid-tree
```

This option is accepted only together with `--test-root`.

After a successful clone, simulation deliberately removes a required Sentinel
file from the staged checkout before validation. Validation must then reject
the acquired tree, acquisition must exit unsuccessfully, staging must be
removed, and no final application tree may be activated.

Simulation exists only to prove the rollback contract. It is not part of
normal production installation behavior.

#### Dual-Mode Install Contract

The resulting `hls install` behavior is:

```text
HomeLab Sentinel absent
        |
        +--> first-install acquisition
                |
                +--> acquire
                +--> validate
                +--> activate
                +--> Platform Bootstrap

HomeLab Sentinel present
        |
        +--> existing-install reconciliation
                |
                +--> Platform Bootstrap
                +--> verify desired platform state
```

Existing-install mode has been regression-tested after introduction of the
first-install acquisition logic and continues to complete the full Platform
Bootstrap and Sentinel verification suite successfully.

---

## Core API

The initial Core API runtime is bound to:

``` text
127.0.0.1:8000
```

The API remains local-only while the final authentication and
authorization boundary is not yet implemented.

Bootstrap verifies availability using:

``` text
/api/v1/health
```

------------------------------------------------------------------------

## Verification

Successful bootstrap requires the existing Sentinel verification system
to pass.

Verification includes:

-   Application tree validation.
-   Inventory database validation.
-   Inventory schema validation.
-   SQLite integrity validation.
-   Core API regression testing.
-   Temporary regression-process cleanup validation.

A bootstrap operation is not considered successful if Sentinel
verification fails.

------------------------------------------------------------------------

## Idempotency

Platform Bootstrap operations must be safe to execute repeatedly.

Re-running the bootstrap may:

-   Re-check mandatory dependencies.
-   Recover missing mandatory dependencies when necessary.
-   Reinstall canonical systemd unit files.
-   Reload systemd.
-   Restart the Core API.
-   Re-enable required services.
-   Re-run verification.

It must not create duplicate services or require manual cleanup between
successful runs.

When all mandatory dependencies are already healthy, dependency
management must not reinstall them unnecessarily.

------------------------------------------------------------------------

## Dependency Layers

HomeLab Sentinel separates dependencies into three layers:

``` text
Host prerequisites
        |
        +-- supported Debian environment
        +-- systemd
        +-- APT
        +-- core host utilities

Sentinel mandatory dependencies
        |
        +-- Python runtime
        +-- Python SQLite capability
        +-- Python YAML capability
        +-- curl

Module dependencies
        |
        +-- Docker
        +-- nmap
        +-- future provider/module-specific capabilities
```

Platform Bootstrap owns the Sentinel mandatory dependency layer.

Module-specific dependencies remain the responsibility of the Module
Deployment Engine.

------------------------------------------------------------------------

## Relationship to the Deployment Engine

The Platform Bootstrap and Module Deployment Engine have separate
responsibilities.

``` text
Platform Bootstrap
        |
        +-- Validate supported host
        +-- Establish mandatory Sentinel dependencies
        +-- Recover supported missing dependencies
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

Docker, nmap, and future provider-specific requirements remain module
dependencies unless they become genuine mandatory requirements of the
Sentinel platform itself.

------------------------------------------------------------------------

## Outside Current Bootstrap Scope

The current bootstrap does not yet:

-   Configure Git credentials or user identity.
-   Deploy Sentinel modules.
-   Configure host networking.
-   Configure firewall rules.
-   Configure external storage.
-   Perform complete provisioning of a bare Debian installation.

These capabilities may be introduced incrementally in later bootstrap
versions where they belong within the platform installation boundary.

------------------------------------------------------------------------

## Future Direction

The long-term installation objective is:

``` text
Supported clean Debian installation
              |
              v
      Bootstrap HLS entry point
              |
              v
      First-install acquisition / existing-install reconciliation
              |
              v
      Platform Bootstrap
              |
              +-- validate supported host
              +-- establish prerequisites
              +-- self-recover supported dependencies
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

-   Reproducibility.
-   Idempotency.
-   Clear failure reporting.
-   Safe automatic recovery where a deterministic repair path exists.
-   Verification after recovery.
-   Explicit testability of recovery behavior.
-   Separation between platform and module responsibilities.
-   Verification before installation is considered successful.
