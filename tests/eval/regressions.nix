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
  enforced =
    extra:
    eval (
      lib.recursiveUpdate {
        services.vpnConfinement.namespaces.vpnapps = {
          servicePolicy = "enforced";
          egress.mode = "allowAllTunnel";
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
        hasError "unverified executable syntax" (strict {
          systemd.services.probe.serviceConfig.ExecStart = lib.mkForce cmd;
        })
      )
      [
        "\"+/bin/true\""
        "\\x2b/bin/true"
        "/bin/true ; +/bin/true"
        "'!/bin/true'"
      ];
  command-diagnostics-distinguish-risk =
    let
      warnings = command: vpnLib.commandWarnings { ExecStart = command; };
      has = text: messages: builtins.any (lib.hasInfix text) messages;
      unverified = [
        "\"relative-executable\""
        "\"/bin/tr\\ue\""
        "/bin/true\n/bin/false"
        "/bin/true\r/bin/false"
        "\"+/bin/true\""
        "\\x2b/bin/true"
        "/bin/true ; +/bin/true"
      ];
    in
    builtins.all (
      command:
      has "unverified executable syntax in ExecStart" (warnings command)
      && !has "privileged command prefixes" (warnings command)
      && has "does not confirm" (warnings command)
      && hasError "unverified executable syntax" (strict {
        systemd.services.probe.serviceConfig.ExecStart = lib.mkForce command;
      })
    ) unverified
    &&
      builtins.all
        (
          prefix:
          has "privileged command prefixes" (warnings "${prefix}/bin/true")
          && !has "unverified executable syntax" (warnings "${prefix}/bin/true")
        )
        [
          "+"
          "!"
          "!!"
          "-+"
          "@:+"
          "\t+"
        ]
    &&
      builtins.all
        (
          command:
          has "privileged command prefixes" (warnings command)
          && !has "unverified executable syntax" (warnings command)
        )
        [
          "+/bin/true\n"
          "!/bin/true\n"
        ]
    && builtins.all (command: warnings command == [ ]) [
      ""
      " \t"
      "/bin/true"
      "-/bin/echo '+hello' '!hello'"
      "@:/bin/echo name"
      "\"/bin/true\""
      "'/bin/true'"
      "\"/bin/echo\" '+arg'"
      "/bin/true\n"
      "/bin/true\r\n\t "
    ]
    &&
      builtins.length (warnings [
        "+/bin/true"
        "\"relative-executable\""
      ]) == 2;
  command-warning-explains-unverified-syntax =
    let
      config = eval { systemd.services.probe.serviceConfig.ExecStart = lib.mkForce "\\x2b/bin/true"; };
    in
    builtins.any (lib.hasInfix "systemd.services.probe has unverified executable syntax in ExecStart") config.warnings
    && !(builtins.any (lib.hasInfix "systemd.services.probe has privileged command prefixes") config.warnings);
  enforced-all-tunnel =
    let
      c = enforced { };
    in
    errors c == [ ]
    && c.services.vpnConfinement.namespaces.vpnapps.securityProfile == "balanced"
    && c.services.vpnConfinement.namespaces.vpnapps.egress.mode == "allowAllTunnel"
    && builtins.deepSeq c.systemd.units."probe.service".text true;
  enforced-rejects-capabilities =
    builtins.all
      (
        field:
        builtins.all
          (
            cap:
            hasError "requires empty CapabilityBoundingSet and AmbientCapabilities" (enforced {
              systemd.services.probe.serviceConfig.${field} = [ cap ];
            })
          )
          [
            "CAP_NET_ADMIN"
            "CAP_SYS_ADMIN"
            "CAP_NET_RAW"
            "CAP_SYS_PTRACE"
            "CAP_DAC_OVERRIDE"
            "CAP_SETUID"
            "CAP_NET_BIND_SERVICE"
            "13"
          ]
      )
      [
        "CapabilityBoundingSet"
        "AmbientCapabilities"
      ];
  enforced-rejects-omitted-bounding-reset =
    hasError "empty list omits the clearing directive"
      (enforced {
        systemd.services.probe.serviceConfig.CapabilityBoundingSet = lib.mkForce [ ];
      });
  enforced-accepts-explicit-bounding-reset =
    let
      c = enforced { systemd.services.probe.serviceConfig.CapabilityBoundingSet = lib.mkForce [ "" ]; };
    in
    errors c == [ ] && lib.hasInfix "CapabilityBoundingSet=\n" c.systemd.units."probe.service".text;
  enforced-rejects-zero-user-variants =
    builtins.all
      (
        user:
        hasError "must run non-root" (enforced {
          systemd.services.probe.serviceConfig.User = user;
        })
      )
      [
        "0"
        "00"
        "000"
        0
      ];
  enforced-rejects-root-alias = hasError "must run non-root" (enforced {
    users.users.root-alias = {
      uid = 0;
      group = "root";
      isSystemUser = true;
    };
    systemd.services.probe.serviceConfig.User = "root-alias";
  });
  enforced-rejects-implicit-root =
    builtins.all
      (
        name:
        hasError "systemd.services.${name} is in namespace vpnapps and must run non-root" (enforced {
          users.users.root-alias = {
            uid = 0;
            group = "root";
            isSystemUser = true;
          };
          systemd.services.${name} = {
            vpn = {
              enable = true;
              namespace = "vpnapps";
            };
            serviceConfig = {
              DynamicUser = true;
              ExecStart = "${pkgs.coreutils}/bin/true";
            };
          };
        })
      )
      [
        "root"
        "root-alias"
      ];
  enforced-rejects-user-specifiers =
    builtins.all
      (
        user:
        hasError "requires a literal User without systemd specifiers" (enforced {
          systemd.services."instance@root" = {
            vpn = {
              enable = true;
              namespace = "vpnapps";
            };
            serviceConfig = {
              User = user;
              ExecStart = "${pkgs.coreutils}/bin/true";
            };
          };
        })
      )
      [
        "%i"
        "%U"
      ];
  enforced-rejects-user-whitespace =
    builtins.all
      (
        user:
        hasError "requires a literal User without systemd specifiers or whitespace" (enforced {
          systemd.services.probe.serviceConfig.User = user;
        })
      )
      [
        " "
        "\t"
        " root"
        "root "
        " root "
        "0\n"
      ];
  enforced-rejects-renamed-root-alias = hasError "must run non-root" (enforced {
    users.users.renamed-root = {
      name = "effective-root";
      uid = 0;
      group = "root";
      isSystemUser = true;
    };
    systemd.services.probe.serviceConfig.User = "effective-root";
  });
  enforced-rejects-root = hasError "must run non-root" (enforced {
    systemd.services.probe.serviceConfig.User = "root";
  });
  enforced-rejects-host-sockets = hasError "host activation" (enforced {
    systemd.sockets.probe.listenStreams = [ "127.0.0.1:18080" ];
  });
  enforced-rejects-privileged-commands =
    builtins.all
      (
        prefix:
        hasError "privileged command" (enforced {
          systemd.services.probe.serviceConfig.ExecStart = lib.mkForce "${prefix}/bin/true";
        })
      )
      [
        "+"
        "!"
        "!!"
        "-+"
        "@:+"
      ];
  enforced-rejects-exceptions =
    builtins.all
      (
        flag:
        hasError "rejects service exception flags" (enforced {
          systemd.services.probe.vpn.${flag} = true;
        })
      )
      [
        "allowRootInHighAssurance"
        "allowUnsafeCapabilities"
        "allowPrivilegedCommands"
        "allowHostSockets"
      ];
  enforced-rejects-new-privileges = hasError "requires NoNewPrivileges = true" (enforced {
    systemd.services.probe.serviceConfig.NoNewPrivileges = lib.mkForce false;
  });
  profile-retains-high-assurance-checks = hasError "must run non-root" (strict {
    services.vpnConfinement.namespaces.vpnapps.servicePolicy = "profile";
    systemd.services.probe.serviceConfig.User = "root";
  });
  high-assurance-enforced-rejects-exceptions = hasError "rejects service exception flags" (strict {
    services.vpnConfinement.namespaces.vpnapps.servicePolicy = "enforced";
    systemd.services.probe.vpn.allowPrivilegedCommands = true;
  });
  native-quoted-executable-accepted =
    builtins.all
      (
        cmd:
        errors (enforced {
          systemd.services.probe.serviceConfig.ExecStart = lib.mkForce cmd;
        }) == [ ]
      )
      [
        "\"${pkgs.coreutils}/bin/sleep\" infinity"
        "'${pkgs.coreutils}/bin/sleep' infinity\n"
        "${pkgs.coreutils}/bin/sleep infinity\r\n\t "
      ];
  enforced-rejects-ambiguous-executable =
    builtins.all
      (
        cmd:
        hasError "unverified executable syntax" (enforced {
          systemd.services.probe.serviceConfig.ExecStart = lib.mkForce cmd;
        })
      )
      [
        "\"+/bin/true\""
        "'!/bin/true'"
        "\"/bin/tr\\ue\""
        "\\x2b/bin/true"
        "\"relative\""
        "/bin/true ; +/bin/true"
        "\"/bin/true\" ; /bin/false"
        "/bin/true\n/bin/false"
        "/bin/true\r/bin/false"
      ];
  high-assurance-rejects-unverified-user =
    builtins.all
      (
        user:
        hasError "requires a literal User without systemd specifiers or whitespace" (strict {
          systemd.services.probe.serviceConfig.User = user;
        })
      )
      [
        "%i"
        "%U"
        " "
        " root "
        "0\n"
      ];
  high-assurance-rejects-zero-user-variants =
    builtins.all
      (
        user:
        hasError "must run non-root" (strict {
          systemd.services.probe.serviceConfig.User = user;
        })
      )
      [
        "00"
        "000"
        0
      ];
  high-assurance-rejects-renamed-root = hasError "must run non-root" (strict {
    users.users.renamed-root = {
      name = "effective-root";
      uid = 0;
      group = "root";
      isSystemUser = true;
    };
    systemd.services.probe.serviceConfig.User = "effective-root";
  });
  high-assurance-rejects-implicit-root =
    hasError "systemd.services.root is in high-assurance namespace vpnapps and must run non-root"
      (strict {
        systemd.services.root = {
          vpn = {
            enable = true;
            namespace = "vpnapps";
          };
          serviceConfig = {
            DynamicUser = true;
            ExecStart = "${pkgs.coreutils}/bin/true";
          };
        };
      });
  strict-policies-reject-permissions-start-only =
    builtins.all
      (
        policy:
        hasError "requires PermissionsStartOnly to be unset or false" (policy {
          systemd.services.probe.serviceConfig.PermissionsStartOnly = true;
        })
      )
      [
        strict
        enforced
      ];
  high-assurance-legacy-command-exception-preserved =
    errors (strict {
      systemd.services.probe = {
        vpn.allowPrivilegedCommands = true;
        serviceConfig = {
          PermissionsStartOnly = true;
          ExecReloadPost = "+/bin/true";
        };
      };
    }) == [ ];
  strict-policies-reject-privileged-reload-post =
    builtins.all
      (
        policy:
        hasError "ExecReloadPost" (policy {
          systemd.services.probe.serviceConfig.ExecReloadPost = "+/bin/true";
        })
      )
      [
        strict
        enforced
      ];
  strict-policies-reject-implicit-root-template =
    builtins.all
      (
        policy:
        builtins.all
          (
            name:
            hasError "and must run non-root" (policy {
              users.users.root-alias = {
                uid = 0;
                group = "root";
                isSystemUser = true;
              };
              systemd.services.${name} = {
                vpn = {
                  enable = true;
                  namespace = "vpnapps";
                };
                serviceConfig = {
                  DynamicUser = true;
                  ExecStart = "${pkgs.coreutils}/bin/true";
                };
              };
            })
          )
          [
            "root@instance"
            "root-alias@instance"
          ]
      )
      [
        strict
        enforced
      ];
  strict-policies-allow-safe-template =
    builtins.all
      (
        policy:
        let
          c = policy {
            systemd.services."safe-probe@instance" = {
              vpn = {
                enable = true;
                namespace = "vpnapps";
              };
              serviceConfig = {
                DynamicUser = true;
                ExecStart = "${pkgs.coreutils}/bin/true";
                ExecReloadPost = "${pkgs.coreutils}/bin/true";
                PermissionsStartOnly = false;
              };
            };
          };
        in
        errors c == [ ] && builtins.stringLength c.systemd.units."safe-probe@instance.service".text > 0
      )
      [
        strict
        enforced
      ];
  high-assurance-root-exception-preserved =
    errors (strict {
      systemd.services.probe = {
        vpn.allowRootInHighAssurance = true;
        serviceConfig.User = "%U";
      };
    }) == [ ];
  high-assurance-rejects-omitted-bounding =
    hasError "requires an explicit CapabilityBoundingSet assignment"
      (strict {
        systemd.services.probe.serviceConfig.CapabilityBoundingSet = lib.mkForce [ ];
      });
  high-assurance-bounding-exception-preserved =
    errors (strict {
      systemd.services.probe = {
        vpn.allowUnsafeCapabilities = true;
        serviceConfig.CapabilityBoundingSet = lib.mkForce [ ];
      };
    }) == [ ];
  high-assurance-known-capability-preserved =
    errors (strict {
      systemd.services.probe.serviceConfig.CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
    }) == [ ];
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
