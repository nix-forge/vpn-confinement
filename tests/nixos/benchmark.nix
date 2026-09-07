# An opt-in experiment, not a performance assertion in CI.
{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.benchmark = {
    seconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
    };
    streams = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
    };
  };
  imports = [ ./runtime-wireguard-handshake.nix ];
  config = {
    name = lib.mkForce "vpn-confinement-benchmark";
    nodes.machine = {
      environment.systemPackages = [
        pkgs.iperf3
        pkgs.nftables
      ];
      systemd.services.iperf = {
        wantedBy = [ "multi-user.target" ];
        after = [ "test-wireguard-peer.service" ];
        requires = [ "test-wireguard-peer.service" ];
        serviceConfig.ExecStart = "${pkgs.iperf3}/bin/iperf3 -s -B 10.71.216.232";
      };
    };
    testScript = lib.mkAfter ''
      import json, os
      machine.wait_for_unit("iperf.service")
      results = {
          "description": "Same VM and WireGuard namespace, with and without namespace nftables. No host link. Root namespace probes, not application sandbox measurements.",
          "kernel": machine.succeed("uname -r").strip(),
          "secondsPerSample": ${toString config.benchmark.seconds},
          "parallelStreams": ${toString config.benchmark.streams}, "runs": []
      }
      def cpu_sample():
          return list(map(int, machine.succeed("head -n 1 /proc/stat").split()[1:9]))
      machine.succeed("ip netns exec vpnapps nft list table inet vpnc > /tmp/benchmark-policy.nft")
      # Alternate order to reduce a simple warmup/order bias.
      for iteration in range(3):
          for mode in (["confinement", "wireguard-only"] if iteration % 2 == 0 else ["wireguard-only", "confinement"]):
              machine.succeed("ip netns exec vpnapps nft destroy table inet vpnc")
              if mode == "confinement":
                  machine.succeed("ip netns exec vpnapps nft -f /tmp/benchmark-policy.nft")
              for label, flags in [("tcp", ""), ("tcp-parallel", "-P ${toString config.benchmark.streams}"), ("udp-100mbit", "-u -b 100M")]:
                  before = cpu_sample()
                  machine.succeed("ip netns exec vpnapps ping -n -q -i 0.2 -w ${toString config.benchmark.seconds} 10.71.216.232 > /tmp/benchmark-latency 2>&1 &")
                  value = json.loads(machine.succeed(f"ip netns exec vpnapps iperf3 -c 10.71.216.232 -t ${toString config.benchmark.seconds} -J {flags}"))
                  delta = [a - b for a, b in zip(cpu_sample(), before)]
                  total = sum(delta)
                  busy = 100 * (total - delta[3] - delta[4]) / total if total else None
                  results["runs"].append({"iteration": iteration, "mode": mode, "workload": label, "result": value,
                      "guestCpuBusyPercent": busy, "latencyUnderLoad": machine.succeed("cat /tmp/benchmark-latency")})
      with open(os.path.join(os.environ["out"], "benchmark.json"), "w") as f:
          json.dump(results, f, indent=2)
    '';
  };
}
