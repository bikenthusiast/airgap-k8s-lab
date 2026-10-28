# airgap-k8s-lab

Air-gapped Kubernetes practice cluster on four VMs for operating, PKI and deliberate failure-injection exercises as preparation for SRE interviews.

## Build order

1. **Four VMs** — `infra`, `cp1`, `w1`, `w2` (roles: see network plan)
2. **Own CA** (certificate authority) — on `infra`, documented in `docs/ca/`
3. **Own registry** (image store) — on `infra`, TLS certificate issued by the own CA
4. **kubeadm** (Kubernetes installer) — control plane on `cp1`, workers `w1`, `w2`
5. **Failure exercises** — failure catalogue from the preparation plan, section 2

## Environment

| | |
|---|---|
| Host | Mac, <arm64 / x86_64>, <RAM> GB RAM |
| Virtualization | VirtualBox <version> |
| VM OS | Ubuntu Server 24.04 LTS (<arm64 / amd64>) |
| Lab network | VirtualBox host-only network `airgap-lab`, 10.10.10.0/24 — see `docs/network/network-plan.md` |
| Base image | `airgap-lab-base` (generalized, snapshot `generalized`); all nodes are clones |

## VMs

| VM | Role | IP | vCPU | RAM | Disk |
|---|---|---|---|---|---|
| airgap-lab-infra | CA, registry | 10.10.10.10 | 2 | 2 GB | 40 GB |
| airgap-lab-cp1 | Kubernetes control plane | 10.10.10.11 | 2 | <2 / 4> GB | 40 GB |
| airgap-lab-w1 | Worker | 10.10.10.21 | 2 | 2 GB | 40 GB |
| airgap-lab-w2 | Worker | 10.10.10.22 | 2 | 2 GB | 40 GB |

Every VM has a snapshot `clean-os` (freshly configured OS) to reset to after failure exercises.

## Rules

- No private keys or certificates in this repo: they live in `pki/`, which is excluded via `.gitignore`.
- Every failure exercise gets an entry in the error journal: hypothesis → diagnosis → what I missed and why.

![airgap-lab overview](docs/architecture/airgap-lab-overview.svg)
