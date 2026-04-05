---
title: Options
description: Practical option guidance and security impact
---

This document focuses on practical usage: safe defaults, when to change an
option, and security impact.

## Global module options

| Option                                     | Default     | When to change                              | Security impact                                     |
| ------------------------------------------ | ----------- | ------------------------------------------- | --------------------------------------------------- |
| `services.vpnConfinement.enable`           | `false`     | Enable module behavior                      | Enables confinement wiring and assertions           |
| `services.vpnConfinement.defaultNamespace` | `"vpnapps"` | Multi-namespace setups or naming preference | Defines fallback trust domain for vpn-enabled units |

## Namespace options

### Identity and profile

| Option                              | Default      | When to change                                | Security impact                                               |
| ----------------------------------- | ------------ | --------------------------------------------- | ------------------------------------------------------------- |
| `namespaces.<name>.enable`          | `false`      | Enable a namespace policy domain              | Disabled namespaces cannot be referenced by vpn-enabled units |
| `namespaces.<name>.securityProfile` | `"balanced"` | Use `"highAssurance"` for stricter assertions | `highAssurance` rejects weaker compatibility paths            |

### WireGuard behavior

| Option                                               | Default | When to change                                  | Security impact                                               |
| ---------------------------------------------------- | ------- | ----------------------------------------------- | ------------------------------------------------------------- |
| `namespaces.<name>.wireguard.interface`              | `"wg0"` | Interface naming or multiple namespaces         | Must be unique across enabled namespaces                      |
| `namespaces.<name>.wireguard.socketNamespace`        | `null`  | Advanced socket birthplace routing requirements | Misuse can weaken assumptions around endpoint path control    |
| `namespaces.<name>.wireguard.allowHostnameEndpoints` | `false` | Only if peers require hostname endpoints        | Weaker than literal IP endpoints; rejected in `highAssurance` |

### DNS policy

| Option                                       | Default    | When to change                                    | Security impact                                                 |
| -------------------------------------------- | ---------- | ------------------------------------------------- | --------------------------------------------------------------- |
| `namespaces.<name>.dns.mode`                 | `"strict"` | `"compat"` only for resolver compatibility issues | `strict` provides common resolver leak resistance               |
| `namespaces.<name>.dns.servers`              | `[]`       | Set namespace resolver IPs                        | In `strict`, only configured resolvers are allowed on DNS ports |
| `namespaces.<name>.dns.search`               | `[]`       | Add required search suffixes                      | Validated domain-style suffixes only                            |
| `namespaces.<name>.dns.allowHostResolverIPC` | `false`    | Expert compatibility override in strict mode      | Weakens strict DNS by allowing host resolver helper IPC         |

### IPv6, ingress, and egress

| Option                                     | Default            | When to change                                  | Security impact                                              |
| ------------------------------------------ | ------------------ | ----------------------------------------------- | ------------------------------------------------------------ |
| `namespaces.<name>.ipv6.mode`              | `"disable"`        | Use `"tunnel"` when IPv6 over WG is intended    | `disable` is fail closed                                     |
| `namespaces.<name>.ingress.fromHost.tcp`   | `[]`               | Host-to-namespace ingress over hostLink         | Requires `hostLink.enable = true`                            |
| `namespaces.<name>.ingress.fromTunnel.tcp` | `[]`               | Expose service TCP listeners through WG         | Expands reachable service surface inside namespace           |
| `namespaces.<name>.ingress.fromTunnel.udp` | `[]`               | Expose service UDP listeners through WG         | Expands reachable service surface inside namespace           |
| `namespaces.<name>.egress.mode`            | `"allowAllTunnel"` | Use `"allowList"` for explicit outbound control | `allowList` is required by `highAssurance`                   |
| `namespaces.<name>.egress.allowedTcpPorts` | `[]`               | Port-level egress control in `allowList`        | Combine with CIDR constraints for strong destination control |
| `namespaces.<name>.egress.allowedUdpPorts` | `[]`               | Port-level egress control in `allowList`        | Combine with CIDR constraints for strong destination control |
| `namespaces.<name>.egress.allowedCidrs`    | `[]`               | Destination allowlist scope                     | Required to be non-empty in `highAssurance`                  |

### Host link

| Option                                  | Default            | When to change                                              | Security impact                       |
| --------------------------------------- | ------------------ | ----------------------------------------------------------- | ------------------------------------- |
| `namespaces.<name>.hostLink.enable`     | `false`            | Only when host-to-namespace path is required                | Adds host communication path          |
| `namespaces.<name>.hostLink.hostIf`     | `"ve-<name>-host"` | Interface naming constraints                                | Must be unique and not equal to WG IF |
| `namespaces.<name>.hostLink.nsIf`       | `"ve-<name>-ns"`   | Interface naming constraints                                | Must be unique and not equal to WG IF |
| `namespaces.<name>.hostLink.subnetIPv4` | `null`             | Set explicit `/30` instead of deterministic auto-allocation | Avoid overlap across host links       |

## Per-service options (`systemd.services.<name>.vpn.*`)

| Option                     | Default      | When to change                                                     | Security impact                                   |
| -------------------------- | ------------ | ------------------------------------------------------------------ | ------------------------------------------------- |
| `enable`                   | `false`      | Confine this service                                               | Service joins namespace policy boundary           |
| `namespace`                | `null`       | Place service in non-default namespace                             | Selects trust domain                              |
| `hardeningProfile`         | `"baseline"` | Use `"strict"` for extra systemd hardening                         | Reduces post-compromise capabilities              |
| `restrictBind`             | `false`      | Constrain service-created listeners to declared ingress            | Defense in depth only                             |
| `allowRootInHighAssurance` | `false`      | Exceptional root-only daemons under `highAssurance`                | Explicitly weakens high-assurance non-root stance |
| `extraAddressFamilies`     | `[]`         | Add AFs needed by daemon compatibility                             | Broadens allowed socket family surface            |
| `extraNetworkInterfaces`   | `[]`         | Add interfaces beyond module default (`lo`, WG, optional hostLink) | Broadens reachable network surface                |

## Per-socket options (`systemd.sockets.<name>.vpn.*`)

| Option      | Default | When to change                 | Security impact                                 |
| ----------- | ------- | ------------------------------ | ----------------------------------------------- |
| `enable`    | `false` | Confine the socket unit itself | Socket namespace aligns with confinement policy |
| `namespace` | `null`  | Override namespace for socket  | Must match vpn-enabled target service policy    |

## High-assurance requirements

`securityProfile = "highAssurance"` enforces:

- `dns.mode = "strict"`
- `dns.allowHostResolverIPC = false`
- `egress.mode = "allowList"`
- non-empty `egress.allowedCidrs`
- literal WireGuard endpoints only (hostname endpoints rejected)
- `networking.wireguard.interfaces.<if>.allowedIPsAsRoutes = true`
- non-root vpn-enabled services by default (`DynamicUser = true` or non-root
  `User`), unless `vpn.allowRootInHighAssurance = true`

## Additional behavior notes

- A service is confined when `systemd.services.<name>.vpn.enable = true`.
- DNS and firewall are namespace policies, not per-service policies.
- Namespace is the trust boundary; services in the same namespace share policy.
- `dns.mode = "strict"` means common resolver leak resistance, not complete
  prevention of arbitrary encrypted DNS over generic allowed destinations.
- vpn-enabled services must not set `serviceConfig.NetworkNamespacePath`,
  `serviceConfig.PrivateNetwork`, or `unitConfig.JoinsNamespaceOf`.
- vpn-enabled sockets must not set `socketConfig.NetworkNamespacePath` or
  `unitConfig.JoinsNamespaceOf`.

## Canonical option sources

- Human-oriented guidance: this document.
- Generated option reference: `reference/options-generated`.
- Nix option declarations: `modules/vpn-confinement/default.nix`,
  `modules/vpn-confinement/service-extension.nix`, and
  `modules/vpn-confinement/socket-extension.nix`.
