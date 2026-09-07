_: {
  perSystem = { pkgs, lib, ... }: {
    packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      vpn-benchmark = pkgs.testers.runNixOSTest {
        imports = [ ../tests/nixos/benchmark.nix ];
        defaults.virtualisation.cores = 2;
      };
      vpn-benchmark-sustained = pkgs.testers.runNixOSTest {
        imports = [ ../tests/nixos/benchmark.nix ];
        benchmark = {
          seconds = 30;
          streams = 32;
        };
        defaults.virtualisation.cores = 2;
      };
    };
  };
}
