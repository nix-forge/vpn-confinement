# Threat model

## In scope

- Prevent non-confined host traffic from being forced through the VPN.
- Prevent confined services from egressing outside the tunnel when kill-switch
  is active.
- Reduce DNS leaks from confined services by resolver pinning and blocked
  DNS-like egress ports.
- Keep policy scoped to a namespace trust boundary (not per-service policy
  isolation within one namespace).

## Out of scope

- Full prevention of HTTPS-based DoH on port 443 without deeper traffic
  controls.
- Protection against compromised root on the host.

## Controls

- Network namespace isolation per confinement domain.
- One namespace equals one trust domain and one firewall/DNS policy surface.
- Namespace-local nftables output default drop.
- WireGuard-only egress allowlist.
- Strict DNS blocked-port policy (`53`, `853`, `5353`, `5355`) by default.
- IPv6 fail-closed namespace default unless explicitly tunneled.
- Resolver and nsswitch bind mounts in strict mode, with inaccessible host
  resolver helper paths.

## Operational constraints

- Socket-activated services are rejected because this module only rewrites
  `systemd.services` units.
- WireGuard backend support is limited to `networking.wireguard.interfaces`.
- Applications that query host resolver APIs directly over D-Bus are not fully
  covered unless bus access is also constrained.
