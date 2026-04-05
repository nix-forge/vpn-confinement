{ pkgs, ... }:
{
  name = "runtime-ip-leak-fail-closed";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "runtime-ip-leak";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguard.interface = "wg0";
        hostLink = {
          enable = true;
          subnetIPv4 = "10.231.0.0/30";
        };
        dns = {
          mode = "strict";
          servers = [ "10.64.0.1" ];
        };
        egress.mode = "allowAllTunnel";
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

    systemd.services.netns-probe = {
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
    machine.wait_for_unit("netns-probe.service")

    machine.succeed("systemctl show -p NetworkNamespacePath --value netns-probe.service | grep -q '^/run/netns/vpnapps$'")
    machine.succeed("ip netns exec vpnapps ip route | grep -q '^default dev wg0'")

    machine.fail("ip netns exec vpnapps ip route | grep -Eq 'default via '")
    machine.succeed("ip route | grep -Eq '^default via '")

    machine.succeed("ip netns exec vpnapps nft list chain inet vpnc output | grep -q 'policy drop'")
    machine.succeed("ip netns exec vpnapps nft list chain inet vpnc output | grep -q 'oifname \"wg0\" accept'")
  '';
}
