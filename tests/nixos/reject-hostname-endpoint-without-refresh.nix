_: {
  name = "reject-hostname-endpoint-without-refresh";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "reject-hostname-endpoint-without-refresh";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguard.interface = "wg0";
        wireguard.allowHostnameEndpoints = true;
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
          endpoint = "localhost:51820";
          dynamicEndpointRefreshSeconds = 0;
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
      dynamicEndpointRefreshSeconds = 0;
    };
  };
}
