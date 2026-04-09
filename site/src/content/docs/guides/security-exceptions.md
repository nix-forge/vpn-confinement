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
- `allowedIPsAsRoutes = false`

Use this profile when compatibility trade-offs are acceptable and
destination-constrained policy is required.
