# ADR-0003: Dedicated infra VM as bastion and service node

- **Status:** Accepted
- **Date:** 2026-09-11

## Context

Inside the air gap we need services that normally come from the internet:
registry, DNS, time, package source. We also need a controlled access path from
the Mac.

## Decision

A dedicated VM `infra` covers both:

1. **Bastion:** the only host connected to the Mac (host-only network = data
   diode). Cluster nodes are reachable only through it (SSH ProxyJump).
2. **Service node:** registry, DNS, NTP and APT repository (from M4).

`infra` is deliberately **not** a Kubernetes node.

## Consequences

- Clean separation: the infrastructure the cluster depends on does not run
  inside the cluster. A broken cluster does not take the registry with it.
- Exactly one crossing point between the zones, so exactly one place to secure
  and check (e.g. no IP forwarding).
- Costs an extra 4 GB of RAM.

## Alternatives considered

- **Registry on the control-plane node:** saves a VM but couples infrastructure
  and cluster.
- **Registry inside the cluster:** chicken-and-egg problem at bootstrap, since
  the cluster needs its own images before it runs.
