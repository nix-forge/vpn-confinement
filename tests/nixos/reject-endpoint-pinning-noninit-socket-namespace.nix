_: {
  name = "reject-endpoint-pinning-noninit-socket-namespace";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "reject-endpoint-pinning-noninit-socket-namespace";
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
        birthplace.enable = true;
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
  };
}
