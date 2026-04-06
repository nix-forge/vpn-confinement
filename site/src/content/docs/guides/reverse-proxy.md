---
title: Reverse Proxy
description: Host reverse proxy to namespace services
---

This is a common deployment pattern:

- reverse proxy stays on host networking
- app service runs in VPN confinement namespace
- host reaches app over `publishToHost.tcp`

## Pattern

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

# app service in namespace
systemd.services.my-app.vpn = {
  enable = true;
  namespace = "vpnapps";
};
```

Then use:

- `services.vpnConfinement.namespaces.vpnapps.derived.hostLink.nsAddressIPv4`

as the upstream target from your host reverse proxy.

## Binding guidance

- Inside namespace, bind the app to the namespace-visible address/port it
  expects.
- From host, proxy to the derived namespace-side host-link address and published
  port.

## When to pin `hostLink.subnetIPv4`

- Leave `null` for most setups (deterministic auto-allocation).
- Pin subnet only when external host policies need a fixed CIDR.
