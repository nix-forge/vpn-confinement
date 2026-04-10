---
title: Generated Options
description: Auto-generated option reference from nixosOptionsDoc
---

This file is generated from module option declarations using
`pkgs.nixosOptionsDoc`.

Regenerate with:

```bash
bash scripts/generate-options-doc.sh x86_64-linux
```

## `services.vpnConfinement.defaultNamespace`

Optional default namespace name used by vpn-enabled services and sockets when
they do not set vpn.namespace.

- **Type:** null or string
- **Default:**

```nix
null
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.enable`

Whether to enable VPN confinement for selected systemd services.

- **Type:** boolean
- **Default:**

```nix
false
```

- **Example:**

```nix
true
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces`

Namespace-scoped confinement policies keyed by namespace name.

- **Type:** attribute set of (submodule)
- **Default:**

```nix
{ }
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.derived.hostLink.hostAddressIPv4`

Computed host-side IPv4 address for the effective hostLink subnet.

- **Type:** null or string (read-only)
- **Default:**

```nix
null
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.derived.hostLink.nsAddressIPv4`

Computed namespace-side IPv4 address for the effective hostLink subnet.

- **Type:** null or string (read-only)
- **Default:**

```nix
null
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.derived.hostLink.subnetIPv4`

Computed effective hostLink subnet (/30) for this namespace.

- **Type:** null or string (read-only)
- **Default:**

```nix
null
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.dns.allowHostResolverIPC`

Allow strict-mode services to reach host resolver helper IPC such as nscd or
system D-Bus. This weakens DNS containment.

- **Type:** boolean
- **Default:**

```nix
false
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.dns.mode`

DNS containment mode. "strict" is the secure default; "compat" weakens resolver
containment for workloads that need it.

- **Type:** one of "strict", "compat"
- **Default:**

```nix
"strict"
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.dns.search`

DNS search suffixes written to generated resolver config; values must be valid
domain-style suffixes.

- **Type:** list of string
- **Default:**

```nix
[ ]
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.dns.servers`

Allowed DNS resolver IPs used to generate namespace-local resolv.conf in strict
mode.

- **Type:** list of string
- **Default:**

```nix
[ ]
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.egress.allowEssentialIcmp`

Allow narrow ICMP/ICMPv6 error traffic for allowList tunnel egress when
allowedCidrs are configured.

- **Type:** boolean
- **Default:**

```nix
true
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.egress.allowedCidrs`

Allowed destination CIDRs (or literal IPs) for allowList mode. Required in
highAssurance.

- **Type:** list of string
- **Default:**

```nix
[ ]
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.egress.allowedTcpPorts`

Allowed TCP destination ports for allowList mode.

- **Type:** list of 16 bit unsigned integer; between 0 and 65535 (both
  inclusive)
- **Default:**

```nix
[ ]
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.egress.allowedUdpPorts`

Allowed UDP destination ports for allowList mode.

- **Type:** list of 16 bit unsigned integer; between 0 and 65535 (both
  inclusive)
- **Default:**

```nix
[ ]
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.egress.mode`

Tunnel egress policy: allow all tunnel traffic or only explicit allowlist rules.

- **Type:** one of "allowAllTunnel", "allowList"
- **Default:**

```nix
"allowAllTunnel"
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.enable`

Whether to enable VPN confinement namespace.

- **Type:** boolean
- **Default:**

```nix
false
```

- **Example:**

```nix
true
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.hostLink.enable`

Enable host-to-namespace veth link for controlled host ingress use cases.

- **Type:** boolean
- **Default:**

```nix
false
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.hostLink.hostIf`

Host-side veth interface name for hostLink mode.

- **Type:** string
- **Default:**

```nix
"vh-f34280bd2454"
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.hostLink.nsIf`

Namespace-side veth interface name for hostLink mode.

- **Type:** string
- **Default:**

```nix
"vn-7a41d7c9e29c"
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.hostLink.subnetIPv4`

Optional hostLink /30 subnet base. Null auto-allocates a deterministic subnet
from 169.254.0.0/16.

- **Type:** null or string
- **Default:**

```nix
null
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.ingress.fromHost.tcp`

TCP ports accepted from hostLink host endpoint into the namespace. Requires
hostLink.enable = true.

- **Type:** list of 16 bit unsigned integer; between 0 and 65535 (both
  inclusive)
- **Default:**

```nix
[ ]
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.ingress.fromTunnel.tcp`

TCP listener ports accepted from the WireGuard interface into the namespace.

- **Type:** list of 16 bit unsigned integer; between 0 and 65535 (both
  inclusive)
- **Default:**

```nix
[ ]
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.ingress.fromTunnel.udp`

UDP listener ports accepted from the WireGuard interface into the namespace.

- **Type:** list of 16 bit unsigned integer; between 0 and 65535 (both
  inclusive)
- **Default:**

```nix
[ ]
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.ipv6.mode`

IPv6 policy inside this namespace: fail-closed disable, or tunnel when WireGuard
IPv6 routes are configured.

- **Type:** one of "disable", "tunnel"
- **Default:**

```nix
"disable"
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.publishToHost.tcp`

Simplified host publish abstraction for namespace services. Ports are merged
with ingress.fromHost.tcp. Non-empty values automatically enable effective
host-link wiring.

- **Type:** list of 16 bit unsigned integer; between 0 and 65535 (both
  inclusive)
- **Default:**

```nix
[ ]
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.securityProfile`

Opinionated namespace security preset. "highAssurance" turns weaker
compatibility paths into explicit evaluation failures.

- **Type:** one of "balanced", "highAssurance"
- **Default:**

```nix
"balanced"
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.wireguard.allowHostnameEndpoints`

Advanced compatibility opt-in for hostname:port WireGuard peer endpoints.
Literal IP endpoints remain the secure default.

- **Type:** boolean
- **Default:**

```nix
false
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.wireguard.endpointPinning.enable`

Pin WireGuard outer UDP egress to configured literal peer endpoints using
host-side nftables policy in the socket birthplace namespace path supported by
this module.

- **Type:** boolean
- **Default:**

```nix
false
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.wireguard.endpointPinning.fwMark`

Optional fwMark used to identify WireGuard outer UDP traffic for endpoint
pinning. Null auto-derives a deterministic non-zero mark from the interface
name.

- **Type:** null or (unsigned integer, meaning >=0)
- **Default:**

```nix
null
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.wireguard.interface`

WireGuard interface name managed for this confinement namespace.

- **Type:** string
- **Default:**

```nix
"wg0"
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `services.vpnConfinement.namespaces.<name>.wireguard.socketNamespace`

Advanced WireGuard UDP socket birthplace namespace. Leave this unset for the
default path, or use "init" when the socket must stay in the host namespace.

- **Type:** null or string
- **Default:**

```nix
null
```

- **Declared by:**
  - [`modules/vpn-confinement/default.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/default.nix)

## `systemd.services.<name>.vpn.allowRootInHighAssurance`

Explicit opt-out for high-assurance non-root enforcement. Use only when this
service cannot run as DynamicUser or a dedicated User.

- **Type:** boolean
- **Default:**

```nix
false
```

- **Declared by:**
  - [`modules/vpn-confinement/service-extension.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/service-extension.nix)

## `systemd.services.<name>.vpn.enable`

Whether to enable run this unit in the VPN confinement namespace.

- **Type:** boolean
- **Default:**

```nix
false
```

- **Example:**

```nix
true
```

- **Declared by:**
  - [`modules/vpn-confinement/service-extension.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/service-extension.nix)

## `systemd.services.<name>.vpn.extraAddressFamilies`

Additional AddressFamily names appended to RestrictAddressFamilies for this
service.

- **Type:** list of string
- **Default:**

```nix
[ ]
```

- **Declared by:**
  - [`modules/vpn-confinement/service-extension.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/service-extension.nix)

## `systemd.services.<name>.vpn.hardeningProfile`

Service hardening preset applied on top of confinement wiring.

- **Type:** one of "baseline", "strict"
- **Default:**

```nix
"baseline"
```

- **Declared by:**
  - [`modules/vpn-confinement/service-extension.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/service-extension.nix)

## `systemd.services.<name>.vpn.namespace`

Namespace name override for this service. Leave unset to use
services.vpnConfinement.defaultNamespace when one is configured.

- **Type:** null or string
- **Default:**

```nix
null
```

- **Declared by:**
  - [`modules/vpn-confinement/service-extension.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/service-extension.nix)

## `systemd.services.<name>.vpn.restrictBind`

Restrict service-created listeners to declared namespace ingress ports as
defense in depth.

- **Type:** boolean
- **Default:**

```nix
false
```

- **Declared by:**
  - [`modules/vpn-confinement/service-extension.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/service-extension.nix)

## `systemd.sockets.<name>.vpn.enable`

Whether to enable run this socket in the VPN confinement namespace.

- **Type:** boolean
- **Default:**

```nix
false
```

- **Example:**

```nix
true
```

- **Declared by:**
  - [`modules/vpn-confinement/socket-extension.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/socket-extension.nix)

## `systemd.sockets.<name>.vpn.namespace`

Namespace name override for this socket. Leave unset to use
services.vpnConfinement.defaultNamespace when one is configured.

- **Type:** null or string
- **Default:**

```nix
null
```

- **Declared by:**
  - [`modules/vpn-confinement/socket-extension.nix`](https://github.com/IanHollow/vpn-confinement/blob/main/modules/vpn-confinement/socket-extension.nix)
