{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    all
    attrByPath
    attrNames
    concatMapStringsSep
    filter
    filterAttrs
    hasSuffix
    mapAttrs'
    mapAttrsToList
    mkDefault
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

  hostLinkEnabled = _nsName: ns: ns.hostLink.enable || ns.publishToHost.tcp != [ ];

  effectiveFromHostIngressTcp = builtins.mapAttrs (
    _nsName: ns: unique (ns.ingress.fromHost.tcp ++ ns.publishToHost.tcp)
  ) enabledNamespaces;

  effectiveHostLink = builtins.mapAttrs (
    nsName: ns:
    let
      subnet =
        if ns.hostLink.subnetIPv4 != null then
          ns.hostLink.subnetIPv4
        else
          vpnLib.hostLinkSubnetFromNamespace nsName;
      pair = vpnLib.deriveHostLinkPair subnet;
    in
    {
      subnetIPv4 = subnet;
      hostAddressIPv4 = if pair == null then null else pair.hostAddressIPv4;
      nsAddressIPv4 = if pair == null then null else pair.nsAddressIPv4;
    }
  ) enabledNamespaces;

  blockedDnsPorts = [
    53
    853
    5353
    5355
  ];

  mkNftSet =
    name: typeName: withInterval: elements:
    if elements == [ ] then
      ""
    else
      ''
        set ${name} {
          type ${typeName};
          ${optionalString withInterval "flags interval;"}
          elements = ${vpnLib.renderNftSetElements elements};
        }
      '';

  mkDnsSetDefinitions =
    ns:
    let
      dns = vpnLib.splitDns ns.dns.servers;
    in
    ''
      ${mkNftSet "dns_servers_v4" "ipv4_addr" false dns.ipv4}
      ${optionalString (ns.ipv6.mode == "tunnel") (mkNftSet "dns_servers_v6" "ipv6_addr" false dns.ipv6)}
      ${mkNftSet "dns_blocked_ports" "inet_service" false blockedDnsPorts}
    '';

  mkDnsBlockedPortRules = ns: ''
    oifname "${ns.wireguard.interface}" udp dport @dns_blocked_ports drop
    oifname "${ns.wireguard.interface}" tcp dport @dns_blocked_ports drop
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
        oifname "${ns.wireguard.interface}" ip daddr @dns_servers_v4 udp dport 53 accept
        oifname "${ns.wireguard.interface}" ip daddr @dns_servers_v4 tcp dport 53 accept
      ''}
      ${optionalString hasV6 ''
        oifname "${ns.wireguard.interface}" ip6 daddr @dns_servers_v6 udp dport 53 accept
        oifname "${ns.wireguard.interface}" ip6 daddr @dns_servers_v6 tcp dport 53 accept
      ''}
      oifname "${ns.wireguard.interface}" udp dport 53 drop
      oifname "${ns.wireguard.interface}" tcp dport 53 drop
    '';

  mkEgressSetDefinitions =
    ns:
    let
      allowedTcp = unique ns.egress.allowedTcpPorts;
      allowedUdp = unique ns.egress.allowedUdpPorts;
      allowedCidrs = unique ns.egress.allowedCidrs;
      cidrs = vpnLib.splitCidrs allowedCidrs;
    in
    ''
      ${mkNftSet "allowed_tcp_ports" "inet_service" false allowedTcp}
      ${mkNftSet "allowed_udp_ports" "inet_service" false allowedUdp}
      ${mkNftSet "allowed_ipv4_cidrs" "ipv4_addr" true cidrs.ipv4}
      ${optionalString (ns.ipv6.mode == "tunnel") (
        mkNftSet "allowed_ipv6_cidrs" "ipv6_addr" true cidrs.ipv6
      )}
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
        if ports == [ ] then
          ""
        else if allowedCidrs == [ ] then
          "oifname \"${ns.wireguard.interface}\" ${proto} dport @allowed_${proto}_ports accept"
        else
          concatMapStringsSep "\n" (rule: rule) (
            lib.optionals (cidrs.ipv4 != [ ]) [
              "oifname \"${ns.wireguard.interface}\" ip daddr @allowed_ipv4_cidrs ${proto} dport @allowed_${proto}_ports accept"
            ]
            ++ lib.optionals (cidrs.ipv6 != [ ]) [
              "oifname \"${ns.wireguard.interface}\" ip6 daddr @allowed_ipv6_cidrs ${proto} dport @allowed_${proto}_ports accept"
            ]
          );

      cidrOnlyRules =
        if allowedCidrs == [ ] || allowedTcp != [ ] || allowedUdp != [ ] then
          ""
        else
          concatMapStringsSep "\n" (rule: rule) (
            lib.optionals (cidrs.ipv4 != [ ]) [
              "oifname \"${ns.wireguard.interface}\" ip daddr @allowed_ipv4_cidrs accept"
            ]
            ++ lib.optionals (cidrs.ipv6 != [ ]) [
              "oifname \"${ns.wireguard.interface}\" ip6 daddr @allowed_ipv6_cidrs accept"
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
      hostIngressTcp = effectiveFromHostIngressTcp.${nsName};
      inboundTcp = unique ns.ingress.fromTunnel.tcp;
      inboundUdp = unique ns.ingress.fromTunnel.udp;
      withHostLink = hostLinkEnabled nsName ns;
      strictDns = ns.dns.mode == "strict";
    in
    ''
      table inet vpnc {
        ${optionalString strictDns (mkDnsSetDefinitions ns)}
        ${optionalString (ns.egress.mode == "allowList") (mkEgressSetDefinitions ns)}

        chain input {
          type filter hook input priority filter; policy drop;
          iifname "lo" accept
          ct state invalid drop
          ${optionalString (ns.ipv6.mode == "disable") "meta nfproto ipv6 drop"}
          ct state established,related accept
          ${optionalString (withHostLink && hostIngressTcp != [ ])
            "iifname \"${ns.hostLink.nsIf}\" ip saddr ${
              effectiveHostLink.${nsName}.hostAddressIPv4
            } tcp dport ${vpnLib.renderPortSet hostIngressTcp} accept"
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
          ct state invalid drop
          ${optionalString (ns.ipv6.mode == "disable") "meta nfproto ipv6 drop"}
          ct state established,related accept
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

        namespace_exists() {
          [ -e ${namespacePath nsName} ]
        }

        cleanup_failed_start() {
          if namespace_exists; then
            ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft delete table inet vpnc >/dev/null 2>&1 || true
          fi

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

        ${pkgs.nftables}/bin/nft -c -f ${nftRules}
        ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft delete table inet vpnc >/dev/null 2>&1 || true
        ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft -f ${nftRules}

        success=1
      '';
      postStop = ''
        set -eu
        if [ -e ${namespacePath nsName} ]; then
          ${pkgs.iproute2}/bin/ip netns exec ${nsName} ${pkgs.nftables}/bin/nft delete table inet vpnc >/dev/null 2>&1 || true
        fi

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

  endpointPinningNamespaces = filter (
    nsName:
    let
      ns = enabledNamespaces.${nsName};
    in
    ns.wireguard.endpointPinning.enable
  ) enabledNamespaceNames;

  endpointPinningMarks = map (
    nsName:
    let
      ns = enabledNamespaces.${nsName};
      assigned =
        if ns.wireguard.endpointPinning.fwMark != null then
          ns.wireguard.endpointPinning.fwMark
        else
          vpnLib.deriveWireguardFwMark ns.wireguard.interface;
    in
    assigned
  ) endpointPinningNamespaces;

  endpointPinningUnits = mapAttrs' (
    nsName: ns:
    let
      wg = ns.wireguard.interface;
      wgConfig = attrByPath [ wg ] null config.networking.wireguard.interfaces;
      mark =
        if ns.wireguard.endpointPinning.fwMark != null then
          ns.wireguard.endpointPinning.fwMark
        else
          vpnLib.deriveWireguardFwMark wg;
      endpointSpecs = builtins.filter (spec: spec != null) (
        map (
          peer:
          let
            endpoint = peer.endpoint or null;
          in
          if endpoint == null then null else vpnLib.parseLiteralEndpoint endpoint
        ) (if wgConfig == null then [ ] else (wgConfig.peers or [ ]))
      );
      policyRules = concatMapStringsSep "\n" (
        spec:
        "meta mark ${toString mark} udp ${spec.family} daddr ${spec.address} udp dport ${toString spec.port} accept"
      ) endpointSpecs;
      socketBirthplace =
        if ns.wireguard.socketNamespace == null || ns.wireguard.socketNamespace == "init" then
          "init"
        else
          ns.wireguard.socketNamespace;
      nftExec =
        if socketBirthplace == "init" then
          "${pkgs.nftables}/bin/nft"
        else
          "${pkgs.iproute2}/bin/ip netns exec ${socketBirthplace} ${pkgs.nftables}/bin/nft";
      tableName = "vpnc_endpoint_pin_${builtins.replaceStrings [ "." "-" ] [ "_" "_" ] nsName}";
      nftRules = pkgs.writeText "vpn-confinement-endpoint-pinning-${nsName}.nft" ''
        table inet ${tableName} {
          chain output {
            type filter hook output priority filter; policy accept;
            ${policyRules}
            meta mark ${toString mark} udp drop
          }
        }
      '';
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
      unitConfig.StopWhenUnneeded = true;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        ${nftExec} -c -f ${nftRules}
        ${nftExec} delete table inet ${tableName} >/dev/null 2>&1 || true
        ${nftExec} -f ${nftRules}
      '';
      postStop = ''
        set -eu
        ${nftExec} delete table inet ${tableName} >/dev/null 2>&1 || true
      '';
    }
  ) (filterAttrs (_: ns: ns.wireguard.endpointPinning.enable) enabledNamespaces);

  wgNames = map (nsName: enabledNamespaces.${nsName}.wireguard.interface) enabledNamespaceNames;

  wireguardPeerRefreshSeconds =
    wgConfig: peer:
    let
      peerRefresh = peer.dynamicEndpointRefreshSeconds or null;
    in
    if peerRefresh != null then peerRefresh else wgConfig.dynamicEndpointRefreshSeconds or 0;

  wireguardPeerHasHostnameEndpoint =
    peer:
    let
      endpoint = peer.endpoint or null;
    in
    endpoint != null && vpnLib.endpointIsHostname endpoint;

  wireguardHostnameEndpointsHaveRefresh =
    wgConfig:
    builtins.all (
      peer: !(wireguardPeerHasHostnameEndpoint peer) || wireguardPeerRefreshSeconds wgConfig peer > 0
    ) (wgConfig.peers or [ ]);

  wireguardHasHostnameEndpoints =
    wgConfig: builtins.any wireguardPeerHasHostnameEndpoint (wgConfig.peers or [ ]);

  joinsNamespaceUnset = value: value == null || value == "" || value == [ ];

  activeHostLinks = lib.filter (
    nsName:
    let
      ns = enabledNamespaces.${nsName};
    in
    hostLinkEnabled nsName ns
  ) enabledNamespaceNames;

  hostIfs = map (nsName: enabledNamespaces.${nsName}.hostLink.hostIf) activeHostLinks;
  nsIfs = map (nsName: enabledNamespaces.${nsName}.hostLink.nsIf) activeHostLinks;
  hostLinkSubnets = map (nsName: effectiveHostLink.${nsName}.subnetIPv4) activeHostLinks;

  namespaceAssertions = builtins.concatMap (
    nsName:
    let
      ns = enabledNamespaces.${nsName};
      wg = ns.wireguard.interface;
      dnsSplit = vpnLib.splitDns ns.dns.servers;
      cidrSplit = vpnLib.splitCidrs ns.egress.allowedCidrs;
      withHostLink = hostLinkEnabled nsName ns;
      highAssurance = ns.securityProfile == "highAssurance";
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
        assertion = all vpnLib.isSearchDomain ns.dns.search;
        message = "services.vpnConfinement.namespaces.${nsName}.dns.search must contain domain-style search suffixes only (valid labels, no empty labels, no whitespace).";
      }
      {
        assertion = vpnLib.isValidInterfaceName wg;
        message = "services.vpnConfinement.namespaces.${nsName}.wireguard.interface must be a valid Linux interface name (1-15 chars, [A-Za-z0-9_.-]).";
      }
      {
        assertion = builtins.all vpnLib.isLiteralCidr ns.egress.allowedCidrs;
        message = "services.vpnConfinement.namespaces.${nsName}.egress.allowedCidrs must contain literal IPv4/IPv6 CIDRs or IPs only.";
      }
      {
        assertion =
          ns.wireguard.socketNamespace == null
          || ns.wireguard.socketNamespace == "init"
          || vpnLib.isValidNamespaceName ns.wireguard.socketNamespace;
        message = "services.vpnConfinement.namespaces.${nsName}.wireguard.socketNamespace must be null, \"init\", or a valid namespace name.";
      }
      {
        assertion = ns.wireguard.socketNamespace != nsName;
        message = "services.vpnConfinement.namespaces.${nsName}.wireguard.socketNamespace must not match the confinement namespace name; use null or \"init\" unless you intentionally need a different birthplace namespace for the WireGuard UDP socket.";
      }
      {
        assertion = !highAssurance || ns.dns.mode == "strict";
        message = "services.vpnConfinement.namespaces.${nsName}.securityProfile = \"highAssurance\" requires dns.mode = \"strict\".";
      }
      {
        assertion = !highAssurance || !ns.dns.allowHostResolverIPC;
        message = "services.vpnConfinement.namespaces.${nsName}.securityProfile = \"highAssurance\" rejects dns.allowHostResolverIPC = true because host resolver IPC weakens DNS containment.";
      }
      {
        assertion = !highAssurance || ns.egress.mode == "allowList";
        message = "services.vpnConfinement.namespaces.${nsName}.securityProfile = \"highAssurance\" requires egress.mode = \"allowList\".";
      }
      {
        assertion = !highAssurance || ns.egress.allowedCidrs != [ ];
        message = "services.vpnConfinement.namespaces.${nsName}.securityProfile = \"highAssurance\" requires egress.allowedCidrs to be non-empty so egress remains destination-constrained.";
      }
      {
        assertion = !highAssurance || !ns.wireguard.allowHostnameEndpoints;
        message = "services.vpnConfinement.namespaces.${nsName}.securityProfile = \"highAssurance\" rejects wireguard.allowHostnameEndpoints = true; use literal peer endpoint IPs instead.";
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
          || (config.networking.wireguard.interfaces.${wg}.interfaceNamespace or null) == nsName;
        message = "services.vpnConfinement owns networking.wireguard.interfaces.${wg}.interfaceNamespace; set it to ${nsName} (or leave unset).";
      }
      {
        assertion =
          !(builtins.hasAttr wg config.networking.wireguard.interfaces)
          || (
            let
              expectedSocketNamespace = ns.wireguard.socketNamespace;
              actualSocketNamespace = config.networking.wireguard.interfaces.${wg}.socketNamespace or null;
            in
            expectedSocketNamespace == actualSocketNamespace
          );
        message = "services.vpnConfinement owns networking.wireguard.interfaces.${wg}.socketNamespace; set it to services.vpnConfinement.namespaces.${nsName}.wireguard.socketNamespace (or leave unset).";
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
        message = "services.vpnConfinement.namespaces.${nsName} requires networking.wireguard.interfaces.${wg}.peers.*.endpoint to use a valid WireGuard endpoint syntax (IPv4:port, [IPv6]:port, or hostname:port).";
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
            ns.wireguard.allowHostnameEndpoints || all vpnLib.isLiteralEndpoint endpoints
          );
        message = "services.vpnConfinement.namespaces.${nsName} defaults to literal WireGuard peer endpoint IPs. Set wireguard.allowHostnameEndpoints = true to opt into hostname:port endpoints.";
      }
      {
        assertion =
          !(builtins.hasAttr wg config.networking.wireguard.interfaces)
          || !ns.wireguard.allowHostnameEndpoints
          || (
            let
              wgConfig = config.networking.wireguard.interfaces.${wg};
            in
            wireguardHostnameEndpointsHaveRefresh wgConfig
          );
        message = "services.vpnConfinement.namespaces.${nsName} allows hostname WireGuard endpoints only when effective dynamic endpoint refresh is enabled on networking.wireguard.interfaces.${wg} (interface-level or per-peer dynamicEndpointRefreshSeconds > 0).";
      }
      {
        assertion =
          !(builtins.hasAttr wg config.networking.wireguard.interfaces)
          || !highAssurance
          || (config.networking.wireguard.interfaces.${wg}.allowedIPsAsRoutes or true);
        message = "services.vpnConfinement.namespaces.${nsName}.securityProfile = \"highAssurance\" requires networking.wireguard.interfaces.${wg}.allowedIPsAsRoutes = true so peer routes remain installed inside the namespace.";
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
        assertion = !withHostLink || vpnLib.isLiteralIpv4Slash30 effectiveHostLink.${nsName}.subnetIPv4;
        message = "services.vpnConfinement.namespaces.${nsName}.hostLink.subnetIPv4 must be a valid IPv4 /30 network base when host link is enabled.";
      }
      {
        assertion = ns.ingress.fromHost.tcp == [ ] || ns.hostLink.enable;
        message = "services.vpnConfinement.namespaces.${nsName}.ingress.fromHost.tcp requires hostLink.enable = true.";
      }
      {
        assertion =
          !(builtins.hasAttr wg config.networking.wireguard.interfaces)
          || !ns.wireguard.endpointPinning.enable
          || (
            let
              wgConfig = config.networking.wireguard.interfaces.${wg};
              endpoints = builtins.filter (endpoint: endpoint != null) (
                map (peer: peer.endpoint or null) (wgConfig.peers or [ ])
              );
            in
            endpoints != [ ] && all vpnLib.isLiteralEndpoint endpoints
          );
        message = "services.vpnConfinement.namespaces.${nsName}.wireguard.endpointPinning.enable requires networking.wireguard.interfaces.${wg}.peers.*.endpoint to be non-empty and literal IP endpoints only.";
      }
      {
        assertion =
          !ns.wireguard.endpointPinning.enable
          || (
            let
              mark =
                if ns.wireguard.endpointPinning.fwMark != null then
                  ns.wireguard.endpointPinning.fwMark
                else
                  vpnLib.deriveWireguardFwMark wg;
            in
            mark >= 1 && mark <= 4294967295
          );
        message = "services.vpnConfinement.namespaces.${nsName}.wireguard.endpointPinning.fwMark must resolve to an integer in [1, 4294967295].";
      }
      {
        assertion = !withHostLink || ns.hostLink.hostIf != ns.hostLink.nsIf;
        message = "services.vpnConfinement.namespaces.${nsName}.hostLink.hostIf and hostLink.nsIf must differ when host link is enabled.";
      }
      {
        assertion = !withHostLink || ns.hostLink.hostIf != wg;
        message = "services.vpnConfinement.namespaces.${nsName}.hostLink.hostIf must not match wireguard.interface when host link is enabled.";
      }
      {
        assertion = !withHostLink || ns.hostLink.nsIf != wg;
        message = "services.vpnConfinement.namespaces.${nsName}.hostLink.nsIf must not match wireguard.interface when host link is enabled.";
      }
    ]
  ) enabledNamespaceNames;

  serviceAssertions = builtins.concatMap (
    serviceName:
    let
      nsName = nsFor serviceName;
      service = config.systemd.services.${serviceName};
      ns = attrByPath [ nsName ] null cfg.namespaces;
      highAssurance = ns != null && ns.securityProfile == "highAssurance";
      serviceConfig = service.serviceConfig or { };
      user = serviceConfig.User or null;
      dynamicUser = serviceConfig.DynamicUser or false;
      rootLike = user == null || user == "" || user == "root" || user == "0";
    in
    [
      {
        assertion = builtins.hasAttr nsName cfg.namespaces;
        message = "systemd.services.${serviceName}.vpn.namespace references unknown namespace ${nsName}.";
      }
      {
        assertion = builtins.hasAttr nsName cfg.namespaces && cfg.namespaces.${nsName}.enable;
        message = "systemd.services.${serviceName}.vpn.namespace references disabled namespace ${nsName}.";
      }
      {
        assertion = (service.serviceConfig.NetworkNamespacePath or null) == namespacePath nsName;
        message = "vpn-confinement owns systemd.services.${serviceName}.serviceConfig.NetworkNamespacePath; leave it unset or set it to ${namespacePath nsName}.";
      }
      {
        assertion = !(service.serviceConfig.PrivateNetwork or false);
        message = "systemd.services.${serviceName}.serviceConfig.PrivateNetwork conflicts with vpn-confinement namespace management; leave it unset.";
      }
      {
        assertion = joinsNamespaceUnset (service.unitConfig.JoinsNamespaceOf or null);
        message = "systemd.services.${serviceName}.unitConfig.JoinsNamespaceOf conflicts with vpn-confinement namespace attachment; leave it unset.";
      }
      {
        assertion = !highAssurance || service.vpn.allowRootInHighAssurance || dynamicUser || !rootLike;
        message = "systemd.services.${serviceName} is in high-assurance namespace ${nsName} and must run non-root. Set serviceConfig.DynamicUser = true or non-root serviceConfig.User, or explicitly opt out with vpn.allowRootInHighAssurance = true.";
      }
    ]
  ) vpnEnabledServiceNames;

  socketAssertions = builtins.concatMap (
    socketName:
    let
      nsName = nsForSocket socketName;
      socket = config.systemd.sockets.${socketName};
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
        assertion = builtins.hasAttr nsName cfg.namespaces && cfg.namespaces.${nsName}.enable;
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
      {
        assertion = (socket.socketConfig.NetworkNamespacePath or null) == namespacePath nsName;
        message = "vpn-confinement owns systemd.sockets.${socketName}.socketConfig.NetworkNamespacePath; leave it unset or set it to ${namespacePath nsName}.";
      }
      {
        assertion = joinsNamespaceUnset (socket.unitConfig.JoinsNamespaceOf or null);
        message = "systemd.sockets.${socketName}.unitConfig.JoinsNamespaceOf conflicts with vpn-confinement namespace attachment; leave it unset.";
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

  namespaceWarnings = builtins.concatMap (
    nsName:
    let
      ns = enabledNamespaces.${nsName};
      wg = ns.wireguard.interface;
      wgExists = builtins.hasAttr wg config.networking.wireguard.interfaces;
      wgConfig = if wgExists then config.networking.wireguard.interfaces.${wg} else null;
    in
    lib.optionals
      (wgExists && ns.wireguard.allowHostnameEndpoints && wireguardHasHostnameEndpoints wgConfig)
      [
        "services.vpnConfinement.namespaces.${nsName} uses hostname WireGuard peer endpoints on ${wg}. This is allowed only with endpoint refresh enabled and is weaker than literal IP endpoints because hostname resolution is performed by the WireGuard management unit, outside the module's strict DNS guarantee."
      ]
    ++
      lib.optionals
        (wgExists && ns.securityProfile != "highAssurance" && !(wgConfig.allowedIPsAsRoutes or true))
        [
          "services.vpnConfinement.namespaces.${nsName} uses networking.wireguard.interfaces.${wg}.allowedIPsAsRoutes = false. vpn-confinement expects WireGuard allowedIPs routes to exist inside the namespace; disabling them is advanced and can break reachability or fail-closed assumptions."
        ]
    ++
      lib.optionals
        (
          ns.wireguard.endpointPinning.enable
          && ns.wireguard.socketNamespace != null
          && ns.wireguard.socketNamespace != "init"
          && !(builtins.hasAttr ns.wireguard.socketNamespace enabledNamespaces)
        )
        [
          "services.vpnConfinement.namespaces.${nsName}.wireguard.endpointPinning.enable targets socket namespace ${ns.wireguard.socketNamespace}, which is not managed by services.vpnConfinement. Ensure that namespace exists before wireguard-${wg}.service starts."
        ]
  ) enabledNamespaceNames;

  restrictBindWarnings = builtins.concatMap (
    serviceName:
    let
      service = config.systemd.services.${serviceName};
      nsName = nsFor serviceName;
      ns = attrByPath [ nsName ] null cfg.namespaces;
      effectiveIngress =
        if ns == null then
          [ ]
        else
          unique (
            ns.ingress.fromHost.tcp
            ++ ns.publishToHost.tcp
            ++ ns.ingress.fromTunnel.tcp
            ++ ns.ingress.fromTunnel.udp
          );
    in
    lib.optionals (service.vpn.restrictBind && effectiveIngress == [ ]) [
      "systemd.services.${serviceName}.vpn.restrictBind = true but namespace ${nsName} exposes no effective ingress ports (ingress.fromHost.tcp, publishToHost.tcp, ingress.fromTunnel.tcp, ingress.fromTunnel.udp). No SocketBindAllow rules will be applied."
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
      description = "Default namespace name used by vpn-enabled services and sockets when they do not set vpn.namespace.";
    };

    namespaces = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, config, ... }:
          {
            options = {
              enable = mkEnableOption "VPN confinement namespace";

              securityProfile = mkOption {
                type = types.enum [
                  "balanced"
                  "highAssurance"
                ];
                default = "balanced";
                description = ''
                  Opinionated namespace security preset. "highAssurance" turns
                  weaker compatibility paths into explicit evaluation failures.
                '';
              };

              wireguard = {
                interface = mkOption {
                  type = types.str;
                  default = "wg0";
                  description = "WireGuard interface name managed for this confinement namespace.";
                };

                socketNamespace = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = ''
                    Advanced WireGuard UDP socket birthplace namespace. Leave this
                    unset for the default path, or use "init" when the socket must
                    stay in the host namespace.
                  '';
                };

                allowHostnameEndpoints = mkOption {
                  type = types.bool;
                  default = false;
                  description = ''
                    Advanced compatibility opt-in for hostname:port WireGuard
                    peer endpoints. Literal IP endpoints remain the secure
                    default.
                  '';
                };

                endpointPinning = {
                  enable = mkOption {
                    type = types.bool;
                    default = false;
                    description = ''
                      Pin WireGuard outer UDP egress to configured literal peer
                      endpoints using host-side nftables policy in the socket
                      birthplace namespace path supported by this module.
                    '';
                  };

                  fwMark = mkOption {
                    type = types.nullOr types.ints.unsigned;
                    default = null;
                    description = ''
                      Optional fwMark used to identify WireGuard outer UDP traffic
                      for endpoint pinning. Null auto-derives a deterministic
                      non-zero mark from the interface name.
                    '';
                  };
                };
              };

              dns = {
                mode = mkOption {
                  type = types.enum [
                    "strict"
                    "compat"
                  ];
                  default = "strict";
                  description = ''
                    DNS containment mode. "strict" is the secure default; "compat"
                    weakens resolver containment for workloads that need it.
                  '';
                };

                servers = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Allowed DNS resolver IPs used to generate namespace-local resolv.conf in strict mode.";
                };

                search = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "DNS search suffixes written to generated resolver config; values must be valid domain-style suffixes.";
                };

                allowHostResolverIPC = mkOption {
                  type = types.bool;
                  default = false;
                  description = ''
                    Allow strict-mode services to reach host resolver helper IPC such
                    as nscd or system D-Bus. This weakens DNS containment.
                  '';
                };
              };

              ipv6.mode = mkOption {
                type = types.enum [
                  "disable"
                  "tunnel"
                ];
                default = "disable";
                description = "IPv6 policy inside this namespace: fail-closed disable, or tunnel when WireGuard IPv6 routes are configured.";
              };

              ingress = {
                fromHost.tcp = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                  description = "TCP ports accepted from hostLink host endpoint into the namespace. Requires hostLink.enable = true.";
                };

                fromTunnel.tcp = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                  description = "TCP listener ports accepted from the WireGuard interface into the namespace.";
                };

                fromTunnel.udp = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                  description = "UDP listener ports accepted from the WireGuard interface into the namespace.";
                };
              };

              publishToHost.tcp = mkOption {
                type = types.listOf types.port;
                default = [ ];
                description = ''
                  Simplified host publish abstraction for namespace services.
                  Ports are merged with ingress.fromHost.tcp. Non-empty values
                  automatically enable effective host-link wiring.
                '';
              };

              egress = {
                mode = mkOption {
                  type = types.enum [
                    "allowAllTunnel"
                    "allowList"
                  ];
                  default = "allowAllTunnel";
                  description = "Tunnel egress policy: allow all tunnel traffic or only explicit allowlist rules.";
                };

                allowedTcpPorts = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                  description = "Allowed TCP destination ports for allowList mode.";
                };

                allowedUdpPorts = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                  description = "Allowed UDP destination ports for allowList mode.";
                };

                allowedCidrs = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Allowed destination CIDRs (or literal IPs) for allowList mode. Required in highAssurance.";
                };
              };

              hostLink = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Enable host-to-namespace veth link for controlled host ingress use cases.";
                };

                hostIf = mkOption {
                  type = types.str;
                  default = "ve-${name}-host";
                  description = "Host-side veth interface name for hostLink mode.";
                };

                nsIf = mkOption {
                  type = types.str;
                  default = "ve-${name}-ns";
                  description = "Namespace-side veth interface name for hostLink mode.";
                };

                subnetIPv4 = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Optional hostLink /30 subnet base. Null auto-allocates a deterministic subnet from 169.254.0.0/16.";
                };
              };

              derived.hostLink = {
                subnetIPv4 = mkOption {
                  type = types.nullOr types.str;
                  readOnly = true;
                  description = "Computed effective hostLink subnet (/30) for this namespace.";
                };

                hostAddressIPv4 = mkOption {
                  type = types.nullOr types.str;
                  readOnly = true;
                  description = "Computed host-side IPv4 address for the effective hostLink subnet.";
                };

                nsAddressIPv4 = mkOption {
                  type = types.nullOr types.str;
                  readOnly = true;
                  description = "Computed namespace-side IPv4 address for the effective hostLink subnet.";
                };
              };
            };

            config =
              let
                withEffectiveHostLink = config.hostLink.enable || config.publishToHost.tcp != [ ];
                derivedSubnet =
                  if config.hostLink.subnetIPv4 != null then
                    config.hostLink.subnetIPv4
                  else
                    vpnLib.hostLinkSubnetFromNamespace name;
                derivedPair = vpnLib.deriveHostLinkPair derivedSubnet;
              in
              mkMerge [
                (mkIf (config.securityProfile == "highAssurance") {
                  dns.mode = mkDefault "strict";
                  dns.allowHostResolverIPC = mkDefault false;
                  egress.mode = mkDefault "allowList";
                  ipv6.mode = mkDefault "disable";
                  wireguard.allowHostnameEndpoints = mkDefault false;
                })
                {
                  derived.hostLink.subnetIPv4 = if withEffectiveHostLink then derivedSubnet else null;
                  derived.hostLink.hostAddressIPv4 =
                    if withEffectiveHostLink && derivedPair != null then derivedPair.hostAddressIPv4 else null;
                  derived.hostLink.nsAddressIPv4 =
                    if withEffectiveHostLink && derivedPair != null then derivedPair.nsAddressIPv4 else null;
                }
              ];
          }
        )
      );
      default = {
        vpnapps.enable = true;
      };
      description = "Namespace-scoped confinement policies keyed by namespace name.";
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
        assertion = unique hostLinkSubnets == hostLinkSubnets;
        message = "Enabled host links must not reuse the same effective hostLink subnet (/30).";
      }
      {
        assertion = unique endpointPinningMarks == endpointPinningMarks;
        message = "Enabled endpoint pinning namespaces must not reuse the same effective WireGuard fwMark.";
      }
      {
        assertion = builtins.length activeHostLinks <= 16384;
        message = "hostLink auto-allocation supports up to 16384 enabled host links from 169.254.0.0/16.";
      }
    ]
    ++ namespaceAssertions
    ++ serviceAssertions
    ++ socketAssertions;

    warnings = rootWarnings ++ namespaceWarnings ++ restrictBindWarnings;

    systemd.services = mkMerge [
      namespaceUnits
      endpointPinningUnits
      wgDependencyUnits
    ];
    networking.wireguard.interfaces = wireguardAssignments;
  };
}
