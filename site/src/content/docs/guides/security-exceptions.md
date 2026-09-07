---
title: Security Exceptions
description: Weaker paths and when to use them
---

This page groups options that intentionally weaken default guarantees.

## DNS containment exceptions

- `dns.mode = "compat"` disables strict DNS containment.
- `dns.allowHostResolverIPC = true` allows resolver helper IPC paths and weakens
  strict-mode isolation.

Use these only when workloads break under strict mode and you cannot fix the
application behavior.

## Endpoint exceptions

- `wireguard.allowHostnameEndpoints = true` allows hostname endpoints and moves
  endpoint resolution outside strict DNS guarantees.
- If you need endpoint pinning, use literal endpoints.

## Host ingress exceptions

- `publishToHost.tcp` and `hostLink.enable` create host-to-namespace
  communication paths.
- This is expected for admin UIs/reverse proxies, but it expands attack surface
  compared to no host ingress.

`publishToHost.tcp` is the common-path abstraction. Raw `hostLink.*` tuning is
for advanced deployments only.

## High-assurance behavior

`securityProfile = "highAssurance"` rejects multiple weaker paths by design.

- `dns.allowHostResolverIPC = true`
- `wireguard.allowHostnameEndpoints = true`
- inline `networking.wireguard.interfaces.<if>.privateKey`
- inline `networking.wireguard.interfaces.<if>.peers.*.presharedKey`
- `allowedIPsAsRoutes = false`

Use this profile when compatibility trade-offs are acceptable and
destination-constrained policy is required.

## Privileges and inherited sockets

`highAssurance` rejects `CAP_NET_RAW`, `CAP_NET_ADMIN`, and `CAP_SYS_ADMIN` grants, as well as numeric,
inverted, or otherwise noncanonical capability syntax. Use canonical capability names. An advanced
workload that needs these privileges must select `vpn.allowUnsafeCapabilities = true`. Raw packet
access can bypass the namespace's ordinary IP firewall on a host link.

`vpn.allowPrivilegedCommands` is a separate exception for privileged lifecycle commands. The check
covers `ExecCondition`, all start/stop hooks, `ExecStart`, and `ExecReload`. Use a plain executable
path without privileged prefixes. Quoted or escaped executable names, standalone semicolon command
separators, and `!!` compatibility prefixes also need the exception because the conservative check
does not reproduce systemd's full command parser. Ordinary quoted arguments remain supported.
Prefer separately trusted setup units over disabling restrictions on application commands.

`vpn.allowHostSockets` acknowledges activation or inherited sockets that cannot be verified in the
same VPN namespace. The check includes socket activation targets, templates, aliases, and the
service's `Sockets` setting. Unknown or dynamic references require an exception. A host Unix socket
can be intentional, but it can also delegate network access to a host process.

The doctor prints these exceptions and effective unsafe capabilities as warnings. `balanced` emits
configuration warnings for these cases; it does not enforce the stronger profile's rejections.

Inline and store-backed WireGuard keys are rejected in both profiles. A legacy balanced deployment
can explicitly select `wireguard.allowInsecureKeyMaterial`; `highAssurance` rejects that exception.

Configuration checks cover structured `systemd.sockets` declarations. Raw units from
`systemd.units`, packaged units, and later runtime changes require deployment review.
The doctor also inspects systemd's loaded `TriggeredBy` and `Sockets` relationships,
including packaged activation sockets, and reports unverified namespace attachment.
