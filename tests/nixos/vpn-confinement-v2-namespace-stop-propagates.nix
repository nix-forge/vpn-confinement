{ pkgs, ... }:
{
  name = "vpn-confinement-v2-namespace-stop-propagates";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-v2-namespace-stop";
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

    systemd.services.netns-lived = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };
      vpn.enable = true;
    };

    environment.systemPackages = [ pkgs.iproute2 ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("vpn-confinement-netns@vpnapps.service")
    machine.wait_for_unit("wireguard-wg0.service")
    machine.wait_for_unit("netns-lived.service")

    machine.succeed("systemctl show -p BindsTo --value netns-lived.service | grep -q 'vpn-confinement-netns@vpnapps.service'")
    machine.succeed("systemctl show -p BindsTo --value wireguard-wg0.service | grep -q 'vpn-confinement-netns@vpnapps.service'")

    machine.succeed("systemctl stop vpn-confinement-netns@vpnapps.service")
    machine.wait_until_succeeds("systemctl show -p ActiveState --value netns-lived.service | grep -q '^inactive$'")
    machine.wait_until_succeeds("systemctl show -p ActiveState --value wireguard-wg0.service | grep -q '^inactive$'")
    machine.wait_until_succeeds("! ip netns list | grep -q '^vpnapps\\b'")
  '';
}
