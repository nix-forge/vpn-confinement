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

## services\.vpnConfinement\.enable

Whether to enable VPN confinement for selected systemd services\.

_Type:_ boolean

_Default:_

```nix
false
```

_Example:_

```nix
true
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.defaultNamespace

Default namespace name used by vpn-enabled services and sockets when they do not
set vpn\.namespace\.

_Type:_ string

_Default:_

```nix
"vpnapps"
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces

Namespace-scoped confinement policies keyed by namespace name\.

_Type:_ attribute set of (submodule)

_Default:_

```nix
{
  vpnapps = {
    enable = true;
  };
}
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.enable

Whether to enable VPN confinement namespace\.

_Type:_ boolean

_Default:_

```nix
false
```

_Example:_

```nix
true
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.dns\.allowHostResolverIPC

Allow strict-mode services to reach host resolver helper IPC such as nscd or
system D-Bus\. This weakens DNS containment\.

_Type:_ boolean

_Default:_

```nix
false
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.dns\.mode

DNS containment mode\. “strict” is the secure default; “compat” weakens resolver
containment for workloads that need it\.

_Type:_ one of “strict”, “compat”

_Default:_

```nix
"strict"
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.dns\.search

DNS search suffixes written to generated resolver config; values must be valid
domain-style suffixes\.

_Type:_ list of string

_Default:_

```nix
[ ]
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.dns\.servers

Allowed DNS resolver IPs used to generate namespace-local resolv\.conf in strict
mode\.

_Type:_ list of string

_Default:_

```nix
[ ]
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.egress\.allowedCidrs

Allowed destination CIDRs (or literal IPs) for allowList mode\. Required in
highAssurance\.

_Type:_ list of string

_Default:_

```nix
[ ]
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.egress\.allowedTcpPorts

Allowed TCP destination ports for allowList mode\.

_Type:_ list of 16 bit unsigned integer; between 0 and 65535 (both inclusive)

_Default:_

```nix
[ ]
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.egress\.allowedUdpPorts

Allowed UDP destination ports for allowList mode\.

_Type:_ list of 16 bit unsigned integer; between 0 and 65535 (both inclusive)

_Default:_

```nix
[ ]
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.egress\.mode

Tunnel egress policy: allow all tunnel traffic or only explicit allowlist
rules\.

_Type:_ one of “allowAllTunnel”, “allowList”

_Default:_

```nix
"allowAllTunnel"
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.hostLink\.enable

Enable host-to-namespace veth link for controlled host ingress use cases\.

_Type:_ boolean

_Default:_

```nix
false
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.hostLink\.hostIf

Host-side veth interface name for hostLink mode\.

_Type:_ string

_Default:_

```nix
"ve-‹name›-host"
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.hostLink\.nsIf

Namespace-side veth interface name for hostLink mode\.

_Type:_ string

_Default:_

```nix
"ve-‹name›-ns"
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.hostLink\.subnetIPv4

Optional hostLink /30 subnet base\. Null auto-allocates a deterministic subnet
from 169\.254\.0\.0/16\.

_Type:_ null or string

_Default:_

```nix
null
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.ingress\.fromHost\.tcp

TCP ports accepted from hostLink host endpoint into the namespace\. Requires
hostLink\.enable = true\.

_Type:_ list of 16 bit unsigned integer; between 0 and 65535 (both inclusive)

_Default:_

```nix
[ ]
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.ingress\.fromTunnel\.tcp

TCP listener ports accepted from the WireGuard interface into the namespace\.

_Type:_ list of 16 bit unsigned integer; between 0 and 65535 (both inclusive)

_Default:_

```nix
[ ]
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.ingress\.fromTunnel\.udp

UDP listener ports accepted from the WireGuard interface into the namespace\.

_Type:_ list of 16 bit unsigned integer; between 0 and 65535 (both inclusive)

_Default:_

```nix
[ ]
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.ipv6\.mode

IPv6 policy inside this namespace: fail-closed disable, or tunnel when WireGuard
IPv6 routes are configured\.

_Type:_ one of “disable”, “tunnel”

_Default:_

```nix
"disable"
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.securityProfile

Opinionated namespace security preset\. “highAssurance” turns weaker
compatibility paths into explicit evaluation failures\.

_Type:_ one of “balanced”, “highAssurance”

_Default:_

```nix
"balanced"
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.wireguard\.allowHostnameEndpoints

Advanced compatibility opt-in for hostname:port WireGuard peer endpoints\.
Literal IP endpoints remain the secure default\.

_Type:_ boolean

_Default:_

```nix
false
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.wireguard\.interface

WireGuard interface name managed for this confinement namespace\.

_Type:_ string

_Default:_

```nix
"wg0"
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## services\.vpnConfinement\.namespaces\.\<name>\.wireguard\.socketNamespace

Advanced WireGuard UDP socket birthplace namespace\. Leave this unset for the
default path, or use “init” when the socket must stay in the host namespace\.

_Type:_ null or string

_Default:_

```nix
null
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/default\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/default.nix)

## systemd\.services\.\<name>\.vpn\.enable

Whether to enable run this unit in the VPN confinement namespace\.

_Type:_ boolean

_Default:_

```nix
false
```

_Example:_

```nix
true
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/service-extension\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/service-extension.nix)

## systemd\.services\.\<name>\.vpn\.allowRootInHighAssurance

Explicit opt-out for high-assurance non-root enforcement\. Use only when this
service cannot run as DynamicUser or a dedicated User\.

_Type:_ boolean

_Default:_

```nix
false
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/service-extension\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/service-extension.nix)

## systemd\.services\.\<name>\.vpn\.extraAddressFamilies

Additional AddressFamily names appended to RestrictAddressFamilies for this
service\.

_Type:_ list of string

_Default:_

```nix
[ ]
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/service-extension\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/service-extension.nix)

## systemd\.services\.\<name>\.vpn\.extraNetworkInterfaces

Additional interface names appended to RestrictNetworkInterfaces for this
service\.

_Type:_ list of string

_Default:_

```nix
[ ]
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/service-extension\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/service-extension.nix)

## systemd\.services\.\<name>\.vpn\.hardeningProfile

Service hardening preset applied on top of confinement wiring\.

_Type:_ one of “baseline”, “strict”

_Default:_

```nix
"baseline"
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/service-extension\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/service-extension.nix)

## systemd\.services\.\<name>\.vpn\.namespace

Namespace name override for this service\. Leave unset to use
services\.vpnConfinement\.defaultNamespace\.

_Type:_ null or string

_Default:_

```nix
null
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/service-extension\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/service-extension.nix)

## systemd\.services\.\<name>\.vpn\.restrictBind

Restrict service-created listeners to declared namespace ingress ports as
defense in depth\.

_Type:_ boolean

_Default:_

```nix
false
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/service-extension\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/service-extension.nix)

## systemd\.sockets\.\<name>\.vpn\.enable

Whether to enable run this socket in the VPN confinement namespace\.

_Type:_ boolean

_Default:_

```nix
false
```

_Example:_

```nix
true
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/socket-extension\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/socket-extension.nix)

## systemd\.sockets\.\<name>\.vpn\.namespace

Namespace name override for this socket\. Leave unset to use
services\.vpnConfinement\.defaultNamespace\.

_Type:_ null or string

_Default:_

```nix
null
```

_Declared by:_

- [\<nixpkgs/modules/vpn-confinement/socket-extension\.nix>](https://github.com/NixOS/nixpkgs/blob//modules/vpn-confinement/socket-extension.nix)
