# Observability and load tools on the nodes

Tools installed on cp1, w1 and w2 for performance analysis and failure exercises. Starting point for those exercises: snapshot **`cluster-tools`** on all four VMs (= `cluster-ok` + these tools + sysstat history).

## Tool → package

| Tool | Package | Purpose | Came from |
|---|---|---|---|
| `vmstat`, `free`, `top` | `procps` | run queue, memory, CPU per interval | base image |
| `mpstat`, `pidstat`, `iostat`, `sar` | `sysstat` | per-CPU, per-process, per-disk statistics; `sar` = history | base image |
| `perf` | `linux-tools-common` + `linux-tools-<kernel>` | CPU profiling, scheduler and syscall events | base image |
| `bpftrace` | `bpftrace` | eBPF one-liners | base image |
| `strace` | `strace` | system calls of a process | base image |
| `lsof` | `lsof` | open files and sockets | base image |
| `tcpdump` | `tcpdump` | packet capture | base image |
| `ss`, `nstat`, `ip` | `iproute2` | sockets, TCP counters | base image |
| `stress-ng` | `stress-ng` | CPU, memory, I/O load | **installed offline** |
| `fio` | `fio` | disk benchmark (IOPS, latency) | **installed offline** |

Exact versions per node: [`versions.txt`](versions.txt).

## How the missing packages got in (air gap)

1. Check on every node: `command -v <tool>` for each tool → only `fio` and `stress-ng` were missing (identical on cp1, w1, w2).
2. On infra (the only VM with internet): `apt-get download` into `~/debs/tools`.
3. Dependency closure **against the nodes**, not against infra:
   `apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances <pkgs>` → [`deps-tools.txt`](deps-tools.txt) (151 packages); per node `dpkg -s` on each entry → what the nodes lack (here: `fio`, `stress-ng` and their libraries, the same on all three nodes); download those on infra one by one.
4. Per node: `scp -3` from infra via the Mac, `sudo apt install -y /tmp/tools-debs/*.deb`, check loop again until no `MISS`.

`apt-get download` alone fetches no dependencies. `linux-tools-<kernel>` must match the **node** kernel (`ssh airgap-lab-cp1 uname -r`), not infra's.

## Limits in VirtualBox

- **perf:** no PMU in the VM → hardware events (`cycles`, `instructions`) show `<not supported>`. Use software events: `perf stat -e task-clock,context-switches`, `perf top -e cpu-clock`, `perf record -e cpu-clock -g`.
- `/usr/bin/perf` is a wrapper script: `command -v perf` succeeds even without the kernel-specific binary. Proof is `perf --version`.
- `perf` and `bpftrace` need `sudo` (`kernel.perf_event_paranoid`).
- `bpftrace -e 'BEGIN { printf("ok\n"); exit(); }'` works → eBPF and kernel BTF are available.

## sysstat history

`/etc/default/sysstat` → `ENABLED="true"`; `sysstat-collect.timer` samples every 10 min into `/var/log/sysstat/`, `sysstat-summary.timer` writes the daily summary.

```bash
sar -u | tail -3                   # CPU today
sar -q -s 10:00:00 -e 11:00:00     # run queue / load in a time window
```

Note: the nodes run in UTC.

## Adding a tool later

Same route as above. Then add it to the table, re-run the version collection into `versions.txt`, and take a new snapshot on all four VMs.
