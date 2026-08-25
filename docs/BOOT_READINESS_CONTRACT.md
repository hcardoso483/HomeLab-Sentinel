# HomeLab Sentinel Boot Readiness Contract

## Status

Platform hardening contract, version 1.0.

## Purpose

Post-boot verification must begin only after the current boot has proven the
minimum stable platform state required for verification.

Elapsed time alone is not readiness.

## Runtime State

The authoritative current-boot readiness record is:

```text
/run/homelab-sentinel/boot-ready
```

Because `/run` is ephemeral, readiness cannot survive a reboot.

## Producer

`scripts/wait-core-api.sh` is the readiness producer.

Readiness requires consecutive successful checks of:

- the Core API health endpoint
- read-only access to the Living Inventory database
- supported Inventory schema visibility
- a basic read from the `entities` table

The readiness file is published atomically only after consecutive successful
readiness passes.

## Consumer

`scripts/check-boot-ready.sh` validates that the readiness record:

- exists
- belongs to the current kernel boot ID
- confirms Core API readiness
- confirms Inventory readiness

`verify-sentinel.sh` refuses to run post-boot regression before this contract is
satisfied.

## Slow Storage

The contract does not assume a fixed boot delay. Slow backing storage may need
longer, while faster systems may become ready almost immediately. Readiness is
therefore based on proven stable state rather than an arbitrary sleep.
