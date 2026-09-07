{ lib, pkgs }:
let
  vpnLib = import ./lib.nix { inherit lib; };
  firewall = import ./firewall.nix { inherit lib; };
  policy =
    name: kind: table: rules:
    let
      runtimeDirectory = "vpn-confinement-${name}-${kind}";
      snapshot = "/run/${runtimeDirectory}/${builtins.hashString "sha256" rules}.json";
    in
    {
      inherit
        rules
        table
        runtimeDirectory
        snapshot
        ;
      file = pkgs.writeText "vpn-confinement-${name}-${kind}.nft" rules;
      # Capture only after the trusted transaction succeeds. A configuration
      # change chooses a different filename, so stale snapshots cannot match.
      capture = ''
        ${pkgs.nftables}/bin/nft --json --stateless list table inet ${table} > ${snapshot}.tmp
        ${pkgs.coreutils}/bin/mv ${snapshot}.tmp ${snapshot}
      '';
    };
in
{
  namespace = name: ns: policy name "namespace" "vpnc" (firewall.mkNftRules name ns);
  endpoint =
    name: ns: wgConfig:
    let
      mark =
        if ns.wireguard.endpointPinning.fwMark != null then
          ns.wireguard.endpointPinning.fwMark
        else
          vpnLib.deriveWireguardFwMark ns.wireguard.interface;
      endpoints = builtins.filter (spec: spec != null) (
        map (
          peer: if (peer.endpoint or null) == null then null else vpnLib.parseLiteralEndpoint peer.endpoint
        ) (wgConfig.peers or [ ])
      );
      table = vpnLib.endpointTableName name;
    in
    policy name "endpoint" table ''
      destroy table inet ${table}
      table inet ${table} {
        chain output {
          type filter hook output priority filter; policy accept;
          ${lib.concatMapStringsSep "\n" (
            spec:
            "meta mark ${toString mark} ${spec.family} daddr ${spec.address} udp dport ${toString spec.port} counter accept"
          ) endpoints}
          meta mark ${toString mark} meta l4proto udp counter drop
        }
      }
    '';
}
