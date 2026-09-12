# ADR-0004: Zot registry, wired in as a containerd mirror

- **Status:** Accepted
- **Date:** 2026-09-11

## Context

All container images must come from a local registry. Two questions: **which
product**, and **how the nodes consume it**.

## Decision

1. **Product:** Zot. A single binary, OCI-native (Helm charts as OCI artefacts
   too), available for amd64 and arm64, easy to install offline.
2. **Integration:** containerd is configured through
   `/etc/containerd/certs.d/<upstream>/hosts.toml` so that requests for
   `registry.k8s.io`, `quay.io`, `docker.io` and `ghcr.io` are redirected to
   Zot.

## Consequences

- Image references keep their original form
  (`registry.k8s.io/kube-apiserver:…`). No manifests or Helm charts need
  rewriting.
- The `pause` image (containerd's sandbox image) is covered automatically by
  the mirror, but it must be present in the bundle.
- No web UI and no built-in vulnerability scanning, unlike Harbor.

## Alternatives considered

- **Harbor:** offers UI, RBAC and scanning, but is much heavier (several
  containers, a database). It can be added later if scanning is worth showing.
- **CNCF Distribution (registry:2):** equally lightweight, but weaker support
  for OCI artefacts.
- **Rewriting `imageRepository` in kubeadm:** covers only the Kubernetes
  components, not the CNI or workloads.
