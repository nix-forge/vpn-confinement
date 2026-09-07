<div align="center">
  <img src="logo.png" alt="vpn-confinement logo" width="220" />

  <h1>VPN Confinement</h1>

  <div>
    <a href="https://github.com/nix-forge/vpn-confinement/issues">
      <img src="https://img.shields.io/github/issues/nix-forge/vpn-confinement?style=for-the-badge&labelColor=303446&color=f5a97f" alt="Open issues" />
    </a>
    <a href="https://github.com/nix-forge/vpn-confinement/stargazers">
      <img src="https://img.shields.io/github/stars/nix-forge/vpn-confinement?style=for-the-badge&labelColor=303446&color=c6a0f6" alt="GitHub stars" />
    </a>
    <a href="https://github.com/nix-forge/vpn-confinement">
      <img src="https://img.shields.io/github/repo-size/nix-forge/vpn-confinement?style=for-the-badge&labelColor=303446&color=ea999c" alt="Repository size" />
    </a>
    <a href="https://github.com/nix-forge/vpn-confinement/blob/main/LICENSE">
      <img src="https://img.shields.io/static/v1?style=for-the-badge&label=License&message=MIT&labelColor=303446&color=a6da95" alt="MIT license" />
    </a>
    <a href="https://nixos.org">
      <img src="https://img.shields.io/badge/NixOS-unstable-91d7e3?style=for-the-badge&labelColor=303446&logo=nixos&logoColor=white" alt="NixOS unstable" />
    </a>
  </div>
</div>

Fail-closed WireGuard confinement for selected NixOS systemd services.

Give each service group a network namespace with WireGuard, default-drop
nftables, and its own DNS policy. Other host services keep their normal routes.
The project targets NixOS unstable and the `networking.wireguard.interfaces`
backend.

## Start here

Follow the [complete Transmission recipe](https://nix-forge.github.io/vpn-confinement/guides/transmission/)
for a working application with persistent downloads, persistent secrets, and an
authenticated local Web UI. The actual configuration is in
[`examples/transmission.nix`](examples/transmission.nix) and is covered by a VM test.

For an existing service, add the flake input:

```nix
inputs.vpn-confinement.url = "github:nix-forge/vpn-confinement";
inputs.vpn-confinement.inputs.nixpkgs.follows = "nixpkgs";
```

Import `inputs.vpn-confinement.nixosModules.default`, configure the namespace and
WireGuard interface using your provider's values, and select the service:

```nix
systemd.services.your-service.vpn = {
  enable = true;
  namespace = "downloads";
};
```

A service or socket declaring `vpn.enable = true` requires the global module to
be enabled. Contradictory settings fail evaluation instead of dropping confinement.

Inspect your deployment without sending external requests or exposing keys:

```bash
sudo vpn-confinement-doctor
sudo vpn-confinement-doctor downloads --json
```

## Security and privacy

Namespace routing and nftables prevent ordinary clearnet fallback. Strict DNS
and IPv6 disable are defaults. Inline and store-backed WireGuard keys are rejected by default.
Keep file-based secrets outside
the world-readable Nix store.

An ISP still sees the VPN connection and traffic patterns. This is protection
against direct traffic leakage, not a promise of anonymity. Host sockets,
privileged helpers, application tracking, and the VPN operator require separate
consideration. Read the [threat model](site/src/content/docs/threat-model.md).

A remote VPN outage can leave an application running with traffic stalled.
Stopping a managed WireGuard unit stops dependent services; restarting it
restarts previously active consumers. See the
[architecture](site/src/content/docs/architecture.md) for exact lifecycle behavior.

Use `balanced` for services such as torrents that need changing destinations.
Service hardening can independently be set to `strict`. Use `highAssurance` for
narrow destination allowlists and stronger assertions.

`publishToHost.tcp` permits host ingress over a veth. It does not create a localhost
listener, reverse proxy, or VPN-provider port forward. The Transmission example
provides the local proxy explicitly.

## Documentation

- [Setup and Transmission](site/src/content/docs/guides/transmission.md)
- [Diagnostics](site/src/content/docs/guides/diagnostics.md)
- [Common deployments](site/src/content/docs/guides/common-deployments.md)
- [Generated options](site/src/content/docs/reference/options-generated.md)
- [Performance measurements](site/src/content/docs/guides/performance.md)
- [Documentation site](https://nix-forge.github.io/vpn-confinement/)

## Development

- Format: `nix fmt`
- Check: `nix flake check --show-trace --system x86_64-linux`
- Regenerate options: `bash scripts/generate-options-doc.sh x86_64-linux`
- Build docs: `bun install --cwd site --frozen-lockfile && bun run --cwd site build`
- Run the optional local benchmark: `nix build .#vpn-benchmark`

Runtime VM checks run on x86_64 Linux. ARM checks currently evaluate configuration;
they do not provide equivalent VM coverage. The benchmark's raw results are in
`result/benchmark.json` and describe a synthetic local tunnel.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
Licensed under [MIT](LICENSE).
