# HomeLab Sentinel Core API

**Core API Version:** 1.0

**Status:** Draft

---

## Purpose

The HomeLab Sentinel Core API exposes authoritative Sentinel Core state through stable, versioned HTTP interfaces.

The API is a presentation and integration boundary over Core state.

It must not bypass the Sentinel Core by querying discovery providers, monitoring providers, infrastructure components, or module-specific storage directly.

Initial Core API 1.0 scope is read-only.

---

## Principles

The Core API follows these principles:

- Sentinel Core remains authoritative.
- API consumers do not reconstruct inventory independently.
- Provider-specific implementation details must not leak into API contracts.
- API responses must remain machine-readable and stable within a version.
- Read-only inventory access comes before mutation endpoints.
- Unknown information remains unknown rather than being guessed.
- Historical evidence remains distinguishable from current state.
- Unresolved observations remain visible as unresolved evidence.
- API evolution must preserve version boundaries.

---

## Versioning

Core API 1.0 uses the path prefix:

```text
/api/v1
```

Breaking contract changes require a new API version.

Compatible additions may be introduced within the same version when they do not change the meaning of existing fields.

---

## Health Endpoint

```text
GET /api/v1/health
```

Purpose:

- Confirm that the Core API process is reachable.
- Confirm that the inventory database can be opened.
- Report the inventory schema version.

Example response:

```json
{
  "status": "ok",
  "inventory_schema_version": 2
}
```

Core API 1.0 health does not represent overall homelab health.

It reports the health of the API and its required Core inventory dependency only.

---

## Inventory List

```text
GET /api/v1/inventory
```

Returns one Living Inventory 1.0 record per resolved Sentinel entity.

Each record follows the Living Inventory contract defined in `docs/LIVING_INVENTORY.md`.

Example response:

```json
{
  "items": [
    {
      "entity_id": "dev-...",
      "entity_type": "device",
      "first_seen": "2026-08-19T14:15:41Z",
      "last_seen": "2026-08-19T14:20:37Z",
      "observation_count": 2,
      "current": {
        "ip_addresses": ["192.168.1.20"],
        "mac_address": "BC:24:11:59:68:6A",
        "hostname": "pi.hole"
      },
      "history": {
        "ip_addresses": ["192.168.1.20"],
        "mac_addresses": ["BC:24:11:59:68:6A"],
        "hostnames": ["pi.hole"]
      },
      "providers": ["nmap"]
    }
  ]
}
```

Unresolved observations are not returned as inventory entities.

---

## Inventory Entity

```text
GET /api/v1/inventory/{entity_id}
```

Returns one authoritative Living Inventory record for the requested Sentinel entity.

Example response:

```json
{
  "entity_id": "dev-...",
  "entity_type": "device",
  "first_seen": "2026-08-19T14:15:41Z",
  "last_seen": "2026-08-19T14:20:37Z",
  "observation_count": 2,
  "current": {
    "ip_addresses": ["192.168.1.20"],
    "mac_address": "BC:24:11:59:68:6A",
    "hostname": "pi.hole"
  },
  "history": {
    "ip_addresses": ["192.168.1.20"],
    "mac_addresses": ["BC:24:11:59:68:6A"],
    "hostnames": ["pi.hole"]
  },
  "providers": ["nmap"]
}
```

If the entity does not exist, the API returns an error response with HTTP status `404`.

---

## Inventory History

```text
GET /api/v1/inventory/{entity_id}/history
```

Returns the resolved observation history associated with the requested Sentinel entity.

The response preserves observation provenance and correlation method.

Example response:

```json
{
  "entity_id": "dev-...",
  "items": [
    {
      "observation_id": "obs-...",
      "provider": "nmap",
      "discovery_method": "host-discovery",
      "discovered_at": "2026-08-19T14:15:41Z",
      "received_at": "2026-08-19T14:15:42Z",
      "correlation_method": "new-entity-mac-evidence",
      "payload": {
        "schema_version": "1.0",
        "provider": "nmap",
        "discovery_method": "host-discovery",
        "discovered_at": "2026-08-19T14:15:41Z",
        "ip_addresses": ["192.168.1.20"],
        "mac_address": "BC:24:11:59:68:6A",
        "hostname": "pi.hole"
      }
    }
  ]
}
```

The API does not rewrite historical observations.

---

## Unresolved Observations

```text
GET /api/v1/inventory/unresolved
```

Returns observations that Core correlation has evaluated but could not safely associate with a persistent entity.

Example response:

```json
{
  "items": [
    {
      "observation_id": "obs-...",
      "status": "unresolved",
      "reason": "no strong identity evidence available",
      "decided_at": "2026-08-19T14:15:42Z",
      "provider": "nmap",
      "discovery_method": "host-discovery",
      "discovered_at": "2026-08-19T14:15:41Z",
      "received_at": "2026-08-19T14:15:41Z",
      "payload": {
        "schema_version": "1.0",
        "provider": "nmap",
        "discovery_method": "host-discovery",
        "discovered_at": "2026-08-19T14:15:41Z",
        "ip_addresses": ["192.168.1.13"],
        "mac_address": null,
        "hostname": null
      }
    }
  ]
}
```

Unresolved observations must not be silently promoted to entities by the API layer.

---

## Response Format

Core API 1.0 uses JSON responses.

Collection endpoints return an object containing an `items` array.

Single-resource endpoints return one JSON object.

Timestamps use the same ISO 8601 representation provided by authoritative Core state.

Unknown scalar values are represented as `null`.

Unknown or empty collections are represented as empty arrays where defined by the underlying Core contract.

---

## Error Format

Errors use a stable JSON structure.

Example:

```json
{
  "error": {
    "code": "entity_not_found",
    "message": "Sentinel entity not found."
  }
}
```

Initial HTTP status behavior:

```text
200  Request completed successfully
400  Invalid request
404  Requested Core resource does not exist
500$ Core API or required Core dependency failed
```

Error responses must not expose stack traces, database internals, secrets, or provider credentials.

---

## Authentication Boundary

Authentication is a Sentinel Core responsibility.

Core API 1.0 defines the inventory contract but does not yet define the final authentication implementation.

The initial implementation may bind only to a trusted local or management interface during development.

A production-facing Sentinel UI must not depend on permanently unauthenticated unrestricted API access.

Authentication and authorization may be introduced without changing the meaning of the versioned inventory resources.

---

## Sentinel UI Relationship

The native Sentinel UI consumes Core API resources.

Conceptually:

```text
Discovery / Monitoring / Integrations
                |
                v
          Sentinel Core
                |
                v
          Core API v1
                |
                v
           Sentinel UI
```

The UI is responsible for presentation and interaction.

The Core API is responsible for exposing authoritative Core state.

The UI must not query providers or the inventory database directly.

---

## Implementation Independence

Core API 1.0 defines HTTP resource contracts rather than a required web framework.

The implementation may use FastAPI, Flask, another Python HTTP framework, or a future Core-native service.

Changing the implementation technology must not require changing the API contract unless the contract itself is intentionally versioned.

---

## Design Rules

- Core API 1.0 is read-only.
- Sentinel Core remains authoritative.
- The API does not perform discovery.
- The API does not perform correlation.
- The API does not assign permanent entity identities.
- The API does not reconstruct inventory independently.
- Living Inventory semantics remain defined by the Core inventory model.
- Historical observations remain immutable evidence.
- Unresolved observations remain explicitly unresolved.
- Provider-specific storage and implementation details remain hidden.
- API responses are JSON.
- Breaking changes require a new API version.
- Authentication remains a Core boundary even when development deployments are initially restricted to trusted interfaces.
- The Sentinel UI communicates with Core through stable interfaces rather than direct infrastructure access.

---

## Status

Core API Version: 1.0

Status: Draft
