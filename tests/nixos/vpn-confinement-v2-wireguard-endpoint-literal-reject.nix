_: {
  name = "vpn-confinement-v2-wireguard-endpoint-literal-reject";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-v2-endpoint-reject";
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
          endpoint = "vpn.example.com:51820";
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
    };
  };
}
