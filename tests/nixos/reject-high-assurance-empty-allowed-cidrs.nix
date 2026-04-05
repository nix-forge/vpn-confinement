_: {
  name = "reject-high-assurance-empty-allowed-cidrs";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "reject-high-assurance-empty-allowed-cidrs";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        securityProfile = "highAssurance";
        wireguard.interface = "wg0";
        dns.servers = [ "10.64.0.1" ];
        egress = {
          mode = "allowList";
          allowedTcpPorts = [ 443 ];
          allowedCidrs = [ ];
        };
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
