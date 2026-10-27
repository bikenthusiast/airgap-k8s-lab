# Network plan

## Topology

```
                     Mac (10.10.10.100)
                            │
          ─────── host-only network "airgap-lab" 10.10.10.0/24 ───────
           │                │                 │                │
     infra .10          cp1 .11           w1 .21           w2 .22
           │   ▲ NTP (UDP 123) ◄──────────────┴────────────────┘
           │
        NAT (enp0s8) ──► internet (packages, images, upstream NTP)
```

## Networks

| | |
|---|---|
| Lab network | 10.10.10.0/24, VirtualBox host-only network `airgap-lab` |
| Mac (host) | 10.10.10.100 — VirtualBox assigns the host the first address of the DHCP range |
| DHCP pool | 10.10.10.100–200; only used temporarily (base VM, freshly started clones) |
| Static node addresses | 10.10.10.10–99 |
| NAT | VirtualBox NAT, 10.0.2.0/24, per VM; only on `infra` |
| Name resolution | `/etc/hosts` on every node (optionally also on the Mac); no DNS server yet |
| Pod network (CNI, planned) | 10.244.0.0/16 — must not overlap the lab network |
| Service network (planned) | 10.96.0.0/12 — kubeadm default |

## Nodes

| Hostname | IP | Interfaces | Default route | Internet | Role |
|---|---|---|---|---|---|
| airgap-lab-infra | 10.10.10.10/24 | `enp0s3` host-only, `enp0s8` NAT (DHCP) | via NAT (10.0.2.2) | yes | NTP server, CA and registry (planned) |
| airgap-lab-cp1 | 10.10.10.11/24 | `enp0s3` host-only | none | no | control plane (planned) |
| airgap-lab-w1 | 10.10.10.21/24 | `enp0s3` host-only | none | no | worker (planned) |
| airgap-lab-w2 | 10.10.10.22/24 | `enp0s3` host-only | none | no | worker (planned) |
| airgap-lab-base | DHCP | `enp0s3` host-only, `enp0s8` NAT | via NAT | yes | golden image, off during normal operation |

Node configuration: static IP in `/etc/netplan/01-airgap-lab.yaml` (`optional: true`), cloud-init network config disabled.

## Lab services

| Service | Host | Port | Clients | Config |
|---|---|---|---|---|
| NTP (chrony) | airgap-lab-infra | UDP 123 | 10.10.10.0/24 | `/etc/chrony/conf.d/airgap-lab-server.conf` |
| CA | airgap-lab-infra | — | planned | `docs/ca/ca.md` |
| Container registry | airgap-lab-infra | planned | planned | planned |

## Time

| | |
|---|---|
| Service | chrony on all nodes, timezone `Etc/UTC` |
| infra | syncs from the Ubuntu NTP pools via NAT; serves the lab: `allow 10.10.10.0/24`, `local stratum 10` (keeps serving if upstream is lost) |
| cp1, w1, w2 | `server 10.10.10.10 iburst prefer` in `/etc/chrony/conf.d/airgap-lab-client.conf`; default pools stay configured but are unreachable (`^?`) |
| Drop-in loading | the active `chrony.conf` had no `confdir`; one line `confdir /etc/chrony/conf.d` added, original kept as `chrony.conf.orig` |
| Why | VirtualBox without Guest Additions doesn't sync guest clocks; measured drift without sync: up to −11 s within a few hours |

Commands: `chronyc -n sources` (`^*` = active source), `chronyc tracking`, `sudo chronyc makestep` (force correction after snapshot restore or Mac sleep).

## Air-gap concept

- Only `infra` can reach the internet; `cp1`, `w1`, `w2` have no NAT adapter and no route out.
- Everything the cluster needs from outside is provided by `infra`: time (done), packages and container images (own registry, planned).
- Later option: remove the NAT adapter from `infra` too, once the registry is populated. NTP keeps working thanks to `local stratum 10`.

## Verification

Run from the Mac after every failure-injection exercise and after restoring `clean-os`:

| Script | Checks | Pass criterion |
|---|---|---|
| `./scripts/check-connectivity.sh` | full-mesh ping by name, ping to the Mac, internet access | all node-to-node cells `ok`; only infra `reachable` |
| `./scripts/check-time.sh` | clock offset vs. Mac, sync state, service, timezone, active source | `synced yes` everywhere; offsets within ± rtt; workers' source `10.10.10.10` |

Last connectivity result: [`connectivity-check.txt`](connectivity-check.txt)

## Open decision before kubeadm

`cp1`, `w1`, `w2` have **no default route**. kubeadm and the kubelet pick the node IP from the default-route interface and fail without one (`unable to select an IP from default routes`). Options:

1. Default route via `infra` (infra forwards inside the lab, but no NAT to the internet) — keeps the air gap, realistic
2. Set the node IP explicitly (`--apiserver-advertise-address`, kubelet `--node-ip`) and add a blackhole default route

To be decided in the kubeadm phase.

## Decision: default route for cp1, w1, w2 (2026-10-27)

- **Chosen:** default route via `airgap-lab-infra` (10.10.10.10), set in `/etc/netplan/01-airgap-lab.yaml`.
- **Why:** kubeadm and the kubelet pick the node address from the default route; without one, address detection fails.
- **Air gap still holds:** infra has `net.ipv4.ip_forward = 0`, so traffic to the internet ends on infra.
- **Verified:** `curl https://1.1.1.1` from w1 → timeout (exit 28); `curl https://registry.k8s.io` → no DNS (exit 6).
- **Side effect:** internet access from nodes fails slowly (timeout) instead of immediately.
