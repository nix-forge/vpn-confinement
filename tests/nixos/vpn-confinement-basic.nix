{ pkgs, ... }:
{
  name = "vpn-confinement-basic";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-basic";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguard.interface = "wg0";
        hostLink.enable = true;
        hostLink.hostAddressIPv4 = "10.231.0.1";
        hostLink.nsAddressIPv4 = "10.231.0.2";
        ingress.fromHost.tcp = [ 8080 ];
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

    systemd.services.netns-echo = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };
      vpn.enable = true;
    };

    environment.systemPackages = [
      pkgs.curl
      pkgs.iproute2
      pkgs.nftables
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("vpn-confinement-netns@vpnapps.service")
    machine.wait_for_unit("wireguard-wg0.service")
    machine.succeed("systemctl show -p Result --value netns-echo.service | grep -q '^success$'")

    machine.succeed("ip netns list | grep -q '^vpnapps\\b'")
    machine.succeed("ip -n vpnapps link show wg0")
    machine.succeed("systemctl show -p NetworkNamespacePath --value netns-echo.service | grep -q '^/run/netns/vpnapps$'")
    machine.succeed("test -s /run/vpn-confinement/vpnapps/resolv.conf")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'policy drop'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'meta nfproto ipv6 drop'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -Eq 'iifname \"ve-vpnapps-ns\" ip saddr 10\\.231\\.0\\.1 tcp dport (\\{ 8080 \\}|8080) accept'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'udp dport { 53, 853, 5353, 5355 } drop'")
    machine.succeed("ip netns exec vpnapps nft list table inet vpnc | grep -q 'tcp dport { 53, 853, 5353, 5355 } drop'")
    machine.succeed("systemctl show -p BindReadOnlyPaths --value netns-echo.service | grep -q '/etc/resolv.conf'")
    machine.succeed("systemctl show -p BindReadOnlyPaths --value netns-echo.service | grep -q '/etc/nsswitch.conf'")
    machine.succeed("systemctl show -p InaccessiblePaths --value netns-echo.service | grep -q '/run/systemd/resolve'")
    machine.succeed("systemctl stop netns-echo.service")
    machine.wait_until_succeeds("! ip netns list | grep -q '^vpnapps\\b'")
  '';
}
