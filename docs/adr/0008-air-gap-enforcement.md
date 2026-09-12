# ADR-0008: Layered air-gap enforcement and automated proof

- **Status:** Accepted
- **Date:** 2026-09-11

## Context

The lab runs on a Mac that has internet access. A single measure such as "no
NAT" is not enough, because there are several inconspicuous ways around the
network separation: Vagrant's NAT adapter, shared folders, Guest Additions time
sync, IP forwarding on the host or the bastion. On top of that, isolation that
is merely claimed is worthless.

## Decision

1. **Multiple layers** (overview in `docs/architecture.md`, section 8.1):
   network topology, NAT disconnect after every boot, closed side channels, no
   unattended upgrades.
2. **Automated proof** from two points of view:
   - Host side: `scripts/airgap.sh status`
   - Guest side: `ansible/playbooks/verify-airgap.yml`, with a **positive
     control** (nodes reach each other) and three negative tests (IP egress,
     DNS, upstream registry).
3. **Break glass:** unsealing is possible (`make unseal`) but logged.
4. Cluster-changing make targets depend on `verify`.

## Consequences

- The proof is repeatable and can be demonstrated live in an interview.
- A short window with NAT exists during boot (risk R-01), because Vagrant needs
  the link for SSH. Deliberately accepted; it disappears on the Pi cluster (M7).
- `vagrant ssh` stops working once the VMs are sealed.

## Alternatives considered

- **Remove the NAT adapter entirely:** Vagrant can then no longer boot the VM.
- **Firewall rules inside the VMs:** easy to loosen by accident, and they do not
  check themselves. Could be added as an extra layer.
