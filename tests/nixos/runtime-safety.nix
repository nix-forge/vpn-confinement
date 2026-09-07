{ pkgs, lib, ... }:
let
  vpnLib = import ../../modules/vpn-confinement/lib.nix { inherit lib; };
  server = pkgs.writeText "vpnc-test-server.py" ''
    import socket, threading
    def udp(port):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind(("10.71.216.232", port))
        while True:
            data, peer = s.recvfrom(4096)
            s.sendto(data, peer)
    for port in [53, 4444]:
        threading.Thread(target=udp, args=(port,), daemon=True).start()
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("10.71.216.232", 8080)); s.listen()
    while True:
        conn, peer = s.accept()
        with conn:
            conn.sendall(b"through-vpn")
  '';
  probe = pkgs.writeText "vpnc-test-probe.py" ''
    import socket, pathlib, time, threading
    def persistent_udp():
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.settimeout(0.5)
            while True:
                try:
                    s.connect(("10.71.216.232", 4444))
                    s.send(b"persistent-vpn-only-probe")
                    if s.recv(1024):
                        pathlib.Path("/var/lib/vpnc-probe/persistent-ready").touch()
                except OSError:
                    pass
                time.sleep(0.2)
    threading.Thread(target=persistent_udp, daemon=True).start()
    try:
        socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    except OSError:
        pathlib.Path("/var/lib/vpnc-probe/ipv6-blocked").touch()
    while True:
        successes = []
        for kind, port in [(socket.SOCK_STREAM, 8080), (socket.SOCK_DGRAM, 4444), (socket.SOCK_DGRAM, 53)]:
            try:
                with socket.socket(socket.AF_INET, kind) as s:
                    s.settimeout(0.5)
                    s.connect(("10.71.216.232", port))
                    if kind == socket.SOCK_DGRAM:
                        s.send(b"vpn-only-probe")
                    if s.recv(1024):
                        successes.append(str(port))
            except OSError:
                pass
        pathlib.Path("/var/lib/vpnc-probe/result").write_text(",".join(successes))
        time.sleep(0.2)
  '';
in
{
  name = lib.mkForce "runtime-safety";
  imports = [ ./runtime-wireguard-handshake.nix ];
  nodes.machine = {
    services.vpnConfinement.namespaces.vpnapps = {
      dns.servers = lib.mkForce [ "10.71.216.232" ];
      wireguard.endpointPinning.enable = true;
      publishToHost.tcp = [ 18080 ];
      # These must be ignored in allowAllTunnel mode, including overlapping CIDRs.
      egress.allowedTcpPorts = [ 443 ];
      egress.allowedUdpPorts = [ 123 ];
      egress.allowedCidrs = [
        "192.0.2.0/24"
        "192.0.2.0/25"
      ];
    };
    systemd.services.vpnc-test-server = {
      wantedBy = [ "multi-user.target" ];
      after = [ "test-wireguard-peer.service" ];
      requires = [ "test-wireguard-peer.service" ];
      serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${server}";
    };
    systemd.services.vpnc-probe = {
      wantedBy = [ "multi-user.target" ];
      vpn = {
        enable = true;
        namespace = "vpnapps";
        hardeningProfile = "strict";
      };
      serviceConfig = {
        DynamicUser = true;
        StateDirectory = "vpnc-probe";
        ExecStart = "${pkgs.python3}/bin/python3 ${probe}";
      };
    };
    systemd.sockets.vpnc-echo = {
      wantedBy = [ "sockets.target" ];
      vpn = {
        enable = true;
        namespace = "vpnapps";
      };
      listenStreams = [ "0.0.0.0:18080" ];
    };
    systemd.services.vpnc-echo = {
      vpn = {
        enable = true;
        namespace = "vpnapps";
      };
      serviceConfig = {
        DynamicUser = true;
        ExecStart = "${pkgs.python3}/bin/python3 -c 'import socket; s=socket.socket(fileno=3); c,a=s.accept(); c.sendall(b\"namespace-listener\"); c.close()'";
      };
    };
    environment.systemPackages = [
      pkgs.nftables
      pkgs.curl
      pkgs.netcat-openbsd
      pkgs.tcpdump
    ];
  };
  testScript = lib.mkAfter ''
    import json
    machine.wait_for_unit("vpnc-probe.service")
    machine.wait_for_unit("vpnc-echo.socket")
    machine.wait_until_succeeds("grep -q '8080,4444,53' /var/lib/vpnc-probe/result")
    machine.wait_until_succeeds("test -e /var/lib/vpnc-probe/persistent-ready")
    machine.succeed("ip netns exec vpnapps ss -ltn | grep ':18080 '")
    machine.fail("ss -ltn | grep ':18080 '")
    host_address = "${
      (vpnLib.effectiveNamespace "vpnapps" {
        hostLink = {
          enable = false;
          subnetIPv4 = null;
        };
        publishToHost.tcp = [ 18080 ];
        ingress.fromHost.tcp = [ ];
      }).hostLink.nsAddressIPv4
    }"
    machine.succeed(f"nc -w 2 {host_address} 18080 | grep namespace-listener")
    report = json.loads(machine.succeed("vpn-confinement-doctor vpnapps --json"))[0]
    assert report["defaultDropChainsPresent"]
    assert report["services"]["vpnc-probe"]["processAttached"] is True
    assert report["services"]["vpnc-probe"]["resolvers"] == ["10.71.216.232"]
    machine.succeed("test $(systemctl show vpnc-probe -p User --value) != root")

    machine.succeed("test -f /var/lib/vpnc-probe/ipv6-blocked")
    machine.wait_until_succeeds("ip -6 route show default | grep default")

    # A positive capture proves the host-link observer can see packets.
    host_if = "${vpnLib.deriveHostLinkInterfaceName "host" "vpnapps"}"
    ns_if = "${vpnLib.deriveHostLinkInterfaceName "ns" "vpnapps"}"
    host_ip = "${
      (vpnLib.effectiveNamespace "vpnapps" {
        hostLink = {
          enable = false;
          subnetIPv4 = null;
        };
        publishToHost.tcp = [ 18080 ];
        ingress.fromHost.tcp = [ ];
      }).hostLink.hostAddressIPv4
    }"
    machine.succeed(f"tcpdump -U -n -i {host_if} -c 1 -w /tmp/control.pcap 'tcp port 18080' >/tmp/control.log 2>&1 &")
    machine.wait_until_succeeds("grep -q listening /tmp/control.log")
    machine.succeed(f"nc -w 2 {host_address} 18080 | grep namespace-listener")
    machine.wait_until_succeeds("tcpdump -n -r /tmp/control.pcap 2>/dev/null | grep 18080")
    # Supply a clearnet route. New AND established service traffic must stay blocked.
    machine.succeed(f"ip -n vpnapps route replace 10.71.216.232/32 via {host_ip} dev {ns_if}")
    machine.succeed(f"sh -c 'timeout 5 tcpdump -U -n -i {host_if} -w /tmp/leak.pcap dst host 10.71.216.232 >/tmp/leak.log 2>&1; touch /tmp/capture-done' &")
    machine.wait_until_succeeds("grep -q listening /tmp/leak.log")
    machine.wait_until_succeeds("test ! -s /var/lib/vpnc-probe/result")
    machine.wait_until_succeeds("test -e /tmp/capture-done")
    machine.succeed("test -z \"$(tcpdump -n -r /tmp/leak.pcap 2>/dev/null)\"")
    machine.succeed("ip -n vpnapps route replace 10.71.216.232/32 dev wg0")
    machine.wait_until_succeeds("grep -q '8080,4444,53' /var/lib/vpnc-probe/result")

    # A failed replacement transaction must retain the working firewall.
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc > /tmp/policy-before")
    machine.succeed("printf 'destroy table inet vpnc\\ntable inet vpnc { chain broken { invalid syntax; } }\\n' > /tmp/invalid.nft")
    machine.fail("ip netns exec vpnapps nft -f /tmp/invalid.nft")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc > /tmp/policy-after; cmp /tmp/policy-before /tmp/policy-after")

    # Remote outage: the application and WG unit remain active, traffic stops.
    machine.succeed("nft add table inet outage")
    machine.succeed("nft 'add chain inet outage output { type filter hook output priority -100; policy accept; }'")
    machine.succeed("nft add rule inet outage output udp dport 51821 drop")
    machine.wait_until_succeeds("test ! -s /var/lib/vpnc-probe/result")
    machine.succeed("systemctl is-active --quiet vpnc-probe wireguard-wg0")
    machine.succeed("nft delete table inet outage")
    machine.wait_until_succeeds("grep -q '8080,4444,53' /var/lib/vpnc-probe/result")

    # Restart propagates to previously active services and sockets.
    machine.succeed("systemctl restart wireguard-wg0.service")
    machine.wait_for_unit("vpnc-probe.service")
    machine.wait_for_unit("vpnc-echo.socket")
    machine.wait_until_succeeds("grep -q '8080,4444,53' /var/lib/vpnc-probe/result")

    # Removing the interface externally must not create a host-link fallback.
    machine.succeed("ip -n vpnapps link del wg0")
    machine.wait_until_succeeds("test ! -s /var/lib/vpnc-probe/result")
    machine.fail("ip -n vpnapps route show | grep '^default '")
    # The namespace inode can outlive its name. Rules must remain with it.
    pid = machine.succeed("systemctl show vpnc-probe -p MainPID --value").strip()
    machine.succeed("ip netns del vpnapps")
    machine.succeed(f"nsenter -t {pid} -n nft list chain inet vpnc output | grep 'policy drop'")
    machine.succeed("systemctl stop vpnc-probe.service")
  '';
}
