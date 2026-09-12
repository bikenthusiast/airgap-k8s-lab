# ADR-0005: Two-tier private PKI with an offline root

- **Status:** Accepted
- **Date:** 2026-09-11

## Context

There is no public CA inside the air gap. Left alone, kubeadm would generate
several unrelated CAs of its own. The registry additionally needs a trusted
server certificate.

## Decision

A private root CA whose key is kept offline signs intermediate CAs for
Kubernetes, etcd, the front proxy and the infra services. Details in
`pki/README.md`.

## Consequences

- A single trust anchor for all services. Nodes and admin machines only need to
  know the root CA.
- If an intermediate CA is compromised, it can be replaced on its own without
  changing the trust anchor.
- Certificate rotation (M6) becomes a realistic exercise.
- Open item: kubeadm's behaviour with an intermediate CA as the cluster CA must
  be verified in M2 (risk R-07).

## Alternatives considered

- **kubeadm defaults (self-generated CAs):** works, but no common anchor and no
  learning value.
- **Single-tier root CA kept online:** simpler, but the most valuable key would
  sit on a server.
