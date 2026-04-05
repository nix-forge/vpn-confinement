{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.partitions ];

  partitionedAttrs = {
    devShells = "dev";
    formatter = "dev";
  };

  partitions = {
    dev = {
      extraInputsFlake = ./dev;
      module.imports = [ ./dev ];
    };
  };
}
