# ADR-0006: Ubuntu Server 24.04 LTS

- **Status:** Accepted
- **Date:** 2026-09-11

## Context

The operating system has to run on the lab VMs (amd64) and later on the
Raspberry Pi 5 (arm64), so that the Ansible roles can be reused unchanged.

## Decision

Ubuntu Server 24.04 LTS. Vagrant box: `bento/ubuntu-24.04`, version pinned in
`versions.yaml`.

## Consequences

- Official images for the Raspberry Pi 5 and maintained Vagrant boxes for
  VirtualBox.
- Widely used in Kubernetes documentation, which helps when troubleshooting.
- Ubuntu 26.04 LTS already exists. 24.04 is chosen deliberately because its
  VirtualBox box is proven. Switching would be its own ADR.

## Alternatives considered

- **Ubuntu 26.04 LTS:** newer, but box maturity for VirtualBox is not yet
  assessed.
- **Raspberry Pi OS:** Pi only, breaks reusability.
- **Rocky Linux / Debian:** possible, but weaker Pi 5 support or no added value.
