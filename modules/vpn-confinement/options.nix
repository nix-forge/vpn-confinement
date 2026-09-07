{ lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkDefault
    mkIf
    mkMerge
    types
    ;
  vpnLib = import ./lib.nix { inherit lib; };
in
{
  options.services.vpnConfinement = {
    enable = mkEnableOption "VPN confinement for selected systemd services";

    defaultNamespace = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional default namespace name used by vpn-enabled services and sockets when they do not set vpn.namespace.";
    };

    namespaces = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, config, ... }: {
            imports = [ (lib.mkAliasOptionModule [ "ingress" "fromHost" "tcp" ] [ "publishToHost" "tcp" ]) ];
            options = {
              enable = mkEnableOption "VPN confinement namespace";

              securityProfile = mkOption {
                type = types.enum [
                  "balanced"
                  "highAssurance"
                ];
                default = "balanced";
                description = ''
                  Opinionated namespace security preset. "highAssurance" turns
                  weaker compatibility paths into explicit evaluation failures.
                '';
              };

              wireguard = {
                allowInsecureKeyMaterial = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Compatibility exception for inline or Nix-store WireGuard keys. Rejected in highAssurance. Prefer root-owned persistent key files or a runtime secret manager.";
                };
                interface = mkOption {
                  type = types.str;
                  default = "wg0";
                  description = "WireGuard interface name managed for this confinement namespace.";
                };

                socketNamespace = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = ''
                    Advanced WireGuard UDP socket birthplace namespace. Leave this
                    unset for the default path, or use "init" when the socket must
                    stay in the host namespace.
                  '';
                };

                allowHostnameEndpoints = mkOption {
                  type = types.bool;
                  default = false;
                  description = ''
                    Advanced compatibility opt-in for hostname:port WireGuard
                    peer endpoints. Literal IP endpoints remain the secure
                    default.
                  '';
                };

                endpointPinning = {
                  enable = mkOption {
                    type = types.bool;
                    default = false;
                    description = ''
                      Pin WireGuard outer UDP egress to configured literal peer
                      endpoints using host-side nftables policy in the socket
                      birthplace namespace path supported by this module.
                    '';
                  };

                  fwMark = mkOption {
                    type = types.nullOr types.ints.unsigned;
                    default = null;
                    description = ''
                      Optional fwMark used to identify WireGuard outer UDP traffic
                      for endpoint pinning. Null auto-derives a deterministic
                      non-zero mark from the interface name.
                    '';
                  };
                };
              };

              dns = {
                mode = mkOption {
                  type = types.enum [
                    "strict"
                    "compat"
                  ];
                  default = "strict";
                  description = ''
                    DNS containment mode. "strict" is the secure default; "compat"
                    weakens resolver containment for workloads that need it.
                  '';
                };

                servers = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Allowed DNS resolver IPs used to generate namespace-local resolv.conf in strict mode.";
                };

                search = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "DNS search suffixes written to generated resolver config; values must be valid domain-style suffixes.";
                };

                allowHostResolverIPC = mkOption {
                  type = types.bool;
                  default = false;
                  description = ''
                    Allow strict-mode services to reach host resolver helper IPC such
                    as nscd or system D-Bus. This weakens DNS containment.
                  '';
                };
              };

              ipv6.mode = mkOption {
                type = types.enum [
                  "disable"
                  "tunnel"
                ];
                default = "disable";
                description = "IPv6 policy inside this namespace: fail-closed disable, or tunnel when WireGuard IPv6 routes are configured.";
              };

              ingress = {
                fromTunnel.tcp = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                  description = "TCP listener ports accepted from the WireGuard interface into the namespace.";
                };

                fromTunnel.udp = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                  description = "UDP listener ports accepted from the WireGuard interface into the namespace.";
                };
              };

              publishToHost.tcp = mkOption {
                type = types.listOf types.port;
                default = [ ];
                description = ''
                  Simplified host publish abstraction for namespace services.
                  The legacy ingress.fromHost.tcp name is an alias. Non-empty values
                  automatically enable effective host-link wiring.
                '';
              };

              egress = {
                mode = mkOption {
                  type = types.enum [
                    "allowAllTunnel"
                    "allowList"
                  ];
                  default = "allowAllTunnel";
                  description = "Tunnel egress policy: allow all tunnel traffic or only explicit allowlist rules.";
                };

                allowedTcpPorts = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                  description = "Allowed TCP destination ports for allowList mode.";
                };

                allowedUdpPorts = mkOption {
                  type = types.listOf types.port;
                  default = [ ];
                  description = "Allowed UDP destination ports for allowList mode.";
                };

                allowedCidrs = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Allowed destination CIDRs (or literal IPs) for allowList mode. Required in highAssurance.";
                };

                allowEssentialIcmp = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Allow narrow ICMP/ICMPv6 error traffic for allowList tunnel egress when allowedCidrs are configured.";
                };
              };

              hostLink = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Enable host-to-namespace veth link for controlled host ingress use cases.";
                };

                hostIf = mkOption {
                  type = types.str;
                  default = vpnLib.deriveHostLinkInterfaceName "host" name;
                  description = "Host-side veth interface name for hostLink mode.";
                };

                nsIf = mkOption {
                  type = types.str;
                  default = vpnLib.deriveHostLinkInterfaceName "ns" name;
                  description = "Namespace-side veth interface name for hostLink mode.";
                };

                subnetIPv4 = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Optional hostLink /30 subnet base. Null auto-allocates a deterministic subnet from 169.254.0.0/16.";
                };
              };

              derived.hostLink = {
                subnetIPv4 = mkOption {
                  type = types.nullOr types.str;
                  readOnly = true;
                  description = "Computed effective hostLink subnet (/30) for this namespace.";
                };

                hostAddressIPv4 = mkOption {
                  type = types.nullOr types.str;
                  readOnly = true;
                  description = "Computed host-side IPv4 address for the effective hostLink subnet.";
                };

                nsAddressIPv4 = mkOption {
                  type = types.nullOr types.str;
                  readOnly = true;
                  description = "Computed namespace-side IPv4 address for the effective hostLink subnet.";
                };
              };
            };

            config =
              let
                policy = vpnLib.effectiveNamespace name config;
                withEffectiveHostLink = policy.withHostLink;
                derivedSubnet = policy.hostLink.subnetIPv4;
                derivedPair = policy.hostLink;
              in
              mkMerge [
                (mkIf (config.securityProfile == "highAssurance") {
                  dns.mode = mkDefault "strict";
                  dns.allowHostResolverIPC = mkDefault false;
                  egress.mode = mkDefault "allowList";
                  ipv6.mode = mkDefault "disable";
                  wireguard.allowHostnameEndpoints = mkDefault false;
                })
                {
                  derived.hostLink = {
                    subnetIPv4 = if withEffectiveHostLink then derivedSubnet else null;
                    hostAddressIPv4 =
                      if withEffectiveHostLink && derivedPair != null then derivedPair.hostAddressIPv4 else null;
                    nsAddressIPv4 =
                      if withEffectiveHostLink && derivedPair != null then derivedPair.nsAddressIPv4 else null;
                  };
                }
              ];
          }
        )
      );
      default = { };
      description = "Namespace-scoped confinement policies keyed by namespace name.";
    };
  };

}
