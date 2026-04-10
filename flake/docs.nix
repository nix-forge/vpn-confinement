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

      repoBlobBase = "https://github.com/IanHollow/vpn-confinement/blob/main";
      optionsJsonPath = "${optionsDoc.optionsJSON}/share/doc/nixos/options.json";

      generatedMarkdown =
        pkgs.runCommand "vpn-confinement-options-generated.md" { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
            python - <<'PY'
            import json
            import os
            import pathlib
            import re

            repo_blob_base = "${repoBlobBase}"
            options_json_path = pathlib.Path("${optionsJsonPath}")
            output_path = pathlib.Path(os.environ["out"])

            options = json.loads(options_json_path.read_text())
            option_names = sorted(options)

            def literal_text(value):
                if value is None:
                    return None
                if isinstance(value, dict):
                    text = value.get("text")
                    if text is not None:
                        return str(text).strip()
                return str(value).strip()

            lines = [
                "---",
                "title: Generated Options",
                "description: Auto-generated option reference from nixosOptionsDoc",
                "---",
                "",
                "This file is generated from module option declarations using `pkgs.nixosOptionsDoc`.",
                "",
                "Regenerate with:",
                "",
                "```bash",
                "bash scripts/generate-options-doc.sh x86_64-linux",
                "```",
                "",
            ]

            for name in option_names:
                option = options[name]
                description = str(option.get("description", "")).strip()
                option_type = str(option.get("type", "unknown")).strip()
                if option.get("readOnly"):
                    option_type = f"{option_type} (read-only)"

                lines.append(f"## `{name}`")
                lines.append("")

                if description:
                    lines.append(description)
                    lines.append("")

                lines.append(f"- **Type:** {option_type}")

                default = literal_text(option.get("default"))
                if default:
                    lines.append("- **Default:**")
                    lines.append("```nix")
                    lines.append(default)
                    lines.append("```")

                example = literal_text(option.get("example"))
                if example:
                    lines.append("- **Example:**")
                    lines.append("```nix")
                    lines.append(example)
                    lines.append("```")

                declarations = option.get("declarations", [])
                if declarations:
                    lines.append("- **Declared by:**")
                    for declaration in declarations:
                        declaration_string = str(declaration).strip()
                        match = re.search(r"(modules/vpn-confinement/.*\\.nix)$", declaration_string)
                        relative_path = match.group(1) if match else declaration_string
                        if relative_path.startswith("modules/vpn-confinement/"):
                            url = f"{repo_blob_base}/{relative_path}"
                            lines.append(f"  - [`{relative_path}`]({url})")
                        else:
                            lines.append(f"  - `{relative_path}`")

                lines.append("")

            output_path.write_text("\n".join(lines).rstrip() + "\n")
            PY
          '';
    in
    {
      packages.options-doc-markdown = generatedMarkdown;
    };
}
