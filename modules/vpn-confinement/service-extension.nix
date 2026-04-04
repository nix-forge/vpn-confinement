{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrByPath
    mkDefault
    mkIf
    mkMerge
    mkEnableOption
    mkOption
    types
    ;

  rootConfig = config;
  vpnLib = import ./lib.nix { inherit lib; };

  hardeningBaseline = {
    NoNewPrivileges = mkDefault true;
    PrivateTmp = mkDefault true;
    ProtectSystem = mkDefault "full";
    ProtectHome = mkDefault "read-only";
    ProtectControlGroups = mkDefault true;
    RestrictSUIDSGID = mkDefault true;
    LockPersonality = mkDefault true;
    CapabilityBoundingSet = mkDefault "";
    AmbientCapabilities = mkDefault [ ];
    UMask = mkDefault "0027";
  };

  hardeningStrict = {
    PrivateDevices = mkDefault true;
    ProtectKernelModules = mkDefault true;
    ProtectKernelTunables = mkDefault true;
    ProtectKernelLogs = mkDefault true;
    ProtectProc = mkDefault "invisible";
    ProcSubset = mkDefault "pid";
    RestrictNamespaces = mkDefault true;
    ProtectClock = mkDefault true;
    ProtectHostname = mkDefault true;
    RestrictRealtime = mkDefault true;
    MemoryDenyWriteExecute = mkDefault true;
    SystemCallArchitectures = mkDefault "native";
    SystemCallFilter = mkDefault [
      "@system-service"
      "~@mount"
    ];
    SystemCallErrorNumber = mkDefault "EPERM";
  };
in
{
  options.systemd.services = mkOption {
    type = types.attrsOf (
      types.submodule (
        { config, ... }:
        let
          vcfg = rootConfig.services.vpnConfinement;
          nsName = if config.vpn.namespace != null then config.vpn.namespace else vcfg.defaultNamespace;
          ns = attrByPath [ nsName ] null vcfg.namespaces;
          nsExists = ns != null;
          strictDns = nsExists && ns.dns.mode == "strict";
          resolvText =
            if nsExists then
              pkgs.writeText "vpn-confinement-${nsName}.resolv.conf" (vpnLib.renderResolvConf ns.dns)
            else
              null;
          nsswitchText =
            if nsExists then
              pkgs.writeText "vpn-confinement-${nsName}.nsswitch.conf" (vpnLib.renderNsswitchConf ns.dns)
            else
              null;
          withHostLink = nsExists && ns.hostLink.enable;
          wgIf = if nsExists then ns.wireguard.interface else "wg0";
          familySet =
            if nsExists && ns.ipv6.mode == "disable" then
              [
                "AF_UNIX"
                "AF_INET"
              ]
            else
              [
                "AF_UNIX"
                "AF_INET"
                "AF_INET6"
              ];
        in
        {
          options.vpn = {
            enable = mkEnableOption "run this unit in the VPN confinement namespace";

            namespace = mkOption {
              type = types.nullOr types.str;
              default = null;
            };

            hardeningProfile = mkOption {
              type = types.enum [
                "baseline"
                "strict"
              ];
              default = "baseline";
            };
          };

          config = mkIf (vcfg.enable && config.vpn.enable) (mkMerge [
            {
              after = [ "vpn-confinement-netns@${nsName}.service" ];
              requires = [ "vpn-confinement-netns@${nsName}.service" ];
              serviceConfig = hardeningBaseline // {
                NetworkNamespacePath = "/run/netns/${nsName}";
                RestrictAddressFamilies = mkDefault familySet;
                RestrictNetworkInterfaces = mkDefault (
                  [
                    "lo"
                    wgIf
                  ]
                  ++ lib.optionals withHostLink [ ns.hostLink.nsIf ]
                );
              };
            }
            (mkIf nsExists {
              after = [ "wireguard-${wgIf}.service" ];
              requires = [ "wireguard-${wgIf}.service" ];
              bindsTo = [ "wireguard-${wgIf}.service" ];
            })
            (mkIf strictDns (
              let
                inaccessiblePaths = [
                  "/run/resolvconf"
                  "-/run/systemd/resolve"
                ]
                ++ lib.optionals (!ns.dns.allowResolverHelpers) [ "/run/nscd" ]
                ++ lib.optionals (!ns.dns.allowResolverHelpers) [
                  "/run/dbus/system_bus_socket"
                  "-/var/run/dbus/system_bus_socket"
                ];
              in
              {
                serviceConfig = {
                  BindReadOnlyPaths = [
                    "${resolvText}:/etc/resolv.conf"
                    "${nsswitchText}:/etc/nsswitch.conf"
                  ];
                  InaccessiblePaths = inaccessiblePaths;
                };
              }
            ))
            (mkIf (config.vpn.hardeningProfile == "strict") { serviceConfig = hardeningStrict; })
          ]);
        }
      )
    );
  };
}
