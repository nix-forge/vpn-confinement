{ lib, config, ... }:
let
  inherit (lib)
    attrByPath
    mkEnableOption
    mkDefault
    mkIf
    mkMerge
    mkOption
    types
    ;

  rootConfig = config;
in
{
  options.systemd.sockets = mkOption {
    type = types.attrsOf (
      types.submodule (
        { config, ... }:
        let
          vcfg = rootConfig.services.vpnConfinement;
          nsName = if config.vpn.namespace != null then config.vpn.namespace else vcfg.defaultNamespace;
          ns = attrByPath [ nsName ] null vcfg.namespaces;
          nsExists = ns != null;
          wgIf = if nsExists then ns.wireguard.interface else "wg0";
        in
        {
          options.vpn = {
            enable = mkEnableOption "run this socket in the VPN confinement namespace";

            namespace = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
          };

          config = mkIf (vcfg.enable && config.vpn.enable) (mkMerge [
            {
              after = [ "vpn-confinement-netns@${nsName}.service" ];
              requires = [ "vpn-confinement-netns@${nsName}.service" ];
              bindsTo = [ "vpn-confinement-netns@${nsName}.service" ];
              socketConfig.NetworkNamespacePath = mkDefault "/run/netns/${nsName}";
            }
            (mkIf nsExists {
              after = [ "wireguard-${wgIf}.service" ];
              requires = [ "wireguard-${wgIf}.service" ];
              bindsTo = [ "wireguard-${wgIf}.service" ];
            })
          ]);
        }
      )
    );
  };
}
