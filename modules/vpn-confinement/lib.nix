{ lib }:
let
  inherit (lib)
    all
    concatMapStringsSep
    hasInfix
    optionalString
    splitString
    unique
    ;

  ipv4Match =
    value: builtins.match "^([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})$" value;

  ipv4OctetValid =
    octet:
    let
      parsed = builtins.fromJSON octet;
    in
    parsed >= 0 && parsed <= 255;

  isLiteralIpv4 =
    value:
    let
      match = ipv4Match value;
    in
    match != null && all ipv4OctetValid match;

  isLiteralIpv6 =
    value: hasInfix ":" value && builtins.match "^[0-9A-Fa-f:.]+$" value != null && !hasInfix "/" value;

  dnsSplit = servers: {
    ipv4 = builtins.filter isLiteralIpv4 servers;
    ipv6 = builtins.filter isLiteralIpv6 servers;
  };
in
{
  uniquePorts = unique;

  renderPortSet = ports: "{ ${concatMapStringsSep ", " toString ports} }";

  splitDns = dnsSplit;

  isLiteralIp = value: isLiteralIpv4 value || isLiteralIpv6 value;

  inherit isLiteralIpv4;

  inherit isLiteralIpv6;

  renderResolvConf =
    dns:
    let
      nameservers = concatMapStringsSep "\n" (server: "nameserver ${server}") dns.servers;
      search = optionalString (dns.search != [ ]) "search ${concatMapStringsSep " " dns.search}";
    in
    ''
      ${nameservers}
      ${search}
      options edns0
    '';

  renderNsswitchConf = _dns: ''
    passwd: files
    group: files
    shadow: files
    hosts: files dns
    networks: files
    protocols: files
    services: files
    ethers: files
    rpc: files
  '';

  normalizeCidrs =
    values:
    builtins.filter (value: builtins.match "^[0-9A-Fa-f:.]+(/[0-9]{1,3})?$" value != null) values;

  splitIpv4 = ip: splitString "." ip;
}
