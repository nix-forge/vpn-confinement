_: {
  name = "vpn-confinement-v2-hostlink-subnet-collision-reject";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-v2-hostlink-collision-reject";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      defaultNamespace = "ns-a";
      namespaces = {
        ns-a = {
          enable = true;
          wireguard.interface = "wg-a";
          hostLink = {
            enable = true;
            subnetIPv4 = "10.231.8.0/30";
          };
          dns = {
            mode = "strict";
            servers = [ "10.64.0.1" ];
          };
        };
        ns-b = {
          enable = true;
          wireguard.interface = "wg-b";
          hostLink = {
            enable = true;
            subnetIPv4 = "10.231.8.0/30";
          };
          dns = {
            mode = "strict";
            servers = [ "10.64.0.1" ];
          };
        };
      };
    };

    networking.wireguard.interfaces.wg-a = {
      privateKeyFile = "/run/wg-test/a.key";
      ips = [ "10.71.216.231/32" ];
      peers = [
        {
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpoint = "138.199.43.91:51820";
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
    };

    networking.wireguard.interfaces.wg-b = {
      privateKeyFile = "/run/wg-test/b.key";
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
}
