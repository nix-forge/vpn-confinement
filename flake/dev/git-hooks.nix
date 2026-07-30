{ inputs, ... }: {
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
        # Hook runners need PTY support, which is unavailable in Linux Nix
        # build sandboxes. CI runs the same hooks directly in its lint job.
        check.enable = pkgs.stdenv.hostPlatform.isDarwin;

        settings = {
          hooks = {
            treefmt = {
              enable = true;
              name = "treefmt";
              pass_filenames = true;
              entry = "${lib.getExe config.treefmt.build.wrapper} --no-cache";
            };

            oxlint = {
              enable = true;
              name = "Oxlint";
              package = pkgs.oxlint;
              entry = "${lib.getExe pkgs.oxlint} -D correctness -D suspicious -W perf --report-unused-disable-directives";
              files = "^site/.*\\.(astro|[cm]?[jt]sx?)$";
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

            editorconfig-checker.enable = true;
            typos = {
              enable = true;
              settings.configPath = ".typos.toml";
            };
            zizmor = {
              enable = true;
              args = [
                "--persona=pedantic"
                "--min-severity=medium"
              ];
            };
            gitleaks = {
              enable = true;
              name = "Gitleaks";
              package = pkgs.gitleaks;
              entry = "${lib.getExe pkgs.gitleaks} git --pre-commit --staged --redact --no-banner";
              pass_filenames = false;
            };

            flake-checker.enable = true;
          };
        };
      };
    };
}
