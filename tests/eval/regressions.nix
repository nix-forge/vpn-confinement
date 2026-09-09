{ pkgs, lib }:
let
  vpnLib = import ../../modules/vpn-confinement/lib.nix { inherit lib; };
  inherit (import ../../modules/vpn-confinement/firewall.nix { inherit lib; }) mkNftRules;
  eval =
    extra:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      inherit (pkgs.stdenv.hostPlatform) system;
      inherit pkgs;
      modules = [
        (import ../nixos/endpoint-pinning-mvp.nix { }).nodes.machine
        {
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          systemd.services.probe = {
            serviceConfig = {
              DynamicUser = true;
              ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
            };
            vpn = {
              enable = true;
              namespace = "vpnapps";
            };
          };
        }
        extra
      ];
    }).config;
  errors = c: map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
  hasError = text: c: builtins.any (lib.hasInfix text) (errors c);
  strict =
    extra:
    eval (
      lib.recursiveUpdate {
        services.vpnConfinement.namespaces.vpnapps = {
          securityProfile = "highAssurance";
          egress.allowedCidrs = [ "192.0.2.0/24" ];
        };
      } extra
    );
  raw = strict {
    services.vpnConfinement.namespaces.vpnapps.hostLink.enable = true;
    systemd.services.probe = {
      vpn.extraAddressFamilies = [ "AF_PACKET" ];
      serviceConfig = {
        CapabilityBoundingSet = [ "CAP_NET_RAW" ];
        AmbientCapabilities = [ "CAP_NET_RAW" ];
      };
    };
  };
  prefixed =
    field: prefix:
    strict {
      systemd.services.probe.serviceConfig.${field} = lib.mkForce "${prefix}${pkgs.coreutils}/bin/true";
    };
  privileged =
    allow:
    eval {
      services.vpnConfinement.namespaces.vpnapps = {
        securityProfile = "highAssurance";
        egress.allowedCidrs = [ "192.0.2.0/24" ];
      };
      systemd.services.probe = {
        serviceConfig.CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE CAP_NET_ADMIN" ];
        vpn.allowUnsafeCapabilities = allow;
      };
    };
  disabled = eval { services.vpnConfinement.enable = lib.mkForce false; };
  disabledSocket = eval {
    services.vpnConfinement.enable = lib.mkForce false;
    systemd.services.probe.vpn.enable = lib.mkForce false;
    systemd.sockets.probe = {
      listenStreams = [ "127.0.0.1:18080" ];
      vpn.enable = true;
    };
  };
  root = eval {
    services.vpnConfinement.namespaces.vpnapps = {
      securityProfile = "highAssurance";
      egress.allowedCidrs = [ "192.0.2.0/24" ];
    };
    systemd.services.probe.serviceConfig.User = "root";
  };
  custom = eval { services.vpnConfinement.namespaces.vpnapps.wireguard.socketNamespace = "uplink"; };
  collision = eval {
    services.vpnConfinement.namespaces."vpn.apps" = {
      enable = true;
      dns.servers = [ "10.64.0.1" ];
      wireguard = {
        interface = "wg1";
        endpointPinning.enable = true;
      };
    };
    services.vpnConfinement.namespaces."vpn-apps" = {
      enable = true;
      dns.servers = [ "10.64.0.1" ];
      wireguard = {
        interface = "wg2";
        endpointPinning.enable = true;
      };
    };
    networking.wireguard.interfaces.wg1 = {
      privateKeyFile = "/run/wg-test/1.key";
      peers = [
        {
          publicKey = "82mHWUiLcZUtgHut8zeEdb9Phu4AMg3b1vU6uQo2IT4=";
          endpoint = "192.0.2.1:51820";
        }
      ];
    };
    networking.wireguard.interfaces.wg2 = {
      privateKeyFile = "/run/wg-test/2.key";
      peers = [
        {
          publicKey = "iCXIkYspxjCzUbbO4CThCIQGu5mVoG7mWw8Ac0wprlg=";
          endpoint = "192.0.2.2:51820";
        }
      ];
    };
  };
  tableFrom =
    name:
    builtins.head (
      builtins.match ".*table inet ([A-Za-z0-9_]+).*"
        collision.systemd.services."vpn-confinement-endpoint-pinning@${name}".postStop
    );
  leftovers =
    map
      (
        settings:
        eval {
          services.vpnConfinement.namespaces.vpnapps.egress = settings // {
            mode = "allowAllTunnel";
          };
        }
      )
      [
        { allowedTcpPorts = [ 443 ]; }
        { allowedUdpPorts = [ 123 ]; }
        { allowedCidrs = [ "192.0.2.0/24" ]; }
      ];
in
{
  stable-derived-network-values =
    builtins.all
      (
        vector:
        vpnLib.hostLinkSubnetFromNamespace vector.name == vector.subnet
        && vpnLib.deriveWireguardFwMark vector.name == vector.mark
      )
      [
        {
          name = "vpnapps";
          subnet = "169.254.202.92/30";
          mark = 3209228952;
        }
        {
          name = "vpn.apps";
          subnet = "169.254.34.152/30";
          mark = 1967474855;
        }
        {
          name = "vpn-apps";
          subnet = "169.254.218.232/30";
          mark = 458438331;
        }
        {
          name = "long-namespace-generated-hostlink";
          subnet = "169.254.14.20/30";
          mark = 4261413766;
        }
        {
          name = "a";
          subnet = "169.254.4.72/30";
          mark = 3398926611;
        }
      ];
  reject-raw-packet-capability = hasError "grants capabilities" raw;
  reject-tab-separated-capability = hasError "grants capabilities" (strict {
    systemd.services.probe.serviceConfig.CapabilityBoundingSet = "CAP_NET_BIND_SERVICE\tCAP_NET_ADMIN";
  });
  reject-privileged-exec-prefixes =
    builtins.all
      (
        field:
        builtins.all (prefix: hasError "privileged command" (prefixed field prefix)) [
          "+"
          "!"
          "!!"
          "-+"
          "@:+"
          "\t+"
        ]
      )
      [
        "ExecStart"
        "ExecStartPre"
        "ExecStartPost"
        "ExecCondition"
        "ExecStop"
        "ExecStopPost"
        "ExecReload"
      ];
  reject-host-activation = hasError "host activation" (strict {
    systemd.sockets.probe.listenStreams = [ "127.0.0.1:18080" ];
  });
  reject-capability-representations =
    builtins.all
      (
        field:
        builtins.all
          (
            value:
            hasError "grants capabilities" (strict {
              systemd.services.probe.serviceConfig.${field} = value;
            })
          )
          [
            "13"
            "0xd"
            "0b1101"
            "0o15"
            "'CAP_NET_RAW'"
            "\"CAP_NET_ADMIN\""
            "~CAP_CHOWN"
          ]
      )
      [
        "CapabilityBoundingSet"
        "AmbientCapabilities"
      ];
  reject-encoded-commands =
    builtins.all
      (
        cmd:
        hasError "privileged command" (strict {
          systemd.services.probe.serviceConfig.ExecStart = lib.mkForce cmd;
        })
      )
      [
        "\"+/bin/true\""
        "\\x2b/bin/true"
        "/bin/true ; +/bin/true"
        "'!/bin/true'"
      ];
  allow-ordinary-command-arguments =
    errors (strict {
      systemd.services.probe.serviceConfig.ExecStart = lib.mkForce "-/bin/echo '+hello' '!hello'";
    }) == [ ];
  allow-command-exception =
    errors (strict {
      systemd.services.probe = {
        vpn.allowPrivilegedCommands = true;
        serviceConfig.ExecStart = lib.mkForce "+/bin/true";
      };
    }) == [ ];
  allow-host-socket-exception =
    errors (strict {
      systemd.sockets.probe.listenStreams = [ "127.0.0.1:18080" ];
      systemd.services.probe.vpn.allowHostSockets = true;
    }) == [ ];
  allow-confined-activation =
    errors (strict {
      systemd.sockets.probe = {
        listenStreams = [ "127.0.0.1:18080" ];
        vpn = {
          enable = true;
          namespace = "vpnapps";
        };
      };
    }) == [ ];
  allow-disabled-unrelated-socket =
    errors (strict {
      systemd.sockets.probe = {
        enable = false;
        listenStreams = [ "127.0.0.1:18080" ];
      };
    }) == [ ];
  reject-inherited-socket = hasError "host activation" (strict {
    systemd.sockets.other.listenStreams = [ "127.0.0.1:18080" ];
    systemd.services.probe.serviceConfig.Sockets = [ "other.socket" ];
  });
  reject-explicit-socket-target = hasError "host activation" (strict {
    systemd.sockets.other = {
      listenStreams = [ "127.0.0.1:18080" ];
      socketConfig.Service = "probe.service";
    };
  });
  reject-unknown-inherited-socket = hasError "host activation" (strict {
    systemd.services.probe.serviceConfig.Sockets = "unresolved.socket";
  });
  reject-template-activation = hasError "host activation" (strict {
    systemd.sockets.worker = {
      listenStreams = [ "127.0.0.1:18080" ];
      socketConfig.Accept = true;
    };
    systemd.services."worker@" = {
      vpn = {
        enable = true;
        namespace = "vpnapps";
      };
      serviceConfig = {
        DynamicUser = true;
        ExecStart = "/bin/true";
      };
    };
  });
  allow-unrelated-string-accept =
    errors (strict {
      systemd.sockets.unrelated = {
        listenStreams = [ "127.0.0.1:18080" ];
        socketConfig.Accept = "yes";
      };
    }) == [ ];
  reject-string-accept-activation = hasError "host activation" (strict {
    systemd.sockets.probe = {
      listenStreams = [ "127.0.0.1:18080" ];
      socketConfig.Accept = "no";
    };
  });
  legacy-host-ingress-alias =
    let
      c = eval { services.vpnConfinement.namespaces.vpnapps.ingress.fromHost.tcp = [ 8080 ]; };
    in
    errors c == [ ]
    && c.services.vpnConfinement.namespaces.vpnapps.publishToHost.tcp == [ 8080 ]
    && c.services.vpnConfinement.namespaces.vpnapps.derived.hostLink.nsAddressIPv4 != null;
  reject-balanced-inline-key = hasError "rejects inline WireGuard secrets" (eval {
    networking.wireguard.interfaces.wg0.privateKey = "test-only-not-a-secret";
  });
  reject-store-key-path = hasError "rejects Nix-store WireGuard key files" (eval {
    networking.wireguard.interfaces.wg0.privateKeyFile = lib.mkForce "/nix/store/example-private-key";
  });
  reject-disabled-service = hasError "refusing to run without confinement" disabled;
  reject-disabled-socket = hasError "refusing to run without confinement" disabledSocket;
  reject-explicit-root-dynamic-user = hasError "must run non-root" root;
  reject-unsafe-capabilities = hasError "grants capabilities" (privileged false);
  allow-explicit-capability-exception = errors (privileged true) == [ ];
  custom-pinning-attachment =
    (custom.systemd.services."vpn-confinement-endpoint-pinning@vpnapps".serviceConfig.NetworkNamespacePath
      or null
    ) == "/run/netns/uplink";
  distinct-pinning-tables = errors collision == [ ] && tableFrom "vpn.apps" != tableFrom "vpn-apps";
  inactive-allowlist = builtins.all (
    c:
    errors c == [ ]
    && !(lib.hasInfix "@allowed_" (mkNftRules "vpnapps" c.services.vpnConfinement.namespaces.vpnapps))
  ) leftovers;
}
