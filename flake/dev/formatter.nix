{ inputs, ... }: {
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem.treefmt.programs = {
    actionlint.enable = true;

    yamlfmt = {
      enable = true;
      priority = 100;
    };
    yamllint = {
      enable = true;
      priority = 200;
      settings = {
        extends = "default";
        rules = {
          comments.min-spaces-from-content = 1;
          document-start = "disable";
          line-length = "disable";
          truthy = {
            allowed-values = [
              "true"
              "false"
            ];
            check-keys = false;
          };
        };
      };
    };

    deadnix = {
      enable = true;
      priority = 100;
    };
    statix = {
      enable = true;
      priority = 200;
    };
    nixfmt = {
      enable = true;
      width = 100;
      strict = true;
      priority = 300;
    };
    nixf-diagnose = {
      enable = true;
      autoFix = false;
      priority = 400;
    };

    shfmt = {
      enable = true;
      indent_size = 2;
      simplify = true;
      priority = 100;
    };
    shellcheck = {
      enable = true;
      priority = 200;
    };

    rumdl-check = {
      enable = true;
      priority = 200;
    };

    keep-sorted.enable = true;
    prettier = {
      enable = true;
      excludes = [
        "*.md"
        "*.yaml"
        "*.yml"
      ];
    };
  };
}
