_: {
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      evalPkgs = import pkgs.path { inherit system; };

      eval = import (evalPkgs.path + "/nixos/lib/eval-config.nix") {
        inherit system;
        pkgs = evalPkgs;
        modules = [ ../modules/default.nix ];
      };

      optionPrefixes = [
        "services.vpnConfinement"
        "systemd.services.<name>.vpn"
        "systemd.sockets.<name>.vpn"
      ];

      includeOption = optionName: builtins.any (prefix: lib.hasPrefix prefix optionName) optionPrefixes;

      transformDeclaration =
        declaration:
        let
          declarationString = toString declaration;
          localPathMatch = builtins.match ".*(modules/vpn-confinement/.*\\.nix)" declarationString;
        in
        if localPathMatch == null then declarationString else builtins.head localPathMatch;

      transformOptions =
        option:
        option
        // {
          visible = option.visible && includeOption option.name;
          declarations = map transformDeclaration (option.declarations or [ ]);
        };

      optionsDoc = pkgs.nixosOptionsDoc {
        inherit (eval) options;
        inherit transformOptions;
      };

      generatedMarkdown = pkgs.runCommand "vpn-confinement-options-generated.md" { } ''
                cat > "$out" <<'EOF'
        ---
        title: Generated Options
        description: Auto-generated option reference from nixosOptionsDoc
        ---

        This file is generated from module option declarations using `pkgs.nixosOptionsDoc`.

        Regenerate with:

        ```bash
        bash scripts/generate-options-doc.sh x86_64-linux
        ```

        EOF
                cat "${optionsDoc.optionsCommonMark}" >> "$out"
      '';
    in
    {
      packages.options-doc-markdown = generatedMarkdown;
    };
}
