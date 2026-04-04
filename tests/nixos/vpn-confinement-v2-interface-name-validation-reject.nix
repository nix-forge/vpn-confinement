_: {
  name = "vpn-confinement-v2-interface-name-validation-reject";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-v2-ifname-reject";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguard.interface = "wg-interface-name-too-long";
        hostLink = {
          enable = true;
          hostIf = "ve-vpnapps-host!";
          nsIf = "ve-vpnapps-namespace-too-long";
        };
        dns = {
          mode = "strict";
          servers = [ "10.64.0.1" ];
        };
      };
    };

    networking.wireguard.interfaces.wg-interface-name-too-long = {
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
  };
}
