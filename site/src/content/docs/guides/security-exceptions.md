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

## Service validation independent of destinations

Set namespace `servicePolicy = "enforced"` to validate service privileges even when
`balanced` and `egress.mode = "allowAllTunnel"` are needed for changing torrent peers.
It requires non-root service execution, `NoNewPrivileges = true`, empty effective
`CapabilityBoundingSet` and `AmbientCapabilities`, verified executable syntax, and
activation or inherited sockets attached to the same namespace. The four exception
flags `allowRootInHighAssurance`, `allowUnsafeCapabilities`, `allowPrivilegedCommands`
and `allowHostSockets` are rejected in this mode, even if the service would otherwise
pass validation. Remove unused flags rather than leaving misleading exceptions enabled. Set
`CapabilityBoundingSet = ""` to emit systemd's clearing directive. An empty Nix list
omits the directive and is rejected; it does not clear systemd's default bounding set.
Explicit `User` settings must be literal, without whitespace or systemd `%` specifiers.
Known NixOS accounts with UID 0 and numeric spellings such as `00` are rejected as root.
This includes known root accounts selected implicitly by `DynamicUser` from a valid
unit name. systemd can reuse an existing static account instead of allocating a new one,
as documented in [systemd.exec](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#DynamicUser=).
Checks do not predict hashed unit-derived names or arbitrary runtime NSS account changes.

The default `servicePolicy = "profile"` preserves existing behavior. `highAssurance`
keeps its existing checks and explicit exceptions. `balanced` reports risky settings
as warnings. Selecting `profile` never disables `highAssurance` checks. Existing
configurations do not migrate automatically; the doctor reports the configured service
policy alongside the namespace policy.

High-assurance non-root checks now also reject previously misclassified numeric zero
identities, known UID 0 aliases, implicit root-account reuse, and identities containing
whitespace or unit specifiers. High-assurance capability checks reject an empty bounding
list that would omit the systemd directive. These are validation fixes; the historical
`allowRootInHighAssurance` and `allowUnsafeCapabilities` exceptions still acknowledge
those risks in `profile` mode. Use a literal dedicated user and an explicit bounding
assignment instead of adding exceptions to silence a failure. Balanced compatibility
behavior is unchanged.

`servicePolicy` does not change DNS, destination filtering or filesystem sandbox
presets. Select those settings separately. It cannot inspect arbitrary runtime unit
changes or prove that application-accessible Unix sockets are safe.

## Privileges and inherited sockets

In `profile` mode, `highAssurance` rejects `CAP_NET_RAW`, `CAP_NET_ADMIN` and
`CAP_SYS_ADMIN`, as well as numeric, inverted or otherwise noncanonical capability
syntax, unless `vpn.allowUnsafeCapabilities` is set. Enforced mode requires empty
capability sets, including capabilities outside that historical list. Move privileged
setup into a separate trusted unit. Raw packet access can bypass the namespace IP
firewall on a host link.

Lifecycle validation covers `ExecCondition`, all start/stop hooks, `ExecStart` and
`ExecReload`. Ordinary absolute executable paths quoted with single or double quotes
are accepted when their path contains only letters, digits, `_`, `.`, `/` and `-`.
Trailing whitespace, including line endings from generated NixOS commands, is accepted.
Ordinary quoted arguments remain supported. The parser still rejects privilege prefixes
`+`, `!` and `!!`, encoded or escaped executable names, quoted relative executables,
standalone semicolon command separators and internal line breaks. It does not reproduce
systemd's full command parser.

Warnings distinguish visible privilege prefixes from executable syntax the checker
cannot verify. An unverified warning does not establish a confinement bypass. Inspect
the reported lifecycle phase in the generated unit. Avoid enabling
`vpn.allowPrivilegedCommands` just to silence a warning. This historical exception is
available only in `profile` mode; enforced mode rejects it.

`vpn.allowHostSockets` acknowledges activation or inherited sockets that cannot be
verified in the same VPN namespace, in `profile` mode only. The check includes socket
activation targets, templates, aliases and the service's `Sockets` setting. A host Unix
socket can delegate network access to a host process. In enforced mode, attach declared
sockets to the same VPN namespace or remove them.

## Composing filesystem defaults

Upstream applies baseline sandbox defaults and a separate strict application preset.
A consumer that requires a stronger `ProtectSystem` or `ProtectHome` setting can assign
it explicitly. An adapter applying stronger defaults may use a priority between ordinary
`mkDefault` at 1000 and this module's strict filesystem settings at 900, such as 950.
This lets the consumer's stronger default override a conflicting native application
default while retaining the upstream strict preset. Do not lower all upstream hardening
priorities or replace entire service configurations. Keep application-specific writable
paths narrow and test the generated unit and actual service startup.

Inline and store-backed WireGuard keys are rejected in both profiles. A legacy balanced deployment
can explicitly select `wireguard.allowInsecureKeyMaterial`; `highAssurance` rejects that exception.

Configuration checks cover structured `systemd.sockets` declarations. Raw units from
`systemd.units`, packaged units, and later runtime changes require deployment review.
The doctor also inspects systemd's loaded `TriggeredBy` and `Sockets` relationships,
including packaged activation sockets, and reports unverified namespace attachment.

Both strict service policies reject `PermissionsStartOnly`, because systemd applies
this legacy option by skipping sandboxing for lifecycle commands. High-assurance
profile mode retains its explicit `allowPrivilegedCommands` exception; enforced
mode permits no exception. Move privileged setup into a separate trusted unit.
Command validation also covers `ExecReloadPost`.
For template units, implicit `DynamicUser` account checks use the prefix before `@`,
matching systemd's account-name derivation.
