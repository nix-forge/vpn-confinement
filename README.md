# vpn-confinement

NixOS module for confining selected systemd services to a WireGuard-routed
network namespace.

## Why network namespaces

`vpn-confinement` uses a dedicated network namespace per trust domain. This
matches WireGuard's namespace model and gives a stronger fail-closed boundary
than policy-routing-only setups for the "only these services use VPN" case.

## Features

- Per-service opt-in via `systemd.services.<name>.vpn.enable`
- Per-socket opt-in via `systemd.sockets.<name>.vpn.enable`
- Service-level API for namespace attachment and hardening only
- Namespace-scoped policy (`one namespace = one trust domain`)
- Native NixOS WireGuard integration via `networking.wireguard.interfaces`
- Namespace-local nftables kill-switch
- Namespace DNS policy with strict/relaxed modes and leak-port blocking
- IPv6 fail-closed default (`disable` unless explicitly tunneled)
- Runtime fail-closed lifecycle with `BindsTo=wireguard-<if>.service`
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
    dynamicEndpointRefreshSeconds = 300;
    peers = [
      {
        publicKey = "...";
        endpoint = "vpn.example.com:51820";
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
  - `wireguard.interface`
  - `wireguard.socketNamespace = null | "init" | <name>`
  - `dns.mode = "strict" | "relaxed"`
  - `dns.allowResolverHelpers = false` by default
  - strict DNS blocks `53`, `853`, `5353`, and `5355`
  - `hostLink.enable = false` by default (`lo + wg` only unless needed)
  - `hostLink.subnetIPv4 = null | "x.x.x.x/30"` (`null` auto-allocates from
    `169.254.0.0/16`)
  - `ipv6.mode = "disable" | "tunnel"` (default: `disable`)
  - `egress.mode = "allowAllTunnel" | "allowList"`
  - `egress.allowedTcpPorts`, `egress.allowedUdpPorts`, `egress.allowedCidrs`
- A service is confined when `systemd.services.<name>.vpn.enable = true`; no
  global service target list exists.
- DNS and firewall policy are namespace-wide. If two services need different
  leak rules, put them in different namespaces.
- Strict DNS also binds namespace-local `nsswitch.conf` with
  `hosts: files myhostname dns` and blocks host resolver helper paths.
- Strict DNS bind-mounts immutable store-generated resolver files directly onto
  `/etc/resolv.conf` and `/etc/nsswitch.conf` inside the confined unit.
- `networking.wireguard.interfaces.<if>.peers.*.endpoint` may use literal IP
  endpoints (`IPv4:port` or `[IPv6]:port`) or hostname endpoints
  (`hostname:port`). Hostname endpoints require refresh
  (`dynamicEndpointRefreshSeconds > 0` at interface or peer level).
- Hostname endpoint refresh is owned by upstream
  `networking.wireguard.interfaces.<if>`, not the confinement namespace API.
- The module warns when a vpn-enabled service still runs as root without
  `DynamicUser = true` or an explicit non-root `User`.

## Compatibility vs strict

- `dns.mode = "strict"` is the secure default: namespace resolver bind mounts,
  resolver helper path blocking, and DNS-like leak-port blocking.
- `dns.mode = "relaxed"` removes strict resolver pinning and leak-port blocking
  for compatibility with software that needs custom resolver flows.
- `dns.allowResolverHelpers = true` is the expert escape hatch for strict mode
  workloads that still need host resolver helpers like nscd or system D-Bus.
- If an application intentionally bypasses system resolver behavior, use
  `egress.mode = "allowList"` with constrained `allowedCidrs`.

## Threat model notes

- Namespace isolation is the primary boundary; services inside a namespace share
  DNS/firewall policy.
- `hostLink` is a convenience mode for host-to-namespace connectivity. It is
  less pure than a tunnel-only namespace and should stay disabled unless needed.
- nftables is intentionally kept as the enforcement backend; the static ruleset
  design is appropriate for this module's policy model.

## DNS caveat

- Strict DNS protects common resolver paths (`resolv.conf`, `nsswitch`, and
  `/run/systemd/resolve` helpers) within confined services.
- Strict DNS blocks classic DNS-like ports (`53`, `853`, `5353`, `5355`) except
  configured resolver paths when `dns.mode = "strict"`.
- Strict mode defaults to maximal helper blocking
  (`dns.allowResolverHelpers = false`), including `/run/nscd` and system D-Bus
  sockets for confined services.
- Applications that directly call host resolver APIs over D-Bus are outside this
  guarantee when `dns.allowResolverHelpers = true`.
- Set `dns.allowResolverHelpers = true` only for workloads that need host
  resolver helper access and accept the weaker DNS containment.
- DNS-over-HTTPS/DNS-over-QUIC over arbitrary destinations is not fully
  preventable without destination allowlisting (for example
  `egress.mode = "allowList"` with constrained `allowedCidrs`).

## Compatibility baseline

- Supported baseline: NixOS 26.05 or newer.
- This baseline assumes modern systemd support for namespace controls used by
  this module (notably `NetworkNamespacePath=` and
  `RestrictNetworkInterfaces=`).

## Troubleshooting

- If WireGuard client traffic does not pass on NixOS, reverse-path filtering can
  be the issue. Try `networking.firewall.checkReversePath = "loose";` as a
  troubleshooting step.

## Socket activation pattern

- For host-facing socket-activated services, the simplest pattern is usually:
  keep the `.socket` in the host namespace and confine only the `.service`.
- This lets systemd accept connections on host sockets while service-created
  outbound traffic stays inside VPN confinement.
- Enable `systemd.sockets.<name>.vpn.*` only when the listening socket itself
  must live inside the VPN namespace.

## Development

- Format: `nix fmt`
- Validation: `nix flake check`

## License

MIT
