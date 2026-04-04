_: {
  perSystem =
    { pkgs, ... }:
    let
      evalPkgs = import pkgs.path {
        inherit (pkgs.stdenv.hostPlatform) system;
        config.problems.handlers.nsncd.broken = "ignore";
      };

      evalNode =
        testFile:
        (import (evalPkgs.path + "/nixos/lib/eval-config.nix") {
          inherit (pkgs.stdenv.hostPlatform) system;
          pkgs = evalPkgs;
          modules = [ (import testFile { pkgs = evalPkgs; }).nodes.machine ];
        }).config;

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
    in
    {
      checks.vpn-confinement-basic = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-basic.nix { inherit pkgs; }
      );

      checks.vpn-confinement-leak-tests = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-leak-tests.nix { inherit pkgs; }
      );

      checks.vpn-confinement-v2-ipv6-disable = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-v2-ipv6-disable.nix { inherit pkgs; }
      );

      checks.vpn-confinement-v2-multi-namespace = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-v2-multi-namespace.nix { inherit pkgs; }
      );

      checks.vpn-confinement-v2-egress-allowlist = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-v2-egress-allowlist.nix { inherit pkgs; }
      );

      checks.vpn-confinement-v2-socket-activation = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-v2-socket-activation.nix { inherit pkgs; }
      );

      checks.vpn-confinement-v2-dns-system-bus-block = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-v2-dns-system-bus-block.nix { inherit pkgs; }
      );

      checks.vpn-confinement-v2-dns-compatibility-mode = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-v2-dns-compatibility-mode.nix { inherit pkgs; }
      );

      checks.vpn-confinement-v2-host-socket-vpn-service-pattern = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-v2-host-socket-vpn-service-pattern.nix { inherit pkgs; }
      );

      checks.vpn-confinement-v2-namespace-stop-propagates = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-v2-namespace-stop-propagates.nix { inherit pkgs; }
      );

      checks.vpn-confinement-v2-strict-dns-direct-port53-block = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-v2-strict-dns-direct-port53-block.nix { inherit pkgs; }
      );

      checks.vpn-confinement-v2-wireguard-hostname-endpoint-refresh = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-v2-wireguard-hostname-endpoint-refresh.nix {
          inherit pkgs;
        }
      );

      checks.vpn-confinement-v2-restrict-bind-deny-any = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-v2-restrict-bind-deny-any.nix { inherit pkgs; }
      );

      checks.vpn-confinement-v2-restrict-bind-allow-ingress = pkgs.testers.runNixOSTest (
        import ../../tests/nixos/vpn-confinement-v2-restrict-bind-allow-ingress.nix { inherit pkgs; }
      );

      checks.vpn-confinement-v2-hostlink-disabled-no-ingress = mkEvalRejectCheck "vpn-confinement-v2-hostlink-disabled-no-ingress" ../../tests/nixos/vpn-confinement-v2-hostlink-disabled-no-ingress.nix;

      checks.vpn-confinement-v2-egress-ipv6-cidr-reject = mkEvalRejectCheck "vpn-confinement-v2-egress-ipv6-cidr-reject" ../../tests/nixos/vpn-confinement-v2-egress-ipv6-cidr-reject.nix;

      checks.vpn-confinement-v2-wireguard-hostname-endpoint-reject = mkEvalRejectCheck "vpn-confinement-v2-wireguard-hostname-endpoint-reject" ../../tests/nixos/vpn-confinement-v2-wireguard-hostname-endpoint-reject.nix;

      checks.vpn-confinement-v2-wireguard-endpoint-ipv6-reject = mkEvalRejectCheck "vpn-confinement-v2-wireguard-endpoint-ipv6-reject" ../../tests/nixos/vpn-confinement-v2-wireguard-endpoint-ipv6-reject.nix;

      checks.vpn-confinement-v2-namespace-name-validation-reject = mkEvalRejectCheck "vpn-confinement-v2-namespace-name-validation-reject" ../../tests/nixos/vpn-confinement-v2-namespace-name-validation-reject.nix;

      checks.vpn-confinement-v2-ipv6-literal-reject = mkEvalRejectCheck "vpn-confinement-v2-ipv6-literal-reject" ../../tests/nixos/vpn-confinement-v2-ipv6-literal-reject.nix;

      checks.vpn-confinement-v2-cidr-prefix-reject = mkEvalRejectCheck "vpn-confinement-v2-cidr-prefix-reject" ../../tests/nixos/vpn-confinement-v2-cidr-prefix-reject.nix;

      checks.vpn-confinement-v2-interface-name-validation-reject = mkEvalRejectCheck "vpn-confinement-v2-interface-name-validation-reject" ../../tests/nixos/vpn-confinement-v2-interface-name-validation-reject.nix;

      checks.vpn-confinement-v2-hostlink-subnet-prefix-reject = mkEvalRejectCheck "vpn-confinement-v2-hostlink-subnet-prefix-reject" ../../tests/nixos/vpn-confinement-v2-hostlink-subnet-prefix-reject.nix;

      checks.vpn-confinement-v2-hostlink-subnet-collision-reject = mkEvalRejectCheck "vpn-confinement-v2-hostlink-subnet-collision-reject" ../../tests/nixos/vpn-confinement-v2-hostlink-subnet-collision-reject.nix;

      checks.vpn-confinement-v2-hostlink-interface-conflict-reject = mkEvalRejectCheck "vpn-confinement-v2-hostlink-interface-conflict-reject" ../../tests/nixos/vpn-confinement-v2-hostlink-interface-conflict-reject.nix;

      checks.vpn-confinement-v2-wireguard-namespace-ownership-reject = mkEvalRejectCheck "vpn-confinement-v2-wireguard-namespace-ownership-reject" ../../tests/nixos/vpn-confinement-v2-wireguard-namespace-ownership-reject.nix;

      checks.vpn-confinement-v2-wireguard-socket-namespace-ownership-reject = mkEvalRejectCheck "vpn-confinement-v2-wireguard-socket-namespace-ownership-reject" ../../tests/nixos/vpn-confinement-v2-wireguard-socket-namespace-ownership-reject.nix;

      checks.vpn-confinement-v2-wireguard-socket-namespace-name-reject = mkEvalRejectCheck "vpn-confinement-v2-wireguard-socket-namespace-name-reject" ../../tests/nixos/vpn-confinement-v2-wireguard-socket-namespace-name-reject.nix;

      checks.vpn-confinement-v2-api-removal-reject = mkEvalRejectCheck "vpn-confinement-v2-api-removal-reject" ../../tests/nixos/vpn-confinement-v2-api-removal-reject.nix;

      checks.vpn-confinement-v2-advanced-option-removal-reject = mkEvalRejectCheck "vpn-confinement-v2-advanced-option-removal-reject" ../../tests/nixos/vpn-confinement-v2-advanced-option-removal-reject.nix;

      checks.vpn-confinement-v2-root-warning =
        let
          cfg = evalNode ../../tests/nixos/vpn-confinement-v2-root-warning.nix;
          inherit (cfg) warnings;
          hasWarning = builtins.any (
            warning: builtins.match ".*vpn\\.enable = true but still runs as root.*" warning != null
          ) warnings;
        in
        pkgs.runCommand "vpn-confinement-v2-root-warning" { } ''
          if [ "${if hasWarning then "1" else "0"}" -ne 1 ]; then
            echo "expected root hardening warning for vpn-enabled service" >&2
            exit 1
          fi
          touch "$out"
        '';

      checks.vpn-confinement-v2-wireguard-warnings =
        let
          cfg = evalNode ../../tests/nixos/vpn-confinement-v2-wireguard-warnings.nix;
          inherit (cfg) warnings;
          hasHostnameWarning = builtins.any (
            warning: builtins.match ".*uses hostname WireGuard peer endpoints.*" warning != null
          ) warnings;
          hasRouteWarning = builtins.any (
            warning: builtins.match ".*allowedIPsAsRoutes = false.*" warning != null
          ) warnings;
        in
        pkgs.runCommand "vpn-confinement-v2-wireguard-warnings" { } ''
          if [ "${if hasHostnameWarning then "1" else "0"}" -ne 1 ]; then
            echo "expected hostname endpoint warning" >&2
            exit 1
          fi
          if [ "${if hasRouteWarning then "1" else "0"}" -ne 1 ]; then
            echo "expected allowedIPsAsRoutes warning" >&2
            exit 1
          fi
          touch "$out"
        '';
    };
}
