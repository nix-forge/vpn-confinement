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
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    mkOverride
    types
    unique
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
          ns = if nsName == null then null else attrByPath [ nsName ] null vcfg.namespaces;
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
          withHostLink = nsExists && (ns.hostLink.enable || ns.publishToHost.tcp != [ ]);
          wgIf = if nsExists then ns.wireguard.interface else "wg0";
          allowedBindTcp =
            if nsExists then
              unique (ns.ingress.fromHost.tcp ++ ns.publishToHost.tcp ++ ns.ingress.fromTunnel.tcp)
            else
              [ ];
          allowedBindUdp = if nsExists then unique ns.ingress.fromTunnel.udp else [ ];
          bindAllowRules =
            (map (port: "tcp:${toString port}") allowedBindTcp)
            ++ (map (port: "udp:${toString port}") allowedBindUdp);
          defaultFamilySet =
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
          familySet = unique (defaultFamilySet ++ config.vpn.extraAddressFamilies);
          defaultInterfaceSet = [
            "lo"
            wgIf
          ]
          ++ lib.optionals withHostLink [ ns.hostLink.nsIf ];
        in
        {
          options.vpn = {
            enable = mkEnableOption "run this unit in the VPN confinement namespace";

            namespace = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Namespace name override for this service. Leave unset to use services.vpnConfinement.defaultNamespace when one is configured.";
            };

            hardeningProfile = mkOption {
              type = types.enum [
                "baseline"
                "strict"
              ];
              default = if nsExists && ns.securityProfile == "highAssurance" then "strict" else "baseline";
              description = "Service hardening preset applied on top of confinement wiring.";
            };

            restrictBind = mkOption {
              type = types.bool;
              default = false;
              description = "Restrict service-created listeners to declared namespace ingress ports as defense in depth.";
            };

            allowRootInHighAssurance = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Explicit opt-out for high-assurance non-root enforcement. Use only
                when this service cannot run as DynamicUser or a dedicated User.
              '';
            };

            extraAddressFamilies = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Additional AddressFamily names appended to RestrictAddressFamilies for this service.";
            };
          };

          config = mkIf (vcfg.enable && config.vpn.enable && nsName != null) (mkMerge [
            {
              after = [ "vpn-confinement-netns@${nsName}.service" ];
              requires = [ "vpn-confinement-netns@${nsName}.service" ];
              bindsTo = [ "vpn-confinement-netns@${nsName}.service" ];
              serviceConfig = hardeningBaseline // {
                NetworkNamespacePath = mkDefault "/run/netns/${nsName}";
                RestrictAddressFamilies = mkDefault familySet;
                RestrictNetworkInterfaces = mkDefault defaultInterfaceSet;
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
                ++ lib.optionals (!ns.dns.allowHostResolverIPC) [ "/run/nscd" ]
                ++ lib.optionals (!ns.dns.allowHostResolverIPC) [
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
            (mkIf (nsExists && config.vpn.restrictBind && bindAllowRules != [ ]) {
              serviceConfig = {
                SocketBindAllow = bindAllowRules;
                SocketBindDeny = [ "any" ];
              };
            })
            (mkIf (config.vpn.hardeningProfile == "strict") {
              serviceConfig = hardeningStrict // {
                ProtectSystem = mkOverride 900 "strict";
                ProtectHome = mkOverride 900 true;
              };
            })
          ]);
        }
      )
    );
  };
}
