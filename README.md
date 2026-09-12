# airgap-k8s-lab

A Kubernetes cluster with no internet access: built with kubeadm, supplied by a
private container registry, secured by a private PKI, and fully reproducible
from a versioned offline bundle.

## Why this project exists

Plenty of security-critical environments — defence, government, critical
infrastructure, sovereign cloud — run **air-gapped**, physically or logically
separated from the internet. A lot of what we take for granted stops working
there: no `apt install`, no `docker pull`, no public CA, no public time server.

This project recreates such an environment at small scale, with three goals:

1. **Learn.** Understand what a Kubernetes cluster actually depends on, and how
   to provide each of those dependencies offline.
2. **Prove.** Show that the cluster really has no internet access, using
   automated tests instead of assertions.
3. **Operate.** Not just stand a cluster up, but handle day-2 work offline:
   upgrades, certificate rotation, backup and restore.

The result is a portfolio project with traceable architecture documentation
(arc42 and ADRs).

## Architecture at a glance

```
  ONLINE ZONE (Mac)                      AIR-GAP ZONE (VirtualBox, internal net 10.20.0.0/24)
 ┌──────────────────────┐              ┌──────────────────────────────────────────────────┐
 │ bundle build         │    data      │  infra (bastion)  10.20.0.10                     │
 │ versions.yaml        │──diode────▶  │  registry · DNS · NTP · package repo             │
 │ root CA (offline)    │  host-only   │        │                                         │
 │ Ansible / Vagrant    │ 192.168.56.x │        ▼                                         │
 └──────────────────────┘              │  cp1 10.20.0.11   w1 10.20.0.21   w2 10.20.0.22  │
                                       │  control plane    worker          worker         │
                                       └──────────────────────────────────────────────────┘
```

Details: [docs/architecture.md](docs/architecture.md)

## Status and roadmap

| Milestone | Content | Status |
|---|---|---|
| **M0** | Skeleton, lab platform, documentation structure | ✅ done |
| **M1** | Air-gap proof: `make verify` passes | ⏳ next step |
| **M2** | Private PKI: offline root and intermediate CAs | planned |
| **M3** | Bundle build and data diode | planned |
| **M4** | Infra services: registry, DNS, NTP, package repository | planned |
| **M5** | Cluster bootstrap with kubeadm and Cilium | planned |
| **M6** | Day 2: offline upgrade 1.36 → 1.37, certificate rotation, etcd backup/restore | planned |
| **M7** | Port to Raspberry Pi 5 (arm64, physical air gap) | planned |

## Requirements (Mac)

- Intel Mac, 32 GB RAM recommended (the lab reserves 16 GB)
- VirtualBox 7 and Vagrant: `brew install --cask virtualbox vagrant`
- Ansible: `uv tool install ansible-core`
- Optional but recommended: `uv tool install pre-commit && pre-commit install`

## Quick start

```bash
make up        # create the VMs; each one is sealed automatically after boot
make verify    # air-gap proof: host side plus tests inside every VM
ssh -F .ssh-config cp1   # access now goes through the bastion only
```

All commands: `make help`

Step-by-step walkthrough including troubleshooting:
**[docs/getting-started.md](docs/getting-started.md)**

> **Note:** after sealing, `vagrant ssh` deliberately stops working, because it
> uses the disconnected NAT adapter. Access goes through the data diode
> instead (see `.ssh-config`).

## What lives where, and why

| Path | Purpose |
|---|---|
| `README.md` | Entry point: purpose, overview, usage (this file) |
| `docs/getting-started.md` | Step-by-step first setup and troubleshooting |
| `versions.yaml` | **Single source of truth for versions.** Every component entering the air gap is pinned here. |
| `ansible/inventory/hosts.yml` | **Single source of truth for topology.** Nodes, IPs, VM sizes; read by Ansible *and* Vagrant. |
| `Vagrantfile` | Creates the VMs from inventory and versions, and enforces the air gap (networks, NAT cut, closed side channels). |
| `Makefile` | Single entry point. Cluster-changing targets depend on `verify`. |
| `scripts/airgap.sh` | Seal, unseal (break glass, logged) and host-side check. |
| `ansible/ansible.cfg` | Ansible configuration for the lab |
| `ansible/playbooks/ssh-config.yml` | Generates `.ssh-config`: bastion direct, cluster nodes via ProxyJump |
| `ansible/playbooks/verify-airgap.yml` | Guest-side air-gap proof with a positive control |
| `ansible/roles/` | Roles planned per milestone (see the README there) |
| `bundle/` | Concept, later the offline bundle build (M3) |
| `pki/` | Concept, later the private PKI tooling (M2) |
| `docs/architecture.md` | Architecture documentation following arc42 |
| `docs/adr/` | Architecture decision records: every significant decision with its rationale |
| `docs/journal.md` | Work journal: what was done when and why, including dead ends |
| `.gitignore` | Keeps key material, VM data and bundles out of the repository |
| `.pre-commit-config.yaml` | Secret scan (gitleaks) before every commit |

## Security note

This project generates CA keys and SSH keys. **Private keys never belong in the
repository.** `.gitignore` and the pre-commit hooks enforce that. Before
publishing on GitHub, also check the history: `gitleaks git .`

## Documentation

- [Getting started](docs/getting-started.md)
- [Architecture (arc42)](docs/architecture.md)
- [Architecture decisions (ADRs)](docs/adr/)
- [Work journal](docs/journal.md)
