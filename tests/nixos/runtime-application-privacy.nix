{ pkgs, lib, ... }:
let
  tracker = pkgs.writeText "local-tracker.py" ''
    import http.server, socket, struct
    class Tracker(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            peer = socket.inet_aton("10.71.216.232") + struct.pack("!H", 51414)
            body = b"d8:intervali1e5:peers6:" + peer + b"e"
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)
    http.server.HTTPServer(("10.71.216.232", 8080), Tracker).serve_forever()
  '';
  resolverProbe = pkgs.writeText "libc-resolver-probe.py" ''
    import pathlib, socket, time
    assert "nameserver 10.71.216.232" in pathlib.Path("/etc/resolv.conf").read_text()
    try:
        socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    except OSError:
        pathlib.Path("/var/lib/resolver-probe/raw-blocked").touch()
    else:
        raise AssertionError("raw packet access unexpectedly permitted")
    while True:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as helper:
                try:
                    helper.connect("/run/systemd/resolve/io.systemd.Resolve")
                except OSError:
                    pass
                else:
                    raise AssertionError("host resolver IPC unexpectedly reachable")
            answers = socket.getaddrinfo("tracker.test", 8080, socket.AF_INET, socket.SOCK_STREAM)
            assert {answer[4][0] for answer in answers} == {"10.71.216.232"}
            pathlib.Path("/var/lib/resolver-probe/ready").write_text("resolved through VPN")
        except (OSError, AssertionError):
            pathlib.Path("/var/lib/resolver-probe/ready").unlink(missing_ok=True)
        time.sleep(0.2)
  '';
in
{
  name = "runtime-application-privacy";
  nodes.machine = { config, ... }: {
    imports = [ ./fixtures/wireguard-peer.nix ];
    services.resolved.enable = true;
    networking.dhcpcd.denyInterfaces = [ "isp-client" ];
    networking.nameservers = [ "192.0.2.1" ];
    services.vpnConfinement.namespaces.vpnapps = {
      dns.servers = lib.mkForce [ "10.71.216.232" ];
      publishToHost.tcp = [ 9091 ];
      hostLink = {
        hostIf = "app-host";
        nsIf = "app-ns";
        subnetIPv4 = "10.231.0.0/30";
      };
    };
    networking.wireguard.interfaces.wg0 = {
      mtu = 1200;
      peers = lib.mkForce [
        {
          publicKey = "iCXIkYspxjCzUbbO4CThCIQGu5mVoG7mWw8Ac0wprlg=";
          endpoint = "192.0.2.2:51821";
          allowedIPs = [ "0.0.0.0/0" ];
          persistentKeepalive = 1;
        }
      ];
    };
    systemd.services.test-wireguard-peer.script = lib.mkForce ''
      set -eu
      umask 077
      mkdir -p /run/wg-test
      printf '%s\n' 'qE43SrN52JGV9FYU5i7jp5zCq+8osxyXORZfS5faf3s=' > /run/wg-test/client.key
      printf '%s\n' 'wOXXEHK/pVYgJSj/mU05R2kCz+bhawfV0TttYud+zk8=' > /run/wg-test/peer.key
      ip netns add provider
      ip link add isp-client type veth peer name isp-provider
      ip link set isp-provider netns provider
      ip addr add 192.0.2.1/30 dev isp-client
      ip link set isp-client mtu 1300 up
      ip -n provider addr add 192.0.2.2/30 dev isp-provider
      ip -n provider link set isp-provider mtu 1300 up
      ip -n provider link set lo up
      ip -n provider link add wg-test-peer type wireguard
      ip -n provider addr add 10.71.216.232/32 dev wg-test-peer
      ip netns exec provider wg set wg-test-peer private-key /run/wg-test/peer.key listen-port 51821 peer 82mHWUiLcZUtgHut8zeEdb9Phu4AMg3b1vU6uQo2IT4= allowed-ips 10.71.216.231/32
      ip -n provider link set wg-test-peer mtu 1200 up
      ip -n provider route add 10.71.216.231/32 dev wg-test-peer
      # Transmission probes routing to choose a source address. Only the
      # configured client has a WireGuard allowed-IP mapping on this link.
      ip -n provider route add default dev wg-test-peer
    '';
    systemd.services.test-wireguard-peer.postStop = lib.mkForce ''
      ${pkgs.iproute2}/bin/ip link del isp-client || true
      ${pkgs.iproute2}/bin/ip netns del provider || true
    '';
    systemd.services.test-dns = {
      wantedBy = [ "multi-user.target" ];
      after = [ "test-wireguard-peer.service" ];
      requires = [ "test-wireguard-peer.service" ];
      serviceConfig = {
        NetworkNamespacePath = "/run/netns/provider";
        ExecStart = "${pkgs.dnsmasq}/bin/dnsmasq --keep-in-foreground --pid-file= --no-resolv --no-hosts --local=/test/ --bind-interfaces --listen-address=10.71.216.232 --address=/test/10.71.216.232 --log-queries --log-facility=-";
      };
    };
    systemd.services.host-dns-control = {
      wantedBy = [ "multi-user.target" ];
      after = [ "test-wireguard-peer.service" ];
      requires = [ "test-wireguard-peer.service" ];
      serviceConfig.ExecStart = "${pkgs.dnsmasq}/bin/dnsmasq --keep-in-foreground --pid-file= --no-resolv --no-hosts --local=/test/ --bind-interfaces --listen-address=192.0.2.1 --address=/test/203.0.113.99 --log-queries --log-facility=-";
    };
    systemd.services.test-tracker = {
      wantedBy = [ "multi-user.target" ];
      after = [ "test-wireguard-peer.service" ];
      requires = [ "test-wireguard-peer.service" ];
      serviceConfig = {
        NetworkNamespacePath = "/run/netns/provider";
        ExecStart = "${pkgs.python3}/bin/python3 ${tracker}";
      };
    };
    systemd.services.test-seeder = {
      wantedBy = [ "multi-user.target" ];
      after = [ "test-wireguard-peer.service" ];
      requires = [ "test-wireguard-peer.service" ];
      serviceConfig = {
        NetworkNamespacePath = "/run/netns/provider";
        StateDirectory = "test-seeder";
        InaccessiblePaths = config.systemd.services.resolver-probe.serviceConfig.InaccessiblePaths;
        BindReadOnlyPaths = [
          "${pkgs.writeText "provider-resolv.conf" "nameserver 10.71.216.232\n"}:/etc/resolv.conf"
          "${pkgs.writeText "provider-nsswitch.conf" "hosts: files dns\n"}:/etc/nsswitch.conf"
        ];
        ExecStart = "${pkgs.transmission_4}/bin/transmission-daemon -f -g /var/lib/test-seeder -w /var/lib/test-seeder/data -p 19091 -P 51414 -T -M -O --no-dht --no-lpd";
      };
    };
    systemd.services.resolver-probe = {
      wantedBy = [ ];
      vpn = {
        enable = true;
        namespace = "vpnapps";
        hardeningProfile = "strict";
      };
      serviceConfig = {
        DynamicUser = true;
        StateDirectory = "resolver-probe";
        ExecStart = "${pkgs.python3}/bin/python3 ${resolverProbe}";
      };
    };
    services.transmission = {
      enable = true;
      settings = {
        rpc-bind-address = config.services.vpnConfinement.namespaces.vpnapps.derived.hostLink.nsAddressIPv4;
        rpc-authentication-required = false;
        rpc-whitelist-enabled = false;
        rpc-host-whitelist-enabled = false;
        port-forwarding-enabled = false;
        dht-enabled = false;
        lpd-enabled = false;
        download-dir = "/var/lib/transmission/Downloads";
        speed-limit-down-enabled = true;
        speed-limit-down = 512;
      };
    };
    systemd.services.transmission.wantedBy = lib.mkForce [ ];
    systemd.services.transmission.vpn = {
      enable = true;
      namespace = "vpnapps";
      hardeningProfile = "strict";
    };
    environment.systemPackages = [
      pkgs.transmission_4
      pkgs.tcpdump
      pkgs.nftables
      pkgs.curl
    ];
  };
  testScript = ''
    import json
    machine.wait_for_unit("test-dns.service")
    machine.wait_for_unit("test-tracker.service")
    machine.wait_for_unit("test-seeder.service")
    machine.wait_for_unit("wireguard-wg0.service")
    machine.wait_until_succeeds("getent ahostsv4 host-control.test | grep 203.0.113.99")
    machine.succeed("test -S /run/systemd/resolve/io.systemd.Resolve")

    # Observe the simulated ISP uplink and all host interfaces. Prove
    # each capture works before checking for absent plaintext during transfer.
    machine.succeed("tcpdump -U -n -i isp-client -w /tmp/isp.pcap >/tmp/isp.log 2>&1 & echo $! > /tmp/isp.pid")
    machine.succeed("tcpdump -U -n -i any -w /tmp/host.pcap >/tmp/host.log 2>&1 & echo $! > /tmp/host.pid")
    machine.wait_until_succeeds("grep -q listening /tmp/isp.log && grep -q listening /tmp/host.log")
    machine.succeed("systemctl start resolver-probe transmission")
    machine.wait_for_unit("transmission.service")
    machine.wait_for_unit("resolver-probe.service")
    machine.wait_until_succeeds("test -e /var/lib/resolver-probe/ready", timeout=45)
    machine.succeed("journalctl -u test-dns --no-pager | grep tracker.test")
    machine.fail("journalctl -u host-dns-control --no-pager | grep tracker.test")

    machine.wait_until_succeeds("transmission-remote 10.231.0.2:9091 -l")
    machine.wait_until_succeeds("tcpdump -nr /tmp/isp.pcap udp port 51821 2>/dev/null | grep 51821")
    machine.wait_until_succeeds("tcpdump -nr /tmp/host.pcap tcp port 9091 2>/dev/null | grep 9091")
    machine.succeed("mkdir -p /var/lib/test-seeder/data; head -c 16777216 /dev/urandom > /var/lib/test-seeder/data/payload")
    machine.succeed("transmission-create -p -t http://tracker.test:8080/announce -o /tmp/local.torrent /var/lib/test-seeder/data/payload")
    machine.wait_until_succeeds("ip netns exec provider transmission-remote 127.0.0.1:19091 -a /tmp/local.torrent")
    machine.wait_until_succeeds("ip netns exec provider transmission-remote 127.0.0.1:19091 -t all -i | grep 'Percent Done: 100%'")
    machine.succeed("transmission-remote 10.231.0.2:9091 -a /tmp/local.torrent")
    machine.wait_until_succeeds("transmission-remote 10.231.0.2:9091 -t all -i | awk '/Percent Done:/ { if ($3+0 > 0 && $3+0 < 100) found=1 } END { exit !found }'", timeout=90)
    machine.succeed("nft add table inet outage; nft 'add chain inet outage output { type filter hook output priority -100; policy accept; }'; nft add rule inet outage output udp dport 51821 drop")
    machine.wait_until_succeeds("test ! -e /var/lib/resolver-probe/ready", timeout=45)
    machine.succeed("systemctl is-active --quiet transmission resolver-probe")
    machine.fail("journalctl -u host-dns-control --no-pager | grep tracker.test")
    machine.succeed("nft delete table inet outage")
    machine.wait_until_succeeds("test -e /var/lib/resolver-probe/ready")
    machine.succeed("systemctl restart wireguard-wg0.service")
    machine.wait_for_unit("transmission.service")
    machine.wait_until_succeeds("transmission-remote 10.231.0.2:9091 -t all -i | grep 'Percent Done: 100%'", timeout=180)
    machine.succeed("cmp /var/lib/test-seeder/data/payload /var/lib/transmission/Downloads/payload")
    report = json.loads(machine.succeed("vpn-confinement-doctor vpnapps --json"))[0]
    assert report["policyMatchesConfiguration"]
    machine.succeed("kill $(cat /tmp/isp.pid) $(cat /tmp/host.pid)")
    machine.fail("tcpdump -nr /tmp/isp.pcap 'port 53 or port 8080 or port 51414' 2>/dev/null | grep .")
    machine.fail("tcpdump -nr /tmp/host.pcap 'port 53 or port 8080 or port 51414' 2>/dev/null | grep .")
    machine.succeed("test -e /var/lib/resolver-probe/raw-blocked")
    # Rule tampering and missing peers must be reported by the real diagnostic.
    machine.succeed("ip netns exec vpnapps nft insert rule inet vpnc output accept")
    machine.fail("vpn-confinement-doctor vpnapps")
    machine.succeed("systemctl restart wireguard-wg0.service")
    machine.wait_for_unit("transmission.service")
    machine.succeed("ip netns exec vpnapps wg set wg0 peer iCXIkYspxjCzUbbO4CThCIQGu5mVoG7mWw8Ac0wprlg= remove")
    machine.fail("vpn-confinement-doctor vpnapps")
  '';
}
