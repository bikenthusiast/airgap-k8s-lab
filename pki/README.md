# pki/ — our own public key infrastructure (milestone M2)

> **Status:** concept. Implemented in M2. Decision: ADR-0005.

## Purpose

There is no public CA inside the air gap. Every TLS connection (Kubernetes API,
etcd, registry) is therefore backed by a two-tier private PKI. The root CA
leaves its secure storage only to sign.

## Planned hierarchy

| CA | Signed by | Purpose | Lifetime (proposed) |
|---|---|---|---|
| Lab Root CA | itself | trust anchor, kept offline | 10 years |
| kubernetes-ca | root | cluster CA (API server, kubelet, admin) | 5 years |
| etcd-ca | root | etcd peer and client certificates | 5 years |
| front-proxy-ca | root | aggregation layer | 5 years |
| infra-ca | root | server certificates of the infra services (registry) | 5 years |

kubeadm reuses an existing CA if `ca.crt` and `ca.key` are placed under
`/etc/kubernetes/pki/` before `kubeadm init` (same for `etcd/ca.*` and
`front-proxy-ca.*`).

**To verify in M2:** how kubeadm behaves when the cluster CA is an intermediate
CA (trust chain in kubeconfig, `kubeadm certs check-expiration`, renewal).

## Rules for key material

1. **Private keys never live in the repository.** `.gitignore` and the
   pre-commit hooks (gitleaks, detect-private-key) enforce this.
2. The root key is stored outside the repository (suggestion: an encrypted disk
   image or a USB stick) and is only attached to sign the intermediates.
3. Only these belong in the repository: configuration (OpenSSL/cfssl/step
   profiles), scripts, and the **public** CA certificates.
4. Time must be correct: without synchronised clocks, certificates are "not yet
   valid" or "expired". See the time concept in `docs/architecture.md`,
   section 8.
