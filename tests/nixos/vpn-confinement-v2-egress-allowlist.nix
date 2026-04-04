{ pkgs, ... }:
{
  name = "vpn-confinement-v2-egress-allowlist";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-v2-egress-allowlist";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguard.interface = "wg0";
        dns = {
          mode = "strict";
          servers = [ "10.64.0.1" ];
        };
        ipv6.mode = "tunnel";
        egress = {
          mode = "allowList";
          allowedTcpPorts = [ 443 ];
          allowedUdpPorts = [ 123 ];
          allowedCidrs = [
            "198.51.100.0/24"
            "2001:db8::/32"
          ];
        };
      };
    };

    networking.wireguard.interfaces.wg0 = {
      privateKeyFile = "/run/wg-test/private.key";
      ips = [
        "10.71.216.231/32"
        "fd00::2/128"
      ];
      peers = [
        {
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpoint = "138.199.43.91:51820";
          persistentKeepalive = 25;
          allowedIPs = [
            "0.0.0.0/0"
            "::/0"
          ];
        }
      ];
    };

    systemd.services.test-vpn-private-key = {
      wantedBy = [ "multi-user.target" ];
      before = [ "wireguard-wg0.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        ${pkgs.coreutils}/bin/mkdir -p /run/wg-test
        ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/private.key
        ${pkgs.coreutils}/bin/chmod 0600 /run/wg-test/private.key
      '';
    };

    systemd.services.netns-allowlist-probe = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };
      vpn.enable = true;
    };

    environment.systemPackages = [
      pkgs.iproute2
      pkgs.nftables
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("vpn-confinement-netns@vpnapps.service")
    machine.wait_for_unit("wireguard-wg0.service")

    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -Eq 'ip daddr 198\\.51\\.100\\.0/24 tcp dport (\\{ 443 \\}|443) accept'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -Eq 'ip6 daddr 2001:db8::/32 tcp dport (\\{ 443 \\}|443) accept'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -Eq 'ip daddr 198\\.51\\.100\\.0/24 udp dport (\\{ 123 \\}|123) accept'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -Eq 'ip6 daddr 2001:db8::/32 udp dport (\\{ 123 \\}|123) accept'")
    machine.fail("ip netns exec vpnapps nft list table inet vpnc | grep -q 'oifname \"wg0\" accept'")
    machine.fail("ip netns exec vpnapps nft list table inet vpnc | grep -q 'meta nfproto ipv6 drop'")

    machine.succeed("systemctl show -p RestrictNetworkInterfaces --value netns-allowlist-probe.service | grep -Eq '(^| )lo( |$)'")
    machine.succeed("systemctl show -p RestrictNetworkInterfaces --value netns-allowlist-probe.service | grep -Eq '(^| )wg0( |$)'")
  '';
}
