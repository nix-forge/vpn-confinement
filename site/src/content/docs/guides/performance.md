---
title: Measure performance
description: A repeatable local WireGuard and nftables benchmark
---

The project includes an opt-in benchmark VM:

```bash
nix build .#vpn-benchmark --out-link result-benchmark
```

`result-benchmark/benchmark.json` records raw iperf3 output, kernel version, CPU
utilization, TCP throughput, four-stream TCP throughput, and UDP results at
100 Mbit/s. It repeats each workload three times, alternating the order of the
two modes. Each sample lasts three seconds.

Both modes use the same WireGuard peer and namespace. One has the module's
nftables policy; the other removes it inside the disposable VM. The benchmark
never changes your host firewall or contacts an external VPN. The VM has no
host-link interface in either mode.

This measures the incremental firewall cost in a synthetic local tunnel. It does
not measure a commercial VPN, storage performance, the full service sandbox,
or an Internet torrent swarm. Do not interpret one short run as a universal
throughput guarantee. Inspect variability and repeat on representative hardware.

For deployment measurements, compare equivalent runs against a server you
control. Record CPU model, kernel, architecture, tunnel MTU, number of streams,
CPU use, packet loss, and latency. Include a sustained transfer and many concurrent
connections. The default WireGuard MTU may need adjustment on a smaller uplink;
fix PMTU problems before raising connection limits or adding kernel tuning.

The runtime IPv6 test transfers 256 KiB through a 1280-byte WireGuard interface.
That verifies a small-MTU transfer, not every ICMP or PMTU discovery failure.
Named nftables sets remain the default. Flowtable offload and per-packet logging
are not enabled.

## Earlier local run

A run on 2026-09-06 used a two-vCPU, 1 GiB KVM guest with Linux 6.18.48.
The peer and client shared that VM. Values below are median receiver throughput
across three samples, in Mbit/s.

| Workload | WireGuard without nftables | WireGuard with confinement policy |
| --- | --- | --- |
| TCP, one stream | 1146.4 | 1128.3 |
| TCP, four streams | 1069.8 | 1043.6 |
| UDP, 100 Mbit/s offered | 100.0 | 100.0 |

The TCP ranges overlap: 1063.7 to 1152.3 without policy and 1110.7 to 1133.3
with policy for one stream. The confined medians are about 1.6% and 2.4% lower,
but these short samples do not isolate a stable firewall cost from run variation.
They support keeping the current implementation until representative measurements
identify a bottleneck.

The [raw results](/vpn-confinement/benchmarks/local-wireguard-2026-09-06.json)
include interval samples and iperf CPU statistics. Those CPU values describe the
iperf processes, not total WireGuard kernel CPU cost.

## Instrumented local run

A fresh 2026-09-07 run exercised all 18 short samples and recorded the added CPU and latency
fields. These are medians from the same two-vCPU guest topology, with Linux 6.18.48:

| Workload | Without namespace policy, Mbit/s | With policy, Mbit/s |
| --- | --- | --- |
| TCP, one stream | 724.7 | 704.3 |
| TCP, four streams | 722.0 | 712.5 |
| UDP, 100 Mbit/s offered | 100.0 | 100.0 |

Median whole-guest CPU use was 98.7% for both TCP modes. UDP medians were 44.6% without
policy and 43.8% with policy. These CPU-bound VM results support testing on the deployment
hardware before tuning. Different host load and the added latency probe prevent treating
the earlier run as a before/after comparison.

[Raw instrumented results](/vpn-confinement/benchmarks/local-wireguard-2026-09-07.json)
include every sample and ping output. The longer variant below has not been measured here.

## Sustained workloads

Use `nix build .#vpn-benchmark-sustained` for 30-second samples and 32 parallel TCP streams.
Both benchmark variants record whole-guest CPU utilization from `/proc/stat` and ping latency under
load alongside the raw iperf results. Whole-guest CPU includes the local peer and test overhead;
it does not isolate the client kernel's encryption cost. The short benchmark remains available for
quick experiments. The recorded run above predates these additional fields.

The application privacy VM also transfers a local torrent over a 1300-byte simulated uplink using a
1200-byte IPv4 WireGuard MTU. This checks a small-underlay configuration. It does not claim coverage
of every path-MTU discovery failure or IPv6 Packet Too Big handling.
