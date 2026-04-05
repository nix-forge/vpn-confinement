_: {
  name = "reject-high-assurance-weakeners";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "reject-high-assurance";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        securityProfile = "highAssurance";
        wireguard = {
          interface = "wg0";
          allowHostnameEndpoints = true;
        };
        dns = {
          servers = [ "10.64.0.1" ];
          allowHostResolverIPC = true;
        };
      };
    };

    networking.wireguard.interfaces.wg0 = {
      privateKeyFile = "/run/wg-test/private.key";
      ips = [ "10.71.216.231/32" ];
      allowedIPsAsRoutes = false;
      dynamicEndpointRefreshSeconds = 300;
      peers = [
        {
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpoint = "localhost:51820";
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
    };
  };
}
