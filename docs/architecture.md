# Architecture

`vpn-confinement` provides fail-closed VPN confinement for selected systemd
services.

## Design

- Services opt in with `systemd.services.<name>.vpn.enable = true`.
- Socket units opt in with `systemd.sockets.<name>.vpn.enable = true`.
- Per-service behavior config is limited to namespace attachment and hardening;
  network policy is namespace-level.
- Confinement uses a dedicated Linux network namespace at `/run/netns/<name>`.
- WireGuard is configured via `networking.wireguard.interfaces.<if>` and
  assigned with `interfaceNamespace`.
- The module can also set WireGuard `socketNamespace` for advanced cases, but
  the recommended path is to leave it unset or use `"init"`.
- `wireguard-<if>.service` explicitly requires and orders after the namespace
  preparation unit and also binds to it for fail-closed teardown.
- Namespace-local nftables enforces deny-by-default egress and allows only
  tunnel traffic according to namespace egress mode.
- Store-generated resolver files are bind-mounted directly into confined units.
- DNS policy is namespace-scoped and controlled by
  `services.vpnConfinement.namespaces.<name>.dns.mode`.
- In `dns.mode = "strict"`, DNS policy blocks non-allowlisted DNS-like traffic
  on ports `53`, `853`, `5353`, and `5355` before generic tunnel egress allow.
- Strict mode also bind-mounts namespace `resolv.conf` and `nsswitch.conf`
  (`hosts: files myhostname dns`) into confined services while hiding resolver
  helper paths.
- `dns.allowHostResolverIPC = false` (default) blocks common host resolver
  helpers (`/run/nscd` and system D-Bus sockets) in strict mode; setting it to
  `true` opts out of those helper blocks.
- `dns.mode = "compat"` is a weaker compatibility path that skips strict DNS
  containment entirely.
- Egress policy is explicit:
  - `egress.mode = "allowAllTunnel"`: allow all tunnel egress (after DNS
    policy).
  - `egress.mode = "allowList"`: allow only configured ports/CIDRs.
- IPv6 defaults to fail-closed
  (`services.vpnConfinement.namespaces.<name>.ipv6.mode = "disable"`).
- Namespace lifecycle is on-demand through
  `vpn-confinement-netns@<name>.service` and cleaned up when unneeded.
- Confined services bind to both the namespace unit and the WireGuard unit so
  namespace teardown propagates cleanly.
- Optional `vpn.restrictBind = true` derives `SocketBindAllow` /
  `SocketBindDeny` from namespace ingress policy as defense in depth for
  service-created listeners.

## Security model

- Host network remains unchanged unless a service explicitly enables VPN
  confinement.
- The trust boundary is the namespace, not the individual service.
- Confined services fail closed if tunnel dependencies are required and
  unavailable.
- Runtime tunnel drops are propagated to vpn-enabled services and sockets with
  `BindsTo=wireguard-<if>.service`.
- Namespace teardown is propagated through `BindsTo=vpn-confinement-netns@...`
  on services, sockets, and generated WireGuard dependency units.
- DNS leakage is reduced by namespace resolver pinning and blocked DNS-like
  ports.
- WireGuard peer endpoints must be literal IPs for confinement-managed
  namespaces.
- Direct resolver API use over D-Bus is outside the strict DNS guarantee unless
  `dns.allowHostResolverIPC = false` (or equivalent unit-local restrictions).
- Bind restrictions are supplemental hardening only; nftables remains the
  primary policy mechanism.

## Socket activation pattern

- Recommended default for host-facing services: leave `.socket` in host
  namespace and run `.service` in VPN namespace.
- This preserves host listener behavior while confining service-originated
  outbound traffic.
- Use socket namespace attachment only when the listening socket itself must be
  inside the VPN namespace.

## Limitations

- Generic HTTPS-based DoH on port 443 is not reliably detectable with simple
  port-based policy.
- DNS-over-HTTPS/DNS-over-QUIC can still traverse generic egress paths unless
  destination allowlisting is enabled.
- This module supports WireGuard integration through
  `networking.wireguard.interfaces` only.
- For strict environments, combine confinement with application policy and
  egress inspection.

## Why netns over policy routing

- The module is designed for "only selected services use VPN". A dedicated
  namespace is a cleaner trust boundary than host-global policy-routing rules.
- The WireGuard interface is moved into the namespace, so confined cleartext
  traffic lives inside that namespace boundary.
- This model minimizes accidental clearnet fallback paths for confined units and
  keeps host networking behavior unchanged for non-confined services.

## Compatibility baseline

- Supported baseline: NixOS 26.05+.
- This assumes modern systemd features required by this module, including
  `NetworkNamespacePath=` and `RestrictNetworkInterfaces=`.
