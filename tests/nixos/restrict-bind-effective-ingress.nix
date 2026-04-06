_: {
  name = "restrict-bind-effective-ingress";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "restrict-bind-effective-ingress";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguard.interface = "wg0";
        publishToHost.tcp = [ 8080 ];
        ingress.fromTunnel = {
          tcp = [ 9090 ];
          udp = [ 51413 ];
        };
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
          endpoint = "138.199.43.91:51820";
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
    };

    systemd.services.restrict-bind-probe = {
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        ExecStart = "/run/current-system/sw/bin/true";
      };
      vpn = {
        enable = true;
        namespace = "vpnapps";
        restrictBind = true;
      };
    };
  };
}
