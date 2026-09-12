# Work journal

A chronological record: what was done when, why, and what was learned or
corrected along the way. Newest entry first.

Decisions with lasting effect are additionally captured as ADRs in
[`adr/`](adr/).

---

## 2026-09-11 — M0: project skeleton created

### Goal

A repository where the lab platform is created from code, the air-gap measures
are built in from the start, and the documentation structure exists before the
real work begins.

### What was created, and why

| Artefact | Why |
|---|---|
| `versions.yaml` | Pin every version in one place. Researched from upstream Git tags: Kubernetes 1.36.4 (install) and 1.37.0 (upgrade target), containerd 2.3.5, Cilium 1.20.1, Zot 2.1.21 |
| `ansible/inventory/hosts.yml` | Topology with four nodes, serving Ansible and Vagrant at the same time (ADR-0010) |
| `Vagrantfile` | Create the VMs from the inventory; internal `airgap` network, data diode on `infra` only, side channels closed, NAT disconnect via trigger (ADR-0008) |
| `scripts/airgap.sh` | Seal, break-glass unseal with logging, host-side check |
| `ansible/playbooks/verify-airgap.yml` | Guest-side proof with a positive control |
| `ansible/playbooks/ssh-config.yml` | Access through the bastion, shared by humans and Ansible |
| `Makefile` | One way to drive everything; `verify` as a gate |
| `docs/getting-started.md` | Step-by-step first setup with troubleshooting |
| `bundle/`, `pki/`, `ansible/roles/` | Concepts and placeholders for M2 to M5 |
| `docs/architecture.md`, `docs/adr/` | arc42 documentation and ten ADRs covering the foundational decisions |
| `.gitignore`, `.pre-commit-config.yaml` | Keep key material and VM data out of the repository, scan for secrets before every commit |

### What came out of the planning

- **Vagrant and air gaps are in tension:** Vagrant needs the NAT adapter for SSH
  during boot. Solution: disconnect the link afterwards. Side effect:
  `vagrant ssh` stops working, hence access through `.ssh-config`.
- **Side channels are easy to miss:** the Guest Additions sync the clock with
  the host. Leaving that on would mean the later NTP architecture never gets
  genuinely tested.
- **macOS ships Bash 3.2:** `scripts/airgap.sh` therefore avoids `mapfile` and
  other Bash 4 features.
- **Box download:** the new Vagrant box metadata requires provider and
  architecture, so the Vagrantfile sets `box_architecture` explicitly.
- **Bug found during testing and fixed:** `is_running` used
  `VBoxManage … | grep -q` under `set -o pipefail`. `grep -q` exits on the first
  match, `VBoxManage` gets SIGPIPE (exit 141) when it keeps writing, and the
  pipeline counts as failed. Effect: running VMs were reported as "not running"
  and never sealed. Fix: read the output fully, then match. Found using a
  VBoxManage stub.
- **A gate with nothing to check:** `airgap.sh status` reported "passed" even
  when no VM was running. It now exits 1 with "nothing checked", following the
  same logic as the positive control in the verify playbook.
- **Noted for later:** with multiple network interfaces, kubeadm would pick the
  NAT address as the node IP (architecture, section 8.4).

### Open items for M1

- [ ] Run `make up` on the Mac, confirm the box download and the triggers
- [ ] Confirm that `VBoxManage showvminfo` reports a link disconnected via
      `controlvm` as `cableconnected1="off"` (assumption made in
      `airgap.sh status`)
- [ ] Get `make verify` to pass and record the result here
- [ ] Check compatibility of the pinned versions (marked `VERIFY` in
      `versions.yaml`)
