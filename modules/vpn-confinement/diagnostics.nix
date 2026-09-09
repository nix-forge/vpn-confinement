{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.vpnConfinement;
  vpnLib = import ./lib.nix { inherit lib; };
  policies = import ./policy.nix { inherit lib pkgs; };
  namespaces = lib.filterAttrs (_: ns: ns.enable) cfg.namespaces;
  selectedNamespace = vpnLib.selectedNamespace cfg;
  manifest = pkgs.writeText "vpn-confinement-diagnostics.json" (
    builtins.toJSON {
      namespaces = lib.mapAttrs (
        name: ns:
        let
          wg = config.networking.wireguard.interfaces.${ns.wireguard.interface};
          services = lib.filterAttrs (
            _: unit: unit.vpn.enable && selectedNamespace unit == name
          ) config.systemd.services;
        in
        {
          interface = ns.wireguard.interface;
          inherit (ns) securityProfile;
          namespaceWarnings =
            lib.optionals ns.wireguard.allowInsecureKeyMaterial [ "insecure key material exception enabled" ]
            ++ lib.optionals ns.wireguard.allowHostnameEndpoints [ "host-side endpoint DNS exception enabled" ];
          dns = { inherit (ns.dns) mode servers allowHostResolverIPC; };
          ipv6 = ns.ipv6.mode;
          egress = ns.egress.mode;
          host = (vpnLib.effectiveNamespace name ns).hostLink;
          hostPorts = (vpnLib.effectiveNamespace name ns).fromHostTcp;
          endpointPinning = ns.wireguard.endpointPinning.enable;
          endpointTable = vpnLib.endpointTableName name;
          socketNamespace = ns.wireguard.socketNamespace;
          policySnapshot = (policies.namespace name ns).snapshot;
          endpointSnapshot = (policies.endpoint name ns wg).snapshot;
          peers = map (peer: {
            keyHash = builtins.hashString "sha256" peer.publicKey;
            inherit (peer) allowedIPs;
          }) wg.peers;
          services = lib.attrNames services;
          serviceWarnings = lib.mapAttrs (
            serviceName: unit:
            lib.optionals (vpnLib.unsafeCapabilities unit.serviceConfig) [
              "unsafe or noncanonical capabilities configured"
            ]
            ++ lib.optionals (vpnLib.privilegedCommandPhases unit.serviceConfig != [ ]) [
              "privileged or unverified lifecycle commands: ${lib.concatStringsSep ", " (vpnLib.privilegedCommandPhases unit.serviceConfig)}"
            ]
            ++
              lib.optionals
                (vpnLib.unconfinedSockets cfg config.systemd.services config.systemd.sockets serviceName != [ ])
                [
                  "host or unverified sockets: ${
                    lib.concatStringsSep ", " (
                      vpnLib.unconfinedSockets cfg config.systemd.services config.systemd.sockets serviceName
                    )
                  }"
                ]
            ++ lib.optionals unit.vpn.allowRootInHighAssurance [ "root exception enabled" ]
            ++ lib.optionals unit.vpn.allowUnsafeCapabilities [ "unsafe capability exception enabled" ]
            ++ lib.optionals unit.vpn.allowPrivilegedCommands [ "privileged command exception enabled" ]
            ++ lib.optionals unit.vpn.allowHostSockets [ "host socket exception enabled" ]
          ) services;
          sockets = lib.attrNames (
            lib.filterAttrs (_: unit: unit.vpn.enable && selectedNamespace unit == name) config.systemd.sockets
          );
        }
      ) namespaces;
    }
  );
  doctor =
    pkgs.writers.writePython3Bin "vpn-confinement-doctor"
      {
        # Substituted store paths exceed 79 columns; keep all other lint checks.
        flakeIgnore = [
          "E501"
          "W503"
        ];
      }
      (
        pkgs.replaceVarsWith {
          name = "vpn-confinement-doctor.py";
          src = ./doctor.py;
          replacements = {
            manifest = toString manifest;
            ip = lib.getExe' pkgs.iproute2 "ip";
            nft = lib.getExe' pkgs.nftables "nft";
            wg = lib.getExe' pkgs.wireguard-tools "wg";
            systemctl = lib.getExe' pkgs.systemd "systemctl";
          };
        }
      );

in
{
  config = lib.mkIf cfg.enable { environment.systemPackages = [ doctor ]; };
}
