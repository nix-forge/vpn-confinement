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
- WireGuard egress policy with explicit namespace mode (`allowAllTunnel` or
  `allowList`).
- Strict DNS blocked-port policy (`53`, `853`, `5353`, `5355`) by default.
- IPv6 fail-closed namespace default unless explicitly tunneled.
- Resolver and nsswitch bind mounts in strict mode, with inaccessible host
  resolver helper paths.
- Strict DNS default blocks common host resolver helpers (`/run/nscd` and system
  D-Bus sockets); `dns.compatibilityMode = true` is the compatibility opt-out.
- WireGuard peer endpoints may be hostnames when periodic endpoint refresh is
  enabled.

## Strict DNS caveat (important)

Strict DNS prevents libc/system resolver leaks and blocks classic
DNS/DoT/mDNS/LLMNR leaks. It does not fully control applications that
intentionally bypass `/etc/resolv.conf` or use their own encrypted DNS stack.
For those applications, use `egress.mode = "allowList"` with constrained
destination CIDRs.

## Operational constraints

- Socket and service units can both be vpn-enabled and should share the same
  namespace policy.
- WireGuard backend support is limited to `networking.wireguard.interfaces`.
- Applications that query host resolver APIs directly over D-Bus are not fully
  covered when `dns.compatibilityMode = true`.
- DoH/DoQ over generic egress is outside strict DNS guarantees unless
  destination allowlisting is configured.
- `hostLink` is a convenience mode and expands attack surface relative to a pure
  tunnel-only namespace. Keep it disabled unless host reachability is required.
