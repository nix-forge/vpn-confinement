_: {
  name = "vpn-confinement-v2-dns-nscd-toggle";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../../modules ];

      networking.hostName = "vpnc-v2-dns-nscd";
      system.stateVersion = "26.05";

      services.vpnConfinement = {
        enable = true;
        defaultNamespace = "ns-default";
        namespaces = {
          ns-default = {
            enable = true;
            wireguard.interface = "wg-default";
            dns = {
              mode = "strict";
              servers = [ "10.64.0.1" ];
            };
          };
          ns-block = {
            enable = true;
            wireguard.interface = "wg-block";
            dns = {
              mode = "strict";
              servers = [ "10.64.0.1" ];
              blockNscd = true;
            };
          };
        };
      };

      networking.wireguard.interfaces.wg-default = {
        privateKeyFile = "/run/wg-test/default.key";
        ips = [ "10.71.216.231/32" ];
        peers = [
          {
            publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
            endpoint = "138.199.43.91:51820";
            allowedIPs = [ "0.0.0.0/0" ];
          }
        ];
      };

      networking.wireguard.interfaces.wg-block = {
        privateKeyFile = "/run/wg-test/block.key";
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
          "wireguard-wg-default.service"
          "wireguard-wg-block.service"
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          set -eu
          ${pkgs.coreutils}/bin/mkdir -p /run/wg-test
          ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/default.key
          ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/block.key
          ${pkgs.coreutils}/bin/chmod 0600 /run/wg-test/default.key /run/wg-test/block.key
        '';
      };

      systemd.services.svc-default = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
        };
        vpn = {
          enable = true;
          namespace = "ns-default";
        };
      };

      systemd.services.svc-block = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
        };
        vpn = {
          enable = true;
          namespace = "ns-block";
        };
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("wireguard-wg-default.service")
    machine.wait_for_unit("wireguard-wg-block.service")
    machine.fail("systemctl show -p InaccessiblePaths --value svc-default.service | grep -q '/run/nscd'")
    machine.succeed("systemctl show -p InaccessiblePaths --value svc-block.service | grep -q '/run/nscd'")
  '';
}
