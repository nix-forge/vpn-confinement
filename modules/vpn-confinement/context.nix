{ lib, config }:
let
  inherit (lib)
    attrNames
    filterAttrs
    hasSuffix
    removeSuffix
    filter
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
    in
    vpnLib.socketTarget socketName socket;

  serviceNameFromUnit =
    unit: if hasSuffix ".service" unit then removeSuffix ".service" unit else unit;

  namespacePath = nsName: "/run/netns/${nsName}";

  effectivePolicies = builtins.mapAttrs vpnLib.effectiveNamespace enabledNamespaces;
  hostLinkEnabled = name: _: effectivePolicies.${name}.withHostLink;
  effectiveHostLink = builtins.mapAttrs (_: policy: policy.hostLink) effectivePolicies;

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
  managedInterfaceNames = wgNames ++ hostIfs ++ nsIfs;
  hostLinkSubnets = map (nsName: effectiveHostLink.${nsName}.subnetIPv4) activeHostLinks;

in
{
  inherit
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
    effectivePolicies
    hostLinkEnabled
    effectiveHostLink
    endpointPinningMarks
    activeHostLinks
    hostIfs
    nsIfs
    managedInterfaceNames
    hostLinkSubnets
    wgNames
    ;
}
