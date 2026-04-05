# vpn-confinement

[![CI](https://github.com/IanHollow/vpn-confinement/actions/workflows/ci.yml/badge.svg)](https://github.com/IanHollow/vpn-confinement/actions/workflows/ci.yml)

NixOS module for confining selected systemd services to a WireGuard-routed
network namespace.

## Why network namespaces

`vpn-confinement` uses a dedicated network namespace per trust domain. This
matches WireGuard's namespace model and gives a stronger fail-closed boundary
than policy-routing-only setups for the "only these services use VPN" case.

## Guarantees

- Selected services run inside a dedicated namespace instead of sharing host
  routing state.
- Namespace-local nftables remains the primary fail-closed enforcement layer.
- Strict DNS pins common resolver behavior to namespace-local generated files
  and blocks classic DNS leak ports.
- IPv6 is fail closed by default unless intentionally tunneled.
- Tunnel or namespace teardown propagates to confined units with `BindsTo=`.

## Non-goals

- Preventing every possible HTTPS-based DoH or DoQ flow without destination
  allowlisting.
- Isolating mutually untrusted services from each other inside the same
  namespace.
- Replacing nftables with policy routing or cgroup-owner packet matching as the
  main policy surface.

## Why not policy routing

- The trust boundary here is the namespace, not host-global route rules.
- WireGuard keeps its UDP socket in the namespace where that socket was born,
  while the interface itself can live in the confined namespace. This fits the
  namespace model cleanly.
- Non-confined host traffic stays on the normal network without extra owner or
  fwmark policy.

## Diagram

```text
host namespace
  |
  |  WireGuard UDP socket birthplace
  v
[ wireguard-wg0.service ]
  |
  | moves wg0 into /run/netns/vpnapps
  v
/run/netns/vpnapps
  |- confined services
  |- lo
  |- wg0 -> allowed tunnel egress
  |- nftables default-drop policy
  `- blocked leak paths: host uplinks, classic DNS ports, optional host IPC
```

## Features

- Per-service opt-in via `systemd.services.<name>.vpn.enable`
- Per-socket opt-in via `systemd.sockets.<name>.vpn.enable`
- Service-level API for namespace attachment and hardening only
- Namespace-scoped policy (`one namespace = one trust domain`)
- Native NixOS WireGuard integration via `networking.wireguard.interfaces`
- Namespace-local nftables kill-switch
- Namespace DNS policy with strict/compat modes and leak-port blocking
- Clear split between common resolver leak resistance and high-assurance egress
- IPv6 fail-closed default (`disable` unless explicitly tunneled)
- Runtime fail-closed lifecycle with namespace and WireGuard `BindsTo=`
  propagation
- Optional `vpn.restrictBind` listener allowlisting as defense in depth
- No runtime writes to `/etc` or `/etc/netns`

## Quick start

```nix
{
  imports = [ vpn-confinement.nixosModules.default ];

  services.vpnConfinement = {
    enable = true;
    defaultNamespace = "vpnapps";
    namespaces.vpnapps = {
      enable = true;
      securityProfile = "balanced";
      wireguard.interface = "wg0";
      dns = {
        mode = "strict";
        servers = [ "10.64.0.1" ];
      };
      ipv6.mode = "disable";
      egress.mode = "allowAllTunnel";
    };
  };

  networking.wireguard.interfaces.wg0 = {
    privateKeyFile = "/run/keys/wg.key";
    ips = [ "10.0.0.2/32" ];
    peers = [
      {
        publicKey = "...";
        endpoint = "198.51.100.10:51820";
        allowedIPs = [ "0.0.0.0/0" ];
      }
    ];
  };

  systemd.services.my-service.vpn = {
    enable = true;
    namespace = "vpnapps";
    hardeningProfile = "baseline";
  };
}
```

## Hardened example

```nix
{
  imports = [ vpn-confinement.nixosModules.default ];

  services.vpnConfinement = {
    enable = true;
    defaultNamespace = "vpnapps";

    namespaces.vpnapps = {
      enable = true;
      securityProfile = "highAssurance";
      wireguard.interface = "wg0";

      dns = {
        mode = "strict";
        servers = [ "10.64.0.1" ];
      };

      ipv6.mode = "disable";

      egress = {
        mode = "allowList";
        allowedTcpPorts = [ 443 80 ];
        allowedUdpPorts = [ 123 ];
        allowedCidrs = [
          "1.1.1.1/32"
          "9.9.9.9/32"
        ];
      };

      hostLink.enable = false;
    };
  };

  systemd.services.qbittorrent.vpn = {
    enable = true;
    namespace = "vpnapps";
    hardeningProfile = "strict";
  };
}
```

## API notes

- Per-service config lives at `systemd.services.<name>.vpn.*`:
  - `enable`, `namespace`, `hardeningProfile`
- Per-socket config lives at `systemd.sockets.<name>.vpn.*`:
  - `enable`, `namespace`
- Namespace defaults live at `services.vpnConfinement.namespaces.<name>.*`,
  including:
  - `securityProfile = "balanced" | "highAssurance"`
  - `wireguard.interface`
  - `wireguard.allowHostnameEndpoints = false` by default
  - `wireguard.socketNamespace = null | "init" | <name>` for advanced usage
  - `dns.mode = "strict" | "compat"`
  - `dns.allowHostResolverIPC = false` by default
  - `dns.search` must contain validated domain-style suffixes only
  - strict DNS blocks `53`, `853`, `5353`, and `5355`
  - `hostLink.enable = false` by default (`lo + wg` only unless needed)
  - `hostLink.subnetIPv4 = null | "x.x.x.x/30"` (`null` auto-allocates from
    `169.254.0.0/16`)
  - `ipv6.mode = "disable" | "tunnel"` (default: `disable`)
  - `egress.mode = "allowAllTunnel" | "allowList"`
  - `egress.allowedTcpPorts`, `egress.allowedUdpPorts`, `egress.allowedCidrs`
- Per-service hardening also includes optional
  `systemd.services.<name>.vpn.restrictBind = true` to deny undeclared
  service-created listeners when namespace ingress ports are declared.
- A service is confined when `systemd.services.<name>.vpn.enable = true`; no
  global service target list exists.
- DNS and firewall policy are namespace-wide. If two services need different
  leak rules, put them in different namespaces.
- Strict DNS also binds namespace-local `nsswitch.conf` with
  `hosts: files myhostname dns` and blocks host resolver helper paths.
- Strict DNS bind-mounts immutable store-generated resolver files directly onto
  `/etc/resolv.conf` and `/etc/nsswitch.conf` inside the confined unit.
- `wireguard.socketNamespace = "init"` is the main advanced case. Setting it to
  the same confinement namespace is rejected because the WireGuard UDP socket
  needs a birthplace namespace with an actual uplink.
- The module owns `networking.wireguard.interfaces.<if>.interfaceNamespace` for
  confinement-managed interfaces and keeps the WireGuard link inside the
  confinement namespace.
- `networking.wireguard.interfaces.<if>.socketNamespace` stays an advanced
  escape hatch for the UDP socket birthplace. Leave it unset for the default
  host/init-namespace socket behavior unless you have a specific routing need.
- The module warns when a vpn-enabled service still runs as root without
  `DynamicUser = true` or an explicit non-root `User`.
- Literal WireGuard peer endpoints are the default and recommended path.
- Hostname endpoints require explicit opt-in with
  `wireguard.allowHostnameEndpoints = true` and still require effective dynamic
  refresh (`dynamicEndpointRefreshSeconds > 0` at the interface or peer level).
- Hostname endpoint refresh remains weaker than literal IPs because it is done
  by WireGuard management units rather than the confined service.
- `networking.wireguard.interfaces.<if>.allowedIPsAsRoutes = false` is treated
  as advanced and emits a warning in `balanced`; `highAssurance` rejects it.
- `networking.wireguard.interfaces.<if>.fwMark` remains an upstream WireGuard
  escape hatch for policy-routing-heavy setups; the confinement model does not
  depend on it.
- `networking.wireguard.interfaces.<if>.mtu` remains an upstream performance
  tuning knob; this module does not add extra MTU logic.

## Profiles

- `securityProfile = "balanced"` keeps the default namespace model opinionated
  but leaves advanced compatibility paths available.
- `securityProfile = "highAssurance"` defaults `egress.mode = "allowList"` and
  turns weaker compatibility paths into assertions.
- `highAssurance` requires literal peer endpoint IPs, rejects
  `dns.allowHostResolverIPC = true`, and rejects `allowedIPsAsRoutes = false`.

## DNS modes

- `dns.mode = "strict"` means common resolver leak resistance: namespace
  resolver bind mounts, helper-path blocking, and DNS-like leak-port blocking.
- `dns.mode = "compat"` removes strict resolver pinning and leak-port blocking
  for compatibility with software that needs custom resolver flows.
- `dns.allowHostResolverIPC = true` is the expert escape hatch for strict mode
  workloads that still need host resolver helpers like nscd or system D-Bus.
- If an application intentionally bypasses system resolver behavior, destination
  allowlisting is the control that matters.
- `vpn.restrictBind = true` is optional defense in depth for services that
  should only listen on namespace-declared ingress ports. It is not the primary
  leak-prevention mechanism.

## Threat model matrix

See `docs/threat-model.md` for the full write-up. The short version is:

| Threat                                                  | dns.mode | egress.mode | hostLink | ipv6.mode | Other control                                        | Covered when                  |
| ------------------------------------------------------- | -------- | ----------- | -------- | --------- | ---------------------------------------------------- | ----------------------------- |
| Classic DNS leak (`resolv.conf`, port 53/853/5353/5355) | `strict` | any         | any      | any       | strict resolver bind mounts + nftables DNS rules     | `dns.mode = "strict"`         |
| DoH / DoQ to arbitrary destinations                     | any      | `allowList` | any      | any       | constrained `allowedCidrs`                           | allowlisted destinations only |
| Route-table / host-routing leak                         | any      | any         | any      | any       | dedicated namespace + `interfaceNamespace` ownership | default design                |
| IPv6 leak                                               | any      | any         | any      | `disable` | namespace-local IPv6 drop + sysctls                  | `ipv6.mode = "disable"`       |
| Host-to-namespace ingress exposure                      | any      | any         | `false`  | any       | no host veth path                                    | `hostLink.enable = false`     |
| Runtime tunnel drop                                     | any      | any         | any      | any       | `BindsTo=` on namespace and WireGuard units          | default design                |

## Threat model notes

- Namespace isolation is the primary boundary; services inside a namespace share
  DNS/firewall policy.
- `hostLink` is a convenience mode for host-to-namespace connectivity. It is
  less pure than a tunnel-only namespace and should stay disabled unless needed.
- nftables is intentionally kept as the enforcement backend; the static ruleset
  design is appropriate for this module's policy model.
- systemd bind restrictions are supplemental hardening only; nftables remains
  the primary enforcement layer.

## DNS caveat

- Strict DNS protects common resolver paths (`resolv.conf`, `nsswitch`, and
  `/run/systemd/resolve` helpers) within confined services.
- Strict DNS blocks classic DNS-like ports (`53`, `853`, `5353`, `5355`) except
  configured resolver paths when `dns.mode = "strict"`.
- Strict DNS does not mean "all DNS exfiltration is impossible". It means the
  common resolver paths are pinned and classic DNS-like egress is blocked.
- Strict mode defaults to maximal helper blocking
  (`dns.allowHostResolverIPC = false`), including `/run/nscd` and system D-Bus
  sockets for confined services.
- Applications that directly call host resolver APIs over D-Bus are outside this
  guarantee when `dns.allowHostResolverIPC = true`.
- Set `dns.allowHostResolverIPC = true` only for workloads that need host
  resolver helper access and accept the weaker DNS containment.
- DNS-over-HTTPS/DNS-over-QUIC over arbitrary destinations is not fully
  preventable without destination allowlisting (for example
  `egress.mode = "allowList"` with constrained `allowedCidrs`).

## WireGuard endpoint model

- The WireGuard interface itself lives in the confinement namespace via
  `interfaceNamespace`.
- The UDP socket birthplace is controlled by `socketNamespace`; leaving it unset
  keeps the standard host/init namespace behavior.
- Literal peer endpoints are strongest.
- Hostname endpoints are accepted only when
  `wireguard.allowHostnameEndpoints = true` and periodic refresh is enabled.
- Even then, they sit outside the strict DNS guarantee because the refresh is
  done by the WireGuard management units rather than the confined service.

## Compatibility baseline

- Supported baseline: NixOS 26.05 or newer.
- This baseline assumes modern systemd support for namespace controls used by
  this module (notably `NetworkNamespacePath=` and
  `RestrictNetworkInterfaces=`).
- `vpn.restrictBind` is documented as defense in depth only. This module does
  not rely on bare `SocketBindDeny=any` as a security guarantee.

## Secrets

- Prefer `sops-nix` or `agenix` for WireGuard private keys.
- Avoid passing long-lived secrets through environment variables.
- Prefer systemd credentials for service secrets that need to be mounted into a
  confined unit.

## Troubleshooting

- If WireGuard client traffic does not pass on NixOS, reverse-path filtering can
  be the issue. Try `networking.firewall.checkReversePath = "loose";` as a
  troubleshooting step.

## Socket activation pattern

- For host-facing socket-activated services, the simplest pattern is usually:
  keep the `.socket` in the host namespace and confine only the `.service`.
- This lets systemd accept connections on host sockets while service-created
  outbound traffic stays inside VPN confinement.
- That host-socket / confined-service split remains the recommended public path.
- Enable `systemd.sockets.<name>.vpn.*` only when the listening socket itself
  must live inside the VPN namespace.

## Development

- Format: `nix fmt`
- Flake checks intentionally run a small strategic Linux matrix: generated unit
  wiring plus the most important validation rejects.
- Linux CI validation:
  `nix flake check --accept-flake-config --option allow-import-from-derivation false --show-trace --system x86_64-linux`

## License

MIT
