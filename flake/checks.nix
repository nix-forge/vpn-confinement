_: {
  perSystem =
    { pkgs, ... }:
    let
      evalPkgs = import pkgs.path { inherit (pkgs.stdenv.hostPlatform) system; };

      scenarioTests = {
        baseline-confinement = ../tests/nixos/baseline-confinement.nix;
        dns-mode-behavior = ../tests/nixos/dns-mode-behavior.nix;
        multi-namespace-lifecycle = ../tests/nixos/multi-namespace-lifecycle.nix;
        socket-activation-in-namespace = ../tests/nixos/socket-activation-in-namespace.nix;
      };

      rejectTests = {
        reject-dns-search-input = ../tests/nixos/reject-dns-search-input.nix;
        reject-high-assurance-weakeners = ../tests/nixos/reject-high-assurance-weakeners.nix;
        reject-manual-service-namespace = ../tests/nixos/reject-manual-service-namespace.nix;
        reject-hostname-wireguard-endpoints = ../tests/nixos/reject-hostname-wireguard-endpoints.nix;
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
      }
      // builtins.mapAttrs mkEvalRejectCheck rejectTests;
    };
}
