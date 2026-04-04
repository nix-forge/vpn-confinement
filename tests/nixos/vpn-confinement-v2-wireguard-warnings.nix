_: {
  name = "vpn-confinement-v2-wireguard-warnings";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-v2-wireguard-warnings";
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
      dynamicEndpointRefreshSeconds = 300;
      allowedIPsAsRoutes = false;
      peers = [
        {
          name = "dynpeer";
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpoint = "localhost:51820";
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
    };
  };
}
