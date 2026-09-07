---
title: Transmission through a VPN
description: Persistent secrets, downloads, and an authenticated local Web UI
---

This recipe runs Transmission in a VPN namespace while Nginx stays on the host.
Downloads use WireGuard. The Web UI listens on host loopback and requires a
username and password. Other host services keep their normal networking.

You need NixOS unstable, a provider-supplied WireGuard configuration, and root
access to install runtime secrets. The example's endpoint and public key are
placeholders. They cannot connect to a provider.

## Add the module and example

Declare the input in your existing flake:

```nix
inputs.vpn-confinement.url = "github:nix-forge/vpn-confinement";
inputs.vpn-confinement.inputs.nixpkgs.follows = "nixpkgs";
```

Copy [`examples/transmission.nix`](https://github.com/nix-forge/vpn-confinement/blob/main/examples/transmission.nix)
into your configuration directory. Include it alongside the module in your
existing `nixosSystem.modules` list:

```nix
modules = [
  inputs.vpn-confinement.nixosModules.default
  ./transmission.nix
  ./configuration.nix
];
```

In the copied example, replace the interface address, peer public key, endpoint,
and DNS address with values from your provider. Keep the endpoint as a literal
IP address. Do not paste private keys into Nix expressions or tracked files.

The example uses broad tunnel egress for changing torrent peer addresses and
strict service hardening. A destination allowlist is useful for an application
with known remote servers, but generally does not fit a public torrent swarm.

## Install persistent secrets

The example reads two root-owned files outside your Nix checkout and the Nix store:

- `/var/lib/vpn-confinement/secrets/vpn-downloads.key`, your provider's private key.
- `/var/lib/vpn-confinement/secrets/transmission-rpc.json`, the Web UI credentials.

Install the key from an existing private file. For the first setup, create the credentials file and
edit it without putting the password in shell history:

```bash
sudo install -d -m 0700 /var/lib/vpn-confinement/secrets
sudo install -m 0600 -o root -g root /path/to/private-key /var/lib/vpn-confinement/secrets/vpn-downloads.key
sudo install -m 0600 -o root -g root /dev/null /var/lib/vpn-confinement/secrets/transmission-rpc.json
sudoedit /var/lib/vpn-confinement/secrets/transmission-rpc.json
```

Use this JSON shape with your own credentials:

```json
{
  "rpc-username": "your-user-name",
  "rpc-password": "your-unique-password"
}
```

Keep both files owned by root with mode `0600`. These files survive reboot. Include them in your
private backup plan. On hosts with ephemeral `/var/lib`, put this directory on persistent storage.
The example declares the directories but never creates or overwrites your secrets.

Use quoted string paths. A Nix path literal can copy a key into the world-readable store. The module
rejects inline keys and store-backed key paths by default in both profiles. The compatibility option
`wireguard.allowInsecureKeyMaterial` is rejected by `highAssurance`.

NixOS Transmission uses a privileged preparation command to merge the root-owned RPC credentials
into its private settings file. This trusted preparation runs separately from the application
process. The doctor reports it as a privileged lifecycle command. Keep the script supplied by the
upstream module under your configuration's control.

To rotate a key, install the replacement with the same ownership and permissions, then restart
`wireguard-wg-downloads.service`. To rotate RPC credentials, edit the JSON and restart
`transmission.service`. A missing file causes startup to fail. Restore it and restart the affected
unit; never switch the application to host networking as a recovery step.

An existing secret manager may instead provision runtime files. Override `privateKeyFile` and
`credentialsFile` with its generated paths and order the consuming units after its provisioning
unit. The persistent-file recipe above needs no additional flake input or provisioning daemon.

## Start and verify

Apply your configuration with your normal `nixos-rebuild switch` command, then run:

```bash
sudo vpn-confinement-doctor downloads
systemctl status transmission.service wireguard-wg-downloads.service
```

Open [the local Web UI](http://127.0.0.1:9091/transmission/web/). From another
computer, use an SSH tunnel to the NixOS host:

```bash
ssh -L 9091:127.0.0.1:9091 your-user@your-nixos-host
```

Then open that same local URL on your computer. The recipe does not expose the
UI on the LAN or the VPN interface. For a shared LAN deployment, use an explicit
reverse proxy with authentication and TLS.

Downloads persist in `/var/lib/transmission/Downloads`. Transmission owns its
state and download directories. Grant a media service access through a dedicated
group or ACL if needed; do not make the directories world-writable.

The diagnostic command makes no Internet request. An installed firewall and a
recent handshake are useful evidence, but do not prove every application path
is safe. See [Diagnostics](../diagnostics/) for the checks and limits.

## Optional incoming peer connections

The Web UI's `publishToHost.tcp = [ 9091 ]` is independent of a provider-forwarded
peer port. It neither requests a provider mapping nor opens the host's physical
network firewall.

If your provider assigns a static incoming port, set the same port in all three
places. This example uses `51413`; replace it with the allocated value:

```nix
services.transmission.settings.peer-port = 51413;
services.vpnConfinement.namespaces.downloads.ingress.fromTunnel = {
  tcp = [ 51413 ];
  udp = [ 51413 ];
};
```

Keep Transmission's router UPnP/NAT-PMP feature disabled. Provider lease renewal
is a separate integration, and is not implemented by this module. Providers that
allocate changing ports require coordinated renewal, firewall updates, and app
updates. An expired mapping reduces inbound reachability; it must not cause
clearnet fallback.

## Outages and restarts

A remote VPN outage leaves Transmission running with traffic blocked or stalled.
Stopping the managed WireGuard unit stops its dependent services. Restarting that
unit restarts previously active confined services and sockets:

```bash
sudo systemctl restart wireguard-wg-downloads.service
```

A separate stop followed by a start does not automatically start every previously
stopped application. Start `transmission.service` explicitly in that case.

After the first successful activation, reboot and repeat the doctor and Web UI checks.

The VM test for this recipe checks startup, persistent credentials across reboot, authenticated
RPC through
the local proxy, process namespace attachment, DNS, writable storage, and a
managed WireGuard restart. It uses disposable test secrets. A separate application privacy VM
transfers a locally seeded
torrent and exercises libc DNS, tunnel outage, and recovery. Neither test contacts a commercial VPN.
