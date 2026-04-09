_: {
  name = "long-namespace-generated-hostlink";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "long-namespace-generated-hostlink";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.this-namespace-name-is-deliberately-long-for-hostlink = {
        enable = true;
        wireguard.interface = "wg0";
        publishToHost.tcp = [ 8080 ];
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
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
    };
  };
}
