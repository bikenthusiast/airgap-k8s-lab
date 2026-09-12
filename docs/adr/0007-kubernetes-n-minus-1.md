# ADR-0007: Install Kubernetes N-1, target N for the upgrade

- **Status:** Accepted
- **Date:** 2026-09-11

## Context

In air-gapped environments the hard part is not the initial installation but
the lifecycle: updates have to be prepared, transported and applied entirely
offline.

## Decision

Install the latest patch of the **second-to-last** minor version (currently
1.36.x). The current minor version (1.37.x) is the target of the offline
upgrade in M6. Both are recorded in `versions.yaml`.

## Consequences

- The upgrade becomes a real, repeatable milestone instead of a statement of
  intent.
- The bundle must later be able to hold two Kubernetes versions at once.
- Still a supported Kubernetes version.

## Alternatives considered

- **Install the latest version:** leaves no upgrade path to practise on until
  the next release ships.
