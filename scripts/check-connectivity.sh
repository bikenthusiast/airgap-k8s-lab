#!/usr/bin/env bash
# Full-mesh connectivity check for airgap-lab.
# Runs on the Mac, logs into every node via SSH and pings every other node and the Mac.
# Requires the airgap-lab-* entries in ~/.ssh/config. Exit code 0 = all node-to-node pings ok.
set -u
NODES=(airgap-lab-infra airgap-lab-cp1 airgap-lab-w1 airgap-lab-w2)
MAC=10.10.10.100
W=18

echo "airgap-lab connectivity check — $(date '+%Y-%m-%d %H:%M')"
echo
printf "%-${W}s" "from \\ to"
for t in "${NODES[@]}" "mac($MAC)"; do printf "%-${W}s" "$t"; done; echo

fail=0
for src in "${NODES[@]}"; do
  printf "%-${W}s" "$src"
  for dst in "${NODES[@]}" "$MAC"; do
    if [ "$src" = "$dst" ]; then printf "%-${W}s" "-"; continue; fi
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
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$src" "curl -s -m5 -o /dev/null https://ubuntu.com"; then r="reachable"; else r="blocked"; fi
  printf "  %-${W}s %s\n" "$src" "$r"
done

echo
[ $fail -eq 0 ] && echo "RESULT: all node-to-node pings ok" || echo "RESULT: FAILURES - see matrix"
exit $fail
