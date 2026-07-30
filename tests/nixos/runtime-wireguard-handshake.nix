{ pkgs, ... }:
let
  clientPublicKey = "82mHWUiLcZUtgHut8zeEdb9Phu4AMg3b1vU6uQo2IT4=";
  peerPublicKey = "iCXIkYspxjCzUbbO4CThCIQGu5mVoG7mWw8Ac0wprlg=";
in
{
  name = "runtime-wireguard-handshake";

  nodes.machine = {
    imports = [ ../../modules ];

    networking = {
      hostName = "runtime-wireguard-handshake";
      firewall.enable = false;
    };
    system.stateVersion = "26.05";

    services.vpnConfinement = {
      enable = true;
      namespaces.vpnapps = {
        enable = true;
        wireguard.interface = "wg0";
        dns.servers = [ "10.64.0.1" ];
      };
    };

    networking.wireguard.interfaces.wg0 = {
      privateKeyFile = "/run/wg-test/client.key";
      ips = [ "10.71.216.231/32" ];
      peers = [
        {
          publicKey = peerPublicKey;
          endpoint = "127.0.0.1:51821";
          persistentKeepalive = 1;
          allowedIPs = [ "10.71.216.232/32" ];
        }
      ];
    };

    systemd.services.test-wireguard-peer = {
      wantedBy = [ "multi-user.target" ];
      before = [ "wireguard-wg0.service" ];
      requiredBy = [ "wireguard-wg0.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.coreutils
        pkgs.iproute2
        pkgs.wireguard-tools
      ];
      script = ''
        set -eu
        mkdir -p /run/wg-test
        printf '%s\n' 'qE43SrN52JGV9FYU5i7jp5zCq+8osxyXORZfS5faf3s=' > /run/wg-test/client.key
        printf '%s\n' 'wOXXEHK/pVYgJSj/mU05R2kCz+bhawfV0TttYud+zk8=' > /run/wg-test/peer.key
        chmod 0600 /run/wg-test/client.key /run/wg-test/peer.key

        ip link add wg-test-peer type wireguard
        ip address add 10.71.216.232/32 dev wg-test-peer
        wg set wg-test-peer \
          private-key /run/wg-test/peer.key \
          listen-port 51821 \
          peer ${clientPublicKey} \
          allowed-ips 10.71.216.231/32
        ip link set wg-test-peer up
        ip route add 10.71.216.231/32 dev wg-test-peer
      '';
      postStop = ''
        ${pkgs.iproute2}/bin/ip link del wg-test-peer 2>/dev/null || true
      '';
    };

    environment.systemPackages = [
      pkgs.iproute2
      pkgs.iputils
      pkgs.wireguard-tools
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("test-wireguard-peer.service")
    machine.wait_for_unit("wireguard-wg0.service")
    machine.wait_until_succeeds("ip netns list | grep -q '^vpnapps\\b'")
    machine.wait_until_succeeds("ip netns exec vpnapps ping -c 1 -W 2 10.71.216.232")
    machine.wait_until_succeeds("ip netns exec vpnapps wg show wg0 latest-handshakes | awk '$2 > 0 { found = 1 } END { exit !found }'")
    machine.wait_until_succeeds("wg show wg-test-peer latest-handshakes | awk '$2 > 0 { found = 1 } END { exit !found }'")
    machine.succeed("ip netns exec vpnapps wg show wg0 transfer | awk '$2 > 0 && $3 > 0 { found = 1 } END { exit !found }'")
  '';
}
