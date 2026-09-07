# Import after inputs.vpn-confinement.nixosModules.default.
# Replace the address, endpoint, public key and DNS with your provider's values.
{ config, ... }:
let
  ns = config.services.vpnConfinement.namespaces.downloads;
in
{
  services.vpnConfinement = {
    enable = true;
    namespaces.downloads = {
      enable = true;
      wireguard.interface = "wg-downloads";
      dns.servers = [ "10.64.0.1" ];
      # The Web UI is reachable from the host at the derived veth address.
      publishToHost.tcp = [ 9091 ];
    };
  };

  networking.wireguard.interfaces.wg-downloads = {
    privateKeyFile = "/var/lib/vpn-confinement/secrets/vpn-downloads.key";
    ips = [ "10.0.0.2/32" ];
    peers = [
      {
        # Documentation placeholder, not a usable provider configuration.
        publicKey = "82mHWUiLcZUtgHut8zeEdb9Phu4AMg3b1vU6uQo2IT4=";
        endpoint = "192.0.2.1:51820";
        allowedIPs = [ "0.0.0.0/0" ];
      }
    ];
  };

  services.transmission = {
    enable = true;
    home = "/var/lib/transmission";
    openPeerPorts = false;
    openRPCPort = false;
    credentialsFile = "/var/lib/vpn-confinement/secrets/transmission-rpc.json";
    settings = {
      download-dir = "/var/lib/transmission/Downloads";
      incomplete-dir = "/var/lib/transmission/.incomplete";
      incomplete-dir-enabled = true;
      rpc-bind-address = ns.derived.hostLink.nsAddressIPv4;
      rpc-authentication-required = true;
      rpc-whitelist-enabled = true;
      rpc-whitelist = ns.derived.hostLink.hostAddressIPv4;
      rpc-host-whitelist-enabled = true;
      rpc-host-whitelist = "localhost,127.0.0.1";
      port-forwarding-enabled = false;
      peer-port-random-on-start = false;
      peer-port = 51413;
    };
  };
  systemd.services.transmission.vpn = {
    enable = true;
    namespace = "downloads";
    hardeningProfile = "strict";
  };

  # Install the two root-owned 0600 files here before the first activation.
  # These paths survive reboot. A secret manager may override them with /run paths.
  systemd.tmpfiles.rules = [
    "d /var/lib/vpn-confinement 0700 root root -"
    "d /var/lib/vpn-confinement/secrets 0700 root root -"
  ];

  # Keep the UI local. Use an SSH tunnel for access from another computer.
  services.nginx = {
    enable = true;
    virtualHosts.transmission = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 9091;
        }
      ];
      locations."/" = {
        proxyPass = "http://${ns.derived.hostLink.nsAddressIPv4}:9091";
        extraConfig = "proxy_set_header Host localhost;";
      };
    };
  };
}
