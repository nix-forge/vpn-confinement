# vpn-confinement

<p align="center">
  <img src=".github/assets/logo-512.png" alt="vpn-confinement logo" width="240" />
</p>

[![CI](https://github.com/IanHollow/vpn-confinement/actions/workflows/ci.yml/badge.svg)](https://github.com/IanHollow/vpn-confinement/actions/workflows/ci.yml)
[![Docs](https://github.com/IanHollow/vpn-confinement/actions/workflows/docs.yml/badge.svg)](https://github.com/IanHollow/vpn-confinement/actions/workflows/docs.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![NixOS](https://img.shields.io/badge/NixOS-26.05%2B-5277C3?logo=nixos&logoColor=white)](https://nixos.org)
[![Flake](https://img.shields.io/badge/Flake-enabled-5277C3?logo=nixos&logoColor=white)](flake.nix)

Fail-closed WireGuard confinement for selected NixOS systemd services.

`vpn-confinement` reduces classic IP and DNS leak paths by combining dedicated
network namespaces, namespace-local nftables policy, strict DNS controls, and
lifecycle teardown via `BindsTo=`. It does not claim blanket prevention of
arbitrary DoH/DoQ over generic egress without destination-constrained
allowlisting.

## Quick Start

Add the module and opt specific services into confinement:

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

## Security Model

- Opt-in model per service or socket (`systemd.services.<name>.vpn.enable`,
  `systemd.sockets.<name>.vpn.enable`).
- Namespace is the trust boundary (`one namespace = one DNS/firewall policy`).
- Namespace-local nftables uses deny-by-default tunnel policy.
- `dns.mode = "strict"` blocks classic DNS-like leak ports (`53`, `853`, `5353`,
  `5355`) and pins resolver config.
- IPv6 is fail-closed by default.
- Tunnel or namespace loss propagates teardown to dependent units.

Profiles:

- `balanced`: secure defaults with explicit compatibility escape hatches.
- `highAssurance`: stricter assertions and destination-constrained egress.

`highAssurance` requires:

- `dns.mode = "strict"`
- `egress.mode = "allowList"`
- non-empty `egress.allowedCidrs`
- non-root service execution by default (`DynamicUser = true` or non-root
  `User`), unless explicitly opted out with
  `systemd.services.<name>.vpn.allowRootInHighAssurance = true`
- literal WireGuard endpoints (hostname endpoints rejected)
- `allowedIPsAsRoutes = true`

## Documentation

- Project docs site: https://ianhollow.github.io/vpn-confinement/
- Architecture: `site/src/content/docs/architecture.md`
- Threat model: `site/src/content/docs/threat-model.md`
- Practical options guide: `site/src/content/docs/options.md`
- Generated option reference:
  `site/src/content/docs/reference/options-generated.md`
- Security policy: `site/src/content/docs/security.md`

Endpoint pinning for the WireGuard UDP socket is not yet implemented; see
`site/src/content/docs/threat-model.md` for current guarantees and caveats.

## Development

- Format: `nix fmt`
- Validate: `nix flake check --show-trace --system <x86_64-linux|aarch64-linux>`
- Regenerate options reference:
  `bash scripts/generate-options-doc.sh x86_64-linux`
- Build docs site: `bun run --cwd site build`

## Community

- Contributing guide: `CONTRIBUTING.md`
- Code of Conduct: `CODE_OF_CONDUCT.md`
- Security reporting: `site/src/content/docs/security.md`

## License

MIT
