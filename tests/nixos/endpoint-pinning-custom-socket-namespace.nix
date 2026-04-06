{ pkgs, ... }:
{
  name = "endpoint-pinning-custom-socket-namespace";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "endpoint-pinning-custom-socket-namespace";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces = {
        vpnapps = {
          enable = true;
          wireguard = {
            interface = "wg0";
            socketNamespace = "birthplace";
            endpointPinning.enable = true;
          };
          dns = {
            mode = "strict";
            servers = [ "10.64.0.1" ];
          };
        };
        birthplace = {
          enable = true;
          wireguard.interface = "wg-birthplace";
          wireguard.socketNamespace = "init";
          dns = {
            mode = "strict";
            servers = [ "10.64.0.1" ];
          };
        };
      };
    };

    networking.wireguard.interfaces = {
      wg0 = {
        privateKeyFile = "/run/wg-test/wg0.key";
        ips = [ "10.71.216.231/32" ];
        peers = [
          {
            publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
            endpoint = "138.199.43.91:51820";
            allowedIPs = [ "0.0.0.0/0" ];
          }
        ];
      };
      wg-birthplace = {
        privateKeyFile = "/run/wg-test/wg-birthplace.key";
        ips = [ "10.71.216.232/32" ];
        peers = [
          {
            publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
            endpoint = "138.199.43.92:51820";
            allowedIPs = [ "0.0.0.0/0" ];
          }
        ];
      };
    };

    systemd.services.test-vpn-private-keys = {
      wantedBy = [ "multi-user.target" ];
      before = [
        "wireguard-wg0.service"
        "wireguard-wg-birthplace.service"
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        ${pkgs.coreutils}/bin/mkdir -p /run/wg-test
        ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/wg0.key
        ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/wg-birthplace.key
        ${pkgs.coreutils}/bin/chmod 0600 /run/wg-test/wg0.key /run/wg-test/wg-birthplace.key
      '';
    };
  };
}
