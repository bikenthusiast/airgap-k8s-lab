#!/usr/bin/env bash
# =============================================================================
# airgap.sh — air-gap control for the lab VMs (VirtualBox, ADR-0008)
# =============================================================================
# Usage:
#   scripts/airgap.sh seal   [vm ...]   disconnect the NAT adapter (NIC1)
#   scripts/airgap.sh unseal [vm ...]   reconnect the NAT adapter (BREAK GLASS)
#   scripts/airgap.sh status            host-side check of all measures
#
# Without VM names, seal/unseal apply to every VM of this Vagrant project.
# "status" exits with code 1 if any measure is violated, so it can be used as
# a gate in make targets.
#
# Note: this covers the host's point of view only. The authoritative proof is
# the guest-side check (ansible/playbooks/verify-airgap.yml).
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACHINES_DIR="$ROOT/.vagrant/machines"
AUDIT_LOG="$ROOT/.airgap-audit.log"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "  $*"; }

command -v VBoxManage >/dev/null 2>&1 || die "VBoxManage not found (is VirtualBox installed?)"

vm_id() {
  local f="$MACHINES_DIR/$1/virtualbox/id"
  [[ -f $f ]] && cat "$f" || true
}

all_vms() {
  [[ -d $MACHINES_DIR ]] || return 0
  find "$MACHINES_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}

vm_info() { VBoxManage showvminfo "$1" --machinereadable 2>/dev/null; }

# Read the output fully, then match. A pipe "vm_info | grep -q" fails under
# pipefail: grep exits on the first match, VBoxManage gets SIGPIPE (exit 141).
is_running() { grep -q '^VMState="running"' <<<"$(vm_info "$1")"; }

audit() {
  printf '%s user=%s action=%s vms=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${USER:-unknown}" "$1" "$2" >> "$AUDIT_LOG"
}

set_link() { # $1 = on|off, remaining arguments = VM names
  # Deliberately no arrays or mapfile: macOS ships Bash 3.2.
  local state=$1; shift
  local list name id
  if [[ $# -gt 0 ]]; then list="$*"; else list="$(all_vms | tr '\n' ' ')"; fi
  [[ -n ${list// /} ]] || die "no VMs found (did you run 'vagrant up' yet?)"

  for name in $list; do
    id="$(vm_id "$name")"
    if [[ -z $id ]]; then info "$name: no VM id, skipped"; continue; fi
    if ! is_running "$id"; then info "$name: not running, skipped"; continue; fi
    VBoxManage controlvm "$id" setlinkstate1 "$state"
    info "$name: NAT link $state"
  done
}

cmd_seal() {
  echo "Sealing the air gap:"
  set_link off "$@"
}

cmd_unseal() {
  echo "!!! BREAK GLASS: the NAT link is being reconnected. The VMs will have"
  echo "!!! internet access afterwards. This action is logged to: $AUDIT_LOG"
  audit "unseal" "${*:-all}"
  set_link on "$@"
  echo "Re-seal as soon as you are done debugging: make seal"
}

cmd_status() {
  local violations=0 checked=0 name id info_out cable timesync
  echo "Host-side air-gap check"
  echo "======================="

  # The Mac must not route packets between networks (that would be a way out)
  if [[ "$(uname)" == "Darwin" ]]; then
    if [[ "$(sysctl -n net.inet.ip.forwarding)" == "0" ]]; then
      info "PASS  Mac: IP forwarding disabled"
    else
      info "FAIL  Mac: IP forwarding enabled (net.inet.ip.forwarding=1)"; violations=$((violations+1))
    fi
  fi

  while read -r name; do
    [[ -n $name ]] || continue
    id="$(vm_id "$name")"
    if [[ -z $id ]] || ! is_running "$id"; then info "--    $name: not running"; continue; fi
    info_out="$(vm_info "$id")"
    checked=$((checked+1))

    cable="$(grep '^cableconnected1=' <<<"$info_out" | cut -d'"' -f2)"
    if [[ $cable == "off" ]]; then
      info "PASS  $name: NAT link disconnected"
    else
      info "FAIL  $name: NAT link connected"; violations=$((violations+1))
    fi

    timesync="$(VBoxManage getextradata "$id" \
      VBoxInternal/Devices/VMMDev/0/Config/GetHostTimeDisabled | awk '{print $2}')"
    if [[ $timesync == "1" ]]; then
      info "PASS  $name: host time sync disabled"
    else
      info "FAIL  $name: host time sync active"; violations=$((violations+1))
    fi

    if grep -q '^SharedFolderNameMachineMapping' <<<"$info_out"; then
      info "FAIL  $name: shared folder configured"; violations=$((violations+1))
    else
      info "PASS  $name: no shared folders"
    fi
  done < <(all_vms)

  echo
  # A gate that reports "passed" without checking anything proves nothing.
  if [[ $checked -eq 0 ]]; then
    echo "Result: nothing checked (no running VM)"; exit 1
  fi
  if [[ $violations -eq 0 ]]; then
    echo "Result: passed (host side)"
  else
    echo "Result: $violations violation(s)"; exit 1
  fi
}

case "${1:-}" in
  seal)   shift; cmd_seal "$@" ;;
  unseal) shift; cmd_unseal "$@" ;;
  status) cmd_status ;;
  *) sed -n '2,16p' "$0"; exit 2 ;;
esac
