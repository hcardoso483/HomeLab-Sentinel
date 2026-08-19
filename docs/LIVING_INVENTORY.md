# HomeLab Sentinel Living Inventory

**Living Inventory Version:** 1.0
**Status:** Draft

---

## Purpose

The Living Inventory is the current Core representation of correlated infrastructure.

It is derived from persistent Sentinel entities and their resolved observations.

The Living Inventory is not an observation store and does not replace historical evidence.

---

## Inventory Record

Living Inventory 1.0 exposes one record per persistent entity.

Each record contains the Sentinel entity identity, first and last observation times, observation count, current attributes, historical attributes, and contributing providers.

Current state and historical evidence remain separate.

## first_seen

The earliest discovered_at timestamp among observations resolved to the entity.

## last_seen

The latest discovered_at timestamp among observations resolved to the entity.

## observation_count

The number of resolved observations associated with the entity.

## current

For Living Inventory 1.0, current network attributes are taken from the most recent resolved host-discovery observation for the entity.

Current attributes include ip_addresses, mac_address, and hostname.

Unknown values remain null or empty collections.

Historical attributes must not be promoted to current state merely because they were previously observed.

## history

History contains unique observed values across all resolved observations associated with the entity.

Initial historical attributes include IP addresses, MAC addresses, and hostnames.

Historical values are evidence and do not imply current state.

## providers

The providers field contains the unique providers that contributed resolved observations to the entity.

Provider information records provenance and does not define Sentinel identity.

## Operational State

Living Inventory 1.0 does not define authoritative online, offline, or health state.

Discovery provides last_seen evidence but does not independently determine operational health.

Availability and health semantics belong to monitoring and future Core state policy.

## Sentinel UI

The Sentinel UI consumes Living Inventory records through Core interfaces.

Summary views may use entity identity, last_seen, current network attributes, and observation_count.

Detail views may additionally expose historical attributes, contributing providers, and underlying observations.

The Sentinel UI must not reconstruct authoritative inventory independently from provider output or observation history.

## Design Rules

- Current state must remain distinct from historical evidence.
- Only resolved observations contribute to entity inventory.
- Unresolved observations remain outside entity inventory.
- No historical attribute automatically becomes current.
- No inventory field defines permanent identity.
- Unknown values remain unknown.
- Inventory output must remain provider-independent.
- Sentinel Core remains authoritative.

---

## Status

Living Inventory Version: 1.0

Status: Draft
