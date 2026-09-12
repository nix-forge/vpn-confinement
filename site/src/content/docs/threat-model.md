---
title: Threat model
description: Privacy guarantees, trust boundaries, and explicit exceptions
---

The project aims to prevent selected services' ordinary Internet traffic and DNS
from leaving outside their configured VPN. Host root, the kernel, the NixOS
configuration, and the WireGuard implementation are trusted.

An ISP can observe the VPN endpoint, timing, and traffic volume. WireGuard does
not disguise its protocol. This module does not promise anonymity or prevent
activity inference. The VPN operator and application-level tracking remain
separate trust concerns. See [WireGuard limitations](https://www.wireguard.com/known-limitations/).

## Boundaries and controls

| Property | Control | Limit |
| --- | --- | --- |
| Selected service traffic uses the tunnel | Network namespace with WireGuard and default-drop nftables | Host sockets and privileged host helpers are separate paths |
| No ordinary fallback when the peer is unreachable | Namespace routing and interface-scoped output policy | Reachability is not the same as systemd unit state |
| Common resolver behavior stays inside the namespace | Strict resolver mounts, helper blocking, and port rules | Arbitrary DoH through allowed tunnel egress can bypass resolver choice |
| IPv6 is disabled by default | Namespace sysctls, nftables, and default address-family restrictions | Dual-stack mode requires a provider address and routes |
| Host UI access is explicit | Optional veth and host-source ingress rules | Replies to permitted connections can carry application data |
| Managed restart and teardown propagate | `BindsTo`, `After`, and `PartOf` | External interface/name deletion has different lifecycle semantics |
| Compromised service has fewer privileges | Non-root execution and service sandbox defaults | Upstream modules and user overrides can change effective settings |

One namespace is one network trust domain. Services in the same namespace can
communicate with one another. They are not mutually isolated by this module.
Use distinct service UIDs and restricted filesystem access as well.

## Profiles

`balanced` keeps strict DNS and IPv6 disable defaults while allowing arbitrary
Internet destinations through the tunnel. It is appropriate for changing torrent
peers. Set a service's `vpn.hardeningProfile = "strict"` independently when the
application supports that sandbox.

`highAssurance` additionally requires strict DNS, a non-empty destination
allowlist, literal endpoints, installed WireGuard peer routes, file-based keys,
and non-root service execution. It rejects dangerous capability grants unless
`vpn.allowUnsafeCapabilities = true` is explicitly selected. Privileged or unverified executable
syntax needs `vpn.allowPrivilegedCommands`; inherited sockets that cannot be verified in the same
VPN namespace need `vpn.allowHostSockets`. These are separate exceptions from root execution.
Explicit root still
requires `vpn.allowRootInHighAssurance`, even with `DynamicUser = true`.

Namespace `servicePolicy = "enforced"` adds service validation independent of egress
mode. It requires non-root execution, `NoNewPrivileges`, empty capability sets, verified
lifecycle executable syntax and confined activation or inherited sockets. All four service
exception flags are rejected. This can accompany `balanced` for dynamic peers without
claiming destination-constrained egress. The default `servicePolicy = "profile"` retains
the high-assurance exception behavior described above.

Choose narrow CIDRs deliberately. A non-empty list containing `0.0.0.0/0` does
not meaningfully restrict IPv4 destinations. Stronger profile naming does not
turn a broad allowlist into an exfiltration defense.

## Explicit exceptions

- `dns.mode = "compat"` skips strict resolver containment.
- `dns.allowHostResolverIPC` allows host helper access and can permit host-side DNS.
- A host activation socket remains a host-network socket when passed to a service.
  The stronger profile requires an explicit exception for host or unverified socket inheritance.
- Filesystem Unix sockets are not isolated by network namespaces. Access to a
  privileged runtime socket or host proxy can create another communication path.
- `hostLink` and `publishToHost` permit selected host communication. They do not
  grant unrestricted new outbound connections to the host.
- Hostname endpoint resolution happens in management units outside strict service
  DNS containment. It requires explicit opt-in and endpoint refresh.
- `allowRootInHighAssurance` and `allowUnsafeCapabilities` weaken the corresponding
  assertions. Inspect effective settings using the diagnostic command.

In particular, a permission to answer a host connection is not a claim that all
bytes produced by that application pass through WireGuard. Keep host-facing
administration local or protect it with authentication and TLS.

## Failure semantics

Stopping a managed WireGuard or namespace unit stops its dependent services.
Restarting the WireGuard unit restarts previously active consumers. A remote
outage can leave units active with traffic blocked or stalled. WireGuard does not
switch an application to host networking when its peer becomes unreachable.

Deleting a namespace name does not necessarily destroy the namespace while a
process still holds it. The firewall remains attached to that namespace. Do not
use namespace-name deletion as a substitute for managed teardown.

Firewall replacement is a single nftables transaction scoped to the project's
table. An invalid transaction preserves the existing policy. No host-global
ruleset flush is used.

## Evidence and non-goals

Runtime tests exercise the described cases in controlled NixOS VMs, including
traffic from actual confined services. They cannot establish the absence of every
kernel vulnerability, host IPC path, application bug, or administrator override.

The module does not provide HTTPS inspection, a full application sandbox,
protection against compromised host root, automatic provider port-forwarding
leases, or OpenVPN/container backend integration. Its supported backend is
`networking.wireguard.interfaces` on NixOS unstable.

See [Architecture](../architecture/) for implementation and
[Diagnostics](../guides/diagnostics/) for local checks.
