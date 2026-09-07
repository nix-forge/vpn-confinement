{ pkgs, lib, ... }:
let
  payload = pkgs.writeTextDir "payload" (
    lib.concatStrings (builtins.genList (_: "0123456789abcdef") 16384)
  );
in
{
  name = lib.mkForce "runtime-ipv6";
  imports = [ ./runtime-wireguard-handshake.nix ];
  nodes.machine = {
    services.vpnConfinement.namespaces.vpnapps = {
      ipv6.mode = "tunnel";
      egress = {
        mode = "allowList";
        allowedCidrs = [
          "fd42::1/128"
          "10.71.216.232/32"
        ];
      };
    };
    networking.wireguard.interfaces.wg0 = {
      mtu = 1280;
      ips = [ "fd42::2/128" ];
      peers = lib.mkForce [
        {
          publicKey = "iCXIkYspxjCzUbbO4CThCIQGu5mVoG7mWw8Ac0wprlg=";
          endpoint = "127.0.0.1:51821";
          allowedIPs = [
            "10.71.216.232/32"
            "fd42::1/128"
          ];
          persistentKeepalive = 1;
        }
      ];
    };
    systemd.services.test-wireguard-peer.script = lib.mkAfter ''
      ip addr add fd42::1/128 dev wg-test-peer
      wg set wg-test-peer peer 82mHWUiLcZUtgHut8zeEdb9Phu4AMg3b1vU6uQo2IT4= allowed-ips 10.71.216.231/32,fd42::2/128
      ip -6 route add fd42::2/128 dev wg-test-peer
    '';
    systemd.services.test-ipv6-server = {
      wantedBy = [ "multi-user.target" ];
      after = [ "test-wireguard-peer.service" ];
      requires = [ "test-wireguard-peer.service" ];
      serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8080 --bind fd42::1 --directory ${payload}";
    };
    systemd.services.ipv6-probe = {
      vpn = {
        enable = true;
        namespace = "vpnapps";
        hardeningProfile = "strict";
      };
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        StateDirectory = "ipv6-probe";
        ExecStart = "${pkgs.curl}/bin/curl -g -6 --fail --connect-timeout 3 --max-time 10 http://[fd42::1]:8080/payload -o /var/lib/ipv6-probe/payload";
      };
    };
  };
  testScript = lib.mkAfter ''
    machine.wait_for_unit("test-ipv6-server.service")
    machine.wait_until_succeeds("systemctl start ipv6-probe.service")
    machine.succeed("test $(wc -c </var/lib/ipv6-probe/payload) -eq 262144")
    machine.succeed("ip -n vpnapps -6 route show | grep 'fd42::1 dev wg0'")
    machine.succeed("systemctl restart wireguard-wg0.service")
    machine.wait_until_succeeds("systemctl start ipv6-probe.service")
    machine.succeed("test $(wc -c </var/lib/ipv6-probe/payload) -eq 262144")
  '';
}
