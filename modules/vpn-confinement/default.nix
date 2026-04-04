{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    all
    attrNames
    concatMapStringsSep
    filterAttrs
    hasSuffix
    mapAttrs'
    mapAttrsToList
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    nameValuePair
    optionalString
    removeSuffix
    splitString
    types
    unique
    ;

  vpnLib = import ./lib.nix { inherit lib; };

  cfg = config.services.vpnConfinement;

  enabledNamespaces = filterAttrs (_: ns: ns.enable) cfg.namespaces;
  enabledNamespaceNames = attrNames enabledNamespaces;
  namespaceNames = attrNames cfg.namespaces;

  servicesWithVpn = filterAttrs (_: svc: (svc.vpn.enable or false)) config.systemd.services;
  vpnEnabledServiceNames = attrNames servicesWithVpn;

  socketsWithVpn = filterAttrs (_: socket: (socket.vpn.enable or false)) config.systemd.sockets;
  vpnEnabledSocketNames = attrNames socketsWithVpn;

  nsFor =
    serviceName:
    let
      inherit (config.systemd.services.${serviceName}) vpn;
    in
    if vpn.namespace != null then vpn.namespace else cfg.defaultNamespace;

  nsForSocket =
    socketName:
    let
      inherit (config.systemd.sockets.${socketName}) vpn;
    in
    if vpn.namespace != null then vpn.namespace else cfg.defaultNamespace;

  socketTargetUnit =
    socketName:
    let
      socket = config.systemd.sockets.${socketName};
      configured = socket.socketConfig.Service or null;
    in
    if configured == null then "${socketName}.service" else configured;

  serviceNameFromUnit =
    unit: if hasSuffix ".service" unit then removeSuffix ".service" unit else unit;

  namespacePath = nsName: "/run/netns/${nsName}";
  runtimePath = nsName: "/run/vpn-confinement/${nsName}";
  resolvConfPath = nsName: "${runtimePath nsName}/resolv.conf";
  nsswitchPath = nsName: "${runtimePath nsName}/nsswitch.conf";

  hostLinkEnabled = _nsName: ns: ns.hostLink.enable;

  blockedDnsPorts = [
    53
    853
    5353
    5355
  ];

  mkDnsBlockedPortRules = ns: ''
    oifname "${ns.wireguard.interface}" udp dport ${vpnLib.renderPortSet blockedDnsPorts} drop
    oifname "${ns.wireguard.interface}" tcp dport ${vpnLib.renderPortSet blockedDnsPorts} drop
  '';

  mkDnsOutputRules =
    ns:
    let
      dns = vpnLib.splitDns ns.dns.servers;
      hasV4 = dns.ipv4 != [ ];
      hasV6 = dns.ipv6 != [ ] && ns.ipv6.mode == "tunnel";
    in
    ''
      ${optionalString hasV4 ''
        oifname "${ns.wireguard.interface}" ip daddr ${vpnLib.renderPortSet dns.ipv4} udp dport 53 accept
        oifname "${ns.wireguard.interface}" ip daddr ${vpnLib.renderPortSet dns.ipv4} tcp dport 53 accept
      ''}
      ${optionalString hasV6 ''
        oifname "${ns.wireguard.interface}" ip6 daddr ${vpnLib.renderPortSet dns.ipv6} udp dport 53 accept
        oifname "${ns.wireguard.interface}" ip6 daddr ${vpnLib.renderPortSet dns.ipv6} tcp dport 53 accept
      ''}
      oifname "${ns.wireguard.interface}" udp dport 53 drop
      oifname "${ns.wireguard.interface}" tcp dport 53 drop
    '';

  mkEgressRules =
    ns:
    let
      allowedTcp = unique ns.egress.allowedTcpPorts;
      allowedUdp = unique ns.egress.allowedUdpPorts;
      allowedCidrs = unique ns.egress.allowedCidrs;
      cidrs = vpnLib.splitCidrs allowedCidrs;

      mkPortRule =
        proto: ports:
        let
          portSet = vpnLib.renderPortSet ports;
          defaultRule = "oifname \"${ns.wireguard.interface}\" ${proto} dport ${portSet} accept";
          ipv4Rule = "oifname \"${ns.wireguard.interface}\" ip daddr ${vpnLib.renderPortSet cidrs.ipv4} ${proto} dport ${portSet} accept";
          ipv6Rule = "oifname \"${ns.wireguard.interface}\" ip6 daddr ${vpnLib.renderPortSet cidrs.ipv6} ${proto} dport ${portSet} accept";
        in
        if ports == [ ] then
          ""
        else if allowedCidrs == [ ] then
          defaultRule
        else
          concatMapStringsSep "\n" (rule: rule) (
            lib.optionals (cidrs.ipv4 != [ ]) [ ipv4Rule ] ++ lib.optionals (cidrs.ipv6 != [ ]) [ ipv6Rule ]
          );

      cidrOnlyRules =
        if allowedCidrs == [ ] || allowedTcp != [ ] || allowedUdp != [ ] then
          ""
        else
          concatMapStringsSep "\n" (rule: rule) (
            lib.optionals (cidrs.ipv4 != [ ]) [
              "oifname \"${ns.wireguard.interface}\" ip daddr ${vpnLib.renderPortSet cidrs.ipv4} accept"
            ]
            ++ lib.optionals (cidrs.ipv6 != [ ]) [
              "oifname \"${ns.wireguard.interface}\" ip6 daddr ${vpnLib.renderPortSet cidrs.ipv6} accept"
            ]
          );
    in
    ''
      ${mkPortRule "tcp" allowedTcp}
      ${mkPortRule "udp" allowedUdp}
      ${cidrOnlyRules}
    '';

  mkNftRules =
    nsName: ns:
    let
      hostIngressTcp = unique ns.ingress.fromHost.tcp;
      inboundTcp = unique ns.ingress.fromTunnel.tcp;
      inboundUdp = unique ns.ingress.fromTunnel.udp;
      withHostLink = hostLinkEnabled nsName ns;
      strictDns = ns.dns.mode == "strict";
    in
    ''
      table inet vpnc {
        chain input {
          type filter hook input priority filter; policy drop;
          iifname "lo" accept
          ct state established,related accept
          ${optionalString (ns.ipv6.mode == "disable") "meta nfproto ipv6 drop"}
          ${optionalString (withHostLink && hostIngressTcp != [ ])
            "iifname \"${ns.hostLink.nsIf}\" ip saddr ${ns.hostLink.hostAddressIPv4} tcp dport ${vpnLib.renderPortSet hostIngressTcp} accept"
          }
          ${optionalString (
            inboundTcp != [ ]
          ) "iifname \"${ns.wireguard.interface}\" tcp dport ${vpnLib.renderPortSet inboundTcp} accept"}
          ${optionalString (
            inboundUdp != [ ]
          ) "iifname \"${ns.wireguard.interface}\" udp dport ${vpnLib.renderPortSet inboundUdp} accept"}
        }

        chain forward {
          type filter hook forward priority filter; policy drop;
        }

        chain output {
          type filter hook output priority filter; policy drop;
          oifname "lo" accept
          ct state established,related accept
          ${optionalString (ns.ipv6.mode == "disable") "meta nfproto ipv6 drop"}
          ${optionalString strictDns (mkDnsOutputRules ns)}
          ${optionalString strictDns (mkDnsBlockedPortRules ns)}
          ${mkEgressRules ns}
          ${optionalString (
            ns.egress.mode == "allowAllTunnel"
          ) "oifname \"${ns.wireguard.interface}\" accept"}
        }
      }
    '';

  namespaceUnits = mapAttrs' (
    nsName: ns:
    let
      withHostLink = hostLinkEnabled nsName ns;
      nftRules = pkgs.writeText "vpn-confinement-${nsName}.nft" (mkNftRules nsName ns);
      resolvText = pkgs.writeText "vpn-confinement-${nsName}.resolv.conf" (
        vpnLib.renderResolvConf ns.dns
      );
      nsswitchText = pkgs.writeText "vpn-confinement-${nsName}.nsswitch.conf" (
        vpnLib.renderNsswitchConf ns.dns
      );
      unitName = "vpn-confinement-netns@${nsName}";
    in
    nameValuePair unitName {
      description = "Prepare VPN confinement namespace ${nsName}";
      before = [ "wireguard-${ns.wireguard.interface}.service" ];
      unitConfig.StopWhenUnneeded = true;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu

        ${pkgs.coreutils}/bin/mkdir -p /run/netns
        if [ ! -e ${namespacePath nsName} ]; then
          ${pkgs.iproute2}/bin/ip netns add ${nsName}
        fi

        ${pkgs.iproute2}/bin/ip -n ${nsName} link set lo up

        ${optionalString withHostLink ''
          ${pkgs.iproute2}/bin/ip link del ${ns.hostLink.hostIf} 2>/dev/null || true
          ${pkgs.iproute2}/bin/ip -n ${nsName} link del ${ns.hostLink.nsIf} 2>/dev/null || true

          ${pkgs.iproute2}/bin/ip link add ${ns.hostLink.hostIf} type veth peer name ${ns.hostLink.nsIf}
          ${pkgs.iproute2}/bin/ip link set ${ns.hostLink.nsIf} netns ${nsName}
          ${pkgs.iproute2}/bin/ip addr replace ${ns.hostLink.hostAddressIPv4}/30 dev ${ns.hostLink.hostIf}
          ${pkgs.iproute2}/bin/ip link set ${ns.hostLink.hostIf} up
          ${pkgs.iproute2}/bin/ip -n ${nsName} addr replace ${ns.hostLink.nsAddressIPv4}/30 dev ${ns.hostLink.nsIf}
          ${pkgs.iproute2}/bin/ip -n ${nsName} link set ${ns.hostLink.nsIf} up
        ''}

        ${optionalString (ns.ipv6.mode == "disable") ''
          ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.procps}/bin/sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
          ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.procps}/bin/sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null
        ''}

        ${pkgs.coreutils}/bin/mkdir -p ${runtimePath nsName}
        ${pkgs.coreutils}/bin/install -m 0444 ${resolvText} ${resolvConfPath nsName}
        ${pkgs.coreutils}/bin/install -m 0444 ${nsswitchText} ${nsswitchPath nsName}

        ${pkgs.coreutils}/bin/mkdir -p /etc/netns/${nsName}
        ${pkgs.coreutils}/bin/install -m 0444 ${resolvText} /etc/netns/${nsName}/resolv.conf

        ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft delete table inet vpnc >/dev/null 2>&1 || true
        ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft -f ${nftRules}
      '';
      postStop = ''
        set -eu
        if [ -e ${namespacePath nsName} ]; then
          ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft delete table inet vpnc >/dev/null 2>&1 || true
        fi

        ${optionalString withHostLink "${pkgs.iproute2}/bin/ip link del ${ns.hostLink.hostIf} 2>/dev/null || true"}
        ${pkgs.coreutils}/bin/rm -rf ${runtimePath nsName}
        ${pkgs.coreutils}/bin/rm -rf /etc/netns/${nsName}
        ${pkgs.iproute2}/bin/ip netns del ${nsName} 2>/dev/null || true
      '';
    }
  ) enabledNamespaces;

  wireguardAssignments = mapAttrs' (
    nsName: ns:
    nameValuePair ns.wireguard.interface (
      {
        interfaceNamespace = nsName;
        dynamicEndpointRefreshSeconds = lib.mkDefault ns.wireguard.dynamicEndpointRefreshSeconds;
      }
      // lib.optionalAttrs (ns.wireguard.socketNamespace != null) {
        socketNamespace = lib.mkDefault ns.wireguard.socketNamespace;
      }
    )
  ) enabledNamespaces;

  wgDependencyUnits = mkMerge (
    mapAttrsToList (nsName: ns: {
      "wireguard-${ns.wireguard.interface}" = {
        after = [ "vpn-confinement-netns@${nsName}.service" ];
        requires = [ "vpn-confinement-netns@${nsName}.service" ];
      };
    }) enabledNamespaces
  );

  wgNames = map (nsName: enabledNamespaces.${nsName}.wireguard.interface) enabledNamespaceNames;

  activeHostLinks = lib.filter (
    nsName:
    let
      ns = enabledNamespaces.${nsName};
    in
    hostLinkEnabled nsName ns
  ) enabledNamespaceNames;

  hostIfs = map (nsName: enabledNamespaces.${nsName}.hostLink.hostIf) activeHostLinks;
  nsIfs = map (nsName: enabledNamespaces.${nsName}.hostLink.nsIf) activeHostLinks;
  hostAddrs = map (nsName: enabledNamespaces.${nsName}.hostLink.hostAddressIPv4) activeHostLinks;
  nsAddrs = map (nsName: enabledNamespaces.${nsName}.hostLink.nsAddressIPv4) activeHostLinks;

  namespaceAssertions = builtins.concatMap (
    nsName:
    let
      ns = enabledNamespaces.${nsName};
      wg = ns.wireguard.interface;
      dnsSplit = vpnLib.splitDns ns.dns.servers;
      cidrSplit = vpnLib.splitCidrs ns.egress.allowedCidrs;
      withHostLink = hostLinkEnabled nsName ns;
    in
    [
      {
        assertion = ns.dns.servers != [ ];
        message = "services.vpnConfinement.namespaces.${nsName}.dns.servers must be non-empty.";
      }
      {
        assertion = all vpnLib.isLiteralIp ns.dns.servers;
        message = "services.vpnConfinement.namespaces.${nsName}.dns.servers must contain literal IP addresses only.";
      }
      {
        assertion = !(ns.ipv6.mode == "disable" && dnsSplit.ipv6 != [ ]);
        message = "services.vpnConfinement.namespaces.${nsName}.dns.servers cannot include IPv6 when ipv6.mode = \"disable\".";
      }
      {
        assertion = vpnLib.isValidInterfaceName wg;
        message = "services.vpnConfinement.namespaces.${nsName}.wireguard.interface must be a valid Linux interface name (1-15 chars, [A-Za-z0-9_.-]).";
      }
      {
        assertion = ns.wireguard.dynamicEndpointRefreshSeconds >= 0;
        message = "services.vpnConfinement.namespaces.${nsName}.wireguard.dynamicEndpointRefreshSeconds must be >= 0.";
      }
      {
        assertion = builtins.all vpnLib.isLiteralCidr ns.egress.allowedCidrs;
        message = "services.vpnConfinement.namespaces.${nsName}.egress.allowedCidrs must contain literal IPv4/IPv6 CIDRs or IPs only.";
      }
      {
        assertion = !(ns.ipv6.mode == "disable" && cidrSplit.ipv6 != [ ]);
        message = "services.vpnConfinement.namespaces.${nsName}.egress.allowedCidrs cannot include IPv6 CIDRs when ipv6.mode = \"disable\".";
      }
      {
        assertion = builtins.hasAttr wg config.networking.wireguard.interfaces;
        message = "WireGuard interface ${wg} must exist under networking.wireguard.interfaces.";
      }
      {
        assertion =
          !(builtins.hasAttr wg config.networking.wireguard.interfaces)
          || (
            let
              wgConfig = config.networking.wireguard.interfaces.${wg};
              endpoints = builtins.filter (endpoint: endpoint != null) (
                map (peer: peer.endpoint or null) (wgConfig.peers or [ ])
              );
            in
            all vpnLib.isSupportedEndpoint endpoints
          );
        message = "services.vpnConfinement.namespaces.${nsName} requires networking.wireguard.interfaces.${wg}.peers.*.endpoint to use either a literal IP endpoint (IPv4:port or [IPv6]:port) or a hostname endpoint (hostname:port).";
      }
      {
        assertion =
          !(builtins.hasAttr wg config.networking.wireguard.interfaces)
          || (
            let
              wgConfig = config.networking.wireguard.interfaces.${wg};
              peers = wgConfig.peers or [ ];
              interfaceRefresh = wgConfig.dynamicEndpointRefreshSeconds or 0;
              peerHasEffectiveRefresh =
                peer:
                let
                  endpoint = peer.endpoint or null;
                  peerRefresh =
                    if (peer.dynamicEndpointRefreshSeconds or null) != null then
                      peer.dynamicEndpointRefreshSeconds
                    else
                      interfaceRefresh;
                in
                endpoint == null || !vpnLib.endpointIsHostname endpoint || peerRefresh > 0;
            in
            builtins.all peerHasEffectiveRefresh peers
          );
        message = "services.vpnConfinement.namespaces.${nsName} requires hostname WireGuard endpoints to have periodic refresh enabled (networking.wireguard.interfaces.${wg}.dynamicEndpointRefreshSeconds > 0 or peer dynamicEndpointRefreshSeconds > 0).";
      }
      {
        assertion =
          ns.ipv6.mode != "tunnel"
          || (
            let
              wgConfig = config.networking.wireguard.interfaces.${wg};
              peerAllowed = builtins.concatLists (map (peer: peer.allowedIPs or [ ]) (wgConfig.peers or [ ]));
              allRoutes = (wgConfig.ips or [ ]) ++ peerAllowed;
              literals = map (entry: builtins.head (splitString "/" entry)) allRoutes;
            in
            builtins.any vpnLib.isLiteralIpv6 literals
          );
        message = "services.vpnConfinement.namespaces.${nsName}.ipv6.mode = \"tunnel\" requires IPv6 routes on networking.wireguard.interfaces.${wg}.";
      }
      {
        assertion = !withHostLink || vpnLib.isValidInterfaceName ns.hostLink.hostIf;
        message = "services.vpnConfinement.namespaces.${nsName}.hostLink.hostIf must be a valid Linux interface name (1-15 chars, [A-Za-z0-9_.-]) when host link is enabled.";
      }
      {
        assertion = !withHostLink || vpnLib.isValidInterfaceName ns.hostLink.nsIf;
        message = "services.vpnConfinement.namespaces.${nsName}.hostLink.nsIf must be a valid Linux interface name (1-15 chars, [A-Za-z0-9_.-]) when host link is enabled.";
      }
      {
        assertion = !withHostLink || vpnLib.isLiteralIpv4 ns.hostLink.hostAddressIPv4;
        message = "services.vpnConfinement.namespaces.${nsName}.hostLink.hostAddressIPv4 must be a literal IPv4 address when host link is enabled.";
      }
      {
        assertion = !withHostLink || vpnLib.isLiteralIpv4 ns.hostLink.nsAddressIPv4;
        message = "services.vpnConfinement.namespaces.${nsName}.hostLink.nsAddressIPv4 must be a literal IPv4 address when host link is enabled.";
      }
    ]
  ) enabledNamespaceNames;

  serviceAssertions = builtins.concatMap (
    serviceName:
    let
      nsName = nsFor serviceName;
    in
    [
      {
        assertion = builtins.hasAttr nsName cfg.namespaces;
        message = "systemd.services.${serviceName}.vpn.namespace references unknown namespace ${nsName}.";
      }
      {
        assertion = cfg.namespaces.${nsName}.enable;
        message = "systemd.services.${serviceName}.vpn.namespace references disabled namespace ${nsName}.";
      }
    ]
  ) vpnEnabledServiceNames;

  socketAssertions = builtins.concatMap (
    socketName:
    let
      nsName = nsForSocket socketName;
      targetUnit = socketTargetUnit socketName;
      targetService = serviceNameFromUnit targetUnit;
      targetExists = builtins.hasAttr targetService config.systemd.services;
      targetVpnEnabled = targetExists && (config.systemd.services.${targetService}.vpn.enable or false);
      socketUnit = if hasSuffix ".socket" socketName then socketName else "${socketName}.socket";
    in
    [
      {
        assertion = builtins.hasAttr nsName cfg.namespaces;
        message = "systemd.sockets.${socketName}.vpn.namespace references unknown namespace ${nsName}.";
      }
      {
        assertion = cfg.namespaces.${nsName}.enable;
        message = "systemd.sockets.${socketName}.vpn.namespace references disabled namespace ${nsName}.";
      }
      {
        assertion = hasSuffix ".service" targetUnit;
        message = "systemd.sockets.${socketName}.socketConfig.Service must reference a .service unit (got ${targetUnit}).";
      }
      {
        assertion = targetExists;
        message = "systemd.sockets.${socketName} references missing ${targetUnit}. Define systemd.services.${targetService} for vpn-enabled sockets.";
      }
      {
        assertion = targetVpnEnabled;
        message = "systemd.sockets.${socketName}.vpn.enable requires systemd.services.${targetService}.vpn.enable = true so socket and service share the same namespace policy.";
      }
      {
        assertion = !targetVpnEnabled || nsFor targetService == nsName;
        message = "systemd.sockets.${socketName}.vpn.namespace (${nsName}) must match systemd.services.${targetService}.vpn.namespace for ${socketUnit}.";
      }
    ]
  ) vpnEnabledSocketNames;

  rootWarnings = builtins.concatMap (
    serviceName:
    let
      serviceConfig = config.systemd.services.${serviceName}.serviceConfig or { };
      user = serviceConfig.User or null;
      dynamicUser = serviceConfig.DynamicUser or false;
      rootLike = user == null || user == "" || user == "root" || user == "0";
    in
    lib.optionals (rootLike && !dynamicUser) [
      "systemd.services.${serviceName} has vpn.enable = true but still runs as root. Prefer serviceConfig.DynamicUser = true or set a dedicated non-root serviceConfig.User."
    ]
  ) vpnEnabledServiceNames;
in
{
  imports = [
    ./service-extension.nix
    ./socket-extension.nix
  ];

  options.services.vpnConfinement = {
    enable = mkEnableOption "VPN confinement for selected systemd services";

    defaultNamespace = mkOption {
      type = types.str;
      default = "vpnapps";
    };

    namespaces = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              enable = mkEnableOption "VPN confinement namespace";

              wireguard = {
                interface = mkOption {
                  type = types.str;
                  default = "wg0";
                };

                socketNamespace = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                };

                dynamicEndpointRefreshSeconds = mkOption {
                  type = types.int;
                  default = 0;
                };
              };

              dns = {
                mode = mkOption {
                  type = types.enum [
                    "strict"
                    "relaxed"
                  ];
                  default = "strict";
                };

                servers = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                };

                search = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                };

                blockNscd = mkOption {
                  type = types.bool;
                  default = false;
                };

                blockSystemBus = mkOption {
                  type = types.bool;
                  default = false;
                };
              };

              ipv6.mode = mkOption {
                type = types.enum [
                  "disable"
                  "tunnel"
                ];
                default = "disable";
              };

              ingress = {
                fromHost.tcp = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                };

                fromTunnel.tcp = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                };

                fromTunnel.udp = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                };
              };

              egress = {
                mode = mkOption {
                  type = types.enum [
                    "allowAllTunnel"
                    "allowList"
                  ];
                  default = "allowAllTunnel";
                };

                allowedTcpPorts = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                };

                allowedUdpPorts = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                };

                allowedCidrs = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                };
              };

              hostLink = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                };

                hostIf = mkOption {
                  type = types.str;
                  default = "ve-${name}-host";
                };

                nsIf = mkOption {
                  type = types.str;
                  default = "ve-${name}-ns";
                };

                hostAddressIPv4 = mkOption {
                  type = types.str;
                  default = "10.231.0.1";
                };

                nsAddressIPv4 = mkOption {
                  type = types.str;
                  default = "10.231.0.2";
                };
              };
            };
          }
        )
      );
      default = {
        vpnapps.enable = true;
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = vpnLib.isValidNamespaceName cfg.defaultNamespace;
        message = "services.vpnConfinement.defaultNamespace must match [A-Za-z0-9_.-]+ and be at most 64 characters.";
      }
      {
        assertion = builtins.hasAttr cfg.defaultNamespace cfg.namespaces;
        message = "services.vpnConfinement.defaultNamespace must exist in services.vpnConfinement.namespaces.";
      }
      {
        assertion = all vpnLib.isValidNamespaceName namespaceNames;
        message = "services.vpnConfinement.namespaces keys must match [A-Za-z0-9_.-]+ and be at most 64 characters.";
      }
      {
        assertion = unique wgNames == wgNames;
        message = "Enabled namespaces must not reuse the same wireguard.interface.";
      }
      {
        assertion = unique hostIfs == hostIfs;
        message = "Enabled host links must not reuse hostLink.hostIf.";
      }
      {
        assertion = unique nsIfs == nsIfs;
        message = "Enabled host links must not reuse hostLink.nsIf.";
      }
      {
        assertion = unique hostAddrs == hostAddrs;
        message = "Enabled host links must not reuse hostLink.hostAddressIPv4.";
      }
      {
        assertion = unique nsAddrs == nsAddrs;
        message = "Enabled host links must not reuse hostLink.nsAddressIPv4.";
      }
    ]
    ++ namespaceAssertions
    ++ serviceAssertions
    ++ socketAssertions;

    warnings = rootWarnings;

    systemd.services = mkMerge [
      namespaceUnits
      wgDependencyUnits
    ];
    networking.wireguard.interfaces = wireguardAssignments;
  };
}
