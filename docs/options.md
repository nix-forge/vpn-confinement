# Options

## Global

- `services.vpnConfinement.enable`
- `services.vpnConfinement.defaultNamespace`
- `services.vpnConfinement.namespaces.<name>.enable`
- `services.vpnConfinement.namespaces.<name>.securityProfile`
- `services.vpnConfinement.namespaces.<name>.wireguard.interface`
- `services.vpnConfinement.namespaces.<name>.wireguard.allowHostnameEndpoints`
- `services.vpnConfinement.namespaces.<name>.wireguard.socketNamespace`
- `services.vpnConfinement.namespaces.<name>.dns.mode`
- `services.vpnConfinement.namespaces.<name>.dns.servers`
- `services.vpnConfinement.namespaces.<name>.dns.search`
- `services.vpnConfinement.namespaces.<name>.dns.allowHostResolverIPC`
- `services.vpnConfinement.namespaces.<name>.ipv6.mode`
- `services.vpnConfinement.namespaces.<name>.hostLink.enable`
- `services.vpnConfinement.namespaces.<name>.hostLink.hostIf`
- `services.vpnConfinement.namespaces.<name>.hostLink.nsIf`
- `services.vpnConfinement.namespaces.<name>.hostLink.subnetIPv4`
- `services.vpnConfinement.namespaces.<name>.ingress.fromHost.tcp`
- `services.vpnConfinement.namespaces.<name>.ingress.fromTunnel.tcp`
- `services.vpnConfinement.namespaces.<name>.ingress.fromTunnel.udp`
- `services.vpnConfinement.namespaces.<name>.egress.mode`
- `services.vpnConfinement.namespaces.<name>.egress.allowedTcpPorts`
- `services.vpnConfinement.namespaces.<name>.egress.allowedUdpPorts`
- `services.vpnConfinement.namespaces.<name>.egress.allowedCidrs`

## Per service

- `systemd.services.<name>.vpn.enable`
- `systemd.services.<name>.vpn.namespace`
- `systemd.services.<name>.vpn.hardeningProfile`
- `systemd.services.<name>.vpn.restrictBind`

## Per socket

- `systemd.sockets.<name>.vpn.enable`
- `systemd.sockets.<name>.vpn.namespace`

## Behavior notes

- A service is confined when `systemd.services.<name>.vpn.enable = true`.
- `services.vpnConfinement.targetServices` was removed in v2.
- DNS enforcement is namespace policy (`dns.mode`), not per-service policy.
- `securityProfile` values are `balanced` or `highAssurance`.
- `securityProfile = "highAssurance"` defaults `egress.mode = "allowList"` and
  turns weaker compatibility paths into assertions.
- `dns.mode` values are `strict` or `compat`.
- `dns.search` must contain validated domain-style search suffixes only.
- `dns.allowHostResolverIPC = false` (default) blocks system D-Bus and
  `/run/nscd` helper paths in strict mode.
- `dns.allowHostResolverIPC = true` relaxes helper-path blocking for
  compatibility.
- `egress.mode = "allowAllTunnel"` allows all tunnel egress after DNS policy.
- `egress.mode = "allowList"` allows only configured `allowed*` rules.
- `dns.mode = "strict"` means common resolver leak resistance, not blanket
  prevention of all encrypted DNS schemes.
- `hostLink.subnetIPv4` must be an IPv4 `/30` network base when set.
- `ingress.fromHost.tcp` requires `hostLink.enable = true`.
- `hostLink.hostIf` and `hostLink.nsIf` must be distinct and must not reuse the
  WireGuard interface name.
- If `hostLink.enable = true` and `hostLink.subnetIPv4 = null`, a deterministic
  namespace-name-hash `/30` is auto-allocated from `169.254.0.0/16`.
- VPN-enabled services running as root emit a warning unless
  `DynamicUser = true` or non-root `User` is set.
- Namespace is the trust boundary. Services in one namespace share firewall and
  DNS policy.
- `vpn.restrictBind = true` denies service-created listeners unless they match
  the namespace ingress policy when ingress ports are declared. It is defense in
  depth only.
- Socket units can be vpn-enabled and should match namespace policy with their
  target service.
- Literal WireGuard peer endpoints are the default and recommended path.
- Hostname endpoints require explicit opt-in with
  `wireguard.allowHostnameEndpoints = true` and effective
  `dynamicEndpointRefreshSeconds > 0`.
- Hostname endpoint refresh is weaker than literal IP endpoints because it is
  performed by WireGuard management units rather than the confined service.
- `wireguard.socketNamespace` is advanced. `"init"` is the main supported
  override; setting it to the same confinement namespace is rejected.
- `networking.wireguard.interfaces.<if>.allowedIPsAsRoutes = false` is advanced
  and emits a warning in `balanced`; `highAssurance` rejects it.
- vpn-enabled services must leave `serviceConfig.NetworkNamespacePath`,
  `serviceConfig.PrivateNetwork`, and `unitConfig.JoinsNamespaceOf` unset.
- vpn-enabled sockets must leave `socketConfig.NetworkNamespacePath` and
  `unitConfig.JoinsNamespaceOf` unset.
- `networking.wireguard.interfaces.<if>.fwMark` remains an upstream advanced
  escape hatch.
- `networking.wireguard.interfaces.<if>.mtu` remains an upstream performance
  tuning control.

## Notes on removed options

- Removed `services.vpnConfinement.namespaces.<name>.dns.blockedPorts`.
- Removed `systemd.services.<name>.vpn.dependsOnTunnel`.
- Removed `services.vpnConfinement.namespaces.<name>.dns.blockSystemBus`.
- Removed `services.vpnConfinement.namespaces.<name>.dns.blockNscd`.
- Removed `services.vpnConfinement.namespaces.<name>.hostLink.hostAddressIPv4`.
- Removed `services.vpnConfinement.namespaces.<name>.hostLink.nsAddressIPv4`.
