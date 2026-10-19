#!/usr/bin/env bash
# Full-mesh connectivity check for airgap-lab.
# Runs on the Mac: shows the VM state of every node, then logs into every running node via SSH
# and pings every other node by name and the Mac by IP.
# Requires VBoxManage and the airgap-lab-* entries in ~/.ssh/config.
# Exit code: 0 = all four nodes running and all node-to-node pings ok, 1 otherwise.
set -u
NODES=(airgap-lab-infra airgap-lab-cp1 airgap-lab-w1 airgap-lab-w2)
MAC=10.10.10.100
W=18
vmstate() {
  local s
  s=$(VBoxManage showvminfo "$1" --machinereadable 2>/dev/null | awk -F= '/^VMState=/{gsub(/"/,"",$2); print $2}')
  echo "${s:-not-found}"
}
is_running() { [ "$(vmstate "$1")" = "running" ]; }

echo "airgap-lab connectivity check — $(date '+%Y-%m-%d %H:%M')"
echo
echo "VM state:"
running=0
for n in "${NODES[@]}"; do
  st=$(vmstate "$n")
  [ "$st" = "running" ] && running=$((running+1))
  printf "  %-${W}s %s\n" "$n" "$st"
done
echo
if [ "$running" -eq 0 ]; then
  echo "No VM running — nothing to check."
  echo "Start them: for vm in infra cp1 w1 w2; do VBoxManage startvm \"airgap-lab-\$vm\" --type headless; done"
  exit 1
fi

printf "%-${W}s" "from \\ to"
for t in "${NODES[@]}" "mac($MAC)"; do printf "%-${W}s" "$t"; done; echo

fail=0
[ "$running" -lt "${#NODES[@]}" ] && fail=1
for src in "${NODES[@]}"; do
  printf "%-${W}s" "$src"
  if ! is_running "$src"; then
    printf "%s\n" "-- VM not running, row skipped"
    continue
  fi
  for dst in "${NODES[@]}" "$MAC"; do
    if [ "$src" = "$dst" ]; then printf "%-${W}s" "-"; continue; fi
    if [ "$dst" != "$MAC" ] && ! is_running "$dst"; then printf "%-${W}s" "off"; continue; fi
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$src" "ping -c1 -W2 $dst >/dev/null 2>&1"; then
      printf "%-${W}s" "ok"
    else
      printf "%-${W}s" "FAIL"
      [ "$dst" != "$MAC" ] && fail=1
    fi
  done
  echo
done

echo
echo "Internet access (expected: only airgap-lab-infra reachable):"
for src in "${NODES[@]}"; do
  if ! is_running "$src"; then printf "  %-${W}s %s\n" "$src" "-- VM not running"; continue; fi
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$src" "curl -s -m5 -o /dev/null https://ubuntu.com"; then r="reachable"; else r="blocked"; fi
  printf "  %-${W}s %s\n" "$src" "$r"
done

echo
if [ "$running" -lt "${#NODES[@]}" ]; then
  echo "RESULT: INCOMPLETE - only $running of ${#NODES[@]} VMs running"
elif [ $fail -eq 0 ]; then
  echo "RESULT: all node-to-node pings ok"
else
  echo "RESULT: FAILURES - see matrix"
fi
exit $fail
