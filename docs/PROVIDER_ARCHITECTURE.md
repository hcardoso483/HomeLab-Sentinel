# HomeLab Sentinel Provider Architecture

## 1. Purpose

HomeLab Sentinel may have multiple modules that provide the same capability.

Examples include:

* Prometheus and VictoriaMetrics providing `metrics`
* Multiple discovery engines providing `discovery`
* Multiple logging systems providing `logging`
* Multiple dashboard implementations providing `dashboard`

The Provider Architecture defines how HomeLab Sentinel discovers, validates, selects, and falls back between these implementations.

The architecture separates **capability declaration** from **provider selection**.

Modules declare what they provide. The installation configuration determines which provider is selected.

---

## 2. Core Principle

**User choices always have priority. Defaults are the recovery mechanism, not a replacement for user choices.**

HomeLab Sentinel MUST NOT silently replace a valid user selection.

When a user selection is invalid or unavailable, HomeLab Sentinel SHOULD report the condition and use the configured installation default when a safe default is available.

The original user configuration MUST NOT be silently rewritten during fallback.

---

## 3. Capability Providers

A module becomes a provider when its metadata declares the requested capability.

Specification 1.1 uses the structured capability format:

```yaml
capabilities:
  provides:
    - metrics
    - monitoring
```

Multiple modules MAY provide the same capability.

The Registry is responsible for discovering providers from module metadata.

Example:

```text
metrics
├── prometheus
└── victoriametrics
```

Both modules are valid providers for `metrics`.

---

## 4. Provider Selection

Provider selection is an installation-level concern.

A provider is selected according to the following priority order:

1. Explicit user selection
2. Installation default
3. Safe alternative provider, where permitted
4. Stop the operation if no valid provider exists

Modules MUST NOT declare themselves as the default provider.

Modules MUST NOT override an explicit user selection.

---

## 5. User Selection

A user MAY explicitly select a provider for a capability.

Example:

```yaml
providers:
  metrics: victoriametrics
```

If the selected module exists and provides the requested capability, it MUST be used.

Example:

```text
[INFO] Capability: metrics
[INFO] User provider: victoriametrics
[OK] Provider validated: victoriametrics
[INFO] Continuing with selected provider.
```

No fallback is performed when the user selection is valid.

---

## 6. Invalid User Selection

A user selection MAY fail validation for several reasons:

* The module does not exist.
* The module is disabled or otherwise unavailable.
* The module does not provide the requested capability.
* The module metadata is non-compliant.
* Required module dependencies cannot be satisfied.

When a user selection is invalid, HomeLab Sentinel MUST report the condition.

If a valid installation default exists, HomeLab Sentinel SHOULD continue using that default.

Example:

```text
[WARNING] Configured provider is unavailable.
[DETAIL] Capability: metrics
[DETAIL] Requested provider: something-that-does-not-exist
[DETAIL] Provider could not be found in the module registry.
[SUGGESTION] The installation default will be used.
[INFO] Selected provider: prometheus
```

The user's configuration MUST remain unchanged.

---

## 7. Capability Mismatch

A provider name alone is not sufficient.

The selected module MUST actually provide the requested capability.

For example:

```yaml
providers:
  metrics: homepage
```

If `homepage` does not provide `metrics`, the selection is invalid.

HomeLab Sentinel SHOULD report:

```text
[WARNING] Configured provider is invalid.
[DETAIL] Capability: metrics
[DETAIL] Requested provider: homepage
[DETAIL] Module does not provide the requested capability.
[SUGGESTION] The installation default will be used.
[INFO] Selected provider: prometheus
```

---

## 8. Installation Defaults

HomeLab Sentinel MUST provide a known default for capabilities that are required by the installation profile.

Defaults exist to provide a predictable working installation and to recover from invalid or incomplete configuration.

Example:

```yaml
default_providers:
  metrics: prometheus
```

The default provider configuration belongs to the installation or deployment configuration, not to an individual module.

A default provider MUST still be validated before use.

---

## 9. Default Validation

The default provider MUST satisfy the same validation rules as a user-selected provider.

The default provider MUST:

* Exist in the Registry.
* Be deployable.
* Be specification-compliant.
* Provide the requested capability.
* Have its required dependencies satisfied.

A default MUST NOT be trusted merely because it is configured as a default.

---

## 10. Fallback Providers

If the user selection is invalid and the installation default is unavailable, HomeLab Sentinel MAY select another valid provider when the installation policy permits it.

For example:

```text
metrics
├── prometheus       unavailable
├── victoriametrics  available
└── another-provider available
```

The Resolver MAY select an available provider according to the installation fallback policy.

The fallback decision MUST be reported.

Example:

```text
[WARNING] Installation default is unavailable.
[DETAIL] Capability: metrics
[DETAIL] Default provider: prometheus
[DETAIL] Prometheus cannot satisfy the current installation requirements.
[INFO] Searching for an alternative provider.
[INFO] Alternative provider found: victoriametrics
[OK] Provider selected: victoriametrics
```

Automatic alternative selection SHOULD be deterministic.

---

## 11. No Provider Available

If no valid provider exists for a required capability, HomeLab Sentinel MUST stop the affected operation.

It MUST NOT silently install a module that does not provide the requested capability.

Example:

```text
[ERROR] No valid provider available.
[DETAIL] Capability: metrics
[DETAIL] Configured provider: invalid-provider
[DETAIL] Installation default: prometheus
[DETAIL] No deployable provider satisfies the capability.
[ERROR] Cannot satisfy required capability: metrics
```

This is a hard failure.

The installation MUST NOT continue past a required unresolved capability.

---

## 12. Error Handling Philosophy

Provider resolution follows a recoverable-error model.

### Recoverable conditions

The installation MAY continue when:

* A user-selected provider is invalid but a valid default exists.
* A default provider is unavailable but a permitted alternative exists.
* Optional capabilities cannot be resolved and the installation profile allows them to remain unavailable.

### Fatal conditions

The affected operation MUST stop when:

* A required capability has no valid provider.
* No safe default or permitted alternative exists.
* Provider dependency requirements cannot be satisfied.
* Provider metadata is non-compliant and no valid alternative exists.

Errors MUST never be hidden.

Recovery MUST always produce an actionable diagnostic message.

---

## 13. Configuration Preservation

Fallback MUST NOT mutate the user's provider configuration automatically.

For example, if the user configured:

```yaml
providers:
  metrics: victoriametrics
```

and VictoriaMetrics is unavailable, HomeLab Sentinel MAY temporarily use Prometheus for the current installation operation if policy permits it.

The configuration MUST remain:

```yaml
providers:
  metrics: victoriametrics
```

This prevents an automatic recovery decision from becoming an unexpected permanent configuration change.

---

## 14. Resolver Responsibilities

The Provider Resolver is responsible for:

1. Reading requested capabilities.
2. Reading user provider selections.
3. Discovering available providers from the Registry.
4. Validating provider capability declarations.
5. Validating module compliance and availability.
6. Applying the provider priority order.
7. Applying installation defaults.
8. Applying permitted fallback policy.
9. Reporting warnings and errors.
10. Returning the final provider selection to the Deployment Engine.

The Resolver SHOULD NOT perform deployment itself.

The Deployment Engine remains responsible for actually deploying the selected module.

---

## 15. Registry Responsibilities

The Registry is responsible for discovering provider candidates.

For each module, the Registry SHOULD expose at least:

* Module ID
* Module name
* Module version
* Specification version
* Category
* Status
* Provided capabilities
* Compliance state
* Dependencies

The Registry does not decide which provider is preferred for an installation.

Provider selection belongs to installation configuration and the Provider Resolver.

---

## 16. Deployment Engine Responsibilities

The Deployment Engine consumes the final provider selection produced by the Provider Resolver.

It MUST NOT assume that a provider is valid merely because the Resolver returned its module ID.

Before deployment, normal module validation and dependency validation still apply.

The Deployment Engine SHOULD report the provider selected for each capability as part of the installation plan.

---

## 17. Fresh Installation Behaviour

A fresh HomeLab Sentinel installation SHOULD expose provider choices for capabilities that support multiple implementations.

For example:

```text
Metrics provider

  [ ] Prometheus
  [ ] VictoriaMetrics

Default: Prometheus
```

The default SHOULD be preselected.

The user MAY accept the default or choose another available provider.

The installation process SHOULD clearly indicate which provider will be used before deployment begins.

---

## 18. Example Installation Resolution

A fresh installation requests:

```text
metrics
monitoring
```

The Registry discovers:

```text
prometheus
  provides: metrics, monitoring

victoriametrics
  provides: metrics, monitoring
```

The installation default is:

```text
metrics -> prometheus
```

The user selects:

```text
metrics -> victoriametrics
```

The Resolver validates the selection and produces:

```text
Capability: metrics
Provider: victoriametrics
Source: user selection
Status: valid
```

The Deployment Engine then deploys VictoriaMetrics.

---

## 19. Example Recovery

The user selects VictoriaMetrics, but the module is missing from the installation source.

The Resolver reports:

```text
[WARNING] Configured provider is unavailable.
[DETAIL] Capability: metrics
[DETAIL] Requested provider: victoriametrics
[DETAIL] Module was not found.
[SUGGESTION] The installation default will be used.
[INFO] Selected provider: prometheus
```

The installation continues with Prometheus.

The user's selection remains unchanged for future operations.

---

## 20. Resolution Failure and Suggestions

Provider resolution failures MUST produce actionable diagnostics.

When no valid provider can be selected for a requested capability, the Resolver MUST:

1. Report the capability that could not be resolved.
2. Report why provider resolution failed.
3. Suggest available providers when candidates exist.
4. Suggest a recommended provider when an installation recommendation is defined.
5. Explain what action the user can take to continue.
6. Stop installation when no valid provider can be selected.

Suggestions are informational and MUST NOT silently become provider selections.

The Resolver MUST NOT modify the user's provider configuration as a side effect of reporting an error.

Example:

```text
[ERROR] No provider available.
[DETAIL] Capability: metrics
[DETAIL] No installed or available module provides this capability.

[SUGGESTION] Install a provider that supports: metrics
[SUGGESTION] Recommended provider: Prometheus
[SUGGESTION] Installation cannot continue until a provider is available.
```

A suggestion MUST NOT override an explicit user selection.


## 21. Design Goals

The Provider Architecture is designed to provide:

* Multiple implementations of the same functionality.
* Clear user choice.
* Predictable defaults.
* Safe automatic recovery.
* No silent configuration mutation.
* Actionable diagnostics.
* Deterministic provider selection.
* Separation between discovery, resolution, and deployment.
* Future support for additional providers without changing the core architecture.

The architecture SHOULD make adding a new provider primarily a module-registration task rather than a core-code modification.
