{
  perSystem =
    { pkgs, config, ... }:
    {
      devShells.default =
        let
          inherit (config.pre-commit.settings) shellHook enabledPackages;
        in
        pkgs.mkShellNoCC {
          inherit shellHook;
          packages =
            enabledPackages
            ++ (with pkgs; [
              nh
              just
              bashInteractive
            ]);
        };
    };
}
