_: {
  name = "reject-missing-namespace-selection";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "reject-missing-namespace-selection";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguard.interface = "wg0";
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

    systemd.services.missing-namespace = {
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        ExecStart = "/run/current-system/sw/bin/true";
      };
      vpn.enable = true;
    };
  };
}
