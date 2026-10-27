#!/usr/bin/env bash
# Prepare an airgap-lab node for kubeadm: kernel settings, containerd, kubelet node IP.
# Usage: sudo ./node-prep.sh <node-ip> <pause-tag>
set -euo pipefail
NODE_IP=${1:?node IP missing}
PAUSE_TAG=${2:?pause tag missing}
REG=airgap-lab-infra:5000
CFG=/etc/containerd/config.toml

# 1. Kernel modules and sysctls required by Kubernetes networking
cat > /etc/modules-load.d/k8s.conf <<'MODS'
overlay
br_netfilter
MODS
modprobe -a overlay br_netfilter
cat > /etc/sysctl.d/99-kubernetes.conf <<'SYS'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
SYS
sysctl --system >/dev/null

# 2. containerd: full default config, systemd cgroups, pinned sandbox image, certs.d
install -d /etc/containerd
[ -f "$CFG" ] && cp "$CFG" "$CFG.bak.$(date +%Y%m%d%H%M%S)"
containerd config default > "$CFG"
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' "$CFG"
sed -i -E "s#^(\s*)sandbox = .*#\1sandbox = 'registry.k8s.io/pause:${PAUSE_TAG}'#" "$CFG"
sed -i -E "s#^(\s*)config_path = ''#\1config_path = '/etc/containerd/certs.d'#" "$CFG"

# 3. Mirror: pull registry.k8s.io images from the lab registry
install -d /etc/containerd/certs.d/registry.k8s.io
cat > /etc/containerd/certs.d/registry.k8s.io/hosts.toml <<HOSTS
server = "https://registry.k8s.io"

[host."https://${REG}"]
  capabilities = ["pull", "resolve"]
HOSTS

# 4. crictl talks to containerd
cat > /etc/crictl.yaml <<'CRI'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
CRI

systemctl restart containerd

# 5. kubelet always uses the lab network address
echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" > /etc/default/kubelet

# 6. Show what matters
echo "--- containerd"; grep -nE 'SystemdCgroup|sandbox = |config_path' "$CFG"
echo "--- sysctl";     sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables
echo "--- kubelet";    cat /etc/default/kubelet
