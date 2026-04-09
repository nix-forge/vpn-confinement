{ pkgs, ... }:
{
  name = "runtime-endpoint-pinning-drop";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "runtime-endpoint-pinning-drop";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguard = {
          interface = "wg0";
          endpointPinning.enable = true;
        };
        dns.servers = [ "10.64.0.1" ];
      };
    };

    networking.wireguard.interfaces.wg0 = {
      privateKeyFile = "/run/wg-test/private.key";
      ips = [ "10.71.216.231/32" ];
      peers = [
        {
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpoint = "138.199.43.91:51820";
          persistentKeepalive = 1;
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
      pkgs.netcat-openbsd
      pkgs.nftables
      pkgs.wireguard-tools
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("wireguard-wg0.service")
    machine.wait_until_succeeds("nft list table inet vpnc_endpoint_pin_vpnapps >/dev/null 2>&1")

    machine.succeed("nft reset counters table inet vpnc_endpoint_pin_vpnapps")
    machine.succeed("ip netns exec vpnapps wg set wg0 peer bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0= endpoint 203.0.113.7:51820 persistent-keepalive 1")
    machine.succeed("ip netns exec vpnapps sh -c 'printf pin | nc -u -w 1 10.0.0.10 53 || true'")
    machine.wait_until_succeeds("nft list chain inet vpnc_endpoint_pin_vpnapps output | grep -Eq 'meta mark [0-9]+ udp counter packets [1-9][0-9]* drop'")
  '';
}
