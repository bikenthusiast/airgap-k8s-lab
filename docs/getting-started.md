# Getting started

This walks you from an empty Mac to a sealed, verified lab. Expect **30 to 60
minutes**, most of it spent downloading the Vagrant box and booting four VMs.

Everything here belongs to milestone **M1**. Later milestones build on it.

---

## Before you start

| Requirement | Notes |
|---|---|
| Intel Mac | The pinned Vagrant box is amd64. Apple Silicon needs a different box and provider. |
| 32 GB RAM recommended | The lab reserves 16 GB (4 VMs × 4 GB). 16 GB total is tight; see step 3 for a smaller profile. |
| ~30 GB free disk | Box, four linked clones, later the bundle. |
| Internet | Needed **only** on the Mac, and only to download the box and tools. The VMs never get online. |
| Admin rights | VirtualBox installs kernel extensions. |

---

## Step 1 — Install the tooling

```bash
brew install --cask virtualbox vagrant
uv tool install ansible-core
uv tool install pre-commit      # optional but recommended
```

macOS will block the VirtualBox kernel extension on first install. Approve it
under **System Settings → Privacy & Security**, then **restart the Mac**. Skipping
the restart is the most common cause of `vagrant up` failing later.

Verify:

```bash
VBoxManage --version          # expect 7.x
vagrant --version             # expect 2.4.x
ansible --version
```

---

## Step 2 — Get the repository ready

```bash
cd airgap-k8s-lab
git init && git add -A && git commit -m "M0: project skeleton"
pre-commit install            # if you installed pre-commit
```

Installing the hook now matters: from M2 onwards this repository sits next to
CA keys, and `gitleaks` runs on every commit from that point on.

---

## Step 3 — Check the profile (optional)

Defaults live in `ansible/inventory/hosts.yml`: four nodes at 2 vCPU / 4 GB
each. With 16 GB of RAM on the Mac, reduce `vm_memory` to `3072` for `cp1` and
`2048` for `w1`/`w2` before the first `vagrant up`. Kubernetes requires at
least 2 GB and 2 CPUs per node, so do not go below that.

Versions are pinned in `versions.yaml`. Leave them as they are for M1; the
items marked `VERIFY` are dealt with before M3.

---

## Step 4 — Host-only network on macOS

VirtualBox on macOS only allows host-only addresses inside `192.168.56.0/21` by
default. The data diode (`192.168.56.10`) is inside that range, so there is
nothing to do. If you ever change `transfer_ip` in the inventory to a different
range, you also have to allow it in `/etc/vbox/networks.conf`.

---

## Step 5 — Create the VMs

```bash
make up
```

What happens, per VM:

1. Vagrant downloads the box on first run (~500 MB, once for all four VMs).
2. The VM boots with three network adapters: NAT (needed by Vagrant for SSH),
   the internal `airgap` network, and — on `infra` only — the host-only diode.
3. Base provisioning disables unattended upgrades and writes the `/etc/hosts`
   block. It downloads nothing.
4. The `after :up` trigger runs `scripts/airgap.sh seal <vm>`, which
   disconnects the NAT link.

Watch for four lines like `Air gap: disconnecting NAT link of cp1`. If they are
missing, the VMs are still online — check step 7.

> **From now on `vagrant ssh` no longer works.** That is intended: it uses the
> NAT adapter, which is now disconnected. Step 6 sets up the replacement.

---

## Step 6 — Prove the air gap

```bash
make verify
```

This runs two independent checks:

| Layer | What it checks |
|---|---|
| Host (`scripts/airgap.sh status`) | NAT link disconnected, host time sync off, no shared folders, no IP forwarding on the Mac |
| Guests (`verify-airgap.yml`) | nodes reach each other (positive control), no IP egress, no external DNS, upstream registry unreachable, bastion does not forward packets |

Along the way `.ssh-config` is generated. A successful run ends with four
`Air-gap proof passed` messages and `failed=0` per host.

Try it yourself:

```bash
ssh -F .ssh-config cp1                     # goes through the bastion
ssh -F .ssh-config cp1 curl -m 5 https://1.1.1.1   # must fail
ssh -F .ssh-config cp1 ping -c2 10.20.0.10         # must succeed
```

That pair of results is the entire point of the project: the node has a working
network, and it cannot reach the internet.

---

## Step 7 — When something goes wrong

| Symptom | Cause and fix |
|---|---|
| `VBoxManage not found` | VirtualBox missing or not in `PATH`. |
| `VERR_NEM_VM_CREATE_FAILED`, VM will not start | Kernel extension not approved or Mac not restarted (step 1). |
| `Box … doesn't support the provider` | Box metadata needs provider and architecture. The Vagrantfile sets `box_architecture`; make sure you are on an Intel Mac. |
| `Result: nothing checked (no running VM)` | No VM is running. `vagrant status`, then `make up`. |
| `FAIL <vm>: NAT link connected` | Trigger did not run. Fix with `make seal`, then `make verify`. |
| Timeout waiting for the machine to boot | `AIRGAP_SEAL=0 vagrant up` to keep NAT connected, inspect the VM in the VirtualBox GUI, then `make seal`. |
| Positive control fails, negative tests pass | The air-gap network itself is broken. Check `virtualbox__intnet: "airgap"` and the IPs in the inventory. |

Need internet inside a VM for debugging:

```bash
make unseal        # logged to .airgap-audit.log
# … debug …
make seal && make verify
```

---

## Step 8 — Daily use

```bash
make down          # shut the VMs down
make up            # start again (sealing happens automatically)
make verify        # after every start: confirm the seal held
make destroy       # discard everything and start over
```

`make up` after `make down` also re-runs the seal trigger, because it is bound
to `:up` and `:reload`. Run `make verify` anyway — the point of a gate is that
you use it.

---

## Step 9 — Record what happened

Add a dated entry to `docs/journal.md`: what worked, what did not, and what you
had to correct. The mistakes are the valuable part — they are what makes the
project credible to a reader later.

---

## What comes next

M1 is done once `make verify` passes reliably and is documented in the journal.
Then continue with **M2 (PKI)**, see `pki/README.md` and ADR-0005. The roadmap
is in the [README](../README.md).
