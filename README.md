<div align="center">
  <img src="logo.png" alt="vpn-confinement logo" width="220" />

  <h1>VPN Confinement</h1>

  <p>
    <a href="https://github.com/IanHollow/vpn-confinement/issues">
      <img src="https://img.shields.io/github/issues/IanHollow/vpn-confinement?style=for-the-badge&labelColor=303446&color=f5a97f" alt="Open issues" />
    </a>
    <a href="https://github.com/IanHollow/vpn-confinement/stargazers">
      <img src="https://img.shields.io/github/stars/IanHollow/vpn-confinement?style=for-the-badge&labelColor=303446&color=c6a0f6" alt="GitHub stars" />
    </a>
    <a href="https://github.com/IanHollow/vpn-confinement">
      <img src="https://img.shields.io/github/repo-size/IanHollow/vpn-confinement?style=for-the-badge&labelColor=303446&color=ea999c" alt="Repository size" />
    </a>
    <a href="https://github.com/IanHollow/vpn-confinement/blob/main/LICENSE">
      <img src="https://img.shields.io/static/v1?style=for-the-badge&label=License&message=MIT&labelColor=303446&color=a6da95" alt="MIT license" />
    </a>
    <a href="https://nixos.org">
      <img src="https://img.shields.io/badge/NixOS-unstable-91d7e3?style=for-the-badge&labelColor=303446&logo=nixos&logoColor=white" alt="NixOS unstable" />
    </a>
  </p>

  <p>
    <a href="https://builtwithnix.org">
      <img src="https://builtwithnix.org/badge.svg" alt="Built with Nix" />
    </a>
  </p>
</div>

Fail-closed WireGuard confinement for selected NixOS systemd services.

`vpn-confinement` places selected services into dedicated network namespaces
with namespace-local nftables policy, generated resolver configuration, and
systemd lifecycle wiring so tunnel or namespace loss propagates cleanly to
confined workloads.

The project currently targets NixOS unstable.

It is intended for the common NixOS case where only specific services should use
VPN egress while the host and other workloads remain on normal networking.

## Documentation

- Docs site: https://ianhollow.github.io/vpn-confinement/
- Architecture: `site/src/content/docs/architecture.md`
- Threat model: `site/src/content/docs/threat-model.md`
- Generated options reference:
  `site/src/content/docs/reference/options-generated.md`

Canonical docs live in `site/src/content/docs/`. Root community docs are synced
into the docs site during docs builds.

## Why it exists

- Confine only the services that should use the tunnel.
- Keep host networking unchanged for non-confined workloads.
- Apply DNS and firewall policy at the namespace boundary.
- Prefer fail-closed teardown when the namespace or tunnel disappears.

## Quick start

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

For exact option names and defaults, start with the generated options reference
in `site/src/content/docs/reference/options-generated.md`.

## Security model

- Opt-in model per service or socket (`systemd.services.<name>.vpn.enable`,
  `systemd.sockets.<name>.vpn.enable`).
- The trust boundary is the namespace
  (`one namespace = one DNS/firewall policy`).
- Namespace-local nftables uses deny-by-default tunnel policy.
- `dns.mode = "strict"` blocks classic DNS-like leak ports (`53`, `853`, `5353`,
  `5355`) and pins resolver configuration.
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
