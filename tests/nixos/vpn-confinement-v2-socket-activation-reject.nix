{ pkgs, ... }:
{
  name = "vpn-confinement-v2-socket-activation-reject";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-v2-socket-reject";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguard.interface = "wg0";
        hostLink.hostAddressIPv4 = "10.231.3.1";
        hostLink.nsAddressIPv4 = "10.231.3.2";
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

    systemd.sockets.bad-socket = {
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = [ "127.0.0.1:18080" ];
        Service = "bad-socket.service";
      };
    };

    systemd.services.bad-socket = {
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };
      vpn.enable = true;
    };
  };

  testScript = ''
    machine.fail("systemctl start bad-socket.service")
    machine.succeed("journalctl -b --no-pager | grep -q 'socket-activated units'")
  '';
}
