{ pkgs, ... }:
{
  name = "vpn-confinement-leak-tests";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-leaks";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguard.interface = "wg0";
        hostLink.subnetIPv4 = "10.231.1.0/30";
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

    systemd.services.netns-probe = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
      };
      vpn.enable = true;
    };

    systemd.services.netns-lived = {
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
    machine.succeed("systemctl show -p Result --value netns-probe.service | grep -q '^success$'")

    machine.succeed("systemctl show -p NetworkNamespacePath --value netns-probe.service | grep -q '^/run/netns/vpnapps$'")
    machine.succeed("systemctl show -p BindsTo --value netns-probe.service | grep -q 'vpn-confinement-netns@vpnapps.service'")
    machine.succeed("systemctl show -p BindsTo --value netns-probe.service | grep -q 'wireguard-wg0.service'")
    machine.succeed("systemctl show -p BindsTo --value wireguard-wg0.service | grep -q 'vpn-confinement-netns@vpnapps.service'")
    machine.wait_for_unit("netns-lived.service")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'udp dport 53 drop'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'tcp dport 53 drop'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'set dns_blocked_ports'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'udp dport @dns_blocked_ports drop'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'tcp dport @dns_blocked_ports drop'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'meta nfproto ipv6 drop'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'oifname \"wg0\" accept'")
    machine.succeed("systemctl show -p InaccessiblePaths --value netns-lived.service | grep -q '/run/systemd/resolve'")
    machine.succeed("systemctl stop wireguard-wg0.service")
    machine.wait_until_succeeds("systemctl show -p ActiveState --value netns-lived.service | grep -q '^inactive$'")
  '';
}
