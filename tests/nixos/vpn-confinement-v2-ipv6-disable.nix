{ pkgs, ... }:
{
  name = "vpn-confinement-v2-ipv6-disable";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-v2-ipv6";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguard.interface = "wg0";
        hostLink.subnetIPv4 = "10.231.2.0/30";
        dns = {
          mode = "strict";
          servers = [ "10.64.0.1" ];
        };
        ipv6.mode = "disable";
      };
    };

    networking.wireguard.interfaces.wg0 = {
      privateKeyFile = "/run/wg-test/private.key";
      ips = [ "10.71.216.231/32" ];
      peers = [
        {
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpoint = "138.199.43.91:51820";
          persistentKeepalive = 25;
          allowedIPs = [ "0.0.0.0/0" ];
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

    systemd.services.netns-ipv6-probe = {
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
      pkgs.procps
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("vpn-confinement-netns@vpnapps.service")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'meta nfproto ipv6 drop'")
    machine.fail("ip netns exec vpnapps nft list table inet vpnc | grep -q 'ip6 daddr'")
    machine.succeed("ip netns exec vpnapps sysctl -n net.ipv6.conf.all.disable_ipv6 | grep -q '^1$'")
    machine.succeed("ip netns exec vpnapps sysctl -n net.ipv6.conf.default.disable_ipv6 | grep -q '^1$'")
    machine.succeed("systemctl show -p RestrictNetworkInterfaces --value netns-ipv6-probe.service | grep -Eq '(^| )lo( |$)'")
    machine.succeed("systemctl show -p RestrictNetworkInterfaces --value netns-ipv6-probe.service | grep -Eq '(^| )wg0( |$)'")
  '';
}
