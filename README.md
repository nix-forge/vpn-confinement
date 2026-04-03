# vpn-confinement

NixOS module for confining selected systemd services to a WireGuard-routed
network namespace.

## Features

- Per-service opt-in via `systemd.services.<name>.vpn.enable`
- One authoritative service API under `systemd.services.<name>.vpn.*`
- Namespace-scoped policy (`one namespace = one trust domain`)
- Native NixOS WireGuard integration via `networking.wireguard.interfaces`
- Namespace-local nftables kill-switch
- Namespace DNS policy with strict/relaxed modes and leak-port blocking
- IPv6 fail-closed default (`disable` unless explicitly tunneled)
- Runtime fail-closed service lifecycle with `BindsTo=wireguard-<if>.service`
- Explicit rejection of socket-activated services

## Quick start

```nix
{
  imports = [ vpn-confinement.nixosModules.default ];

  services.vpnConfinement = {
    enable = true;
    namespaces.vpnapps = {
      enable = true;
      wireguard.interface = "wg0";
      wireguard.socketNamespace = null;
      hostLink.enable = true;
      hostLink.hostAddressIPv4 = "10.231.0.1";
      hostLink.nsAddressIPv4 = "10.231.0.2";
      dns = {
        mode = "strict";
        servers = [ "10.64.0.1" ];
      };
      ipv6.mode = "disable";
    };
  };

  networking.wireguard.interfaces.wg0 = {
    privateKeyFile = "/run/keys/wg.key";
    ips = [ "10.0.0.2/32" ];
    peers = [
      {
        publicKey = "...";
        endpoint = "198.51.100.1:51820";
        allowedIPs = [ "0.0.0.0/0" ];
      }
    ];
  };

  systemd.services.my-service.vpn.enable = true;
}
```

## API notes

- Per-service config lives at `systemd.services.<name>.vpn.*`:
  - `namespace`, `dependsOnTunnel`, `hardeningProfile`
  - `ingress.fromHost.tcp`, `ingress.fromTunnel.tcp`, `ingress.fromTunnel.udp`
- Namespace defaults live at `services.vpnConfinement.namespaces.<name>.*`,
  including:
  - `wireguard.interface` and `wireguard.socketNamespace`
  - `dns.mode = "strict" | "relaxed"`
  - `dns.blockedPorts = [ 53 853 5353 5355 ]` (when mode is `strict`)
  - `hostLink.enable = false` by default (`lo + wg` only unless needed)
  - `ipv6.mode = "disable" | "tunnel"` (default: `disable`)
  - `egress.extraTcp`, `egress.extraUdp`, `egress.extraCidrs`, `egress.rawRules`
- A service is confined when `systemd.services.<name>.vpn.enable = true`; no
  global service target list exists.
- DNS and firewall policy are namespace-wide. If two services need different
  leak rules, put them in different namespaces.
- Strict DNS also binds namespace-local `nsswitch.conf` with `hosts: files dns`
  and blocks host resolver helper paths.
- Only `systemd.services` units are supported; socket-activated services are
  rejected.

## DNS caveat

- Strict DNS protects common resolver paths (`resolv.conf`, `nsswitch`, and
  `/run/systemd/resolve` helpers) within confined services.
- Applications that directly call host resolver APIs over D-Bus are outside this
  guarantee unless the service also blocks system bus access.

## License

MIT
