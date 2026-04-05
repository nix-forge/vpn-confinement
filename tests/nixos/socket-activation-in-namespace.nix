_: {
  name = "socket-activation-in-namespace";

  nodes.machine =
    { pkgs, ... }:
    {
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

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    machine.succeed("systemctl show -p NetworkNamespacePath --value socket-echo.socket | grep -q '^/run/netns/vpnapps$'")
    machine.succeed("systemctl show -p NetworkNamespacePath --value socket-echo.service | grep -q '^/run/netns/vpnapps$'")
    machine.succeed("systemctl show -p BindsTo --value socket-echo.socket | grep -q 'vpn-confinement-netns@vpnapps.service'")
    machine.succeed("systemctl show -p BindsTo --value socket-echo.socket | grep -q 'wireguard-wg0.service'")
    machine.succeed("systemctl show -p BindsTo --value socket-echo.service | grep -q 'wireguard-wg0.service'")

    machine.succeed("systemctl start socket-echo.socket")
    machine.wait_for_unit("socket-echo.socket")
    machine.wait_for_unit("vpn-confinement-netns@vpnapps.service")
    machine.wait_for_unit("wireguard-wg0.service")

    machine.succeed("systemctl start socket-echo.service")
    machine.succeed("systemctl show -p Result --value socket-echo.service | grep -q '^success$'")
  '';
}
