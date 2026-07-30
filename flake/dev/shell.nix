{
  perSystem = { pkgs, config, ... }: {
    devShells.default =
      let
        inherit (config.pre-commit.settings) shellHook enabledPackages;
      in
      pkgs.mkShellNoCC {
        inherit shellHook;
        packages =
          enabledPackages
          ++ [ config.pre-commit.settings.package ]
          ++ (with pkgs; [
            nh
            just
            nixd
            bun
            bashInteractive
          ]);
      };
  };
}
