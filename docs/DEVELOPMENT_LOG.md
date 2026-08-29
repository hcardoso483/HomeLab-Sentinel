# HomeLab Sentinel Development Log

## 2026-08-06 - Module 001: Dashboard Module

### Objective
Implement the first operational module of HomeLab Sentinel using Homepage as the dashboard.

### Completed
- Designed the modular Compose architecture.
- Created the Dashboard Module.
- Implemented environment-based configuration.
- Separated repository files from runtime data.
- Created and validated the shared Docker network.
- Added HomeLab Sentinel module labels.
- Resolved Homepage host validation.
- Verified browser access.
- Confirmed healthy container status.

### Lessons Learned
- Homepage requires explicit allowed hosts when accessed by IP.
- Runtime data should remain under `/srv/homelab-sentinel`.
- Docker labels provide a better long-term identification strategy than fixed container names.
- Every module should be validated before being committed.

### Result
Module 001 is complete and serves as the reference implementation for future modules.

---

## 2026-08-29 - Discovery and Living Inventory Foundations

### Objective

Establish automatic network discovery and convert provider observations into stable Sentinel-owned infrastructure identities.

### Completed

- Defined the Discovery contract and discovery scope boundaries.
- Implemented provider-neutral discovery orchestration.
- Added multi-pass discovery.
- Added observation validation and correlation.
- Implemented persistent Sentinel-owned device identities.
- Added MAC-aware identity handling.
- Added Living Inventory persistence.
- Added discovery scheduling.
- Added shared runtime locking for inventory-sensitive operations.
- Verified identity continuity across rediscovery and reboot.
- Added deterministic discovery and identity regression tests.

### Result

HomeLab Sentinel can automatically observe the network and maintain stable infrastructure identities instead of treating every discovery pass as an unrelated scan.

---

## 2026-08-29 - Platform Readiness and Core Status

### Objective

Make HomeLab Sentinel capable of determining and exposing its own operational readiness.

### Completed

- Implemented the Core API.
- Added canonical structured platform status.
- Added CLI platform status.
- Added inventory readiness and integrity reporting.
- Added discovery freshness and scheduler status.
- Defined boot-readiness requirements.
- Added stable discovery-pass requirements during startup.
- Added post-boot verification.
- Added systemd scheduling for Sentinel runtime services.
- Added restricted Homepage access to the loopback-bound Core API.
- Verified clean autonomous recovery after reboot.

### Result

HomeLab Sentinel can now report whether its own core subsystems are ready instead of relying on external inspection of individual processes or containers.

---

## 2026-08-29 - Monitoring v1 Complete

### Objective

Implement the first provider-neutral Monitoring capability using Living Inventory identities and real monitoring evidence.

### Completed

- Defined the Monitoring v1 contract.
- Implemented deterministic target derivation from Living Inventory entities.
- Integrated capability-based provider resolution.
- Added Prometheus as the current monitoring provider.
- Added Prometheus target rendering and reconciliation.
- Integrated Blackbox Exporter for ICMP reachability probing.
- Defined and implemented the Monitoring provider adapter boundary.
- Added normalized Sentinel-owned monitoring observations.
- Added monitoring observation persistence and history.
- Added evidence freshness handling.
- Implemented canonical health states:
  - `UNKNOWN`
  - `HEALTHY`
  - `DEGRADED`
  - `DOWN`
- Added protection against provider failure being interpreted as false device failure.
- Added provider-neutral Monitoring orchestration.
- Added automatic Monitoring reconciliation and collection scheduling.
- Serialized Monitoring, Discovery, and verification where required through the shared runtime lock.
- Added Monitoring CLI surfaces for:
  - status
  - provider
  - targets
  - health
  - history
- Integrated canonical Monitoring state into platform status and the Core API.
- Added read-only Sentinel Monitoring status to Homepage.
- Added deterministic regression coverage.
- Tested real device offline and recovery behavior.
- Completed unattended soak testing.
- Completed final restart and reboot proof.

### Validation

The final Monitoring v1 reboot proof confirmed:

- Sentinel returned to READY automatically.
- Discovery resumed successfully.
- Monitoring reconciliation resumed successfully.
- Monitoring collection resumed successfully.
- Post-boot verification succeeded.
- Prometheus and Blackbox Exporter returned healthy.
- Monitoring history persisted across reboot.
- Fresh post-reboot evidence was appended to the same canonical entity.
- No failed systemd units remained.
- Repository state was clean and synchronized.

### Result

Monitoring v1 is considered complete.

Project checkpoint:

```text
15bd0a9 Add Monitoring history CLI
```

This checkpoint represents the completed Monitoring v1 foundation. Further monitoring refinement belongs to later development unless operational experience reveals a defect.

---

## Current Direction

HomeLab Sentinel has now established working foundations for:

- Modular provider architecture
- Deployment lifecycle
- Automatic discovery
- Persistent identity
- Living Inventory
- Platform readiness
- Core API and status
- Monitoring v1
- Initial read-only dashboard integration

The next development phase should be selected from the original HomeLab Sentinel v1 goals.

The current priority is to make remaining v1 capabilities operational and useful before investing in refinement intended for HomeLab Sentinel v2.
