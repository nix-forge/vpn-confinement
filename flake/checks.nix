_: {
  perSystem =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      evalPkgs = import pkgs.path { inherit (pkgs.stdenv.hostPlatform) system; };
      vmPkgs = evalPkgs.extend (
        _final: prev: {
          # QEMU TCG can take more than five minutes to boot multi-namespace
          # guests. Double the driver's shell-connect attempts to ten minutes.
          nixos-test-driver = prev.nixos-test-driver.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace test_driver/machine/__init__.py \
                --replace-fail "for _ in range(10):" "for _ in range(20):"
            '';
          });
        }
      );
      vpnLib = import ../modules/vpn-confinement/lib.nix { inherit lib; };

      scenarioTests = {
        baseline-confinement = ../tests/nixos/baseline-confinement.nix;
        dns-mode-behavior = ../tests/nixos/dns-mode-behavior.nix;
        endpoint-pinning-custom-socket-namespace = ../tests/nixos/endpoint-pinning-custom-socket-namespace.nix;
        endpoint-pinning-mvp = ../tests/nixos/endpoint-pinning-mvp.nix;
        high-assurance-root-optout = ../tests/nixos/high-assurance-root-optout.nix;
        long-namespace-generated-hostlink = ../tests/nixos/long-namespace-generated-hostlink.nix;
        multi-namespace-lifecycle = ../tests/nixos/multi-namespace-lifecycle.nix;
        publish-to-host-abstraction = ../tests/nixos/publish-to-host-abstraction.nix;
        restrict-bind-effective-ingress = ../tests/nixos/restrict-bind-effective-ingress.nix;
        socket-activation-in-namespace = ../tests/nixos/socket-activation-in-namespace.nix;
      };

      runtimeTests = {
        vm-baseline-confinement = ../tests/nixos/baseline-confinement.nix;
        vm-endpoint-pinning-drop = ../tests/nixos/runtime-endpoint-pinning-drop.nix;
        vm-ip-leak-fail-closed = ../tests/nixos/runtime-ip-leak-fail-closed.nix;
        vm-dns-leak-strict-vs-compat = ../tests/nixos/runtime-dns-leak-strict-vs-compat.nix;
        vm-fail-closed-tunnel-drop = ../tests/nixos/runtime-fail-closed-tunnel-drop.nix;
        vm-multi-namespace-lifecycle = ../tests/nixos/multi-namespace-lifecycle.nix;
        vm-wireguard-handshake = ../tests/nixos/runtime-wireguard-handshake.nix;
      };

      rejectTests = {
        reject-cross-role-interface-collision = {
          file = ../tests/nixos/reject-cross-role-interface-collision.nix;
          expectedMessages = [
            "Enabled namespaces must use globally unique WireGuard and host-link interface names."
          ];
        };
        reject-dns-search-input = {
          file = ../tests/nixos/reject-dns-search-input.nix;
          expectedMessages = [
            "services.vpnConfinement.namespaces.vpnapps.dns.search must contain domain-style search suffixes only (valid labels, no empty labels, no whitespace)."
          ];
        };
        reject-endpoint-pinning-fwmark-override = {
          file = ../tests/nixos/reject-endpoint-pinning-fwmark-override.nix;
          expectedMessages = [
            "services.vpnConfinement.namespaces.vpnapps.wireguard.endpointPinning.enable requires networking.wireguard.interfaces.wg0.fwMark to match its configured or derived endpoint-pinning mark; leave the WireGuard fwMark unset unless it matches."
          ];
        };
        reject-endpoint-pinning-hostname-endpoints = {
          file = ../tests/nixos/reject-endpoint-pinning-hostname-endpoints.nix;
          expectedMessages = [
            "services.vpnConfinement.namespaces.vpnapps.wireguard.endpointPinning.enable requires networking.wireguard.interfaces.wg0.peers.*.endpoint to be non-empty and literal IP endpoints only."
          ];
        };
        reject-high-assurance-empty-allowed-cidrs = {
          file = ../tests/nixos/reject-high-assurance-empty-allowed-cidrs.nix;
          expectedMessages = [
            "services.vpnConfinement.namespaces.vpnapps.securityProfile = \"highAssurance\" requires egress.allowedCidrs to be non-empty so egress remains destination-constrained."
          ];
        };
        reject-high-assurance-inline-preshared-key = {
          file = ../tests/nixos/reject-high-assurance-inline-preshared-key.nix;
          expectedMessages = [
            "services.vpnConfinement.namespaces.vpnapps.securityProfile = \"highAssurance\" rejects inline networking.wireguard.interfaces.wg0.peers.*.presharedKey values because inline secrets land in the Nix store. Use presharedKeyFile instead."
          ];
        };
        reject-high-assurance-inline-private-key = {
          file = ../tests/nixos/reject-high-assurance-inline-private-key.nix;
          expectedMessages = [
            "services.vpnConfinement.namespaces.vpnapps.securityProfile = \"highAssurance\" rejects networking.wireguard.interfaces.wg0.privateKey because inline secrets land in the Nix store. Use privateKeyFile or generatePrivateKeyFile instead."
          ];
        };
        reject-high-assurance-root-service = {
          file = ../tests/nixos/reject-high-assurance-root-service.nix;
          expectedMessages = [
            "systemd.services.rooty is in high-assurance namespace vpnapps and must run non-root. Set serviceConfig.DynamicUser = true or non-root serviceConfig.User, or explicitly opt out with vpn.allowRootInHighAssurance = true."
          ];
        };
        reject-high-assurance-weakeners = {
          file = ../tests/nixos/reject-high-assurance-weakeners.nix;
          expectedMessages = [
            "services.vpnConfinement.namespaces.vpnapps.securityProfile = \"highAssurance\" rejects dns.allowHostResolverIPC = true because host resolver IPC weakens DNS containment."
            "services.vpnConfinement.namespaces.vpnapps.securityProfile = \"highAssurance\" requires egress.allowedCidrs to be non-empty so egress remains destination-constrained."
            "services.vpnConfinement.namespaces.vpnapps.securityProfile = \"highAssurance\" rejects wireguard.allowHostnameEndpoints = true; use literal peer endpoint IPs instead."
            "services.vpnConfinement.namespaces.vpnapps.securityProfile = \"highAssurance\" requires networking.wireguard.interfaces.wg0.allowedIPsAsRoutes = true so peer routes remain installed inside the namespace."
          ];
        };
        reject-hostname-endpoint-without-refresh = {
          file = ../tests/nixos/reject-hostname-endpoint-without-refresh.nix;
          expectedMessages = [
            "services.vpnConfinement.namespaces.vpnapps allows hostname WireGuard endpoints only when effective dynamic endpoint refresh is enabled on networking.wireguard.interfaces.wg0 (interface-level or per-peer dynamicEndpointRefreshSeconds > 0)."
          ];
        };
        reject-hostname-wireguard-endpoints = {
          file = ../tests/nixos/reject-hostname-wireguard-endpoints.nix;
          expectedMessages = [
            "services.vpnConfinement.namespaces.vpnapps defaults to literal WireGuard peer endpoint IPs. Set wireguard.allowHostnameEndpoints = true to opt into hostname:port endpoints."
          ];
        };
        reject-manual-service-namespace = {
          file = ../tests/nixos/reject-manual-service-namespace.nix;
          expectedMessages = [
            "vpn-confinement owns systemd.services.manual-netns.serviceConfig.NetworkNamespacePath; leave it unset or set it to /run/netns/vpnapps."
            "systemd.services.manual-netns.unitConfig.JoinsNamespaceOf conflicts with vpn-confinement namespace attachment; leave it unset."
          ];
        };
        reject-missing-namespace-selection = {
          file = ../tests/nixos/reject-missing-namespace-selection.nix;
          expectedMessages = [
            "systemd.services.missing-namespace.vpn.enable requires vpn.namespace to be set, or services.vpnConfinement.defaultNamespace to be configured explicitly."
          ];
        };
        reject-unsafe-namespace-name = {
          file = ../tests/nixos/reject-unsafe-namespace-name.nix;
          expectedMessages = [
            "services.vpnConfinement.namespaces keys must begin and end with an alphanumeric character, contain only [A-Za-z0-9_.-], and be at most 64 characters."
          ];
        };
      };

      evalNode =
        testFile:
        (import (evalPkgs.path + "/nixos/lib/eval-config.nix") {
          inherit (pkgs.stdenv.hostPlatform) system;
          pkgs = evalPkgs;
          modules = [
            (import testFile { pkgs = evalPkgs; }).nodes.machine
            {
              # Rejection checks inspect this module's failed assertions, so
              # supply the unrelated boot baseline expected by eval-config.
              boot.loader.grub.enable = false;
              fileSystems."/".device = "none";
              fileSystems."/".fsType = "tmpfs";
            }
          ];
        }).config;

      contains = needle: haystack: builtins.any (item: item == needle) haystack;

      containsMatch =
        pattern: haystack: builtins.any (item: builtins.match pattern item != null) haystack;

      mkEvalAssertCheck =
        name: assertion: message:
        pkgs.runCommand name { } ''
          if [ "${if assertion then "1" else "0"}" -ne 1 ]; then
            echo ${builtins.toJSON message} >&2
            exit 1
          fi
          touch "$out"
        '';

      mkEvalRejectCheck =
        name: testSpec:
        let
          failedMessages = map (item: item.message) (
            builtins.filter (item: !item.assertion) (evalNode testSpec.file).assertions
          );
          missingMessages = builtins.filter (
            message: !(contains message failedMessages)
          ) testSpec.expectedMessages;
          unexpectedMessages = builtins.filter (
            message: !(contains message testSpec.expectedMessages)
          ) failedMessages;
        in
        mkEvalAssertCheck name (missingMessages == [ ] && unexpectedMessages == [ ]) (
          "expected these failed assertions: ${builtins.toJSON testSpec.expectedMessages}; "
          + "actual failed assertions: ${builtins.toJSON failedMessages}"
        );

      mkVmRuntimeCheck =
        _name: testFile:
        let
          initrdLinuxTerminfo = vmPkgs.runCommand "initrd-linux-terminfo" { } ''
            for candidate in \
              ${vmPkgs.ncurses}/share/terminfo/l/linux \
              ${vmPkgs.ncurses}/share/terminfo/l~nix~case~hack~1/linux
            do
              if [ -e "$candidate" ]; then
                cp "$candidate" "$out"
                exit 0
              fi
            done

            echo "ncurses does not contain the linux terminfo entry" >&2
            exit 1
          '';
        in
        vmPkgs.testers.runNixOSTest {
          imports = [ testFile ];

          # A case-insensitive Darwin Nix store encodes ncurses' lowercase
          # terminfo directory before copying the Linux closure to the builder.
          defaults.boot.initrd.systemd.contents."/etc/terminfo/l/linux".source =
            lib.mkForce initrdLinuxTerminfo;

          # Two vCPUs reduce multi-namespace boot time under QEMU TCG.
          defaults.virtualisation.cores = 2;
        };

      runtimeCheckAttrs =
        if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then
          builtins.mapAttrs mkVmRuntimeCheck runtimeTests
        else
          { };

      baselineCfg = evalNode scenarioTests.baseline-confinement;
      baselineService = baselineCfg.systemd.services.netns-echo.serviceConfig;
      baselineWireguard = baselineCfg.systemd.services."wireguard-wg0";

      dnsModeCfg = evalNode scenarioTests.dns-mode-behavior;
      strictService = dnsModeCfg.systemd.services.svc-strict.serviceConfig;
      compatService = dnsModeCfg.systemd.services.svc-compat.serviceConfig;
      helpersService = dnsModeCfg.systemd.services.svc-helpers.serviceConfig;

      multiNsCfg = evalNode scenarioTests.multi-namespace-lifecycle;
      mediaProbe = multiNsCfg.systemd.services.media-probe.serviceConfig;
      appsProbe = multiNsCfg.systemd.services.apps-probe.serviceConfig;
      mediaProbeUnit = multiNsCfg.systemd.services.media-probe;
      appsProbeUnit = multiNsCfg.systemd.services.apps-probe;

      socketCfg = evalNode scenarioTests.socket-activation-in-namespace;
      socketUnit = socketCfg.systemd.sockets.socket-echo;
      socketService = socketCfg.systemd.services.socket-echo;

      rootOptoutCfg = evalNode scenarioTests.high-assurance-root-optout;
      rootOptoutService = rootOptoutCfg.systemd.services.rooty-optout;

      endpointPinningCfg = evalNode scenarioTests.endpoint-pinning-mvp;
      endpointPinningWireguard = endpointPinningCfg.systemd.services."wireguard-wg0";
      endpointPinningUnit =
        endpointPinningCfg.systemd.services."vpn-confinement-endpoint-pinning@vpnapps";
      endpointPinningFwMark = endpointPinningCfg.networking.wireguard.interfaces.wg0.fwMark;

      endpointPinningCustomCfg = evalNode scenarioTests.endpoint-pinning-custom-socket-namespace;
      endpointPinningCustomWireguard = endpointPinningCustomCfg.systemd.services."wireguard-wg0";
      endpointPinningCustomUnit =
        endpointPinningCustomCfg.systemd.services."vpn-confinement-endpoint-pinning@vpnapps";

      publishCfg = evalNode scenarioTests.publish-to-host-abstraction;
      publishNs = publishCfg.services.vpnConfinement.namespaces.vpnapps;
      publishServiceUnit = publishCfg.systemd.services."vpn-confinement-netns@vpnapps";

      longHostLinkCfg = evalNode scenarioTests.long-namespace-generated-hostlink;
      longHostLinkNs =
        longHostLinkCfg.services.vpnConfinement.namespaces.this-namespace-name-is-deliberately-long-for-hostlink;
      longHostLinkUnit =
        longHostLinkCfg.systemd.services."vpn-confinement-netns@this-namespace-name-is-deliberately-long-for-hostlink";

      restrictBindCfg = evalNode scenarioTests.restrict-bind-effective-ingress;
      restrictBindService = restrictBindCfg.systemd.services.restrict-bind-probe.serviceConfig;

      restrictBindNoIngressCfg = evalNode ../tests/nixos/restrict-bind-no-ingress.nix;
      restrictBindNoIngressService =
        restrictBindNoIngressCfg.systemd.services.restrict-bind-probe.serviceConfig;
    in
    {
      checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
        {
          baseline-confinement = mkEvalAssertCheck "baseline-confinement" (
            baselineService.NetworkNamespacePath == "/run/netns/vpnapps"
            && containsMatch ".*:/etc/resolv\\.conf" baselineService.BindReadOnlyPaths
            && containsMatch ".*:/etc/nsswitch\\.conf" baselineService.BindReadOnlyPaths
            && containsMatch ".*/run/systemd/resolve" baselineService.InaccessiblePaths
            && contains "/run/nscd" baselineService.InaccessiblePaths
            && contains "/run/dbus/system_bus_socket" baselineService.InaccessiblePaths
            && contains "lo" baselineService.RestrictNetworkInterfaces
            && contains "wg0" baselineService.RestrictNetworkInterfaces
            && contains "ve-vpnapps-ns" baselineService.RestrictNetworkInterfaces
            && contains "vpn-confinement-netns@vpnapps.service" baselineWireguard.after
            && contains "vpn-confinement-netns@vpnapps.service" baselineWireguard.requires
            && contains "vpn-confinement-netns@vpnapps.service" baselineWireguard.bindsTo
          ) "baseline confinement evaluation did not generate the expected namespace, DNS, or unit wiring";

          dns-mode-behavior = mkEvalAssertCheck "dns-mode-behavior" (
            contains "/run/nscd" strictService.InaccessiblePaths
            && contains "/run/dbus/system_bus_socket" strictService.InaccessiblePaths
            && !(compatService ? BindReadOnlyPaths)
            && !(compatService ? InaccessiblePaths)
            && containsMatch ".*:/etc/resolv\\.conf" helpersService.BindReadOnlyPaths
            && !(contains "/run/nscd" (helpersService.InaccessiblePaths or [ ]))
            && !(contains "/run/dbus/system_bus_socket" (helpersService.InaccessiblePaths or [ ]))
          ) "dns mode evaluation did not preserve the expected strict, compat, and helper IPC behaviors";

          multi-namespace-lifecycle = mkEvalAssertCheck "multi-namespace-lifecycle" (
            mediaProbe.NetworkNamespacePath == "/run/netns/media"
            && appsProbe.NetworkNamespacePath == "/run/netns/apps"
            && contains "vpn-confinement-netns@media.service" mediaProbeUnit.bindsTo
            && contains "wireguard-wg-media.service" mediaProbeUnit.bindsTo
            && contains "vpn-confinement-netns@apps.service" appsProbeUnit.bindsTo
            && contains "wireguard-wg-apps.service" appsProbeUnit.bindsTo
          ) "multi-namespace evaluation did not generate distinct service attachments and namespace units";

          socket-activation-in-namespace =
            mkEvalAssertCheck "socket-activation-in-namespace"
              (
                socketUnit.socketConfig.NetworkNamespacePath == "/run/netns/vpnapps"
                && socketService.serviceConfig.NetworkNamespacePath == "/run/netns/vpnapps"
                && contains "vpn-confinement-netns@vpnapps.service" socketUnit.bindsTo
                && contains "wireguard-wg0.service" socketUnit.bindsTo
                && contains "wireguard-wg0.service" socketService.bindsTo
              )
              "socket activation evaluation did not keep the socket and service inside the namespace with the expected dependencies";

          high-assurance-root-optout =
            mkEvalAssertCheck "high-assurance-root-optout"
              (
                rootOptoutService.serviceConfig.NetworkNamespacePath == "/run/netns/vpnapps"
                && contains "vpn-confinement-netns@vpnapps.service" rootOptoutService.bindsTo
                && contains "wireguard-wg0.service" rootOptoutService.bindsTo
                && rootOptoutService.serviceConfig.ProtectSystem == "strict"
                && rootOptoutService.serviceConfig.ProtectHome
              )
              "high-assurance root opt-out evaluation did not preserve expected namespace attachment and dependency wiring";

          endpoint-pinning-mvp = mkEvalAssertCheck "endpoint-pinning-mvp" (
            contains "vpn-confinement-endpoint-pinning@vpnapps.service" endpointPinningWireguard.after
            && contains "vpn-confinement-endpoint-pinning@vpnapps.service" endpointPinningWireguard.requires
            && contains "vpn-confinement-endpoint-pinning@vpnapps.service" endpointPinningWireguard.bindsTo
            && builtins.match "^[0-9]+$" endpointPinningFwMark != null
            && contains "wireguard-wg0.service" endpointPinningUnit.before
          ) "endpoint pinning evaluation did not generate expected WireGuard dependency wiring and fwMark";

          endpoint-pinning-custom-socket-namespace =
            mkEvalAssertCheck "endpoint-pinning-custom-socket-namespace"
              (
                contains "vpn-confinement-endpoint-pinning@vpnapps.service" endpointPinningCustomWireguard.after
                && contains "vpn-confinement-netns@birthplace.service" endpointPinningCustomUnit.after
                && contains "vpn-confinement-netns@birthplace.service" endpointPinningCustomUnit.requires
                && contains "vpn-confinement-netns@birthplace.service" endpointPinningCustomUnit.bindsTo
                && builtins.match ".*ip netns exec birthplace .*" endpointPinningCustomUnit.script != null
              )
              "endpoint pinning did not attach policy to the configured custom socket birthplace namespace";

          publish-to-host-abstraction = mkEvalAssertCheck "publish-to-host-abstraction" (
            !publishNs.hostLink.enable
            && publishNs.publishToHost.tcp == [ 8080 ]
            && publishNs.derived.hostLink.subnetIPv4 != null
            && publishNs.derived.hostLink.hostAddressIPv4 != null
            && publishNs.derived.hostLink.nsAddressIPv4 != null
            && publishServiceUnit.serviceConfig.NoNewPrivileges
            && builtins.stringLength publishNs.hostLink.hostIf <= 15
            && builtins.stringLength publishNs.hostLink.nsIf <= 15
            && builtins.match ".*${publishNs.hostLink.hostIf}.*" publishServiceUnit.script != null
            && builtins.match ".*${publishNs.hostLink.nsIf}.*" publishServiceUnit.script != null
          ) "publishToHost evaluation did not expose derived hostLink values or host ingress wiring";

          long-namespace-generated-hostlink = mkEvalAssertCheck "long-namespace-generated-hostlink" (
            builtins.stringLength longHostLinkNs.hostLink.hostIf <= 15
            && builtins.stringLength longHostLinkNs.hostLink.nsIf <= 15
            && longHostLinkNs.hostLink.hostIf != longHostLinkNs.hostLink.nsIf
            && builtins.match ".*${longHostLinkNs.hostLink.hostIf}.*" longHostLinkUnit.script != null
            && builtins.match ".*${longHostLinkNs.hostLink.nsIf}.*" longHostLinkUnit.script != null
          ) "long namespace host-link evaluation did not generate deterministic Linux-safe interface names";

          restrict-bind-effective-ingress = mkEvalAssertCheck "restrict-bind-effective-ingress" (
            contains "tcp:8080" restrictBindService.SocketBindAllow
            && contains "tcp:9090" restrictBindService.SocketBindAllow
            && contains "udp:51413" restrictBindService.SocketBindAllow
            && contains "any" restrictBindService.SocketBindDeny
          ) "restrictBind evaluation did not derive bind restrictions from effective ingress";

          restrict-bind-no-ingress = mkEvalAssertCheck "restrict-bind-no-ingress" (
            contains "any" restrictBindNoIngressService.SocketBindDeny
            && !(restrictBindNoIngressService ? SocketBindAllow)
          ) "restrictBind without declared ingress did not fail closed with SocketBindDeny=any";

          security-input-validation = mkEvalAssertCheck "security-input-validation" (
            vpnLib.isLiteralIpv4 "192.0.2.1"
            && !vpnLib.isLiteralIpv4 "192.0.02.1"
            && vpnLib.isLiteralIpv6 "::"
            && vpnLib.isLiteralIpv6 "2001:db8::1"
            && vpnLib.isLiteralIpv6 "::ffff:192.0.2.1"
            && !vpnLib.isLiteralIpv6 "192.0.2.1::"
            && !vpnLib.isLiteralIpv6 "2001:192.0.2.1::1"
            && vpnLib.isLiteralCidr "192.0.2.1/32"
            && !vpnLib.isLiteralCidr "192.0.2.1/033"
            && vpnLib.isValidNamespaceName "vpn.apps-1"
            && !vpnLib.isValidNamespaceName "."
            && !vpnLib.isValidNamespaceName ".."
            && !vpnLib.isValidNamespaceName "-vpnapps"
            && vpnLib.isValidInterfaceName "wg0"
            && !vpnLib.isValidInterfaceName "-wg0"
          ) "security-sensitive address, namespace, or interface validation accepted an unsafe input";

          options-doc-generation = config.packages.options-doc-markdown;
        }
        // builtins.mapAttrs mkEvalRejectCheck rejectTests
        // runtimeCheckAttrs
      );
    };
}
