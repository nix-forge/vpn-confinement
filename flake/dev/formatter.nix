{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem.treefmt.programs = {
    actionlint.enable = true;

    yamlfmt = {
      enable = true;
      priority = 100;
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

    keep-sorted.enable = true;
    prettier = {
      enable = true;
      excludes = [
        "*.yaml"
        "*.yml"
      ];
      settings.proseWrap = "always";
    };
  };
}
