# ADR-0002: VirtualBox and Vagrant as the lab platform

- **Status:** Accepted
- **Date:** 2026-09-11

## Context

The lab initially runs on an Intel Mac with 32 GB RAM. It needs four VMs, an
isolated network without a gateway, and a separate access path from the host.
The setup must be reproducible from code, because the VMs are recreated often.

## Decision

VirtualBox 7 as the hypervisor, Vagrant to describe and drive the VMs.

## Consequences

- VirtualBox's **internal network** mode is exactly what is needed: VMs see each
  other, but neither the host nor the internet.
- Vagrant always creates a NAT adapter as NIC1 because it needs it for SSH
  during boot. That link has to be disconnected after boot (ADR-0008).
- After disconnecting, `vagrant ssh` and `vagrant provision` no longer work.
  All configuration then runs through Ansible via the bastion.
- Free and widely documented.

## Alternatives considered

- **VMware Fusion:** free for personal use, but the isolated network is more
  cumbersome to configure.
- **UTM (QEMU):** fine for single VMs, harder to automate.
- **kind/k3d (containers instead of VMs):** unsuitable, because kubeadm, kernel
  configuration and network separation are meant to be exercised on real nodes.
