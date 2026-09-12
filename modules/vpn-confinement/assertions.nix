{ lib, config, ... }:
let
  inherit (lib)
    all
    attrByPath
    hasSuffix
    mkIf
    mkMerge
    splitString
    unique
    ;
  inherit (import ./context.nix { inherit config lib; })
    cfg
    vpnLib
    enabledNamespaces
    enabledNamespaceNames
    namespaceNames
    vpnEnabledServiceNames
    vpnEnabledSocketNames
    nsFor
    nsForSocket
    socketTargetUnit
    serviceNameFromUnit
    namespacePath
    hostLinkEnabled
    effectiveHostLink
    endpointPinningMarks
    activeHostLinks
    managedInterfaceNames
    hostLinkSubnets
    ;
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

  namespaceAssertions = builtins.concatMap (
    nsName:
    let
      ns = enabledNamespaces.${nsName};
      wg = ns.wireguard.interface;
      dnsSplit = vpnLib.splitDns ns.dns.servers;
      cidrSplit = vpnLib.splitCidrs ns.egress.allowedCidrs;
      withHostLink = hostLinkEnabled nsName ns;
      highAssurance = ns.securityProfile == "highAssurance";
      wgConfig = config.networking.wireguard.interfaces.${wg} or { };
      keyPaths = lib.filter (path: path != null) (
        [ (wgConfig.privateKeyFile or null) ]
        ++ map (peer: peer.presharedKeyFile or null) (wgConfig.peers or [ ])
      );
      endpointPinningMark =
        if ns.wireguard.endpointPinning.fwMark != null then
          ns.wireguard.endpointPinning.fwMark
        else
          vpnLib.deriveWireguardFwMark wg;
    in
    [
      {
        assertion = ns.dns.servers != [ ];
        message = "services.vpnConfinement.namespaces.${nsName}.dns.servers must be non-empty.";
      }
      {
        assertion = !highAssurance || !ns.wireguard.allowInsecureKeyMaterial;
        message = "services.vpnConfinement.namespaces.${nsName}.securityProfile = highAssurance rejects wireguard.allowInsecureKeyMaterial.";
      }
      {
        assertion =
          highAssurance
          || ns.wireguard.allowInsecureKeyMaterial
          || (
            (wgConfig.privateKey or null) == null
            && builtins.all (peer: (peer.presharedKey or null) == null) (wgConfig.peers or [ ])
          );
        message = "services.vpnConfinement.namespaces.${nsName} rejects inline WireGuard secrets. Use file-based secrets or explicitly set wireguard.allowInsecureKeyMaterial = true in balanced mode.";
      }
      {
        assertion =
          ns.wireguard.allowInsecureKeyMaterial
          || builtins.all (
            path: !(lib.hasPrefix builtins.storeDir (toString path)) && !(builtins.hasContext (toString path))
          ) keyPaths;
        message = "services.vpnConfinement.namespaces.${nsName} rejects Nix-store WireGuard key files. Use string paths to secrets outside the store.";
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
        message = "services.vpnConfinement.namespaces.${nsName}.wireguard.interface must begin and end with an alphanumeric character, contain only [A-Za-z0-9_.-], and be at most 15 characters.";
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
        assertion =
          !(builtins.hasAttr wg config.networking.wireguard.interfaces)
          || !highAssurance
          || (config.networking.wireguard.interfaces.${wg}.privateKey or null) == null;
        message = "services.vpnConfinement.namespaces.${nsName}.securityProfile = \"highAssurance\" rejects networking.wireguard.interfaces.${wg}.privateKey because inline secrets land in the Nix store. Use privateKeyFile or generatePrivateKeyFile instead.";
      }
      {
        assertion =
          !(builtins.hasAttr wg config.networking.wireguard.interfaces)
          || !highAssurance
          || builtins.all (peer: (peer.presharedKey or null) == null) (
            config.networking.wireguard.interfaces.${wg}.peers or [ ]
          );
        message = "services.vpnConfinement.namespaces.${nsName}.securityProfile = \"highAssurance\" rejects inline networking.wireguard.interfaces.${wg}.peers.*.presharedKey values because inline secrets land in the Nix store. Use presharedKeyFile instead.";
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
        message = "services.vpnConfinement.namespaces.${nsName}.hostLink.hostIf must begin and end with an alphanumeric character, contain only [A-Za-z0-9_.-], and be at most 15 characters when host link is enabled.";
      }
      {
        assertion = !withHostLink || vpnLib.isValidInterfaceName ns.hostLink.nsIf;
        message = "services.vpnConfinement.namespaces.${nsName}.hostLink.nsIf must begin and end with an alphanumeric character, contain only [A-Za-z0-9_.-], and be at most 15 characters when host link is enabled.";
      }
      {
        assertion = !withHostLink || vpnLib.isLiteralIpv4Slash30 effectiveHostLink.${nsName}.subnetIPv4;
        message = "services.vpnConfinement.namespaces.${nsName}.hostLink.subnetIPv4 must be a valid IPv4 /30 network base when host link is enabled.";
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
        assertion =
          !ns.wireguard.endpointPinning.enable
          || !(builtins.hasAttr wg config.networking.wireguard.interfaces)
          || (config.networking.wireguard.interfaces.${wg}.fwMark or null) == toString endpointPinningMark;
        message = "services.vpnConfinement.namespaces.${nsName}.wireguard.endpointPinning.enable requires networking.wireguard.interfaces.${wg}.fwMark to match its configured or derived endpoint-pinning mark; leave the WireGuard fwMark unset unless it matches.";
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
      nsDisplay = if nsName == null then "<unset>" else nsName;
      service = config.systemd.services.${serviceName};
      ns = if nsName == null then null else attrByPath [ nsName ] null cfg.namespaces;
      highAssurance = ns != null && ns.securityProfile == "highAssurance";
      enforced = ns != null && ns.servicePolicy == "enforced";
      validateServices = highAssurance || enforced;
      validateNonRoot = validateServices && (enforced || !service.vpn.allowRootInHighAssurance);
      exceptionFlags = builtins.filter (flag: service.vpn.${flag}) [
        "allowRootInHighAssurance"
        "allowUnsafeCapabilities"
        "allowPrivilegedCommands"
        "allowHostSockets"
      ];
      serviceConfig = service.serviceConfig or { };
      user = serviceConfig.User or null;
      dynamicUser = serviceConfig.DynamicUser or false;
      rootLike = user == null || user == "" || user == "root" || user == "0";
      knownRootUser =
        name:
        builtins.any (account: account.name == name && (account.uid or null) == 0) (
          lib.attrValues config.users.users
        );
      validatedRootLike =
        rootLike
        || user == 0
        || (user != null && !(builtins.isString user || builtins.isInt user))
        || (builtins.isString user && (builtins.match "0+" user != null || knownRootUser user));
      # DynamicUser reuses a static account with the unit-derived name when
      # User is absent. Check known literal account names without predicting
      # systemd's hash fallback or arbitrary runtime NSS results.
      implicitUser = builtins.head (lib.splitString "@" (lib.removeSuffix ".service" service.name));
      implicitRoot =
        builtins.match "[A-Za-z_][A-Za-z0-9_-]*" implicitUser != null
        && (implicitUser == "root" || knownRootUser implicitUser);
      dynamicNonRoot = dynamicUser == true && (user == null || user == "") && !implicitRoot;
      boundingSet = serviceConfig.CapabilityBoundingSet or null;
      boundingSetSpecified =
        builtins.isString boundingSet
        || (
          builtins.isList boundingSet && boundingSet != [ ] && builtins.all builtins.isString boundingSet
        );
      emptyReset = value: builtins.isString value && lib.strings.trim value == "";
      clearsBoundingSet =
        emptyReset boundingSet
        || (builtins.isList boundingSet && boundingSet != [ ] && builtins.all emptyReset boundingSet);
      expectedNamespacePath = if nsName == null then "/run/netns/<namespace>" else namespacePath nsName;
    in
    [
      {
        assertion =
          !validateNonRoot
          || !(
            builtins.isString user && (lib.hasInfix "%" user || builtins.match "[^[:space:]]*" user == null)
          );
        message = "systemd.services.${serviceName} requires a literal User without systemd specifiers or whitespace for non-root validation. Set a dedicated non-root User or use DynamicUser without User.";
      }
      {
        assertion = !enforced || exceptionFlags == [ ];
        message = "systemd.services.${serviceName} has servicePolicy = enforced and rejects service exception flags: ${lib.concatStringsSep ", " exceptionFlags}. Remove these flags and satisfy the service checks.";
      }
      {
        assertion =
          !enforced
          || (clearsBoundingSet && vpnLib.systemdWords (serviceConfig.AmbientCapabilities or [ ]) == [ ]);
        message =
          "systemd.services.${serviceName} has servicePolicy = enforced and requires empty CapabilityBoundingSet and AmbientCapabilities. Set CapabilityBoundingSet = "
          + builtins.toJSON ""
          + "; an empty list omits the clearing directive. Move privileged setup into a separate trusted unit.";
      }
      {
        assertion =
          !highAssurance || enforced || service.vpn.allowUnsafeCapabilities || boundingSetSpecified;
        message = "systemd.services.${serviceName} requires an explicit CapabilityBoundingSet assignment for highAssurance. An empty list omits the directive and leaves systemd's default bounding set. Set an empty string to clear capabilities or explicitly acknowledge the risk with vpn.allowUnsafeCapabilities in profile mode.";
      }
      {
        assertion =
          !validateServices
          || (!enforced && service.vpn.allowPrivilegedCommands)
          || (serviceConfig.PermissionsStartOnly or false) == false;
        message = "systemd.services.${serviceName} requires PermissionsStartOnly to be unset or false. This legacy setting bypasses service sandboxing for lifecycle commands; move privileged setup into a separate trusted unit. ${
          if enforced then
            "servicePolicy = enforced does not permit command exceptions."
          else
            "highAssurance requires vpn.allowPrivilegedCommands = true to explicitly acknowledge this risk."
        }";
      }
      {
        assertion = !enforced || (serviceConfig.NoNewPrivileges or false) == true;
        message = "systemd.services.${serviceName} has servicePolicy = enforced and requires NoNewPrivileges = true.";
      }
      {
        assertion = nsName != null;
        message = "systemd.services.${serviceName}.vpn.enable requires vpn.namespace to be set, or services.vpnConfinement.defaultNamespace to be configured explicitly.";
      }
      {
        assertion = nsName == null || builtins.hasAttr nsName cfg.namespaces;
        message = "systemd.services.${serviceName}.vpn.namespace references unknown namespace ${nsDisplay}.";
      }
      {
        assertion =
          nsName == null || (builtins.hasAttr nsName cfg.namespaces && cfg.namespaces.${nsName}.enable);
        message = "systemd.services.${serviceName}.vpn.namespace references disabled namespace ${nsDisplay}.";
      }
      {
        assertion =
          nsName == null || (service.serviceConfig.NetworkNamespacePath or null) == namespacePath nsName;
        message = "vpn-confinement owns systemd.services.${serviceName}.serviceConfig.NetworkNamespacePath; leave it unset or set it to ${expectedNamespacePath}.";
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
        assertion =
          !validateServices
          || (!enforced && service.vpn.allowUnsafeCapabilities)
          || !(vpnLib.unsafeCapabilities serviceConfig);
        message =
          "systemd.services.${serviceName} grants capabilities that can undermine confinement. "
          + (
            if enforced then
              "Remove capabilities; servicePolicy = enforced does not permit capability exceptions."
            else
              "Use canonical capability names, remove CAP_NET_ADMIN/CAP_SYS_ADMIN/CAP_NET_RAW or explicitly set vpn.allowUnsafeCapabilities = true."
          );
      }
      {
        assertion =
          !validateServices
          || (!enforced && service.vpn.allowPrivilegedCommands)
          || vpnLib.privilegedCommandPhases serviceConfig == [ ];
        message = "systemd.services.${serviceName} has ${lib.concatStringsSep "; " (vpnLib.commandWarnings serviceConfig)}. Use a plain executable without privileged prefixes, or a separate trusted setup unit. ${
          if enforced then
            "servicePolicy = enforced does not permit command exceptions."
          else
            "highAssurance rejects these commands unless vpn.allowPrivilegedCommands = true explicitly acknowledges the risk."
        }";
      }
      {
        assertion =
          !validateServices
          || (!enforced && service.vpn.allowHostSockets)
          || vpnLib.unconfinedSockets cfg config.systemd.services config.systemd.sockets serviceName == [ ];
        message = "systemd.services.${serviceName} has unverified host activation or inherited sockets: ${
          lib.concatStringsSep ", " (
            vpnLib.unconfinedSockets cfg config.systemd.services config.systemd.sockets serviceName
          )
        }. ${
          if enforced then
            "Confine the sockets to the same namespace. servicePolicy = enforced does not permit host socket exceptions."
          else
            "Confine the sockets to the same namespace or explicitly set vpn.allowHostSockets = true."
        }";
      }
      {
        assertion = !validateNonRoot || !validatedRootLike || dynamicNonRoot;
        message =
          if enforced then
            "systemd.services.${serviceName} is in namespace ${nsDisplay} and must run non-root. Set serviceConfig.DynamicUser = true or a dedicated non-root serviceConfig.User. servicePolicy = enforced does not permit root exceptions."
          else
            "systemd.services.${serviceName} is in high-assurance namespace ${nsDisplay} and must run non-root. Set serviceConfig.DynamicUser = true or non-root serviceConfig.User, or explicitly opt out with vpn.allowRootInHighAssurance = true.";
      }
    ]
  ) vpnEnabledServiceNames;

  socketAssertions = builtins.concatMap (
    socketName:
    let
      nsName = nsForSocket socketName;
      nsDisplay = if nsName == null then "<unset>" else nsName;
      socket = config.systemd.sockets.${socketName};
      targetUnit = socketTargetUnit socketName;
      targetService = serviceNameFromUnit targetUnit;
      targetExists = builtins.hasAttr targetService config.systemd.services;
      targetVpnEnabled = targetExists && (config.systemd.services.${targetService}.vpn.enable or false);
      socketUnit = if hasSuffix ".socket" socketName then socketName else "${socketName}.socket";
      expectedNamespacePath = if nsName == null then "/run/netns/<namespace>" else namespacePath nsName;
    in
    [
      {
        assertion = nsName != null;
        message = "systemd.sockets.${socketName}.vpn.enable requires vpn.namespace to be set, or services.vpnConfinement.defaultNamespace to be configured explicitly.";
      }
      {
        assertion = nsName == null || builtins.hasAttr nsName cfg.namespaces;
        message = "systemd.sockets.${socketName}.vpn.namespace references unknown namespace ${nsDisplay}.";
      }
      {
        assertion =
          nsName == null || (builtins.hasAttr nsName cfg.namespaces && cfg.namespaces.${nsName}.enable);
        message = "systemd.sockets.${socketName}.vpn.namespace references disabled namespace ${nsDisplay}.";
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
        message = "systemd.sockets.${socketName}.vpn.namespace (${nsDisplay}) must match systemd.services.${targetService}.vpn.namespace for ${socketUnit}.";
      }
      {
        assertion =
          nsName == null || (socket.socketConfig.NetworkNamespacePath or null) == namespacePath nsName;
        message = "vpn-confinement owns systemd.sockets.${socketName}.socketConfig.NetworkNamespacePath; leave it unset or set it to ${expectedNamespacePath}.";
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
    lib.optionals (rootLike && (!(dynamicUser && (user == null || user == "")))) [
      "systemd.services.${serviceName} has vpn.enable = true but still runs as root. Prefer serviceConfig.DynamicUser = true or set a dedicated non-root serviceConfig.User."
    ]
  ) vpnEnabledServiceNames;

  hardeningWarnings = builtins.concatMap (
    name:
    let
      sc = config.systemd.services.${name}.serviceConfig;
    in
    lib.optionals (vpnLib.unsafeCapabilities sc) [
      "systemd.services.${name} grants unsafe or noncanonical capabilities, including CAP_NET_ADMIN/CAP_SYS_ADMIN/CAP_NET_RAW; a compromised process may bypass confinement."
    ]
    ++ map (warning: "systemd.services.${name} has ${warning}.") (vpnLib.commandWarnings sc)
    ++
      lib.optionals
        (vpnLib.unconfinedSockets cfg config.systemd.services config.systemd.sockets name != [ ])
        [
          "systemd.services.${name} inherits host or unverified sockets: ${
            lib.concatStringsSep ", " (
              vpnLib.unconfinedSockets cfg config.systemd.services config.systemd.sockets name
            )
          }. Those descriptors may communicate outside the VPN."
        ]
    ++
      lib.optionals
        ((sc.RestrictNetworkInterfaces or [ ]) != [ ] && (sc.RestrictNetworkInterfaces or "") != "")
        [
          "systemd.services.${name}.RestrictNetworkInterfaces resolves interface names in the service manager's namespace and may block VPN traffic. Use namespace nftables for network policy."
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
        (wgExists && ns.securityProfile != "highAssurance" && (wgConfig.privateKey or null) != null)
        [
          "services.vpnConfinement.namespaces.${nsName} uses networking.wireguard.interfaces.${wg}.privateKey. Inline WireGuard secrets land in the Nix store; prefer privateKeyFile or generatePrivateKeyFile."
        ]
    ++
      lib.optionals
        (
          wgExists
          && ns.securityProfile != "highAssurance"
          && builtins.any (peer: (peer.presharedKey or null) != null) (wgConfig.peers or [ ])
        )
        [
          "services.vpnConfinement.namespaces.${nsName} uses an inline networking.wireguard.interfaces.${wg}.peers.*.presharedKey. Inline WireGuard secrets land in the Nix store; prefer presharedKeyFile."
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

in
{
  config = mkMerge [
    {
      assertions = [
        {
          assertion = cfg.enable || (vpnEnabledServiceNames == [ ] && vpnEnabledSocketNames == [ ]);
          message = "vpn-enabled services or sockets require services.vpnConfinement.enable = true; refusing to run without confinement.";
        }
      ];
    }
    (mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.defaultNamespace == null || vpnLib.isValidNamespaceName cfg.defaultNamespace;
          message = "services.vpnConfinement.defaultNamespace must begin and end with an alphanumeric character, contain only [A-Za-z0-9_.-], and be at most 64 characters.";
        }
        {
          assertion = cfg.defaultNamespace == null || builtins.hasAttr cfg.defaultNamespace cfg.namespaces;
          message = "services.vpnConfinement.defaultNamespace must exist in services.vpnConfinement.namespaces.";
        }
        {
          assertion = all vpnLib.isValidNamespaceName namespaceNames;
          message = "services.vpnConfinement.namespaces keys must begin and end with an alphanumeric character, contain only [A-Za-z0-9_.-], and be at most 64 characters.";
        }
        {
          assertion = unique managedInterfaceNames == managedInterfaceNames;
          message = "Enabled namespaces must use globally unique WireGuard and host-link interface names.";
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

      warnings = rootWarnings ++ hardeningWarnings ++ namespaceWarnings;

    })
  ];
}
