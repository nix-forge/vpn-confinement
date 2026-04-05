# vpn-confinement

[![CI](https://github.com/IanHollow/vpn-confinement/actions/workflows/ci.yml/badge.svg)](https://github.com/IanHollow/vpn-confinement/actions/workflows/ci.yml)

Fail-closed WireGuard confinement for selected NixOS systemd services.

It provides strong protection against classic IP/DNS leaks by combining network
namespaces, namespace-local nftables, strict DNS controls, and lifecycle
teardown via `BindsTo=`. It does not claim blanket prevention of arbitrary
DoH/DoQ-style traffic unless you use destination-constrained allowlisting.

## Security properties

- Per-service and per-socket opt-in (`systemd.services.<name>.vpn.enable`,
  `systemd.sockets.<name>.vpn.enable`).
- Namespace-scoped trust boundary (`one namespace = one DNS/firewall policy`).
- Namespace-local nftables default drop with tunnel-only policy.
- Strict DNS mode pins resolver files and blocks classic DNS-like leak ports
  (`53`, `853`, `5353`, `5355`).
- IPv6 is fail closed by default.
- Tunnel or namespace loss tears down dependent confined units.

## Profiles

- `balanced`: secure defaults with explicit compatibility escape hatches.
- `highAssurance`: stricter policy with assertion-based enforcement.

`highAssurance` requires:

- `dns.mode = "strict"`
- `egress.mode = "allowList"`
- non-empty `egress.allowedCidrs` (destination-constrained egress)
- non-root service execution by default (`DynamicUser = true` or non-root
  `User`), unless explicitly overridden with
  `systemd.services.<name>.vpn.allowRootInHighAssurance = true`
- literal WireGuard endpoints (hostname endpoints rejected)
- `allowedIPsAsRoutes = true`

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
    peers = [
      {
        publicKey = "...";
        endpoint = "198.51.100.10:51820";
        allowedIPs = [ "0.0.0.0/0" ];
      }
    ];
  };

  systemd.services.my-service = {
    serviceConfig.DynamicUser = true;
    vpn.enable = true;
  };
}
```

## Hardened example

```nix
{
  imports = [ vpn-confinement.nixosModules.default ];

  services.vpnConfinement = {
    enable = true;
    namespaces.vpnapps = {
      enable = true;
      securityProfile = "highAssurance";
      wireguard.interface = "wg0";
      dns = {
        mode = "strict";
        servers = [ "10.64.0.1" ];
      };
      egress = {
        mode = "allowList";
        allowedTcpPorts = [ 443 80 ];
        allowedUdpPorts = [ 123 ];
        allowedCidrs = [
          "1.1.1.1/32"
          "9.9.9.9/32"
        ];
      };
      ipv6.mode = "disable";
    };
  };

  systemd.services.example = {
    serviceConfig.DynamicUser = true;
    vpn = {
      enable = true;
      hardeningProfile = "strict";
    };
  };
}
```

## Threat coverage summary

| Threat                                     | Covered when                                                  |
| ------------------------------------------ | ------------------------------------------------------------- |
| Classic resolver and DNS-port leaks        | `dns.mode = "strict"`                                         |
| DoH/DoQ to arbitrary internet destinations | only constrained by `egress.allowedCidrs` in `allowList` mode |
| IPv6 leak paths                            | `ipv6.mode = "disable"`                                       |
| Tunnel drop / namespace teardown           | default `BindsTo=` propagation                                |

## API highlights

- Namespace options: `services.vpnConfinement.namespaces.<name>.*`
- Per-service options: `systemd.services.<name>.vpn.*`
- Per-socket options: `systemd.sockets.<name>.vpn.*`
- Advanced service escape hatches:
  - `vpn.extraAddressFamilies`
  - `vpn.extraNetworkInterfaces`

For complete reference and security notes, see:

- `docs/options.md`
- `docs/threat-model.md`
- `docs/architecture.md`

## Endpoint pinning note

WireGuard endpoint pinning is not implemented yet. Robust pinning likely
requires policy in the socket birthplace namespace (often host/init namespace),
not only inside the confined namespace. See `docs/threat-model.md` for details.

## Compatibility baseline

- Supported baseline: NixOS 26.05+

## Development

- Format: `nix fmt`
- Validate: `nix flake check --show-trace --system <x86_64-linux|aarch64-linux>`
- Runtime VM tests run on `x86_64-linux` checks; non-VM eval/reject checks run
  on both `x86_64-linux` and `aarch64-linux`.

## License

MIT
