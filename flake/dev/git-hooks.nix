{ inputs, ... }:
{
  imports = [ inputs.git-hooks-nix.flakeModule ];

  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      pre-commit = {
        settings = {
          package = pkgs.prek;
          hooks = {
            treefmt = {
              enable = true;
              name = "treefmt";
              pass_filenames = true;
              entry = "${lib.getExe config.treefmt.build.wrapper} --no-cache";
            };

            end-of-file-fixer = {
              enable = true;
              after = [ "treefmt" ];
            };
            trim-trailing-whitespace = {
              enable = true;
              after = [ "treefmt" ];
            };
            mixed-line-endings = {
              enable = true;
              args = [ "--fix=lf" ];
              after = [ "treefmt" ];
            };

            detect-private-keys.enable = true;
            check-executables-have-shebangs.enable = true;
            check-shebang-scripts-are-executable.enable = true;
            fix-byte-order-marker.enable = true;
            check-json.enable = true;
            check-toml.enable = true;
            check-yaml.enable = true;
            flake-checker.enable = true;
          };
        };
      };
    };
}
