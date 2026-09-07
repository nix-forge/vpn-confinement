{ inputs, ... }: {
  imports = [ inputs.flake-parts.flakeModules.partitions ];

  partitionedAttrs = {
    checks = "dev";
    devShells = "dev";
    formatter = "dev";
  };

  partitions.dev = {
    # The nested flake keeps development-only inputs out of the consumer lock graph.
    # Supply source metadata directly. Re-copying this nested source through
    # flake-compat's path branch fails with Determinate Nix lazy trees.
    extraInputs =
      (import (inputs.flake-parts.outPath + "/vendor/flake-compat") { src.outPath = ./dev; })
      .outputs.inputs;
    module.imports = [ ./dev ];
  };
}
