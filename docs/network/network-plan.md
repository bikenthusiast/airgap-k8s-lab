# Network plan

## Networks

| | |
|---|---|
| Lab network | 10.10.10.0/24, VirtualBox host-only network `airgap-lab` |
| Mac (host) | 10.10.10.1 (assigned by VirtualBox) |
| DHCP range | 10.10.10.100–200 (only used during base install) |
| Static IPs | 10.10.10.10–99 |
| Internet | only `infra`, via a second NAT adapter |
| DNS | `/etc/hosts` on all nodes (no DNS server yet) |
| Pod network (CNI) | 10.244.0.0/16 (must not overlap the lab network) |
| Service network | 10.96.0.0/12 (kubeadm default) |

## Hosts

| Hostname | IP | Adapters | Role |
|---|---|---|---|
| airgap-lab-infra | 10.10.10.10 | host-only + NAT | CA, registry |
| airgap-lab-cp1 | 10.10.10.11 | host-only | control plane |
| airgap-lab-w1 | 10.10.10.21 | host-only | worker |
| airgap-lab-w2 | 10.10.10.22 | host-only | worker |

## Air-gap concept

- Only `infra` can reach the internet; `cp1`, `w1`, `w2` never can.
- Packages and container images are fetched on `infra` and served to the cluster from there (own registry).
- Later option: remove the NAT adapter from `infra` too, once the registry is populated.

## Node configuration

- Static IP via `/etc/netplan/01-airgap-lab.yaml`; cloud-init network config disabled.
- Swap disabled, unique machine-id and SSH host keys per node.
