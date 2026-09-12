# ADR-0009: Multi-arch bundle (amd64 and arm64) from day one

- **Status:** Accepted
- **Date:** 2026-09-11

## Context

The lab runs on amd64 (Mac), the later hardware cluster on arm64 (Raspberry
Pi 5). Images, packages and binaries are architecture-specific. A bundle
containing only one architecture would have to be redesigned for the port.

## Decision

The bundle carries both architectures from the start. Images are copied with
all platforms (`skopeo copy --all` or the equivalent crane options), packages
and binaries are separated into `amd64/` and `arm64/`. The list lives in
`versions.yaml` under `platform.architectures`.

## Consequences

- Porting to the Pi (M7) needs no new bundle concept.
- The bundle roughly doubles in size.
- It creates a realistic supply-chain lesson: an image that exists only for
  amd64 shows up at build time instead of in production.

## Alternatives considered

- **amd64 only, extend later:** smaller, but defers the problem to M7.
