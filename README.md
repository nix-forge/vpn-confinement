# vpn-confinement

<p align="center">
  <img src="logo.png" alt="vpn-confinement logo" width="280" />
</p>

[![CI](https://github.com/IanHollow/vpn-confinement/actions/workflows/ci.yml/badge.svg)](https://github.com/IanHollow/vpn-confinement/actions/workflows/ci.yml)
[![Docs](https://github.com/IanHollow/vpn-confinement/actions/workflows/docs.yml/badge.svg)](https://github.com/IanHollow/vpn-confinement/actions/workflows/docs.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![NixOS](https://img.shields.io/badge/NixOS-26.05%2B-5277C3?logo=nixos&logoColor=white)](https://nixos.org)
[![Flake](https://img.shields.io/badge/Flake-enabled-5277C3?logo=nixos&logoColor=white)](flake.nix)

Fail-closed WireGuard confinement for selected NixOS systemd services.

`vpn-confinement` lets you keep the host on its normal network while moving
selected services into dedicated network namespaces with namespace-local
nftables policy, strict DNS controls, and teardown wiring via `BindsTo=`.

It reduces classic IP and DNS leak paths for confined services. It does not
claim blanket prevention of arbitrary DoH or DoQ over generic allowed egress
without destination-constrained allowlisting.

## Start Here

- Docs site: https://ianhollow.github.io/vpn-confinement/
- Overview: `site/src/content/docs/index.mdx`
- Architecture: `site/src/content/docs/architecture.md`
- Threat model: `site/src/content/docs/threat-model.md`
- Generated options reference:
  `site/src/content/docs/reference/options-generated.md`

Canonical docs live in `site/src/content/docs/`. Root community docs are synced
into the docs site during docs builds.

## Why This Exists

- Confine only the services that should use the VPN.
- Keep the host and non-confined workloads on normal networking.
- Put DNS and firewall policy at the namespace boundary.
- Prefer fail-closed teardown when the namespace or tunnel disappears.

## Quick Start

Add the module and opt specific services into confinement:

```nix
{inputs, ...}:
{
  imports = [ inputs.vpn-confinement.nixosModules.default ];

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

For exact option names and defaults, start with
`site/src/content/docs/reference/options-generated.md`.

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
