# pki/ — public part of the lab PKI

Single-tier PKI: the **airgap-lab Root CA** on `airgap-lab-infra` signs server certificates directly (`pathlen:0`).

| File | Content |
|---|---|
| `ca.crt`, `ca.cnf` | Root CA certificate and its OpenSSL config |
| `registry.crt`, `registry.cnf` | Registry server certificate (SAN `airgap-lab-infra`, `10.10.10.10`) and its config |

Private keys never live here: CA key under `/srv/ca/private/` and registry key under `/srv/registry/tls/` on infra.
Details, fingerprints and expiry dates: [`docs/ca/ca.md`](../docs/ca/ca.md).

Kubernetes uses its own CA, created by `kubeadm init` under `/etc/kubernetes/pki/` on cp1. It is separate from this lab CA.
