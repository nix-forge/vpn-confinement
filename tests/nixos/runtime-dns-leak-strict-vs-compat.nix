{ pkgs, ... }: {
  name = "runtime-dns-leak-strict-vs-compat";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "runtime-dns-leak";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces = {
        ns-strict = {
          enable = true;
          wireguard.interface = "wg-strict";
          dns = {
            mode = "strict";
            servers = [ "10.64.0.1" ];
          };
          egress.mode = "allowAllTunnel";
        };
        ns-compat = {
          enable = true;
          wireguard.interface = "wg-compat";
          dns = {
            mode = "compat";
            servers = [ "10.64.0.1" ];
          };
          egress.mode = "allowAllTunnel";
        };
      };
    };

    networking.wireguard.interfaces.wg-strict = {
      privateKeyFile = "/run/wg-test/strict.key";
      ips = [ "10.71.216.231/32" ];
      peers = [
        {
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpoint = "138.199.43.91:51820";
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
    };

    networking.wireguard.interfaces.wg-compat = {
      privateKeyFile = "/run/wg-test/compat.key";
      ips = [ "10.71.216.232/32" ];
      peers = [
        {
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpoint = "138.199.43.92:51820";
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
    };

    systemd.services.test-vpn-private-keys = {
      wantedBy = [ "multi-user.target" ];
      before = [
        "wireguard-wg-strict.service"
        "wireguard-wg-compat.service"
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        umask 077
        ${pkgs.coreutils}/bin/mkdir -p /run/wg-test
        ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/strict.key
        ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/compat.key
        ${pkgs.coreutils}/bin/chmod 0600 /run/wg-test/strict.key /run/wg-test/compat.key
      '';
    };

    systemd.services.svc-strict = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
      };
      vpn = {
        enable = true;
        namespace = "ns-strict";
      };
    };

    systemd.services.svc-compat = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
      };
      vpn = {
        enable = true;
        namespace = "ns-compat";
      };
    };

    environment.systemPackages = [
      pkgs.netcat-openbsd
      pkgs.nftables
      pkgs.iproute2
    ];
  };

  testScript = ''
    import re

    def assert_trace(namespace, name, protocol, destination, port, verdict):
        trace_file = f"/tmp/{name}.trace"
        pid_file = f"/tmp/{name}.pid"
        machine.succeed(f"rm -f {trace_file} {pid_file}")
        machine.succeed(
            f"sh -c '${pkgs.coreutils}/bin/stdbuf -oL -eL "
            f"ip netns exec {namespace} nft monitor trace >{trace_file} 2>&1 & "
            f"echo $! >{pid_file}'"
        )
        machine.wait_until_succeeds(f"test -s {pid_file} && kill -0 $(cat {pid_file})")
        machine.succeed("sleep 1")

        nc_flag = "-u " if protocol == "udp" else ""
        machine.succeed(
            f"ip netns exec {namespace} sh -c "
            f"'printf dns | nc {nc_flag}-w 1 {destination} {port} || true'"
        )
        machine.wait_until_succeeds(
            f"grep -q 'ip daddr {destination}' {trace_file}",
            timeout=30,
        )
        machine.succeed(f"kill $(cat {pid_file}) || true")

        trace = machine.succeed(f"cat {trace_file}")
        packet_pattern = re.compile(
            rf"trace id ([0-9a-f]+).*packet:.*ip daddr {re.escape(destination)}"
            rf".*{protocol}.*dport {port}\b"
        )
        trace_ids = packet_pattern.findall(trace)
        assert trace_ids, f"no trace found for {protocol} {destination}:{port}:\n{trace}"
        assert any(
            re.search(rf"trace id {trace_id}\b.*verdict {verdict}\b", trace)
            for trace_id in trace_ids
        ), f"no {verdict} verdict found for {protocol} {destination}:{port}:\n{trace}"

    machine.wait_for_unit("multi-user.target")
    machine.wait_until_succeeds("ip netns list | grep -q '^ns-strict\\b'")
    machine.wait_until_succeeds("ip netns list | grep -q '^ns-compat\\b'")
    machine.wait_for_unit("wireguard-wg-strict.service")
    machine.wait_for_unit("wireguard-wg-compat.service")

    machine.succeed("systemctl show -p InaccessiblePaths --value svc-strict.service | grep -q '/run/nscd'")
    machine.fail("systemctl show -p InaccessiblePaths --value svc-compat.service | grep -q '/run/nscd'")

    machine.succeed("ip netns exec ns-strict nft list table inet vpnc | grep -q 'set dns_blocked_ports'")
    machine.succeed("ip netns exec ns-strict nft list table inet vpnc | grep -q 'udp dport @dns_blocked_ports drop'")
    machine.succeed("ip netns exec ns-strict nft list table inet vpnc | grep -q 'tcp dport @dns_blocked_ports drop'")

    machine.fail("ip netns exec ns-compat nft list table inet vpnc | grep -q 'set dns_blocked_ports'")

    machine.succeed("ip netns exec ns-strict nft insert rule inet vpnc output meta nftrace set 1")
    assert_trace("ns-strict", "strict-allowed-udp", "udp", "10.64.0.1", 53, "accept")
    assert_trace("ns-strict", "strict-allowed-tcp", "tcp", "10.64.0.1", 53, "accept")

    for protocol in ("udp", "tcp"):
        for port in (53, 853, 5353, 5355):
            assert_trace(
                "ns-strict",
                f"strict-blocked-{protocol}-{port}",
                protocol,
                "198.51.100.53",
                port,
                "drop",
            )

    machine.succeed("ip netns exec ns-compat nft insert rule inet vpnc output meta nftrace set 1")
    for protocol in ("udp", "tcp"):
        for port in (53, 853, 5353, 5355):
            assert_trace(
                "ns-compat",
                f"compat-allowed-{protocol}-{port}",
                protocol,
                "198.51.100.53",
                port,
                "accept",
            )
  '';
}
