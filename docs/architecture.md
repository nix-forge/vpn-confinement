# Architecture

`vpn-confinement` provides fail-closed VPN confinement for selected systemd
services.

## Design

- Services opt in with `systemd.services.<name>.vpn.enable = true`.
- Per-service behavior config is limited to namespace attachment and hardening;
  network policy is namespace-level.
- Confinement uses a dedicated Linux network namespace at `/run/netns/<name>`.
- WireGuard is configured via `networking.wireguard.interfaces.<if>` and
  assigned with `interfaceNamespace`; `socketNamespace` is set intentionally per
  namespace configuration.
- Namespace-local nftables enforces deny-by-default egress and allows only
  tunnel traffic according to namespace egress mode.
- A namespace-specific `resolv.conf` is bind-mounted into confined units.
- DNS policy is namespace-scoped and controlled by
  `services.vpnConfinement.namespaces.<name>.dns.mode`.
- In `dns.mode = "strict"`, DNS policy blocks non-allowlisted DNS-like traffic
  on ports `53`, `853`, `5353`, and `5355` before generic tunnel egress allow.
- Strict mode also bind-mounts namespace `resolv.conf` and `nsswitch.conf`
  (`hosts: files myhostname dns`) into confined services while hiding resolver
  helper paths.
- Egress policy is explicit:
  - `egress.mode = "allowAllTunnel"`: allow all tunnel egress (after DNS
    policy).
  - `egress.mode = "allowList"`: allow only configured ports/CIDRs.
- IPv6 defaults to fail-closed
  (`services.vpnConfinement.namespaces.<name>.ipv6.mode = "disable"`).
- Namespace lifecycle is on-demand through
  `vpn-confinement-netns@<name>.service` and cleaned up when unneeded.

## Security model

- Host network remains unchanged unless a service explicitly enables VPN
  confinement.
- The trust boundary is the namespace, not the individual service.
- Confined services fail closed if tunnel dependencies are required and
  unavailable.
- Runtime tunnel drops are propagated to confined services with
  `BindsTo=wireguard-<if>.service` when `dependsOnTunnel = true`.
- DNS leakage is reduced by namespace resolver pinning and blocked DNS-like
  ports.
- WireGuard peer endpoints must be literal IP endpoints to avoid hostname
  resolution ambiguity across namespaces.
- Direct resolver API use over D-Bus is outside the strict DNS guarantee unless
  system bus access is additionally restricted for that unit.

## Limitations

- Generic HTTPS-based DoH on port 443 is not reliably detectable with simple
  port-based policy.
- DNS-over-HTTPS/DNS-over-QUIC can still traverse generic egress paths unless
  destination allowlisting is enabled.
- Socket-activated services are not supported.
- This module supports WireGuard integration through
  `networking.wireguard.interfaces` only.
- For strict environments, combine confinement with application policy and
  egress inspection.
