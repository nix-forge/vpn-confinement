{ pkgs, lib, ... }:
let
  vpnLib = import ../../modules/vpn-confinement/lib.nix { inherit lib; };
  names = [
    "vpn-a"
    "vpn.a"
  ];
  tableA = vpnLib.endpointTableName "vpn-a";
  tableB = vpnLib.endpointTableName "vpn.a";
in
{
  name = "runtime-policy-lifecycle";
  nodes.machine = {
    imports = [ ../../modules ];
    system.stateVersion = "26.05";
    services.vpnConfinement = {
      enable = true;
      namespaces = lib.genAttrs names (name: {
        enable = true;
        wireguard = {
          interface = if name == "vpn-a" then "wg-a" else "wg-b";
          socketNamespace = "uplink";
          endpointPinning.enable = true;
        };
        dns.servers = [ "10.64.0.1" ];
        egress = {
          mode = "allowList";
          allowedCidrs = [
            "192.0.2.0/24"
            "192.0.2.0/25"
          ];
        };
      });
    };
    networking.wireguard.interfaces = lib.genAttrs [ "wg-a" "wg-b" ] (_: {
      privateKeyFile = "/run/test-key";
      peers = [
        {
          publicKey = "82mHWUiLcZUtgHut8zeEdb9Phu4AMg3b1vU6uQo2IT4=";
          endpoint = "192.0.2.1:51820";
          allowedIPs = [ "0.0.0.0/0" ];
        }
      ];
    });
    systemd.services = {
      test-uplink = {
        before = map (n: "vpn-confinement-endpoint-pinning@${n}.service") names;
        requiredBy = map (n: "vpn-confinement-endpoint-pinning@${n}.service") names;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          umask 077
          ${pkgs.wireguard-tools}/bin/wg genkey > /run/test-key
          ${pkgs.iproute2}/bin/ip netns add uplink
          ${pkgs.iproute2}/bin/ip -n uplink link set lo up
        '';
      };
    };
    environment.systemPackages = [
      pkgs.iproute2
      pkgs.nftables
    ];
  };
  testScript = ''
    machine.wait_for_unit("wireguard-wg-a.service")
    machine.wait_for_unit("wireguard-wg-b.service")
    machine.succeed("ip netns exec uplink nft list table inet ${tableA}")
    machine.succeed("ip netns exec uplink nft list table inet ${tableB}")
    machine.fail("nft list table inet ${tableA}")
    machine.succeed("systemctl restart wireguard-wg-a.service")
    machine.wait_for_unit("wireguard-wg-a.service")
    machine.succeed("ip netns exec uplink nft list table inet ${tableB}")
    machine.succeed("systemctl stop wireguard-wg-a.service")
    machine.wait_until_succeeds("! systemctl is-active --quiet vpn-confinement-endpoint-pinning@vpn-a.service")
    machine.wait_until_succeeds("! ip netns exec uplink nft list table inet ${tableA}")
    machine.succeed("ip netns exec uplink nft list table inet ${tableB}")
    machine.succeed("systemctl is-active --quiet wireguard-wg-b.service")
  '';
}
