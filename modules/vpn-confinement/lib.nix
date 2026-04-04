{ lib }:
let
  inherit (lib)
    all
    concatMapStringsSep
    foldl'
    hasInfix
    length
    optionalString
    removeSuffix
    splitString
    unique
    ;

  ipv4Match =
    value: builtins.match "^([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})$" value;

  ipv4OctetValid =
    octet:
    let
      parsed = builtins.tryEval (builtins.fromJSON octet);
    in
    parsed.success && builtins.isInt parsed.value && parsed.value >= 0 && parsed.value <= 255;

  isLiteralIpv4 =
    value:
    let
      match = ipv4Match value;
    in
    match != null && all ipv4OctetValid match;

  parseNumber =
    value:
    let
      parsed = builtins.tryEval (builtins.fromJSON value);
    in
    if builtins.match "^[0-9]+$" value == null || !parsed.success || !(builtins.isInt parsed.value) then
      null
    else
      parsed.value;

  intMod = a: b: a - (builtins.div a b) * b;

  stringChars =
    value: builtins.genList (idx: builtins.substring idx 1 value) (builtins.stringLength value);

  hexDigitValue =
    digit:
    if digit == "0" then
      0
    else if digit == "1" then
      1
    else if digit == "2" then
      2
    else if digit == "3" then
      3
    else if digit == "4" then
      4
    else if digit == "5" then
      5
    else if digit == "6" then
      6
    else if digit == "7" then
      7
    else if digit == "8" then
      8
    else if digit == "9" then
      9
    else if digit == "a" || digit == "A" then
      10
    else if digit == "b" || digit == "B" then
      11
    else if digit == "c" || digit == "C" then
      12
    else if digit == "d" || digit == "D" then
      13
    else if digit == "e" || digit == "E" then
      14
    else if digit == "f" || digit == "F" then
      15
    else
      null;

  hexToInt =
    value:
    foldl' (
      acc: digit:
      if acc == null then
        null
      else
        let
          parsed = hexDigitValue digit;
        in
        if parsed == null then null else acc * 16 + parsed
    ) 0 (stringChars value);

  isValidHextet = value: builtins.match "^[0-9A-Fa-f]{1,4}$" value != null;

  hasEmptyPart = parts: builtins.any (part: part == "") parts;

  parseIpv6Side =
    parts:
    let
      indexed = builtins.genList (idx: {
        inherit idx;
        part = builtins.elemAt parts idx;
      }) (length parts);
      ipv4Tail = builtins.filter (item: isLiteralIpv4 item.part) indexed;
      ipv4TailValid =
        length ipv4Tail == 0
        || (length ipv4Tail == 1 && (builtins.head ipv4Tail).idx == (length parts - 1));
      partsValid = all (item: isValidHextet item.part || isLiteralIpv4 item.part) indexed;
      groups = builtins.foldl' (acc: item: acc + (if isLiteralIpv4 item.part then 2 else 1)) 0 indexed;
    in
    {
      valid = (!hasEmptyPart parts) && ipv4TailValid && partsValid;
      inherit groups;
    };

  parseIpv6Literal =
    value:
    if value == "" || !hasInfix ":" value || hasInfix "/" value || hasInfix "%" value then
      false
    else if hasInfix "::" value then
      let
        compressed = splitString "::" value;
      in
      if length compressed != 2 then
        false
      else
        let
          leftRaw = builtins.elemAt compressed 0;
          rightRaw = builtins.elemAt compressed 1;
          left =
            if leftRaw == "" then
              {
                valid = true;
                groups = 0;
              }
            else
              parseIpv6Side (splitString ":" leftRaw);
          right =
            if rightRaw == "" then
              {
                valid = true;
                groups = 0;
              }
            else
              parseIpv6Side (splitString ":" rightRaw);
          explicitGroups = left.groups + right.groups;
        in
        left.valid && right.valid && explicitGroups < 8
    else
      let
        parsed = parseIpv6Side (splitString ":" value);
      in
      parsed.valid && parsed.groups == 8;

  isLiteralIpv6 = parseIpv6Literal;

  dnsSplit = servers: {
    ipv4 = builtins.filter isLiteralIpv4 servers;
    ipv6 = builtins.filter isLiteralIpv6 servers;
  };

  parsePrefix = parseNumber;

  parsePort =
    value:
    let
      parsed = parseNumber value;
    in
    if builtins.match "^[0-9]{1,5}$" value == null || parsed == null then null else parsed;

  parseCidr =
    value:
    let
      parts = splitString "/" value;
      partsLen = length parts;
    in
    if partsLen == 1 then
      {
        address = builtins.elemAt parts 0;
        hasPrefix = false;
        prefix = null;
      }
    else if partsLen == 2 then
      let
        prefix = parsePrefix (builtins.elemAt parts 1);
      in
      if prefix == null then
        null
      else
        {
          address = builtins.elemAt parts 0;
          hasPrefix = true;
          inherit prefix;
        }
    else
      null;

  parseLiteralIpv4Cidr =
    value:
    let
      parsed = parseCidr value;
    in
    if parsed == null || !isLiteralIpv4 parsed.address then null else parsed;

  isLiteralIpv4Cidr =
    value:
    let
      parsed = parseLiteralIpv4Cidr value;
    in
    parsed != null && ((!parsed.hasPrefix) || (parsed.prefix >= 0 && parsed.prefix <= 32));

  isLiteralIpv6Cidr =
    value:
    let
      parsed = parseCidr value;
    in
    parsed != null
    && isLiteralIpv6 parsed.address
    && ((!parsed.hasPrefix) || (parsed.prefix >= 0 && parsed.prefix <= 128));

  isLiteralCidr = value: isLiteralIpv4Cidr value || isLiteralIpv6Cidr value;

  cidrSplit = values: {
    ipv4 = builtins.filter isLiteralIpv4Cidr values;
    ipv6 = builtins.filter isLiteralIpv6Cidr values;
    invalid = builtins.filter (value: !isLiteralCidr value) values;
  };

  isValidPort = value: value >= 1 && value <= 65535;

  endpointIpv4Match =
    value: builtins.match "^([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}):([0-9]{1,5})$" value;

  endpointIpv6Match = value: builtins.match "^[[](.+)[]]:([0-9]{1,5})$" value;

  endpointHostnameMatch = value: builtins.match "^([^:]+):([0-9]{1,5})$" value;

  isLiteralIpv4Endpoint =
    value:
    let
      match = endpointIpv4Match value;
      port = if match == null then null else parsePort (builtins.elemAt match 1);
    in
    match != null && isLiteralIpv4 (builtins.elemAt match 0) && port != null && isValidPort port;

  isLiteralIpv6Endpoint =
    value:
    let
      match = endpointIpv6Match value;
      port = if match == null then null else parsePort (builtins.elemAt match 1);
    in
    match != null && isLiteralIpv6 (builtins.elemAt match 0) && port != null && isValidPort port;

  hostnameLabelMatch = label: builtins.match "^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$" label;

  stripOptionalTrailingDot =
    value: if builtins.match ".*[.]$" value != null then removeSuffix "." value else value;

  hasWhitespace = value: builtins.match ".*[[:space:]].*" value != null;

  isHostname =
    value:
    let
      labels = splitString "." value;
    in
    builtins.stringLength value >= 1
    && builtins.stringLength value <= 253
    && labels != [ ]
    && all (label: label != "" && hostnameLabelMatch label != null) labels;

  isHostnameEndpoint =
    value:
    let
      match = endpointHostnameMatch value;
      host = if match == null then null else builtins.elemAt match 0;
      port = if match == null then null else parsePort (builtins.elemAt match 1);
    in
    match != null
    && host != null
    && isHostname host
    && port != null
    && isValidPort port
    && !isLiteralIpv4 host
    && !isLiteralIpv6 host;

  isSearchDomain =
    value:
    let
      normalized = stripOptionalTrailingDot value;
      labels = splitString "." normalized;
    in
    builtins.stringLength value >= 1
    && builtins.stringLength value <= 254
    && !hasWhitespace value
    && normalized != ""
    && labels != [ ]
    && all (label: label != "" && hostnameLabelMatch label != null) labels;

  isSupportedEndpoint =
    value: isLiteralIpv4Endpoint value || isLiteralIpv6Endpoint value || isHostnameEndpoint value;

  isValidNamespaceName =
    value:
    builtins.stringLength value >= 1
    && builtins.stringLength value <= 64
    && builtins.match "^[A-Za-z0-9_.-]+$" value != null;

  isValidInterfaceName =
    value:
    builtins.stringLength value >= 1
    && builtins.stringLength value <= 15
    && builtins.match "^[A-Za-z0-9_.-]+$" value != null;

  isLiteralIpv4Slash30 =
    value:
    let
      parsed = parseLiteralIpv4Cidr value;
      octets = if parsed == null then [ ] else splitString "." parsed.address;
      lastOctet = if length octets == 4 then parseNumber (builtins.elemAt octets 3) else null;
    in
    parsed != null
    && parsed.hasPrefix
    && parsed.prefix == 30
    && lastOctet != null
    && lastOctet <= 252
    && intMod lastOctet 4 == 0;

  deriveHostLinkPair =
    subnet:
    let
      parsed = parseLiteralIpv4Cidr subnet;
      octets = if parsed == null then [ ] else splitString "." parsed.address;
      lastOctet = if length octets == 4 then parseNumber (builtins.elemAt octets 3) else null;
      prefixValid = parsed != null && parsed.hasPrefix && parsed.prefix == 30;
      baseValid = lastOctet != null && lastOctet <= 252 && intMod lastOctet 4 == 0;
      prefix = concatMapStringsSep "." (idx: builtins.elemAt octets idx) [
        0
        1
        2
      ];
      hostOctet = if lastOctet == null then null else lastOctet + 1;
      nsOctet = if lastOctet == null then null else lastOctet + 2;
    in
    if !prefixValid || !baseValid then
      null
    else
      {
        subnetIPv4 = "${parsed.address}/${toString parsed.prefix}";
        hostAddressIPv4 = "${prefix}.${toString hostOctet}";
        nsAddressIPv4 = "${prefix}.${toString nsOctet}";
      };

  hostLinkSubnetFromNamespace =
    namespaceName:
    let
      digest = builtins.hashString "sha256" namespaceName;
      idx = intMod (hexToInt (builtins.substring 0 8 digest)) 16384;
      base = idx * 4;
      third = builtins.div base 256;
      fourth = intMod base 256;
    in
    "169.254.${toString third}.${toString fourth}/30";
in
{
  uniquePorts = unique;

  renderNftSetElements = values: "{ ${concatMapStringsSep ", " toString values} }";

  renderPortSet = values: "{ ${concatMapStringsSep ", " toString values} }";

  splitDns = dnsSplit;

  isLiteralIp = value: isLiteralIpv4 value || isLiteralIpv6 value;

  inherit isLiteralIpv4;

  inherit isLiteralIpv4Slash30;

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
    hosts: files myhostname dns
    networks: files
    protocols: files
    services: files
    ethers: files
    rpc: files
  '';

  splitCidrs = cidrSplit;

  inherit isLiteralCidr;

  isLiteralEndpoint = value: isLiteralIpv4Endpoint value || isLiteralIpv6Endpoint value;

  inherit isSupportedEndpoint;

  endpointIsHostname = isHostnameEndpoint;

  inherit deriveHostLinkPair;

  inherit hostLinkSubnetFromNamespace;

  inherit isValidInterfaceName;

  inherit isValidNamespaceName;

  inherit isSearchDomain;

  splitIpv4 = ip: splitString "." ip;
}
