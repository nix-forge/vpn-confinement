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

      checks.vpn-confinement-v2-socket-activation-reject = mkEvalRejectCheck "vpn-confinement-v2-socket-activation-reject" ../../tests/nixos/vpn-confinement-v2-socket-activation-reject.nix;

      checks.vpn-confinement-v2-egress-ipv6-cidr-reject = mkEvalRejectCheck "vpn-confinement-v2-egress-ipv6-cidr-reject" ../../tests/nixos/vpn-confinement-v2-egress-ipv6-cidr-reject.nix;

      checks.vpn-confinement-v2-wireguard-endpoint-literal-reject = mkEvalRejectCheck "vpn-confinement-v2-wireguard-endpoint-literal-reject" ../../tests/nixos/vpn-confinement-v2-wireguard-endpoint-literal-reject.nix;

      checks.vpn-confinement-v2-interface-name-validation-reject = mkEvalRejectCheck "vpn-confinement-v2-interface-name-validation-reject" ../../tests/nixos/vpn-confinement-v2-interface-name-validation-reject.nix;

      checks.vpn-confinement-v2-api-removal-reject = mkEvalRejectCheck "vpn-confinement-v2-api-removal-reject" ../../tests/nixos/vpn-confinement-v2-api-removal-reject.nix;

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
    };
}
