# Options

## Global

- `services.vpnConfinement.enable`
- `services.vpnConfinement.defaultNamespace`
- `services.vpnConfinement.namespaces.<name>.enable`
- `services.vpnConfinement.namespaces.<name>.wireguard.interface`
- `services.vpnConfinement.namespaces.<name>.wireguard.socketNamespace`
- `services.vpnConfinement.namespaces.<name>.dns.mode`
- `services.vpnConfinement.namespaces.<name>.dns.servers`
- `services.vpnConfinement.namespaces.<name>.dns.search`
- `services.vpnConfinement.namespaces.<name>.dns.blockedPorts`
- `services.vpnConfinement.namespaces.<name>.ipv6.mode`
- `services.vpnConfinement.namespaces.<name>.hostLink.enable`
- `services.vpnConfinement.namespaces.<name>.hostLink.hostIf`
- `services.vpnConfinement.namespaces.<name>.hostLink.nsIf`
- `services.vpnConfinement.namespaces.<name>.hostLink.hostAddressIPv4`
- `services.vpnConfinement.namespaces.<name>.hostLink.nsAddressIPv4`
- `services.vpnConfinement.namespaces.<name>.ingress.fromHost.tcp`
- `services.vpnConfinement.namespaces.<name>.ingress.fromTunnel.tcp`
- `services.vpnConfinement.namespaces.<name>.ingress.fromTunnel.udp`
- `services.vpnConfinement.namespaces.<name>.egress.extraTcp`
- `services.vpnConfinement.namespaces.<name>.egress.extraUdp`
- `services.vpnConfinement.namespaces.<name>.egress.extraCidrs`
- `services.vpnConfinement.namespaces.<name>.egress.rawRules`

## Per service

- `systemd.services.<name>.vpn.enable`
- `systemd.services.<name>.vpn.namespace`
- `systemd.services.<name>.vpn.dependsOnTunnel`
- `systemd.services.<name>.vpn.hardeningProfile`
- `systemd.services.<name>.vpn.ingress.fromHost.tcp`
- `systemd.services.<name>.vpn.ingress.fromTunnel.tcp`
- `systemd.services.<name>.vpn.ingress.fromTunnel.udp`

## Behavior notes

- A service is confined when `systemd.services.<name>.vpn.enable = true`.
- `services.vpnConfinement.targetServices` was removed in v2.
- DNS enforcement is namespace policy (`dns.mode`), not per-service policy.
- `dns.mode` values are `strict` or `relaxed`.
- Namespace is the trust boundary. Services in one namespace share firewall and
  DNS policy.
- Socket-activated services are not supported.
