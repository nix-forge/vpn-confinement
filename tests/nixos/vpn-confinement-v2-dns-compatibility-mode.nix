_: {
  name = "vpn-confinement-v2-dns-compatibility-mode";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../../modules ];

      networking.hostName = "vpnc-v2-dns-compat";
      system.stateVersion = "26.05";

      services.vpnConfinement = {
        enable = true;
        defaultNamespace = "ns-strict";
        namespaces = {
          ns-strict = {
            enable = true;
            wireguard.interface = "wg-strict";
            dns = {
              mode = "strict";
              servers = [ "10.64.0.1" ];
            };
          };
          ns-compat = {
            enable = true;
            wireguard.interface = "wg-compat";
            dns = {
              mode = "strict";
              servers = [ "10.64.0.1" ];
              compatibilityMode = true;
            };
          };
        };
      };

      networking.wireguard.interfaces.wg-strict = {
        privateKeyFile = "/run/wg-test/strict.key";
        ips = [ "10.71.216.231/32" ];
        peers = [
          {
            publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
            endpoint = "138.199.43.91:51820";
            allowedIPs = [ "0.0.0.0/0" ];
          }
        ];
      };

      networking.wireguard.interfaces.wg-compat = {
        privateKeyFile = "/run/wg-test/compat.key";
        ips = [ "10.71.216.232/32" ];
        peers = [
          {
            publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
            endpoint = "138.199.43.92:51820";
            allowedIPs = [ "0.0.0.0/0" ];
          }
        ];
      };

      systemd.services.test-vpn-private-keys = {
        wantedBy = [ "multi-user.target" ];
        before = [
          "wireguard-wg-strict.service"
          "wireguard-wg-compat.service"
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          set -eu
          ${pkgs.coreutils}/bin/mkdir -p /run/wg-test
          ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/strict.key
          ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/compat.key
          ${pkgs.coreutils}/bin/chmod 0600 /run/wg-test/strict.key /run/wg-test/compat.key
        '';
      };

      systemd.services.svc-strict = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
        };
        vpn = {
          enable = true;
          namespace = "ns-strict";
        };
      };

      systemd.services.svc-compat = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
        };
        vpn = {
          enable = true;
          namespace = "ns-compat";
        };
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("wireguard-wg-strict.service")
    machine.wait_for_unit("wireguard-wg-compat.service")
    machine.succeed("systemctl show -p InaccessiblePaths --value svc-strict.service | grep -q '/run/nscd'")
    machine.succeed("systemctl show -p InaccessiblePaths --value svc-strict.service | grep -q '/run/dbus/system_bus_socket'")
    machine.fail("systemctl show -p InaccessiblePaths --value svc-compat.service | grep -q '/run/nscd'")
    machine.fail("systemctl show -p InaccessiblePaths --value svc-compat.service | grep -q '/run/dbus/system_bus_socket'")
  '';
}
