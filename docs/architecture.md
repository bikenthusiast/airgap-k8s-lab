# Architecture documentation: airgap-k8s-lab

Structured after [arc42](https://arc42.org). Sections that are not worked out
yet are marked *open* and get filled in with their milestones. Individual
decisions live as ADRs in [`adr/`](adr/).

**As of:** 2026-09-11, milestone M0

---

## 1. Introduction and goals

### 1.1 Requirements overview

Build a Kubernetes cluster that can be installed, operated and upgraded without
any internet access. All dependencies — operating system packages, binaries,
container images, certificates, time, name resolution — are provided inside the
isolated zone.

The project is a learning and portfolio project. It should demonstrate
practical competence in building and operating sovereign, internet-isolated
platforms.

### 1.2 Quality goals

| Prio | Quality goal | What it means here |
|---|---|---|
| 1 | **Isolation (provable)** | No node can reach the internet. This is tested automatically, not merely claimed. |
| 2 | **Reproducibility** | The whole cluster can be rebuilt identically from `versions.yaml` and the bundle. |
| 3 | **Operability (day 2)** | Upgrade, certificate rotation and backup/restore all work offline. |
| 4 | **Portability** | The same code runs on VMs (amd64) and on Raspberry Pi 5 (arm64). |
| 5 | **Traceability** | Every significant decision is documented with its rationale. |

### 1.3 Stakeholders

| Role | Expectation |
|---|---|
| Project owner (development, operations) | Learn something, get a working lab, reusable code |
| Portfolio reader (e.g. recruiter, interviewer) | Quickly grasp what was built, why, and how it is proven |

---

## 2. Constraints

| Type | Constraint |
|---|---|
| Technical | Lab host is an Intel Mac with 32 GB RAM, architecture amd64 |
| Technical | Virtualisation with VirtualBox 7 and Vagrant (ADR-0002) |
| Technical | Target platform later Raspberry Pi 5, architecture arm64 (M7) |
| Technical | Kubernetes installed with kubeadm (project premise) |
| Organisational | One-person project, delivered in milestones |
| Convention | Documentation in English, arc42 plus ADRs (ADR-0001) |
| Convention | Versions only in `versions.yaml`, topology only in the inventory (ADR-0010) |

---

## 3. Context and scope

```
                     ┌─────────────────────────────── internet ───────────────────────────────┐
                     │ registry.k8s.io · quay.io · docker.io · ghcr.io · pkgs.k8s.io ·        │
                     │ Ubuntu archive · GitHub releases                                       │
                     └──────────────────────────────┬─────────────────────────────────────────┘
                                                    │ downloads happen only here, at build time
                                          ┌─────────▼─────────┐
                                          │  online zone      │
                                          │  (Mac)            │
                                          └─────────┬─────────┘
                                                    │ data diode (host-only, scp)
                                          ┌─────────▼─────────┐
                                          │  air-gap zone     │
                                          │  (infra + cluster)│
                                          └───────────────────┘
```

| Neighbour | Interface | Direction |
|---|---|---|
| Upstream registries and package sources | HTTPS | only the online zone downloads; the air-gap zone never does |
| Online zone (Mac) | SSH/scp over the host-only network, to `infra` only | Mac → infra |
| Offline storage of the root CA | manual, only for signing | outside both zones |

---

## 4. Solution strategy

| Quality goal | Approach | ADR |
|---|---|---|
| Isolation | Enforced in layers (network topology, NAT cut, closed side channels) plus an automated proof | 0008 |
| Isolation | The only crossing point is the data diode to the bastion | 0003 |
| Reproducibility | All versions pinned in `versions.yaml`; the bundle is built from it alone | 0009 |
| Reproducibility | Topology declared once in the Ansible inventory; Vagrant reads the same file | 0010 |
| Operability | Install N-1 so that the offline upgrade is a real exercise | 0007 |
| Operability | Registry acts as a mirror: image references stay unchanged | 0004 |
| Security | Two-tier PKI with an offline root | 0005 |
| Portability | Ubuntu LTS on both platforms, multi-arch bundle | 0006, 0009 |

---

## 5. Building block view

### 5.1 Repository (level 1)

| Building block | Responsibility |
|---|---|
| `versions.yaml` | What gets installed |
| `ansible/inventory/hosts.yml` | Where it gets installed |
| `Vagrantfile` | Lab platform and air-gap enforcement |
| `scripts/airgap.sh` | Seal, unseal, host-side check |
| `ansible/` | Configuration and proof inside the VMs |
| `bundle/` | Build and verify the offline bundle (M3) |
| `pki/` | Create and manage the CA hierarchy (M2) |
| `docs/` | Architecture, decisions, journal |

### 5.2 Runtime building blocks (target picture)

| Building block | Host | Task | Milestone |
|---|---|---|---|
| Zot (registry) | infra | Container images and Helm charts (OCI) | M4 |
| DNS | infra | Name resolution for `lab.internal` | M4 |
| chrony | infra | The only time source inside the air gap | M4 |
| APT repository | infra | Operating system packages from the bundle | M4 |
| Control plane | cp1 | API server, etcd, scheduler, controller manager | M5 |
| Workers | w1, w2 | Workloads | M5 |
| Cilium | all cluster nodes | Pod network | M5 |

---

## 6. Runtime view

### 6.1 Start the lab and seal it (implemented in M0)

1. `make up` → Vagrant boots each VM with NAT (needed for SSH during boot).
2. On first boot: base provisioning disables unattended upgrades and writes
   `/etc/hosts`. Nothing is downloaded.
3. The `after :up` trigger runs `scripts/airgap.sh seal <vm>`, disconnecting the
   NAT link.
4. `make verify` → host-side check, then guest-side proof via Ansible through
   the bastion.

### 6.2 Move software into the air gap (target picture, M3/M4)

1. The Mac builds the bundle from `versions.yaml`.
2. `scp` to `infra` through the data diode.
3. `infra` verifies signature and checksums; on mismatch it aborts.
4. Packages → APT repository, images and charts → Zot.

### 6.3 Image pull on a node (target picture, M5)

1. kubelet requests e.g. `registry.k8s.io/kube-proxy:v1.36.4`.
2. containerd finds the mirror `registry.lab.internal` in
   `/etc/containerd/certs.d/registry.k8s.io/hosts.toml`.
3. It pulls from Zot over TLS, using a certificate from the private PKI.
4. The original name is preserved everywhere; no manifest needs rewriting.

---

## 7. Deployment view

### 7.1 Lab on the Mac (M0 to M6)

| VM | Role | vCPU | RAM | Air-gap IP | Data diode |
|---|---|---|---|---|---|
| infra | Bastion, infra services | 2 | 4 GB | 10.20.0.10 | 192.168.56.10 |
| cp1 | Control plane | 2 | 4 GB | 10.20.0.11 | – |
| w1 | Worker | 2 | 4 GB | 10.20.0.21 | – |
| w2 | Worker | 2 | 4 GB | 10.20.0.22 | – |

| Network | VirtualBox type | Range | Purpose |
|---|---|---|---|
| NAT (NIC1) | NAT | 10.0.2.0/24 | only for Vagrant during boot, disconnected afterwards |
| airgap (NIC2) | internal network | 10.20.0.0/24 | cluster network, no gateway |
| data diode (NIC3, infra only) | host-only | 192.168.56.0/24 | access from the Mac |
| Pods | Cilium | 10.244.0.0/16 | pod network |
| Services | Kubernetes | 10.96.0.0/12 | service network |

### 7.2 Raspberry Pi cluster (M7, open)

Four Pi 5 on a dedicated switch with no uplink (physical air gap). The data
diode becomes a USB storage device. Details follow in M7.

---

## 8. Cross-cutting concepts

### 8.1 Air-gap enforcement (defence in depth)

| Layer | Measure | Where |
|---|---|---|
| Topology | Cluster nodes only on the internal network, no gateway | `Vagrantfile` |
| NAT | Link disconnected after every boot | trigger + `scripts/airgap.sh` |
| Forwarding | No IP forwarding on the Mac or the bastion | checked by `status` and `verify` |
| Side channels | Shared folders, clipboard, drag & drop, time sync disabled | `Vagrantfile` |
| Behaviour | Unattended upgrades and snap refresh disabled | base provisioning |
| Proof | Positive control plus three negative tests per node | `verify-airgap.yml` |
| Exception | Unsealing only as break glass, and it is logged | `.airgap-audit.log` |

### 8.2 Versioning

There are exactly two configuration sources: `versions.yaml` (what) and the
inventory (where). Everything else derives from them. Version changes are their
own commits with a rationale.

### 8.3 Time

Certificates have validity windows. There is no public time server inside the
air gap, therefore:

- The VMs must **not** take their clock from the Mac (Guest Additions time sync
  is off). Otherwise the NTP architecture would be theatre.
- From M4 onwards the only time source is chrony on `infra`; the cluster nodes
  synchronise against it.
- On the Pi (M7): RTC battery, optionally GPS with PPS as a stratum-1 source.

### 8.4 Node IP with multiple network interfaces

Every VM has the (disconnected) NAT adapter carrying the default route. Without
explicit configuration, kubeadm and kubelet pick the address of the default
route, which is 10.0.2.15 — identical on every VM and useless inside the air
gap. **Therefore, mandatory in M5:** set `advertiseAddress` for the API server
and `node-ip` for every kubelet to the node's air-gap IP.

### 8.5 Handling secrets

Private keys (CA, SSH) never live in the repository. Enforced by `.gitignore`
and pre-commit hooks (gitleaks, detect-private-key). The root CA is kept
offline (see `pki/README.md`).

---

## 9. Architecture decisions

| ADR | Title | Status |
|---|---|---|
| [0001](adr/0001-arc42-and-adrs.md) | Architecture documentation with arc42 and ADRs | Accepted |
| [0002](adr/0002-virtualbox-and-vagrant.md) | VirtualBox and Vagrant as the lab platform | Accepted |
| [0003](adr/0003-dedicated-infra-vm.md) | Dedicated infra VM as bastion and service node | Accepted |
| [0004](adr/0004-registry-zot-as-mirror.md) | Zot registry, wired in as a containerd mirror | Accepted |
| [0005](adr/0005-two-tier-pki.md) | Two-tier private PKI with an offline root | Accepted |
| [0006](adr/0006-ubuntu-lts.md) | Ubuntu Server 24.04 LTS | Accepted |
| [0007](adr/0007-kubernetes-n-minus-1.md) | Install Kubernetes N-1 | Accepted |
| [0008](adr/0008-air-gap-enforcement.md) | Layered air-gap enforcement and proof | Accepted |
| [0009](adr/0009-multi-arch-bundle.md) | Multi-arch bundle from day one | Accepted |
| [0010](adr/0010-inventory-as-topology-source.md) | Ansible inventory as the single topology source | Accepted |

---

## 10. Quality requirements

| ID | Quality scenario | Evidence |
|---|---|---|
| Q-01 | A connection attempt to the internet fails on every node within 10 s, while the nodes still reach each other. | `make verify` |
| Q-02 | If a NAT link is reconnected by accident, `make status` reports it and exits with code 1. | `make status` |
| Q-03 | After `make destroy`, an identical cluster can be rebuilt from `versions.yaml` and the bundle with no internet. | from M5 |
| Q-04 | Upgrade from 1.36 to 1.37 offline, with no downtime for a test workload of two replicas. | M6 |
| Q-05 | After an etcd restore, all Kubernetes objects from the backup point in time are present again. | M6 |

---

## 11. Risks and technical debt

| ID | Risk / debt | Impact | Mitigation |
|---|---|---|---|
| R-01 | The NAT link is briefly connected while booting (Vagrant needs it for SSH). | A short theoretical window with internet | Unattended upgrades are off; the trigger seals immediately; the Pi cluster (M7) has a physical air gap |
| R-02 | The Mac itself is online; the lab is only logically separated. | No true physical air gap | Accepted for the lab; resolved in M7 |
| R-03 | `vagrant ssh` and `vagrant provision` stop working after sealing. | Unfamiliar workflow | Access via `.ssh-config`; configuration only through Ansible |
| R-04 | Node IP selection by kubeadm (see 8.4) | Cluster would not work | Configure explicitly in M5 |
| R-05 | `host_key_checking` is disabled. | No MITM protection inside the lab network | Lab simplification; manage host keys on the Pi cluster |
| R-06 | Pinned versions not yet checked for compatibility (Cilium ↔ Kubernetes, Helm 4). | Bootstrap could fail | Check before M3, marked `VERIFY` in `versions.yaml` |
| R-07 | Using an intermediate CA as the Kubernetes cluster CA is unverified. | The PKI design may need adjusting | Test in M2 |

---

## 12. Glossary

| Term | Meaning |
|---|---|
| Air gap | Physical or logical separation of a system from the internet |
| Bastion | The only externally reachable host; access to everything else goes through it |
| Break glass | A documented emergency exception to a security rule |
| Bundle | Versioned, signed package of all artefacts for the air gap |
| Data diode | Controlled handover point between the online and air-gap zones |
| Mirror | A registry that serves images under their original names |
| N-1 | One minor version below the current Kubernetes release |
| Positive control | A test proving that the test setup itself works |
| Seal | Disconnecting a VM's NAT link |
| Side channel | An unintended data path around the network separation (e.g. shared folder, time sync) |
