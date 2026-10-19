#!/usr/bin/env bash
# Clock check for airgap-lab: offset of every node against the Mac, NTP sync state,
# time service, timezone and the source chrony currently uses.
# Offset accuracy is about +/- half the SSH round trip (shown as rtt_ms).
# Requires the airgap-lab-* entries in ~/.ssh/config.
set -u
NODES=(airgap-lab-infra airgap-lab-cp1 airgap-lab-w1 airgap-lab-w2)
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }

echo "airgap-lab clock check — Mac: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo
printf "%-18s %10s %8s  %-6s %-10s %-10s %s\n" node offset_ms rtt_ms synced service timezone source
for n in "${NODES[@]}"; do
  t0=$(now)
  r=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$n" 'date +%s.%N' 2>/dev/null)
  t1=$(now)
  if [ -z "$r" ]; then printf "%-18s unreachable\n" "$n"; continue; fi
  off=$(awk -v r="$r" -v a="$t0" -v b="$t1" 'BEGIN{printf "%+.0f", (r-(a+b)/2)*1000}')
  rtt=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.0f", (b-a)*1000}')
  info=$(ssh -o BatchMode=yes "$n" '
    s=$(timedatectl show -p NTPSynchronized --value)
    tz=$(timedatectl show -p Timezone --value)
    svc=none; for x in chrony systemd-timesyncd; do systemctl is-active -q $x && svc=$x; done
    src=$(chronyc -n sources 2>/dev/null | awk "/^\^\*/{print \$2}")
    echo "$s $svc $tz ${src:-none}"')
  read -r synced svc tz src <<<"$info"
  printf "%-18s %10s %8s  %-6s %-10s %-10s %s\n" "$n" "$off" "$rtt" "$synced" "$svc" "$tz" "$src"
done
