_: {
  name = "reject-cross-role-interface-collision";

  nodes.machine = {
    imports = [ ../../modules ];

    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces = {
        first = {
          enable = true;
          wireguard.interface = "wg-first";
          hostLink = {
            enable = true;
            hostIf = "shared-if";
            nsIf = "first-ns";
            subnetIPv4 = "10.231.0.0/30";
          };
          dns.servers = [ "10.64.0.1" ];
        };
        second = {
          enable = true;
          wireguard.interface = "wg-second";
          hostLink = {
            enable = true;
            hostIf = "second-host";
            nsIf = "shared-if";
            subnetIPv4 = "10.231.0.4/30";
          };
          dns.servers = [ "10.64.0.1" ];
        };
      };
    };

    networking.wireguard.interfaces = {
      wg-first = {
        privateKeyFile = "/run/wg-test/first.key";
        ips = [ "10.71.216.231/32" ];
        peers = [
          {
            publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
            endpoint = "138.199.43.91:51820";
            allowedIPs = [ "0.0.0.0/0" ];
          }
        ];
      };
      wg-second = {
        privateKeyFile = "/run/wg-test/second.key";
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
  };
}
