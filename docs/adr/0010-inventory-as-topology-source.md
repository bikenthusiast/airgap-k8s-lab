# ADR-0010: Ansible inventory as the single topology source

- **Status:** Accepted
- **Date:** 2026-09-11

## Context

Hostnames, IPs and VM sizes are needed in several places: Vagrant (create the
VMs), Ansible (configure them), SSH access, `/etc/hosts`. Data maintained twice
drifts apart sooner or later.

## Decision

`ansible/inventory/hosts.yml` is the only source for the topology. The
Vagrantfile reads that file and creates the VMs from it; `.ssh-config` and the
`/etc/hosts` block are generated from it too.

## Consequences

- A node is added or changed in exactly one place.
- For the Pi cluster (M7) a second inventory with the same structure is added;
  the Vagrant-specific fields (`vm_cpus`, `vm_memory`) are simply ignored there.
- The inventory deliberately contains no `ansible_host`, because access goes
  through the generated `.ssh-config`.

## Alternatives considered

- **A separate `topology.yaml` that generates the inventory:** clean, but an
  extra generation step with no benefit at this project size.
- **Maintaining IPs in both the Vagrantfile and the inventory:** error-prone.
