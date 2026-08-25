# HomeLab Sentinel Persistent Identity Contract

## Status

Contract version: 1.0

Persistent Identity answers:

> Who has Sentinel previously identified?

It MUST NOT answer:

> Who is present now?

Current presence remains owned by fresh Discovery and the current Inventory.

## Runtime Location

`/srv/homelab-sentinel/sentinel/identity.db`

Persistent Identity and current Inventory are separate stores.

## Identity Record

Persistent Identity v1 stores MAC identity evidence with:

- entity_id
- identity_type
- identity_value
- identity_class
- confidence
- authoritative
- first_seen
- last_confirmed

For v1, `identity_type = mac`.

Supported classes are `global-mac` and `local-mac`.

## Authority

Globally administered MAC identity MAY be authoritative for preserving a canonical `entity_id`.

Locally administered MAC identity MUST NOT be authoritative in v1. A local MAC MAY be recorded as evidence, but ordinary authoritative lookup MUST NOT return it as proof of permanent identity.

## Registration

Re-registering the same MAC for the same `entity_id` MUST be idempotent.

Registering the same MAC for a different `entity_id` MUST fail.

Persistent Identity MUST NOT silently transfer identity between entities.

## Presence Boundary

The existence of an identity record MUST NOT imply current presence, current IP address, current hostname, current reachability, current health, or current Monitoring state.

`historical identity != current presence`

## Fresh-Boot Inventory Relationship

A later Fresh Boot Inventory slice MAY archive the previous `inventory.db`, create a fresh current Inventory, run fresh Discovery, use `identity.db` only to preserve canonical identity during correlation, and publish Inventory readiness only after fresh Discovery and correlation finish.

Archived Inventory MUST NOT be consulted to establish current presence.
