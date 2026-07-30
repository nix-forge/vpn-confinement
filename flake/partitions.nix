{ inputs, ... }: {
  imports = [ inputs.flake-parts.flakeModules.partitions ];

  partitionedAttrs = {
    checks = "dev";
    devShells = "dev";
    formatter = "dev";
  };

  partitions.dev = {
    # The nested flake keeps development-only inputs out of the consumer lock graph.
    extraInputsFlake = ./dev;
    module.imports = [ ./dev ];
  };
}
