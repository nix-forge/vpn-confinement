{ pkgs, ... }:
{
  name = "multi-namespace-lifecycle";

  nodes.machine = {
    imports = [ ../../modules ];

    networking.hostName = "multi-namespace";
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      defaultNamespace = "media";
      namespaces = {
        media = {
          enable = true;
          wireguard.interface = "wg-media";
          hostLink.enable = true;
          dns = {
            mode = "strict";
            servers = [ "10.64.0.1" ];
          };
        };
        apps = {
          enable = true;
          wireguard.interface = "wg-apps";
          hostLink.enable = true;
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
    media_host_ip = machine.succeed("ip -4 -o addr show dev ve-media-host | awk '{print $4}'").strip()
    apps_host_ip = machine.succeed("ip -4 -o addr show dev ve-apps-host | awk '{print $4}'").strip()
    media_ns_ip = machine.succeed("ip netns exec media ip -4 -o addr show dev ve-media-ns | awk '{print $4}'").strip()
    apps_ns_ip = machine.succeed("ip netns exec apps ip -4 -o addr show dev ve-apps-ns | awk '{print $4}'").strip()
    assert media_host_ip.startswith("169.254.")
    assert apps_host_ip.startswith("169.254.")
    assert media_ns_ip.startswith("169.254.")
    assert apps_ns_ip.startswith("169.254.")
    assert media_host_ip.endswith("/30")
    assert apps_host_ip.endswith("/30")
    assert media_ns_ip.endswith("/30")
    assert apps_ns_ip.endswith("/30")
    assert media_host_ip != apps_host_ip
    machine.succeed("systemctl show -p NetworkNamespacePath --value media-probe.service | grep -q '^/run/netns/media$'")
    machine.succeed("systemctl show -p NetworkNamespacePath --value apps-probe.service | grep -q '^/run/netns/apps$'")
    machine.succeed("systemctl stop media-probe.service apps-probe.service wireguard-wg-media.service wireguard-wg-apps.service")
    machine.wait_until_succeeds("! ip netns list | grep -q '^media\\b'")
    machine.wait_until_succeeds("! ip netns list | grep -q '^apps\\b'")
  '';
}
