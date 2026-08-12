# HomeLab Sentinel Module Registry

## Overview

The HomeLab Sentinel Module Registry is the central catalogue of modules available to the platform.

The Registry provides a consistent way for HomeLab Sentinel to discover, identify, classify, and manage modules.

The Registry is designed to work together with the Deployment Engine and module metadata.

The Registry does not replace module metadata.

Instead, module metadata is the authoritative definition of a module, while the Registry provides an indexed view of available modules.

---

# Goals

The Registry is responsible for:

- Discovering available modules.
- Indexing module metadata.
- Providing module lookup.
- Providing module classification.
- Providing module status information.
- Providing module locations.
- Supporting the Deployment Engine.
- Providing a foundation for future automatic module management.

---

# Design Principle

The module's `metadata.yml` file is the authoritative source of information about that module.

The Registry should not maintain a second independent copy of module configuration.

The relationship is:

```text
Module
   │
   ├── metadata.yml
   │
   ▼
Registry
   │
   ▼
Indexed module information

# Diagnostics and Suggestions

The Registry should provide actionable diagnostics when module validation fails.

Errors should explain:

- What failed.
- Which module is affected.
- Which file or component caused the problem.
- Where appropriate, how the problem can be corrected.

The preferred diagnostic structure is:

```text
[ERROR] What went wrong
[DETAIL] Relevant context
[SUGGESTION] Recommended corrective action


Example

[ERROR] Module metadata is invalid.
[DETAIL] Module: prometheus
[DETAIL] Missing required field: version
[SUGGESTION] Add a version field to metadata.yml.
