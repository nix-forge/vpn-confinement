_: {
  name = "vpn-confinement-v2-host-socket-vpn-service-pattern";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../../modules ];

      networking.hostName = "vpnc-v2-host-socket-pattern";
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

      systemd.sockets.socket-host = {
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = [ "127.0.0.1:18081" ];
          Service = "socket-host.service";
        };
      };

      systemd.services.socket-host = {
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
    machine.wait_for_unit("wireguard-wg0.service")
    machine.succeed("systemctl start socket-host.socket")
    machine.wait_for_unit("socket-host.socket")
    machine.fail("systemctl show -p NetworkNamespacePath --value socket-host.socket | grep -q '^/run/netns/vpnapps$'")
    machine.succeed("systemctl show -p NetworkNamespacePath --value socket-host.service | grep -q '^/run/netns/vpnapps$'")
  '';
}
