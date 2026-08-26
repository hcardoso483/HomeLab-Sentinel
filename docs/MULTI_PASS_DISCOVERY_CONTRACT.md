# HomeLab Sentinel Multi-Pass Discovery Contract

## Purpose

HomeLab Sentinel Discovery is an observation system.

A single provider scan is not sufficient evidence of current network
presence because valid devices may respond slowly, intermittently, or not
at all during an individual scan.

Multi-Pass Discovery improves observation reliability by collecting
multiple independent provider observations before publishing the result of
one Discovery cycle.

## Terminology

### Discovery cycle

One complete HomeLab Sentinel Discovery operation.

A cycle contains all required Discovery passes, consolidation, storage,
correlation, and publication of the resulting runtime state.

### Discovery pass

One execution of the configured Discovery provider against one authorized
Discovery scope.

A pass is observation evidence. It is not a retry.

### Observation

Evidence produced by a Discovery provider during a pass.

Repeated observation of the same device in multiple passes is meaningful
evidence and must not be treated merely as accidental duplication.

### Presence

The conclusion derived from observations collected during a completed
Discovery cycle.

### Retry

Recovery from an execution failure of the Discovery pipeline.

Pipeline retry and Multi-Pass Discovery are separate mechanisms and MUST
remain semantically independent.

## v1 Pass Policy

Multi-Pass Discovery v1 performs three Discovery passes for every
authorized Discovery scope.

The default policy is:

    passes: 3

A configurable interval MUST separate consecutive passes.

The implementation MUST permit the pass count and interval to be changed
without modifying provider code.

## Provider Independence

Multi-Pass orchestration belongs to the HomeLab Sentinel Discovery layer.

Providers perform one scan when invoked.

Providers MUST NOT implement the Multi-Pass policy themselves.

The contract therefore remains valid for future Discovery providers in
addition to the current nmap provider.

## Observation Semantics

Each successful provider pass contributes independent evidence.

For a three-pass cycle:

    3/3  observed in all passes
    2/3  observed in two passes
    1/3  observed in one pass
    0/3  not observed during this cycle

A device observed in only one pass is still an observed device.

Failure to observe a device during a pass MUST NOT be interpreted as a
provider execution failure.

A 0/3 result MUST NOT by itself delete persistent identity or historical
knowledge about a device.

## Consolidation

All successful passes belonging to the same Discovery cycle MUST be
consolidated before the cycle is considered complete.

Consolidation MUST preserve sufficient evidence to determine how many
passes observed a device.

Repeated observations across passes MUST NOT be discarded before
pass-level presence evidence can be derived.

The consolidated result becomes the current Discovery observation for that
cycle.

## Storage and Correlation

Storage and correlation occur after Multi-Pass observation collection.

The Discovery pipeline MUST NOT independently perform the entire
store/correlate/publish sequence once per normal Discovery pass.

Persistent Identity remains separate from current Discovery presence.

Discovery answers:

    What did Sentinel observe during this cycle?

Persistent Identity answers:

    Who is this device across time?

## Failure Semantics

The following conditions are different and MUST remain distinguishable:

1. Host not observed during a successful pass.
2. Provider pass execution failure.
3. Discovery cycle execution failure.
4. Pipeline retry after a retryable failure.

A host not responding is normal observation evidence and MUST NOT trigger
pipeline recovery by itself.

A provider execution failure MAY cause the Discovery cycle to fail
according to Discovery runtime policy.

The existing runtime retry mechanism remains responsible for recovery from
retryable pipeline failures.

Multi-Pass Discovery MUST NOT consume or replace that retry mechanism.

## Completion Semantics

A Discovery cycle is complete only after:

1. all required normal passes have completed successfully;
2. their observations have been consolidated;
3. consolidated observations have been stored;
4. correlation has completed successfully; and
5. the resulting Discovery runtime state has been published.

Completion MUST NOT be published merely because one provider pass exited
successfully.

## Current Presence

Multi-Pass Discovery establishes observation evidence for current
presence.

The v1 contract preserves pass evidence without requiring final long-term
presence policy.

Future presence policy may distinguish states such as:

    PRESENT
    RECENTLY_SEEN
    STALE

Those states MUST be derived from observation evidence rather than by
assuming that absence from one scan means disappearance.

## Future Evidence Sources

Network Discovery is one independent observation source.

The architecture MUST permit future evidence from sources including:

- SNMP
- Prometheus / Blackbox
- Home Assistant
- switches
- access points
- service probes
- storage systems
- cameras
- DHCP / DNS
- other provider adapters

No individual observation provider owns Persistent Identity.

## Non-Goals for v1

Multi-Pass Discovery v1 does not:

- seed Persistent Identity;
- delete historical entities;
- define final device-health policy;
- define VLAN topology;
- integrate Home Assistant;
- perform root-cause analysis;
- replace Monitoring;
- replace the existing pipeline retry mechanism.

Those capabilities may consume Multi-Pass Discovery evidence later.

## Core Invariant

HomeLab Sentinel MUST distinguish:

    "I did not observe this device in this pass"

from:

    "This device does not exist"

and from:

    "Discovery failed"

Multi-Pass Discovery exists to make that distinction reliable.
