_: {
  name = "socket-activation-in-namespace";

  nodes.machine = { pkgs, ... }: {
    imports = [ ../../modules ];

    networking.hostName = "socket-activation";
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
      peers = [
        {
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpoint = "138.199.43.91:51820";
          persistentKeepalive = 25;
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
    };

    systemd.services.test-vpn-private-key = {
      wantedBy = [ "multi-user.target" ];
      before = [ "wireguard-wg0.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        umask 077
        ${pkgs.coreutils}/bin/mkdir -p /run/wg-test
        ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/private.key
        ${pkgs.coreutils}/bin/chmod 0600 /run/wg-test/private.key
      '';
    };

    systemd.sockets.socket-echo = {
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = [ "127.0.0.1:18080" ];
        Service = "socket-echo.service";
      };
      vpn = {
        enable = true;
        namespace = "vpnapps";
      };
    };

    systemd.services.socket-echo = {
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
      };
      vpn = {
        enable = true;
        namespace = "vpnapps";
      };
    };
  };

}
