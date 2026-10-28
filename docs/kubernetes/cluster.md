# Kubernetes cluster (kubeadm)

Status 2026-10-28: control plane on cp1 initialized; w1/w2 join, CNI and first workload follow (part 2).

## Versions

| Component | Version |
|---|---|
| Kubernetes (kubeadm, kubelet, kubectl) | v1.37.1 — package `1.37.1-1.1` from `pkgs.k8s.io/core:/stable:/v1.37`, `apt-mark hold` |
| containerd | 2.2.2 (`2.2.2-0ubuntu1.2`), runc from the Ubuntu archive |
| OS / kernel | Ubuntu 26.04.1 LTS, `7.0.0-38-generic` |
| Control plane images | `registry.k8s.io/…` v1.37.1, etcd `3.7.0-0`, CoreDNS `v1.14.6`, pause `3.10.2` (mirrored, see [`../registry/images-v1.37.1.txt`](../registry/images-v1.37.1.txt)) |

## Nodes

| Node | IP | Role | CPU / RAM |
|---|---|---|---|
| airgap-lab-cp1 | 10.10.10.11 | control plane | 2 / ~3.4 GB |
| airgap-lab-w1 | 10.10.10.21 | worker (joins in part 2) | 2 / 3 GB |
| airgap-lab-w2 | 10.10.10.22 | worker (joins in part 2) | 2 / 3 GB |

## Networks

| | |
|---|---|
| Node network | 10.10.10.0/24 (host-only `airgap-lab`) |
| Pod network | 10.244.0.0/16 (`--pod-network-cidr`; CNI must use the same range) |
| Service network | 10.96.0.0/12 (default) |
| API server | `https://10.10.10.11:6443` (`--apiserver-advertise-address 10.10.10.11`) |
| Default route | via infra 10.10.10.10, which does not forward → air gap holds (see [`../network/network-plan.md`](../network/network-plan.md)) |

kubeadm and the kubelet pick their address from the default route; both are therefore set explicitly: `--apiserver-advertise-address` on `kubeadm init`, `--node-ip` via `/etc/default/kubelet`.

## Node preparation

[`scripts/node-prep.sh`](../../scripts/node-prep.sh) `<node-ip> <pause-tag>`, run on every node:

- kernel modules `overlay`, `br_netfilter`; sysctls `net.ipv4.ip_forward = 1`, `net.bridge.bridge-nf-call-iptables = 1`
- containerd: `SystemdCgroup = true`, sandbox image `registry.k8s.io/pause:3.10.2`, `config_path = /etc/containerd/certs.d`
- mirror `registry.k8s.io` → `airgap-lab-infra:5000` (`hosts.toml`)
- `/etc/crictl.yaml`, `KUBELET_EXTRA_ARGS=--node-ip=<ip>`

Packages come offline: downloaded on infra with `apt-get install --download-only --reinstall`, copied with `scp -3`, installed with `apt install ./*.deb`.

## Control plane init (cp1)

```bash
sudo kubeadm config images pull --kubernetes-version v1.37.1
sudo kubeadm init --kubernetes-version v1.37.1 --apiserver-advertise-address 10.10.10.11 \
  --node-name airgap-lab-cp1 --pod-network-cidr 10.244.0.0/16 --service-cidr 10.96.0.0/12
```

Always pass `--kubernetes-version`: without it kubeadm asks the internet for the latest version and times out in the air gap.

## Certificates (kubeadm's own PKI, separate from the lab CA)

From `kubeadm certs check-expiration` on cp1, 2026-10-28:

| | Expires |
|---|---|
| Leaf certificates and kubeconfigs (apiserver, etcd, admin.conf, …) | **2027-10-27 16:36 UTC** (1 year) |
| CAs `ca`, `etcd-ca`, `front-proxy-ca` | 2036-10-24 16:36 UTC (10 years) |

Renewal before expiry: `sudo kubeadm certs renew all`, then restart the control plane static pods (move the manifests out of `/etc/kubernetes/manifests/` and back, or reboot cp1) and refresh `~/.kube/config` from `admin.conf`. A kubeadm control plane upgrade renews them automatically.

## Checks

```bash
kubectl get nodes -o wide                 # INTERNAL-IP = lab address
kubectl get pods -n kube-system -o wide
kubectl cluster-info
sudo kubeadm certs check-expiration
```

Expected before the CNI plugin: node `NotReady`, CoreDNS `Pending`.

## Never in the repo

`/etc/kubernetes/admin.conf`, `super-admin.conf`, `~/.kube/config`, join tokens (`kubeadm-init.log`), anything under `/etc/kubernetes/pki/`.
