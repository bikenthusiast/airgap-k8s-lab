# ansible/roles/ — Ansible roles

> **Status:** empty. Roles are added along with their milestones.

Every role installs **exclusively from the bundle** or from the services on
`infra` (local package repository, registry). A role that contacts an internet
address is a bug.

| Role (planned) | Target hosts | Milestone | Purpose |
|---|---|---|---|
| `bundle_import` | bastion | M3 | verify the bundle (signature, checksums) and unpack it |
| `chrony_server` | bastion | M4 | the only time source inside the air gap |
| `chrony_client` | k8s_cluster | M4 | take time from infra |
| `dns` | bastion | M4 | name resolution for `lab.internal` |
| `offline_repo` | bastion | M4 | local APT repository built from the bundle |
| `registry_zot` | bastion | M4 | container registry with TLS from our own PKI |
| `pki_trust` | all | M4 | distribute the root CA into the trust stores |
| `node_prep` | k8s_cluster | M5 | kernel modules, sysctl, swap off |
| `containerd` | k8s_cluster | M5 | runtime including mirror config (`hosts.toml`) |
| `kubeadm_init` | control_plane | M5 | initialise the cluster with our own CA |
| `kubeadm_join` | workers | M5 | join the workers |
| `cni_cilium` | control_plane | M5 | CNI offline via Helm from the registry |

These roles are meant to run unchanged on the Raspberry Pi cluster later (M7).
Platform differences belong in variables, not in branches in the code.
