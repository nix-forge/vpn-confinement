---
title: Advanced Tuning
description: Escape hatches and low-level controls
---

These settings are for advanced deployments. Start with the common path first.

## Advanced knobs

- `wireguard.socketNamespace`
- `wireguard.allowHostnameEndpoints`
- manual `hostLink.hostIf` / `hostLink.nsIf`
- `hostLink.subnetIPv4`
- `dns.mode = "compat"`
- `dns.allowHostResolverIPC = true`

## `wireguard.socketNamespace`

Treat this as an escape hatch. Leave unset unless you have a concrete reason to
move WireGuard socket birthplace.

When `wireguard.endpointPinning.enable = true`, pinning is applied in the
effective socket birthplace namespace (`init` by default or a custom
`wireguard.socketNamespace`).

## Manual host-link subnet pinning

By default, host-link subnets are deterministic `/30` allocations from
`169.254.0.0/16`.

The default host-link interface names are also deterministic and automatically
kept within Linux's 15-character interface-name limit.

Set `hostLink.subnetIPv4` only when you need stable coordination with external
host policy, monitoring, or strict inventory requirements.

Override `hostLink.hostIf` or `hostLink.nsIf` only when you must align with
existing host tooling.

## Hostname endpoints

Literal endpoints remain the secure default. Hostname endpoints are
compatibility mode and rely on WireGuard endpoint refresh behavior.

Endpoint pinning requires literal endpoints.

## Read next

- [`Security Exceptions`](../security-exceptions/)
- [`Threat Model`](../../threat-model/)
