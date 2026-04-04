{ pkgs, ... }:
{
  name = "vpn-confinement-v2-strict-dns-direct-port53-block";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-v2-strict-dns-port53";
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

    environment.systemPackages = [
      pkgs.iproute2
      pkgs.nftables
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("vpn-confinement-netns@vpnapps.service")

    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'ip daddr 10.64.0.1 udp dport 53 accept'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'ip daddr 10.64.0.1 tcp dport 53 accept'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'oifname \"wg0\" udp dport 53 drop'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'oifname \"wg0\" tcp dport 53 drop'")
    machine.fail("ip netns exec vpnapps nft list table inet vpnc | grep -q '1.1.1.1.*dport 53 accept'")
  '';
}
