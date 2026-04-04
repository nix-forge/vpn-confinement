{ pkgs, ... }:
{
  name = "vpn-confinement-v2-multi-namespace";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "vpnc-v2-multi";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      defaultNamespace = "media";
      namespaces = {
        media = {
          enable = true;
          wireguard.interface = "wg-media";
          hostLink.enable = true;
          hostLink.hostAddressIPv4 = "10.231.10.1";
          hostLink.nsAddressIPv4 = "10.231.10.2";
          dns = {
            mode = "strict";
            servers = [ "10.64.0.1" ];
          };
        };
        apps = {
          enable = true;
          wireguard.interface = "wg-apps";
          hostLink.enable = true;
          hostLink.hostAddressIPv4 = "10.231.11.1";
          hostLink.nsAddressIPv4 = "10.231.11.2";
          dns = {
            mode = "strict";
            servers = [ "10.64.0.1" ];
          };
        };
      };
    };

    networking.wireguard.interfaces.wg-media = {
      privateKeyFile = "/run/wg-test/media.key";
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

    networking.wireguard.interfaces.wg-apps = {
      privateKeyFile = "/run/wg-test/apps.key";
      ips = [ "10.71.216.232/32" ];
      peers = [
        {
          publicKey = "bZQF7VRDRK/JUJ8L6EFzF/zRw2tsqMRk6FesGtTgsC0=";
          endpoint = "138.199.43.92:51820";
          persistentKeepalive = 25;
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
    };

    systemd.services.test-vpn-private-keys = {
      wantedBy = [ "multi-user.target" ];
      before = [
        "wireguard-wg-media.service"
        "wireguard-wg-apps.service"
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        ${pkgs.coreutils}/bin/mkdir -p /run/wg-test
        ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/media.key
        ${pkgs.wireguard-tools}/bin/wg genkey > /run/wg-test/apps.key
        ${pkgs.coreutils}/bin/chmod 0600 /run/wg-test/media.key /run/wg-test/apps.key
      '';
    };

    systemd.services.media-probe = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };
      vpn = {
        enable = true;
        namespace = "media";
      };
    };

    systemd.services.apps-probe = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };
      vpn = {
        enable = true;
        namespace = "apps";
      };
    };

    environment.systemPackages = [
      pkgs.iproute2
      pkgs.nftables
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("vpn-confinement-netns@media.service")
    machine.wait_for_unit("vpn-confinement-netns@apps.service")
    machine.succeed("ip netns list | grep -q '^media\\b'")
    machine.succeed("ip netns list | grep -q '^apps\\b'")
    machine.succeed("ip addr show ve-media-host | grep -q '10.231.10.1/30'")
    machine.succeed("ip addr show ve-apps-host | grep -q '10.231.11.1/30'")
    machine.succeed("ip netns exec media ip addr show ve-media-ns | grep -q '10.231.10.2/30'")
    machine.succeed("ip netns exec apps ip addr show ve-apps-ns | grep -q '10.231.11.2/30'")
    machine.succeed("systemctl show -p NetworkNamespacePath --value media-probe.service | grep -q '^/run/netns/media$'")
    machine.succeed("systemctl show -p NetworkNamespacePath --value apps-probe.service | grep -q '^/run/netns/apps$'")
    machine.succeed("systemctl stop media-probe.service apps-probe.service")
    machine.wait_until_succeeds("! ip netns list | grep -q '^media\\b'")
    machine.wait_until_succeeds("! ip netns list | grep -q '^apps\\b'")
  '';
}
