{
  lib,
  root,
  extra ? { },
}:
let
  files = lib.filterAttrs (
    name: type: type == "regular" && lib.hasPrefix "runtime-" name && lib.hasSuffix ".nix" name
  ) (builtins.readDir root);
  discovered = lib.mapAttrs' (
    name: _:
    lib.nameValuePair
      # Preserve this established check name while discovering the file normally.
      (
        if name == "runtime-safety.nix" then
          "vm-runtime-safety"
        else
          "vm-${lib.removeSuffix ".nix" (lib.removePrefix "runtime-" name)}"
      )
      (root + "/${name}")
  ) files;
in
assert lib.assertMsg (
  builtins.length (builtins.attrNames discovered) == builtins.length (builtins.attrNames files)
) "Runtime test files produce duplicate check names";
assert lib.assertMsg (
  builtins.intersectAttrs discovered extra == { }
) "Discovered runtime tests collide with explicit dual-coverage checks";
discovered // extra
