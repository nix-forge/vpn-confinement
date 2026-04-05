# Architecture

`vpn-confinement` provides fail-closed VPN confinement for selected systemd
services.

## Design

- Services opt in with `systemd.services.<name>.vpn.enable = true`.
- Socket units opt in with `systemd.sockets.<name>.vpn.enable = true`.
- Per-service behavior config is limited to namespace attachment and hardening;
  network policy is namespace-level.
- `services.vpnConfinement.namespaces.<name>.securityProfile` provides a small,
  opinionated top-level selector for stronger defaults and assertions.
- Confinement uses a dedicated Linux network namespace at `/run/netns/<name>`.
- WireGuard is configured via `networking.wireguard.interfaces.<if>` and
  assigned with `interfaceNamespace`.
- The module can also set WireGuard `socketNamespace` for advanced cases, but
  the recommended path is to leave it unset or use `"init"`.
- Hostname WireGuard endpoints are treated as an explicit advanced opt-in with
  `wireguard.allowHostnameEndpoints = true`.
- `interfaceNamespace` is the main mechanism: the WireGuard link itself is kept
  inside the confinement namespace.
- `socketNamespace` controls only the UDP socket birthplace and should be viewed
  as an advanced escape hatch, not the primary design surface.
- `wireguard-<if>.service` explicitly requires and orders after the namespace
  preparation unit and also binds to it for fail-closed teardown.
- Namespace-local nftables enforces deny-by-default egress and allows only
  tunnel traffic according to namespace egress mode.
- Store-generated resolver files are bind-mounted directly into confined units.
- DNS policy is namespace-scoped and controlled by
  `services.vpnConfinement.namespaces.<name>.dns.mode`.
- In `dns.mode = "strict"`, DNS policy blocks non-allowlisted DNS-like traffic
  on ports `53`, `853`, `5353`, and `5355` before generic tunnel egress allow.
- `dns.mode = "strict"` is about common resolver leak resistance.
- `securityProfile = "highAssurance"` defaults `egress.mode = "allowList"` and
  rejects weaker compatibility paths such as hostname endpoints or host resolver
  IPC.
- `securityProfile = "highAssurance"` requires non-empty `egress.allowedCidrs`
  so outbound policy remains destination-constrained.
- Strict mode also bind-mounts namespace `resolv.conf` and `nsswitch.conf`
  (`hosts: files myhostname dns`) into confined services while hiding resolver
  helper paths.
- In `highAssurance`, vpn-enabled services must run as non-root by default
  (`DynamicUser = true` or explicit non-root `User`) unless explicitly opted out
  per service.
- `dns.allowHostResolverIPC = false` (default) blocks common host resolver
  helpers (`/run/nscd` and system D-Bus sockets) in strict mode; setting it to
  `true` opts out of those helper blocks.
- `dns.mode = "compat"` is a weaker compatibility path that skips strict DNS
  containment entirely.
- Egress policy is explicit:
  - `egress.mode = "allowAllTunnel"`: allow all tunnel egress (after DNS
    policy).
  - `egress.mode = "allowList"`: allow only configured ports/CIDRs.
- nftables rules use named sets for DNS servers, blocked DNS ports, allowed
  ports, and allowed CIDRs so the policy stays auditable as the ruleset grows.
- IPv6 defaults to fail-closed
  (`services.vpnConfinement.namespaces.<name>.ipv6.mode = "disable"`).
- Namespace lifecycle is on-demand through
  `vpn-confinement-netns@<name>.service` and cleaned up when unneeded.
- Namespace setup validates the generated nftables rules before applying them
  and uses shell traps to clean up partial state on failed starts.
- Confined services bind to both the namespace unit and the WireGuard unit so
  namespace teardown propagates cleanly.
- Optional `vpn.restrictBind = true` derives `SocketBindAllow` /
  `SocketBindDeny` from namespace ingress policy as defense in depth for
  service-created listeners when ingress ports are declared.

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
- Literal WireGuard peer endpoints are preferred.
- Hostname endpoints are permitted only with explicit opt-in and endpoint
  refresh enabled, and remain outside the module's strict DNS guarantee.
- Direct resolver API use over D-Bus is outside the strict DNS guarantee unless
  `dns.allowHostResolverIPC = false` (or equivalent unit-local restrictions).
- Bind restrictions are supplemental hardening only; nftables remains the
  primary policy mechanism.
- vpn-enabled services and sockets must not manually set namespace attachment
  controls that conflict with module-managed `NetworkNamespacePath` behavior.

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
- `networking.wireguard.interfaces.<if>.fwMark` and `.mtu` remain upstream
  WireGuard controls; this module documents them but does not build policy
  around them.
- This module supports WireGuard integration through
  `networking.wireguard.interfaces` only.
- WireGuard endpoint pinning is not yet implemented. Pinning the UDP socket path
  likely requires additional enforcement in the socket birthplace namespace.
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
