_: {
  perSystem =
    { pkgs, ... }:
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

      checks.vpn-confinement-v2-socket-activation-reject =
        let
          socketRejectNode =
            (import ../../tests/nixos/vpn-confinement-v2-socket-activation-reject.nix { inherit pkgs; })
            .nodes.machine;
          socketActivationEval =
            builtins.tryEval
              (import (pkgs.path + "/nixos/lib/eval-config.nix") {
                inherit (pkgs.stdenv.hostPlatform) system;
                modules = [ socketRejectNode ];
              }).config.system.build.toplevel;
        in
        pkgs.runCommand "vpn-confinement-v2-socket-activation-reject" { } ''
          if [ "${if socketActivationEval.success then "1" else "0"}" -eq 1 ]; then
            echo "expected NixOS evaluation failure for socket-activation rejection" >&2
            exit 1
          fi
          touch "$out"
        '';
    };
}
