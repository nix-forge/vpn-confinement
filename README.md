# vpn-confinement

NixOS module for confining selected systemd services to a WireGuard-routed
network namespace.

## Features

- Per-service opt-in via `systemd.services.<name>.vpn.enable`
- Native NixOS WireGuard integration with `interfaceNamespace`
- Namespace-local nftables kill-switch
- Service-local resolver binding for DNS leak resistance

## Quick start

```nix
{
  imports = [ vpn-confinement.nixosModules.default ];

  services.vpnConfinement = {
    enable = true;
    namespaces.vpnapps = {
      enable = true;
      wireguardInterface = "wg0";
      dns.servers = [ "10.64.0.1" ];
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

## License

MIT
