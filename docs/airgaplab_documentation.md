# airgap-lab — VM Build Documentation

Build log and runbook for the four VMs of the air-gapped Kubernetes practice lab.
Sessions: 2026-10-18 (evening) and 2026-10-19 (morning).

Purpose of this document:

1. **Reproduce** the VM setup from scratch (sections 3–6).
2. **Operate** the VMs day to day (section 8).
3. **Learn** from what went wrong during the build (section 9) — each incident is written up as symptom → hypothesis → evidence → fix → lesson, the same structure used for troubleshooting interview practice.

Items marked **[verify]** were not explicitly confirmed during the sessions and should be checked once.

---

## 1. Final state (as built)

### 1.1 Host

| | |
|---|---|
| Machine | Mac, Intel (`uname -m` → `x86_64`) |
| RAM | **[verify]** `sysctl -n hw.memsize \| awk '{print $1/1024^3 " GB"}'` |
| Virtualization | VirtualBox **7.2.16** |
| Other VMs on the host | `ubuntu-24.04-amd64_…` (Vagrant), host-only network `vagrantnet-vbox1` (192.168.56.0/24) — unrelated, left untouched |

### 1.2 VMs

| VM | Role | IP (lab network) | Adapters | Snapshot |
|---|---|---|---|---|
| `airgap-lab-base` | golden image, never runs alongside the clones | DHCP (was .101) | 1: host-only, 2: NAT | `generalized` |
| `airgap-lab-infra` | CA, registry (later) | **10.10.10.10** | 1: host-only, 2: NAT | `clean-os` |
| `airgap-lab-cp1` | Kubernetes control plane (later) | **10.10.10.11** | 1: host-only | `clean-os` |
| `airgap-lab-w1` | worker (later) | **10.10.10.21** | 1: host-only | `clean-os` |
| `airgap-lab-w2` | worker (later) | **10.10.10.22** | 1: host-only | `clean-os` |

Common to all VMs:

| | |
|---|---|
| OS | Ubuntu Server **26.04.1 LTS**, amd64 |
| User | `tobiask` (sudo with password) |
| Login | SSH key `~/.ssh/id_ed25519` from the Mac |
| Disk | 40 GB VDI, dynamically allocated; LVM root extended to full size |
| Swap | disabled (kubeadm requirement) |
| Interfaces | `enp0s3` = host-only (lab network), `enp0s8` = NAT (infra and base only) |
| Network config | `/etc/netplan/01-airgap-lab.yaml`; cloud-init network config disabled |
| Identity | unique hostname, machine-id and SSH host keys per VM |
| Time | chrony; `infra` syncs from the internet and serves time to 10.10.10.0/24 (`local stratum 10`); cp1, w1, w2 sync only from 10.10.10.10; timezone `Etc/UTC` everywhere |
| Resources | 2 vCPU, 2048 MB RAM; cp1 **[verify]** 2048 or 4096 MB |

### 1.3 Network

| Address / range | Use |
|---|---|
| 10.10.10.0/24 | lab network, VirtualBox host-only network `airgap-lab` |
| **10.10.10.100** | the Mac — VirtualBox gives the host the first address of the DHCP range |
| 10.10.10.101–200 | DHCP pool; only used temporarily (base VM, freshly started clones) |
| 10.10.10.10–99 | static addresses for the lab nodes |
| 10.0.2.0/24 | VirtualBox NAT (per VM, not routable between VMs) |

Air-gap concept: only `infra` reaches the internet (via NAT). `cp1`, `w1`, `w2` have no NAT adapter and therefore no route out. Name resolution inside the lab is via `/etc/hosts`.

```
                     Mac (10.10.10.100)
                            │
          ─────── host-only network "airgap-lab" 10.10.10.0/24 ───────
           │                │                 │                │
     infra .10          cp1 .11           w1 .21           w2 .22
           │
        NAT (enp0s8) ──► internet
```

---

## 2. Design decisions

| Decision | Why |
|---|---|
| **Golden image + clones** instead of four installs | one installation instead of four; guarantees identical nodes |
| **Ubuntu 26.04.1 LTS** | current LTS with longest support; kubeadm guides exist. Note for later: ships containerd 2.x (config layout differs from 1.x) and Rust-based `sudo`/coreutils |
| **Host-only network + NAT only on infra** | Mac can reach every node; only one node can reach the internet → realistic air gap; packages and images must flow through infra |
| **Static IPs outside the DHCP pool** | certificates (SAN) and kubeadm need stable addresses; no collision with DHCP leases |
| **machine-id emptied before cloning** | each clone generates its own ID → distinct DHCP client IDs and IDs as required by kubeadm |
| **Swap off in the base image** | kubeadm requirement; done once for all nodes |
| **Snapshot `clean-os` per node** | reset point after every failure-injection exercise |
| **Base VM kept** | re-clone at any time without reinstalling |
| **infra as the lab's time server** | without Guest Additions VirtualBox doesn't sync guest clocks, and only infra can reach internet NTP; measured drift was up to −11 s within a few hours. TLS, etcd and kubeadm need consistent clocks |
| **chrony drop-ins via `confdir`** | the active `chrony.conf` loads no drop-in directory; one added `confdir` line keeps the original file intact and makes own settings visible as separate files |
| **NTP server addressed by IP** | time sync must not depend on `/etc/hosts` or a future DNS server |

---

## 3. Prerequisites

```bash
uname -m                                  # x86_64 → amd64 ISO
VBoxManage --version                      # 7.x required for "hostonlynet"
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -C "airgap-lab"
```

ISO: `ubuntu-26.04.1-live-server-amd64.iso` from ubuntu.com/download/server, checksum verified:

```bash
shasum -a 256 ~/Downloads/ubuntu-26.04.1-live-server-amd64.iso   # compare with SHA256SUMS
```

---

## 4. Phase A — remove old VMs, create the lab network

### 4.1 Delete the old VMs

The previous lab VMs (same names) were deleted because their login credentials were unknown.

```bash
VBoxManage list vms
for vm in airgap-lab-infra airgap-lab-cp1 airgap-lab-w1 airgap-lab-w2; do
  VBoxManage controlvm "$vm" poweroff 2>/dev/null
  VBoxManage unregistervm "$vm" --delete          # irreversible: removes VM and disk
done
ls ~/"VirtualBox VMs"/
```

### 4.2 Host-only network

```bash
VBoxManage hostonlynet add --name=airgap-lab --netmask=255.255.255.0 \
  --lower-ip=10.10.10.100 --upper-ip=10.10.10.200 --enable
VBoxManage list hostonlynets
```

Result:

```
Name:            airgap-lab
LowerIP:         10.10.10.100
UpperIP:         10.10.10.200
VBoxNetworkName: hostonly-airgap-lab
```

---

## 5. Phase B/C — base VM `airgap-lab-base`

### 5.1 Create the VM (VirtualBox GUI)

1. **New** → name `airgap-lab-base`, select the ISO, tick **Skip unattended installation**
2. 2048 MB RAM, 2 CPUs
3. 40 GB disk, dynamically allocated
4. **Before first boot**, set the adapters — adapter order matters (see incident 9.2):

```bash
VBoxManage modifyvm airgap-lab-base --nic1 hostonlynet --host-only-net1=airgap-lab --nic2 nat
VBoxManage showvminfo airgap-lab-base --machinereadable | grep -E '^nic[12]=|hostonly'
# nic1="hostonlynet"  hostonly-network1="airgap-lab"  nic2="nat"
```

### 5.2 Install Ubuntu Server

| Screen | Choice |
|---|---|
| Language | English |
| Keyboard | **German** — check this screen; it defaulted to US (see incident 9.1) |
| Type | Ubuntu Server (not minimized) |
| Network | DHCP on both interfaces |
| Storage | entire disk, LVM |
| Profile | server name `airgap-lab-base`, user `tobiask` |
| SSH | **Install OpenSSH server: yes** — make sure it is ticked (see incident 9.4) |
| Snaps | none |

### 5.3 Keyboard layout (if it came up as US/QWERTY)

At the console (with US layout active: `-` is on the `ß` key, `y`/`z` swapped, `/` is on the `-` key):

```bash
sudo dpkg-reconfigure keyboard-configuration
# Generic 105-key PC → German → German (or "eliminate dead keys") → default AltGr → no compose
sudo setupcon
```

Or non-interactively over SSH:

```bash
sudo sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="de"/; s/^XKBVARIANT=.*/XKBVARIANT="nodeadkeys"/' /etc/default/keyboard
sudo setupcon
```

### 5.4 Network config of the base VM

The installer's netplan no longer matched after the adapter change (incident 9.3). Replaced with:

```bash
sudo rm -f /etc/netplan/*.yaml
sudo tee /etc/netplan/01-airgap-lab.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: true
      optional: true
    enp0s8:
      dhcp4: true
      optional: true
EOF
sudo chmod 600 /etc/netplan/01-airgap-lab.yaml
sudo netplan apply
ip -br addr      # enp0s3 10.10.10.1xx/24, enp0s8 10.0.2.15/24
```

**[verify]** whether the base VM ended up with DHCP (as above, consistent with the observed address .101) or the static 10.10.10.50 variant. Either works; `optional: true` is the important part.

### 5.5 SSH server and key

```bash
# in the VM, if SSH was not installed
sudo apt update && sudo apt install -y openssh-server
sudo systemctl enable --now ssh
sudo ss -tlnp | grep ':22'
```

```bash
# on the Mac
ssh-copy-id -i ~/.ssh/id_ed25519.pub tobiask@10.10.10.101
ssh tobiask@10.10.10.101
```

`-i` is needed: without it `ssh-copy-id` picked the older `id_rsa.pub`.

### 5.6 Base configuration (in the VM, via SSH)

```bash
# updates and tools
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y vim curl jq tcpdump dnsutils bash-completion

# use the full disk (installer allocates only part of the LVM volume group)
sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
df -h /

# swap off permanently
sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
sudo rm -f /swap.img
free -h                                   # Swap: 0B

# netplan managed by hand, not by cloud-init
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

### 5.7 Generalize and snapshot

```bash
# in the VM
sudo truncate -s 0 /etc/machine-id
sudo apt clean
sudo poweroff
```

```bash
# on the Mac
VBoxManage snapshot airgap-lab-base take generalized
VBoxManage modifyvm airgap-lab-base --natpf2 delete ssh 2>/dev/null   # remove temporary port forward, if any
```

---

## 6. Phase D — clones

### 6.1 Clone and adjust hardware

```bash
VBoxManage list runningvms                       # base must be off
for vm in infra cp1 w1 w2; do
  VBoxManage clonevm airgap-lab-base --name "airgap-lab-$vm" --register
done
for vm in cp1 w1 w2; do VBoxManage modifyvm "airgap-lab-$vm" --nic2 none; done   # only infra keeps NAT
# optional, Mac with >= 16 GB: VBoxManage modifyvm airgap-lab-cp1 --memory 4096
VBoxManage list vms
```

`clonevm` creates full clones with new MAC addresses and a new hardware UUID.

### 6.2 Personalize each clone — one at a time

Every clone boots with the base VM's network config and gets a DHCP address from the pool. Because the machine-id was emptied, the address differs from the base VM's (e.g. .102 instead of .101 — see incident 9.5). Start **one** clone, configure it, then the next.

```bash
# on the Mac
VBoxManage startvm airgap-lab-infra --type headless
for i in $(seq 100 120); do ping -c1 -t1 10.10.10.$i >/dev/null 2>&1 && echo "10.10.10.$i is up"; done
ssh tobiask@10.10.10.<dhcp-address>
```

In the VM — adjust the first line per node:

```bash
NAME=airgap-lab-infra; IP=10.10.10.10

# hostname
sudo hostnamectl set-hostname "$NAME"
sudo sed -i "s/airgap-lab-base/$NAME/" /etc/hosts

# fresh SSH host keys
sudo rm /etc/ssh/ssh_host_* && sudo dpkg-reconfigure openssh-server

# lab hosts
grep -q '^10\.10\.10\.10 ' /etc/hosts || sudo tee -a /etc/hosts >/dev/null <<'EOF'
10.10.10.10 airgap-lab-infra
10.10.10.11 airgap-lab-cp1
10.10.10.21 airgap-lab-w1
10.10.10.22 airgap-lab-w2
EOF

# static IP
sudo rm -f /etc/netplan/*.yaml
sudo tee /etc/netplan/01-airgap-lab.yaml >/dev/null <<EOF
network:
  version: 2
  ethernets:
    enp0s3:
      dhcp4: false
      addresses: [$IP/24]
      optional: true
EOF
```

Only on infra, additionally:

```bash
sudo tee -a /etc/netplan/01-airgap-lab.yaml >/dev/null <<'EOF'
    enp0s8:
      dhcp4: true
      optional: true
EOF
```

Finish (the SSH session drops at `netplan apply` because the address changes):

```bash
cat /etc/machine-id                         # not empty
sudo chmod 600 /etc/netplan/01-airgap-lab.yaml
sudo netplan apply
```

| Node | First line | NAT block |
|---|---|---|
| infra | `NAME=airgap-lab-infra; IP=10.10.10.10` | yes |
| cp1 | `NAME=airgap-lab-cp1; IP=10.10.10.11` | no |
| w1 | `NAME=airgap-lab-w1; IP=10.10.10.21` | no |
| w2 | `NAME=airgap-lab-w2; IP=10.10.10.22` | no |

Reconnect on the Mac at the static address:

```bash
ssh-keygen -R 10.10.10.10
ssh tobiask@10.10.10.10 hostname           # → airgap-lab-infra
```

### 6.3 SSH shortcuts on the Mac (`~/.ssh/config`)

```
Host airgap-lab-infra
  HostName 10.10.10.10
Host airgap-lab-cp1
  HostName 10.10.10.11
Host airgap-lab-w1
  HostName 10.10.10.21
Host airgap-lab-w2
  HostName 10.10.10.22
Host airgap-lab-*
  User tobiask
  IdentityFile ~/.ssh/id_ed25519
```

### 6.4 Time synchronisation (chrony)

**Starting point** (measured with `scripts/check-time.sh`, 2026-10-19 14:40): all nodes run chrony, timezone `Etc/UTC`. infra synchronized via NAT; cp1, w1, w2 not synchronized, offsets −0.7 s (cp1, freshly rebooted), −6.3 s (w1), −10.8 s (w2) and growing.

**Check where chrony reads drop-ins** — on Ubuntu 26.04.1 the active `chrony.conf` has **no** `confdir`/`sourcedir`/`include`, so files in `/etc/chrony/conf.d/` and `sources.d/` are silently ignored (incident 9.10). A packaged default `chrony.conf.dist` exists next to it; it was deliberately *not* activated to avoid pulling in unrelated changes (e.g. NTS sources).

```bash
ssh airgap-lab-infra "grep -nE '^(confdir|sourcedir|include|makestep|pool|server)' /etc/chrony/chrony.conf"
# pool 0..3.ubuntu.pool.ntp.org iburst, makestep 1 3 — no confdir
```

**1. Enable a drop-in directory on all four nodes** (backup once, idempotent guard on the exact line):

```bash
for n in infra cp1 w1 w2; do
  echo "== $n"
  ssh -t "airgap-lab-$n" '
  sudo cp -n /etc/chrony/chrony.conf /etc/chrony/chrony.conf.orig
  sudo mkdir -p /etc/chrony/conf.d
  grep -q "^confdir /etc/chrony/conf.d" /etc/chrony/chrony.conf || \
    printf "\n# airgap-lab: load drop-in config\nconfdir /etc/chrony/conf.d\n" | sudo tee -a /etc/chrony/chrony.conf >/dev/null
  tail -2 /etc/chrony/chrony.conf'
done
```

**2. infra serves time to the lab network:**

```bash
ssh -t airgap-lab-infra '
printf "# airgap-lab: serve time to the lab network\nallow 10.10.10.0/24\nlocal stratum 10\n" | sudo tee /etc/chrony/conf.d/airgap-lab-server.conf
sudo systemctl restart chrony
sleep 3
sudo ss -ulnp | grep ":123 "
chronyc tracking | head -5'
```

- `allow 10.10.10.0/24` — answer NTP requests from the lab network
- `local stratum 10` — keep serving time even if infra loses its own internet sources (e.g. once the NAT adapter is removed)

**3. cp1, w1, w2 use infra:**

```bash
for n in cp1 w1 w2; do
  echo "== $n"
  ssh -t "airgap-lab-$n" '
  echo "server 10.10.10.10 iburst prefer" | sudo tee /etc/chrony/conf.d/airgap-lab-client.conf
  sudo systemctl restart chrony'
done
```

The default Ubuntu pools stay configured; from the workers they are unreachable (`^?`), which is expected. After the restart, `makestep 1 3` lets chrony step the clock during the first three updates, so the −11 s were corrected immediately instead of slewed over hours.

**4. Verify:**

```bash
for n in cp1 w1 w2; do echo "== $n"; ssh "airgap-lab-$n" 'chronyc -n sources | grep -E "^\^"'; done
# expected per node: ^* 10.10.10.10 …   (pools: ^?)
./scripts/check-time.sh
```

Note `-n`: without it `chronyc` shows the source as `airgap-lab-infra` (reverse lookup via `/etc/hosts`), so a `grep` for the IP finds nothing (incident 9.11).

Result 2026-10-19 14:50:

```
node                offset_ms   rtt_ms  synced service            timezone
airgap-lab-infra         +580     1040  yes    chrony             Etc/UTC
airgap-lab-cp1           +510     1122  yes    chrony             Etc/UTC
airgap-lab-w1            +113      354  yes    chrony             Etc/UTC
airgap-lab-w2            +225      640  yes    chrony             Etc/UTC
```

All offsets are within the measurement uncertainty (± half the SSH round trip) → clocks agree.

**Rollback** if chrony fails to start: `sudo cp /etc/chrony/chrony.conf.orig /etc/chrony/chrony.conf && sudo rm /etc/chrony/conf.d/airgap-lab-*.conf && sudo systemctl restart chrony`.

### 6.5 Clean shutdown and `clean-os` snapshots

`sudo poweroff` over SSH does not work non-interactively (incident 9.6). Use ACPI from the host, and only snapshot powered-off VMs:

To replace an existing `clean-os` (e.g. after the hosts fix and time sync), delete it first: `VBoxManage snapshot airgap-lab-<node> delete clean-os`.

```bash
for vm in infra cp1 w1 w2; do VBoxManage controlvm "airgap-lab-$vm" acpipowerbutton; done
while VBoxManage list runningvms | grep -q 'airgap-lab-'; do sleep 3; done; echo "all off"
for vm in infra cp1 w1 w2; do VBoxManage snapshot "airgap-lab-$vm" take clean-os; done
for vm in infra cp1 w1 w2; do echo "== $vm"; VBoxManage snapshot "airgap-lab-$vm" list; done
```

---

## 7. Verification

Two check scripts in the repo, run from the Mac. Run both after every failure-injection exercise and after restoring `clean-os`. Both first query each VM's power state via `VBoxManage showvminfo` (`running`, `poweroff`, `saved`, `aborted`, …) and skip nodes that aren't running instead of reporting them as network failures. `check-connectivity.sh` exits with 1 and `RESULT: INCOMPLETE` if not all four VMs run.

| Script | Checks | Pass criterion |
|---|---|---|
| `./scripts/check-connectivity.sh \| tee docs/network/connectivity-check.txt` | full-mesh ping by name, ping to the Mac by IP, internet access | every node-to-node cell `ok`; only infra `reachable` |
| `./scripts/check-time.sh` | clock offset vs. Mac, NTP sync state, time service, timezone, active source | `synced yes` everywhere; offsets within ± rtt; workers' source `10.10.10.10` |

Manual equivalent of the basic checks:

```bash
for vm in infra cp1 w1 w2; do
  ssh "airgap-lab-$vm" 'hostname; cat /etc/machine-id; free -h | grep Swap'
done
ssh airgap-lab-cp1   'ping -c1 airgap-lab-w2'
ssh airgap-lab-infra 'curl -sI -m5 https://ubuntu.com | head -1'                 # HTTP/… → internet OK
ssh airgap-lab-cp1   'curl -sI -m5 https://ubuntu.com || echo "no internet - correct"'
```

Expected: four different hostnames and machine-ids, `Swap: 0B` everywhere, node-to-node ping works, only infra reaches the internet.

---

## 8. Operations cheat sheet

| Task | Command |
|---|---|
| Start all nodes | `for vm in infra cp1 w1 w2; do VBoxManage startvm "airgap-lab-$vm" --type headless; done` |
| Running VMs | `VBoxManage list runningvms` |
| Clean shutdown | `VBoxManage controlvm airgap-lab-<node> acpipowerbutton` |
| Hard power-off (only if hung) | `VBoxManage controlvm airgap-lab-<node> poweroff` |
| Wait until all off | `while VBoxManage list runningvms \| grep -q 'airgap-lab-'; do sleep 3; done` |
| Take snapshot (VM off) | `VBoxManage snapshot airgap-lab-<node> take <name>` |
| List snapshots | `VBoxManage snapshot airgap-lab-<node> list` |
| Reset to clean state (VM off) | `VBoxManage snapshot airgap-lab-<node> restore clean-os` |
| Console of a headless VM | VirtualBox GUI → select VM → **Show** |
| sudo over SSH | `ssh -t airgap-lab-<node> 'sudo …'` (asks for the password) |
| Forget old host key | `ssh-keygen -R <ip>` |
| Re-clone a node | power off, `VBoxManage unregistervm airgap-lab-<node> --delete`, then 6.1–6.5 for that node |
| Time sources of a node | `ssh airgap-lab-<node> 'chronyc -n sources'` (`^*` = active source) |
| Sync state | `ssh airgap-lab-<node> 'chronyc tracking'` |
| Force immediate clock correction (after snapshot restore or Mac sleep) | `ssh -t airgap-lab-<node> 'sudo chronyc makestep'` |

Rules learned the hard way:

- Snapshot only when `VBoxManage list runningvms` shows the VM as off.
- Never use wildcards like `airgap-lab-*` in delete commands — they also match `airgap-lab-base`, whose `Snapshots/` folder holds the `generalized` snapshot.
- Start freshly cloned VMs one at a time.
- Idempotency guards (`grep -q … || append`) test for the exact line being added — never for a hostname or anything that can exist for another reason.
- Before adding a drop-in config file, check that the main config actually loads that directory.

---

## 9. Incident log

### 9.1 Keyboard came up as QWERTY

| | |
|---|---|
| Symptom | `y`/`z` swapped, special characters in wrong places at the VM console |
| Cause | keyboard screen in the installer left at the US default |
| Fix | `dpkg-reconfigure keyboard-configuration` + `setupcon` (5.3) |
| Lesson | work over SSH from the Mac terminal; the console is only for emergencies. The VirtualBox shared clipboard does not help either: it needs Guest Additions **and** a graphical session, which Ubuntu Server doesn't have |

### 9.2 VM only had a NAT address

| | |
|---|---|
| Symptom | `ip -br addr` showed only `lo` and `enp0s3 10.0.2.15` |
| Hypothesis | 10.0.2.15 is VirtualBox's NAT signature → adapter 1 is NAT, host-only adapter missing |
| Evidence | `VBoxManage showvminfo … --machinereadable` → `nic1="nat"`, `nic2="none"`; network `airgap-lab` existed |
| Fix | VM off, `modifyvm --nic1 hostonlynet --host-only-net1=airgap-lab --nic2 nat` |
| Lesson | adapter order is part of the design: the clone step removes **nic2** from the workers. With NAT as nic1 and host-only as nic2, the workers would have lost their lab connection |

### 9.3 Boot hung at `systemd-networkd-wait-online`

| | |
|---|---|
| Symptom | after reboot, boot stuck at `job systemd-networkd-wait-online.service/start` |
| Cause | the installer's netplan was bound to the old interface (NAT); after the adapter swap the configured interface never became ready. wait-online waits for every configured, non-optional interface |
| Fix | wait for the 2-minute timeout, log in, replace netplan (5.4) with `optional: true` |
| Lesson | network config can block boot; `optional: true` decouples boot from interfaces that may legitimately be down |

### 9.4 SSH: `Connection refused`

| | |
|---|---|
| Symptom | `ssh tobiask@10.10.10.101` → `Connection refused` |
| Interpretation | *refused* = host reachable, nothing listening on port 22 (a network problem would show as a *timeout*) |
| Fix | install/enable `openssh-server` at the console (5.5) |
| Side finding | VirtualBox can forward a host port over NAT as a fallback: `VBoxManage controlvm <vm> natpf2 "ssh,tcp,127.0.0.1,2222,,22"` → `ssh -p 2222 tobiask@127.0.0.1` |

### 9.5 Clone not reachable at the base VM's address

| | |
|---|---|
| Symptom | `ssh tobiask@10.10.10.101` hung after starting the first clone |
| Cause | expected behaviour: emptied machine-id → new DHCP client ID → new lease (.102). The clone still reported hostname `airgap-lab-base` because it wasn't personalized yet |
| Fix | ping scan over the DHCP pool, connect to .102, continue with 6.2 |
| Lesson | *timeout* means nothing answers at that address — check which address the host actually has before debugging SSH |

### 9.6 Snapshots failed: `sudo: A terminal is required to authenticate` → `NS_ERROR_ABORT`

| | |
|---|---|
| Symptom | `ssh … 'sudo poweroff'` printed `sudo: A terminal is required to authenticate` four times; the following `VBoxManage snapshot … take clean-os` failed with `NS_ERROR_ABORT` for all four VMs |
| Cause | `sudo` needs a TTY to ask for the password; non-interactive SSH has none → VMs never shut down → snapshot of running VMs aborted |
| Fix | shut down via `VBoxManage controlvm … acpipowerbutton`, wait until no VM runs, then snapshot (6.5) |
| Lesson | a chained command sequence continued after its first step had visibly failed. Check each step's result before the next one builds on it |

### 9.7 All four clones `<inaccessible>`

The most instructive incident — useful as a troubleshooting story.

**Symptom**

```
"airgap-lab-base" {ec71e892-…}
"<inaccessible>" {d15eb0bc-…}
"<inaccessible>" {1f67cc9d-…}
"<inaccessible>" {b1a0480a-…}
"<inaccessible>" {8eb1aeb6-…}
```

`showvminfo` → `E_ACCESSDENIED … The object functionality is limited`.

**Hypotheses and evidence**

| Hypothesis | Check | Result |
|---|---|---|
| files lost | `ls -la ~/"VirtualBox VMs"/airgap-lab-infra/` | `.vbox`, `.vbox-prev`, 7 GB `.vdi`, `Logs/`, `Snapshots/` all present → rejected |
| truncated `.vbox` (current file 4697 B, `.vbox-prev` 5240 B) | `xmllint --noout` on both | both valid XML → rejected |
| stale state in VBoxSVC | `killall VBoxSVC`, `list vms` | still inaccessible → rejected |
| content difference | `diff .vbox-prev .vbox` | only `aborted="true"` and missing transient guest properties → harmless |
| broken media registry | re-register: `unregistervm` + `registervm` | `Hard disk '…infra.vdi' cannot be directly attached … because it has 1 differencing child hard disks` → **confirmed** |

**Root cause**: the aborted snapshot had already created a differencing disk (`Snapshots/{uuid}.vdi`, 2 MB) and registered it in each clone's `.vbox` media registry as a child of the main disk — but no `<Snapshot>` element existed, and the VM still attached the main disk directly. VirtualBox refuses that combination. `.vbox-prev` contained the same entry, so restoring it would not have helped.

**Fix** (only the four clones, by explicit name):

```bash
# 1. inspect: one self-closing child entry per clone, 0 real snapshots
grep -n 'Snapshots/' ~/"VirtualBox VMs"/airgap-lab-*/airgap-lab-*.vbox
grep -c '<Snapshot ' ~/"VirtualBox VMs"/airgap-lab-*/airgap-lab-*.vbox
#    → base: 1 real snapshot ("generalized") — must NOT be touched

# 2. remove the child entry, with backup
for vm in infra cp1 w1 w2; do
  f=~/"VirtualBox VMs/airgap-lab-$vm/airgap-lab-$vm.vbox"
  cp "$f" "$f.bak-before-fix"
  sed -i '' '/location="Snapshots\//d' "$f"
  xmllint --noout "$f" && echo "$vm: XML OK, remaining refs: $(grep -c 'Snapshots/' "$f")"
done

# 3. move orphaned differencing disks aside
mkdir -p ~/vbox-orphans
for vm in infra cp1 w1 w2; do
  for f in ~/"VirtualBox VMs/airgap-lab-$vm/Snapshots/"*.vdi; do mv "$f" ~/vbox-orphans/"$vm-$(basename "$f")"; done
done

# 4. register again
for vm in infra cp1 w1 w2; do VBoxManage registervm ~/"VirtualBox VMs/airgap-lab-$vm/airgap-lab-$vm.vbox"; done
VBoxManage list vms
```

Then clean boot, ACPI shutdown, `clean-os` snapshots (6.5). Afterwards backups removed:

```bash
for vm in infra cp1 w1 w2; do rm -v ~/"VirtualBox VMs/airgap-lab-$vm/airgap-lab-$vm.vbox.bak-before-fix"; done
rm -rv ~/vbox-orphans
```

**Lessons**

- Diagnose before repairing: every hypothesis was tested with a cheap, read-only check first.
- The decisive information came from a *write* attempt (`registervm`) — the read-only `showvminfo` only said "access denied".
- Back up before editing, move instead of delete until the result is verified.
- A wildcard delete suggested during the incident (`rm …/airgap-lab-*/Snapshots/*.vdi`) would have destroyed the base VM's `generalized` snapshot. The `grep` in step 1 exposed this. Delete only by explicit name.

### 9.8 cp1 could not reach other nodes by name

| | |
|---|---|
| Symptom | `scripts/check-connectivity.sh`: row `airgap-lab-cp1` → FAIL to infra, w1, w2; but cp1 → Mac (by IP) ok, and every other node → cp1 ok |
| Hypothesis | network of cp1 is fine (it answers pings and reaches the Mac by IP); only targets addressed **by name** fail → name resolution on cp1 |
| Evidence | `/etc/hosts` on cp1 had no lab entries; `getent hosts airgap-lab-w1` empty; `ping 10.10.10.21` ok |
| Root cause | idempotency guard in the personalization step: `grep -q airgap-lab-cp1 /etc/hosts \|\| tee -a …`. The preceding `sed` had already written `127.0.1.1 airgap-lab-cp1`, so on cp1 — and only there — the guard matched and the hosts block was skipped |
| Fix | `ssh -t airgap-lab-cp1 "printf '…' \| sudo tee -a /etc/hosts"`, re-run the check, retake `clean-os` for cp1. Guard in 6.2 changed to `grep -q '^10\.10\.10\.10 '` (matches the block itself, not a hostname) |
| Lesson | an idempotency check must test for the thing it is about to add, not for something that may exist for another reason. The full-mesh check caught it before kubeadm would have failed in a much less obvious way |

### 9.9 Clocks drifting apart on the air-gapped nodes

| | |
|---|---|
| Symptom | `check-time.sh`: infra synced; cp1 −0.7 s, w1 −6.3 s, w2 −10.8 s, all `synced no` |
| Interpretation | the pattern fits drift since boot: cp1 had just been rebooted (clock taken from the host at boot), w1/w2 had run longest without a reachable time source |
| Root cause | VirtualBox without Guest Additions doesn't sync guest clocks; chrony on the workers only knew the Ubuntu internet pools, unreachable in the air gap |
| Fix | infra as lab NTP server, workers point to 10.10.10.10 (6.4) |
| Lesson | an air gap removes more than package downloads — every service that silently relied on the internet (NTP here; later DNS, image pulls, CRL/OCSP) needs an internal replacement. Found before TLS and etcd would have produced confusing errors |

### 9.10 chrony drop-in files would have been ignored

| | |
|---|---|
| Symptom | none yet — caught by checking before changing |
| Check | `grep -nE '^(confdir\|sourcedir\|include)' /etc/chrony/chrony.conf` → no match; directories `conf.d/` and `sources.d/` exist anyway |
| Risk | config written to `sources.d/` would have been silently ignored: chrony restarts fine, still no sync, no error message |
| Fix | one `confdir /etc/chrony/conf.d` line appended (with backup `chrony.conf.orig`); own settings as separate drop-in files |
| Lesson | an existing directory doesn't prove it is read. Check the including directive first — "silently ignored config" is one of the most time-consuming failure modes |

### 9.11 `grep` for the NTP server IP found nothing

| | |
|---|---|
| Symptom | `chronyc sources \| grep 10.10.10.10` empty on all workers, although `check-time.sh` showed `synced yes` |
| Cause | `chronyc` resolves source addresses to names by default (`/etc/hosts` → `airgap-lab-infra`) |
| Fix | `chronyc -n sources` |
| Lesson | when two signals contradict, suspect the measuring tool before the system. Prefer numeric output (`-n`) in checks and scripts |

### 9.12 Interview story (STAR draft)

- **Situation**: four freshly built lab VMs became unusable after an aborted snapshot; VirtualBox reported only "access denied".
- **Task**: restore them without losing the configured nodes, and without risking the golden image.
- **Action**: ruled out file loss, file corruption and service state with read-only checks; forced a precise error by re-registering; identified a half-written media-registry entry; fixed it with backups, scoped strictly to the four affected VMs; caught a wildcard that would have hit the golden image.
- **Result**: all four nodes recovered and snapshotted within about 15 minutes, no re-clone needed; procedure documented as a runbook.
- **Change afterwards**: snapshots only on powered-off VMs, ACPI shutdown from the host, no wildcards in delete commands.

---

## 10. Open items

- [ ] Retake `clean-os` on all four nodes (includes hosts fix on cp1 and time sync) — 6.5
- [ ] Commit `scripts/check-connectivity.sh`, `scripts/check-time.sh`, `docs/network/network-plan.md` (incl. time section), `docs/network/connectivity-check.txt`, this document
- [ ] Push repo to GitHub (decision: public; enable secret scanning and push protection; use the GitHub noreply email for commits; topics `kubernetes, air-gapped, kubeadm, sre, homelab`)
- [ ] README: fill remaining placeholders (Mac RAM, cp1 RAM), user `tobiask`
- [ ] Optional: lab names in the Mac's `/etc/hosts` (needed at the latest for TLS tests against the registry by name)
- [ ] Optional: passwordless sudo in the lab nodes for scripted exercises (`/etc/sudoers.d/tobiask`) — then retake `clean-os`
- [ ] Decide before kubeadm: default route for cp1/w1/w2 (via infra, or explicit node IP + blackhole route) — see network plan
- [ ] Next phase: own CA on `airgap-lab-infra` (tool choice: openssl or step-ca), keys under `pki/`, docs in `docs/ca/ca.md`
