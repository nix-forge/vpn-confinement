_: {
  perSystem =
    { pkgs, config, ... }:
    let
      evalPkgs = import pkgs.path { inherit (pkgs.stdenv.hostPlatform) system; };

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
        vm-endpoint-pinning-drop = ../tests/nixos/runtime-endpoint-pinning-drop.nix;
        vm-ip-leak-fail-closed = ../tests/nixos/runtime-ip-leak-fail-closed.nix;
        vm-dns-leak-strict-vs-compat = ../tests/nixos/runtime-dns-leak-strict-vs-compat.nix;
        vm-fail-closed-tunnel-drop = ../tests/nixos/runtime-fail-closed-tunnel-drop.nix;
      };

      rejectTests = {
        reject-dns-search-input = ../tests/nixos/reject-dns-search-input.nix;
        reject-endpoint-pinning-hostname-endpoints = ../tests/nixos/reject-endpoint-pinning-hostname-endpoints.nix;
        reject-high-assurance-empty-allowed-cidrs = ../tests/nixos/reject-high-assurance-empty-allowed-cidrs.nix;
        reject-high-assurance-inline-private-key = ../tests/nixos/reject-high-assurance-inline-private-key.nix;
        reject-high-assurance-root-service = ../tests/nixos/reject-high-assurance-root-service.nix;
        reject-high-assurance-weakeners = ../tests/nixos/reject-high-assurance-weakeners.nix;
        reject-missing-namespace-selection = ../tests/nixos/reject-missing-namespace-selection.nix;
        reject-manual-service-namespace = ../tests/nixos/reject-manual-service-namespace.nix;
        reject-hostname-wireguard-endpoints = ../tests/nixos/reject-hostname-wireguard-endpoints.nix;
        reject-hostname-endpoint-without-refresh = ../tests/nixos/reject-hostname-endpoint-without-refresh.nix;
      };

      evalNode =
        testFile:
        (import (evalPkgs.path + "/nixos/lib/eval-config.nix") {
          inherit (pkgs.stdenv.hostPlatform) system;
          pkgs = evalPkgs;
          modules = [ (import testFile { pkgs = evalPkgs; }).nodes.machine ];
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
        name: testFile:
        let
          evaluated = builtins.tryEval (evalNode testFile).system.build.toplevel;
        in
        pkgs.runCommand name { } ''
          if [ "${if evaluated.success then "1" else "0"}" -eq 1 ]; then
            echo "expected NixOS evaluation failure" >&2
            exit 1
          fi
          touch "$out"
        '';

      mkVmRuntimeCheck = _name: testFile: evalPkgs.testers.runNixOSTest { imports = [ testFile ]; };

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
    in
    {
      checks = {
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

        options-doc-generation = config.packages.options-doc-markdown;
      }
      // builtins.mapAttrs mkEvalRejectCheck rejectTests
      // runtimeCheckAttrs;
    };
}
