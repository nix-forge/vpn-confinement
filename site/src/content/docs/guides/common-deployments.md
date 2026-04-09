---
title: Common Deployments
description: Recommended defaults for day-1 setups
---

This page is the fast path for most operators.

## Recommended baseline

- Use one namespace per trust domain.
- Set `vpn.namespace` explicitly on each confined service or socket.
- Keep `dns.mode = "strict"`.
- Keep `ipv6.mode = "disable"` unless your tunnel is explicitly IPv6-ready.
- Keep literal WireGuard peer endpoints.
- Start with `securityProfile = "balanced"` unless your app has a narrow, known
  destination set.

## Publish app ports to host

Use `publishToHost.tcp` for host-to-namespace access without manual veth/subnet
work:

```nix
services.vpnConfinement.namespaces.vpnapps = {
  enable = true;
  wireguard.interface = "wg0";
  publishToHost.tcp = [ 8080 ];
  dns = {
    mode = "strict";
    servers = [ "10.64.0.1" ];
  };
};

systemd.services.my-app.vpn = {
  enable = true;
  namespace = "vpnapps";
};
```

`publishToHost` is backed by the same host-link mechanism as `hostLink.*`. It is
the common-path API; `hostLink.*` remains the advanced escape hatch.

## Use derived hostLink values

The module exports effective host-link addresses so other services can reference
them directly:

- `services.vpnConfinement.namespaces.<name>.derived.hostLink.subnetIPv4`
- `services.vpnConfinement.namespaces.<name>.derived.hostLink.hostAddressIPv4`
- `services.vpnConfinement.namespaces.<name>.derived.hostLink.nsAddressIPv4`

These are useful for reverse proxy upstreams and host-side monitoring targets.

## Endpoint pinning

Enable endpoint pinning when peers use literal endpoint IPs:

```nix
services.vpnConfinement.namespaces.vpnapps.wireguard.endpointPinning.enable = true;
```

Endpoint pinning behavior:

- Works in the effective WireGuard socket birthplace namespace (`init` by
  default, or a custom `wireguard.socketNamespace` when configured).
- Uses a WireGuard fwmark selector and nftables policy in that birthplace
  namespace to allow only configured endpoint tuples.
- Hostname endpoints are rejected when pinning is enabled.

## High-assurance path

Use `securityProfile = "highAssurance"` when you want the strict preset.

- It defaults vpn-enabled services in that namespace to strict service
  hardening.
- It rejects inline WireGuard private keys; use `privateKeyFile` or
  `generatePrivateKeyFile`.
- It requires destination-constrained allowlisting.

## Read next

- [`Reverse Proxy`](../reverse-proxy/)
- [`Security Profile Decision Matrix`](../security-profile-decision-matrix/)
- [`Advanced Tuning`](../advanced-tuning/)
