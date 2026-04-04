_: {
  name = "vpn-confinement-v2-dns-system-bus-block";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../../modules ];

      networking.hostName = "vpnc-v2-dns-system-bus";
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

      systemd.services.netns-echo = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
        };
        vpn.enable = true;
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("wireguard-wg0.service")
    machine.succeed("systemctl show -p InaccessiblePaths --value netns-echo.service | grep -q '/run/dbus/system_bus_socket'")
  '';
}
