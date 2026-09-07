{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    attrByPath
    mapAttrs'
    mapAttrsToList
    mkMerge
    mkIf
    nameValuePair
    optionalString
    filterAttrs
    ;
  inherit (import ./context.nix { inherit config lib; })
    cfg
    vpnLib
    enabledNamespaces
    hostLinkEnabled
    effectiveHostLink
    namespacePath
    hostIfs
    nsIfs
    ;
  helperUnitHardeningBase = {
    NoNewPrivileges = true;
    LockPersonality = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    AmbientCapabilities = [ ];
  };

  namespaceUnitHardening = helperUnitHardeningBase // {
    CapabilityBoundingSet = [
      "CAP_NET_ADMIN"
      "CAP_SYS_ADMIN"
    ];
  };

  endpointPinningUnitHardening = helperUnitHardeningBase // {
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
  };

  policies = import ./policy.nix { inherit lib pkgs; };

  namespaceUnits = mapAttrs' (
    nsName: ns:
    let
      withHostLink = hostLinkEnabled nsName ns;
      policy = policies.namespace nsName ns;
      unitName = "vpn-confinement-netns@${nsName}";
    in
    nameValuePair unitName {
      description = "Prepare VPN confinement namespace ${nsName}";
      before = [ "wireguard-${ns.wireguard.interface}.service" ];
      partOf = [ "wireguard-${ns.wireguard.interface}.service" ];
      serviceConfig = namespaceUnitHardening // {
        RuntimeDirectory = policy.runtimeDirectory;
        RuntimeDirectoryMode = "0700";
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu

        cleanup_failed_start() {
          ${optionalString withHostLink "${pkgs.iproute2}/bin/ip link del ${ns.hostLink.hostIf} 2>/dev/null || true"}
          ${pkgs.iproute2}/bin/ip netns del ${nsName} 2>/dev/null || true
        }

        success=0
        trap 'if [ "$success" -ne 1 ]; then cleanup_failed_start; fi' EXIT INT TERM

        ${pkgs.coreutils}/bin/mkdir -p /run/netns
        if [ ! -e ${namespacePath nsName} ]; then
          ${pkgs.iproute2}/bin/ip netns add ${nsName}
        fi

        ${pkgs.iproute2}/bin/ip -n ${nsName} link set lo up

        ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft -f ${policy.file}

        ${optionalString withHostLink ''
          ${pkgs.iproute2}/bin/ip link del ${ns.hostLink.hostIf} 2>/dev/null || true
          ${pkgs.iproute2}/bin/ip -n ${nsName} link del ${ns.hostLink.nsIf} 2>/dev/null || true

          ${pkgs.iproute2}/bin/ip link add ${ns.hostLink.hostIf} type veth peer name ${ns.hostLink.nsIf}
          ${pkgs.iproute2}/bin/ip link set ${ns.hostLink.nsIf} netns ${nsName}
          ${pkgs.iproute2}/bin/ip addr replace ${
            effectiveHostLink.${nsName}.hostAddressIPv4
          }/30 dev ${ns.hostLink.hostIf}
          ${pkgs.iproute2}/bin/ip link set ${ns.hostLink.hostIf} up
          ${pkgs.iproute2}/bin/ip -n ${nsName} addr replace ${
            effectiveHostLink.${nsName}.nsAddressIPv4
          }/30 dev ${ns.hostLink.nsIf}
          ${pkgs.iproute2}/bin/ip -n ${nsName} link set ${ns.hostLink.nsIf} up
        ''}

        ${optionalString (ns.ipv6.mode == "disable") ''
          ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.procps}/bin/sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
          ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.procps}/bin/sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
        ''}

        ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.runtimeShell} -c ${lib.escapeShellArg policy.capture}

        success=1
      '';
      postStop = ''
        set -eu
        ${optionalString withHostLink "${pkgs.iproute2}/bin/ip link del ${ns.hostLink.hostIf} 2>/dev/null || true"}
        ${pkgs.iproute2}/bin/ip netns del ${nsName} 2>/dev/null || true
      '';
    }
  ) enabledNamespaces;

  wireguardAssignments = mapAttrs' (
    nsName: ns:
    let
      endpointPinningMark =
        if ns.wireguard.endpointPinning.fwMark != null then
          ns.wireguard.endpointPinning.fwMark
        else
          vpnLib.deriveWireguardFwMark ns.wireguard.interface;
    in
    nameValuePair ns.wireguard.interface (
      {
        interfaceNamespace = lib.mkDefault nsName;
      }
      // lib.optionalAttrs (ns.wireguard.socketNamespace != null) {
        socketNamespace = lib.mkDefault ns.wireguard.socketNamespace;
      }
      // lib.optionalAttrs ns.wireguard.endpointPinning.enable {
        fwMark = lib.mkDefault (toString endpointPinningMark);
      }
    )
  ) enabledNamespaces;

  wgDependencyUnits = mkMerge (
    mapAttrsToList (nsName: ns: {
      "wireguard-${ns.wireguard.interface}" = {
        after = [
          "vpn-confinement-netns@${nsName}.service"
        ]
        ++ lib.optionals ns.wireguard.endpointPinning.enable [
          "vpn-confinement-endpoint-pinning@${nsName}.service"
        ];
        requires = [
          "vpn-confinement-netns@${nsName}.service"
        ]
        ++ lib.optionals ns.wireguard.endpointPinning.enable [
          "vpn-confinement-endpoint-pinning@${nsName}.service"
        ];
        bindsTo = [
          "vpn-confinement-netns@${nsName}.service"
        ]
        ++ lib.optionals ns.wireguard.endpointPinning.enable [
          "vpn-confinement-endpoint-pinning@${nsName}.service"
        ];
      };
    }) enabledNamespaces
  );

  endpointPinningUnits = mapAttrs' (
    nsName: ns:
    let
      wg = ns.wireguard.interface;
      wgConfig = attrByPath [ wg ] null config.networking.wireguard.interfaces;
      policy = policies.endpoint nsName ns (if wgConfig == null then { } else wgConfig);
      socketBirthplace =
        if ns.wireguard.socketNamespace == null || ns.wireguard.socketNamespace == "init" then
          "init"
        else
          ns.wireguard.socketNamespace;
      nftExec = "${pkgs.nftables}/bin/nft";
      tableName = policy.table;
      birthplaceManaged =
        socketBirthplace != "init" && builtins.hasAttr socketBirthplace enabledNamespaces;
      unitName = "vpn-confinement-endpoint-pinning@${nsName}";
    in
    nameValuePair unitName {
      description = "Apply endpoint pinning policy for ${wg}";
      before = [ "wireguard-${wg}.service" ];
      after = lib.optionals birthplaceManaged [ "vpn-confinement-netns@${socketBirthplace}.service" ];
      requires = lib.optionals birthplaceManaged [ "vpn-confinement-netns@${socketBirthplace}.service" ];
      bindsTo = lib.optionals birthplaceManaged [ "vpn-confinement-netns@${socketBirthplace}.service" ];
      partOf = [ "wireguard-${wg}.service" ];
      serviceConfig =
        endpointPinningUnitHardening
        // lib.optionalAttrs (socketBirthplace != "init") {
          NetworkNamespacePath = namespacePath socketBirthplace;
        }
        // {
          Type = "oneshot";
          RemainAfterExit = true;
          RuntimeDirectory = policy.runtimeDirectory;
          RuntimeDirectoryMode = "0700";
        };
      script = ''
        set -eu
        ${nftExec} -f ${policy.file}
        ${policy.capture}
      '';
      postStop = ''
        set -eu
        ${nftExec} delete table inet ${tableName} >/dev/null 2>&1 || true
      '';
    }
  ) (filterAttrs (_: ns: ns.wireguard.endpointPinning.enable) enabledNamespaces);

in
{
  config = mkIf cfg.enable {
    systemd.services = mkMerge [
      namespaceUnits
      endpointPinningUnits
      wgDependencyUnits
    ];
    networking.wireguard.interfaces = wireguardAssignments;
    # These veths have module-owned static addresses. Host managers must not
    # add DHCP, IPv4LL or router-discovery configuration to them.
    networking.dhcpcd.denyInterfaces = hostIfs ++ nsIfs;
    networking.networkmanager.unmanaged = map (name: "interface-name:${name}") (hostIfs ++ nsIfs);
    systemd.network.networks = lib.listToAttrs (
      map (name: {
        name = "09-vpn-confinement-${name}";
        value = {
          matchConfig.Name = name;
          linkConfig.Unmanaged = true;
        };
      }) (hostIfs ++ nsIfs)
    );
  };
}
