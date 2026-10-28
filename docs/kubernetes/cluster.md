# Kubernetes cluster (kubeadm)

Status 2026-10-28: 3 nodes `Ready` (cp1 control plane, w1, w2 workers), CNI Flannel, workload tests passed, snapshot `cluster-ok` taken on all four VMs — baseline for the failure exercises.

## Versions

| Component | Version |
|---|---|
| Kubernetes (kubeadm, kubelet, kubectl) | v1.37.1 — package `1.37.1-1.1` from `pkgs.k8s.io/core:/stable:/v1.37`, `apt-mark hold` |
| containerd | 2.2.2 (`2.2.2-0ubuntu1.2`), runc from the Ubuntu archive |
| OS / kernel | Ubuntu 26.04.1 LTS, `7.0.0-38-generic` |
| CNI | Flannel v0.28.10 (VXLAN backend), see [CNI](#cni) |
| Control plane images | `registry.k8s.io/…` v1.37.1, etcd `3.7.0-0`, CoreDNS `v1.14.6`, pause `3.10.2` (mirrored, see [`../registry/images-v1.37.1.txt`](../registry/images-v1.37.1.txt)) |

## Nodes

| Node | IP | Role | CPU / RAM |
|---|---|---|---|
| airgap-lab-cp1 | 10.10.10.11 | control plane | 2 / ~3.4 GB |
| airgap-lab-w1 | 10.10.10.21 | worker (joined 2026-10-28) | 2 / 3 GB |
| airgap-lab-w2 | 10.10.10.22 | worker (joined 2026-10-28) | 2 / 3 GB |

## Networks

| | |
|---|---|
| Node network | 10.10.10.0/24 (host-only `airgap-lab`) |
| Pod network | 10.244.0.0/16 (`--pod-network-cidr`; CNI must use the same range) |
| Service network | 10.96.0.0/12 (default) |
| API server | `https://10.10.10.11:6443` (`--apiserver-advertise-address 10.10.10.11`) |
| Default route | via infra 10.10.10.10, which does not forward → air gap holds (see [`../network/network-plan.md`](../network/network-plan.md)) |

kubeadm and the kubelet pick their address from the default route; both are therefore set explicitly: `--apiserver-advertise-address` on `kubeadm init`, `--node-ip` via `/etc/default/kubelet`.

## CNI

| | |
|---|---|
| Plugin | **Flannel** v0.28.10, manifest `kube-flannel.yml` from the GitHub release (pinned version, not `latest`) |
| Why Flannel | one manifest, few images, low RAM; default network 10.244.0.0/16 = `--pod-network-cidr`, so the manifest is used unchanged. Trade-off: no NetworkPolicy support (Calico would be the option for policy exercises) |
| Backend | VXLAN overlay: pod traffic between nodes is wrapped in UDP between node addresses → pod MTU **1450** (1500 − 50 bytes) |
| Interface | picked from the default route → `enp0s3` (lab network) |
| Images | `flannel-io/flannel:v0.28.10`, `flannel-io/flannel-cni-plugin:v1.9.1-flannel3` ([`../registry/images-flannel-v0.28.10.txt`](../registry/images-flannel-v0.28.10.txt)), mirrored with skopeo: `ghcr.io/X` → `airgap-lab-infra:5000/X` |
| Mirror | `/etc/containerd/certs.d/ghcr.io/hosts.toml` on every node (added to [`scripts/node-prep.sh`](../../scripts/node-prep.sh) on 2026-10-28) |
| Deployed as | DaemonSet `kube-flannel-ds` in namespace `kube-flannel`, one pod per node, `hostNetwork: true` (pod IP = node IP) |
| On the node | `/etc/cni/net.d/10-flannel.conflist`, interfaces `flannel.1` (VXLAN tunnel) and `cni0` (bridge for local pods) |

### Pod CIDR per node

| Node | podCIDR |
|---|---|
| airgap-lab-cp1 | 10.244.0.0/24 |
| airgap-lab-w1 | 10.244.1.0/24 |
| airgap-lab-w2 | 10.244.2.0/24 |

Check: `kubectl get nodes -o custom-columns='NAME:.metadata.name,PODCIDR:.spec.podCIDR,FLANNEL-IP:.metadata.annotations.flannel\.alpha\.coreos\.com/public-ip'` — `FLANNEL-IP` must be the node address, otherwise the tunnels point to the wrong host although the node is `Ready`.

### CoreDNS in the air gap

- After the pod network came up, CoreDNS went into `CrashLoopBackOff`: `plugin/forward: no valid upstream addresses found`. The Corefile forwards non-cluster names to the node's `/etc/resolv.conf`, which has no nameserver in the air gap.
- **Interim fix (2026-10-28):** `forward` block removed from the `coredns` ConfigMap (backup on cp1: `~/coredns-backup.yaml`), `kubectl replace`, `rollout restart`. Both CoreDNS pods `1/1 Running`.
- Side effect: at start the `loop` plugin logs once `HINFO: plugin/loop: no next plugin found` (its self-test query has no plugin left to answer it). Harmless. Names outside the cluster fail immediately with `SERVFAIL`.
- **Planned permanent fix:** internal DNS on infra (dnsmasq, zone `lab.internal`), CoreDNS `forward . 10.10.10.10`.

## Joining workers

```bash
JOIN=$(ssh airgap-lab-cp1 kubeadm token create --print-join-command --kubeconfig .kube/config)
ssh -t airgap-lab-w1 "sudo $JOIN --node-name airgap-lab-w1"
ssh -t airgap-lab-w2 "sudo $JOIN --node-name airgap-lab-w2"
unset JOIN
```

- `--node-ip` is set in `/etc/default/kubelet` **before** the join (by `node-prep.sh`); the first registration fixes the node's `INTERNAL-IP`.
- Join tokens are valid 24 h and are secrets: never in the repo, journal or result files.

## Workload tests (2026-10-28)

| Test | How | Result |
|---|---|---|
| Image from the lab registry | `kubectl run test-registry --image=airgap-lab-infra:5000/library/busybox:1.37 …`, image name points to the lab registry explicitly | `Running` on a worker; Events: `Successfully pulled image "airgap-lab-infra:5000/library/busybox:1.37"` ✔ |
| Scheduling | control plane taint `node-role.kubernetes.io/control-plane:NoSchedule` | test pods land on w1/w2 only ✔ |
| Pod to pod across nodes | `p1` pinned to w1, `p2` pinned to w2 (`nodeName`), `kubectl exec p1 -- ping -c 3 <p2-ip>` | 0 % packet loss ✔ |
| Large packets | `ping -s 1400` (just below the pod MTU) | 0 % packet loss ✔ |
| Pod MTU | `kubectl exec p1 -- ip link show eth0` | `mtu 1450` (VXLAN overhead 50 bytes) ✔ |
| Cluster DNS | `kubectl exec p1 -- nslookup kubernetes.default.svc.cluster.local` | answered by CoreDNS `10.96.0.10` → `10.96.0.1` ✔ |
| External names | `nslookup google.com` from a pod | fails immediately (no `forward` in the Corefile) — intended in the air gap |

Test pods were deleted afterwards. Application image list: [`../registry/images-apps.txt`](../registry/images-apps.txt).

`Ready` nodes alone do not prove pod-to-pod traffic across nodes; the cross-node ping is the real check for the overlay.

## Snapshot `cluster-ok`

- Taken 2026-10-28 on **all four VMs** (infra, cp1, w1, w2), powered off.
- Shutdown order: w1, w2 → cp1 → infra. Start order: infra → cp1 → w1, w2.
- After restart: 3× `Ready`, all pods `Running`.
- **Baseline for every failure exercise** (Defekt catalog). Always restore the snapshot on all VMs together: a single VM on an older state no longer matches what etcd on cp1 knows about it.

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
