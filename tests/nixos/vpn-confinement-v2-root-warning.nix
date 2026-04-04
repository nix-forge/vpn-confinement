{ pkgs, ... }:
{
  name = "vpn-confinement-v2-root-warning";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-v2-root-warning";
    system.stateVersion = "26.05";
    services.nscd.enable = false;

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
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
    };

    systemd.services.root-vpn-service = {
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };
      vpn.enable = true;
    };
  };
}
