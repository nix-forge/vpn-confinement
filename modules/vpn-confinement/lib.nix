{ lib }:
let
  inherit (lib)
    all
    concatMapStringsSep
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
      canonical = builtins.match "^(0|[1-9][0-9]{0,2})$" octet != null;
      parsed = if canonical then builtins.fromJSON octet else null;
    in
    canonical && builtins.isInt parsed && parsed >= 0 && parsed <= 255;

  isLiteralIpv4 =
    value:
    let
      match = ipv4Match value;
    in
    match != null && all ipv4OctetValid match;

  parseNumber =
    value:
    let
      canonical = builtins.stringLength value <= 5 && builtins.match "^(0|[1-9][0-9]*)$" value != null;
    in
    if canonical then builtins.fromJSON value else null;

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
      hasIpv4 = ipv4Tail != [ ];
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
                hasIpv4 = false;
                groups = 0;
              }
            else
              parseIpv6Side (splitString ":" leftRaw);
          right =
            if rightRaw == "" then
              {
                valid = true;
                hasIpv4 = false;
                groups = 0;
              }
            else
              parseIpv6Side (splitString ":" rightRaw);
          explicitGroups = left.groups + right.groups;
        in
        left.valid && right.valid && !left.hasIpv4 && explicitGroups < 8
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

  parseLiteralEndpoint =
    value:
    let
      ipv4Match = endpointIpv4Match value;
      ipv6Match = endpointIpv6Match value;
      ipv4Port = if ipv4Match == null then null else parsePort (builtins.elemAt ipv4Match 1);
      ipv6Port = if ipv6Match == null then null else parsePort (builtins.elemAt ipv6Match 1);
      ipv4Address = if ipv4Match == null then null else builtins.elemAt ipv4Match 0;
      ipv6Address = if ipv6Match == null then null else builtins.elemAt ipv6Match 0;
    in
    if ipv4Match != null && isLiteralIpv4 ipv4Address && ipv4Port != null && isValidPort ipv4Port then
      {
        family = "ip";
        address = ipv4Address;
        port = ipv4Port;
      }
    else if
      ipv6Match != null && isLiteralIpv6 ipv6Address && ipv6Port != null && isValidPort ipv6Port
    then
      {
        family = "ip6";
        address = ipv6Address;
        port = ipv6Port;
      }
    else
      null;

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
    && builtins.match "^[A-Za-z0-9]([A-Za-z0-9_.-]{0,62}[A-Za-z0-9])?$" value != null;

  isValidInterfaceName =
    value:
    builtins.stringLength value >= 1
    && builtins.stringLength value <= 15
    && builtins.match "^[A-Za-z0-9]([A-Za-z0-9_.-]{0,13}[A-Za-z0-9])?$" value != null;

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
    && lib.mod lastOctet 4 == 0;

  deriveHostLinkPair =
    subnet:
    let
      parsed = parseLiteralIpv4Cidr subnet;
      octets = if parsed == null then [ ] else splitString "." parsed.address;
      lastOctet = if length octets == 4 then parseNumber (builtins.elemAt octets 3) else null;
      prefixValid = parsed != null && parsed.hasPrefix && parsed.prefix == 30;
      baseValid = lastOctet != null && lastOctet <= 252 && lib.mod lastOctet 4 == 0;
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
      idx = lib.mod (lib.fromHexString (builtins.substring 0 8 digest)) 16384;
      base = idx * 4;
      third = builtins.div base 256;
      fourth = lib.mod base 256;
    in
    "169.254.${toString third}.${toString fourth}/30";

  deriveHostLinkInterfaceName =
    role: namespaceName:
    let
      prefix = if role == "host" then "vh-" else "vn-";
      digest = builtins.hashString "sha256" "${role}:${namespaceName}";
      suffixLength = 15 - builtins.stringLength prefix;
    in
    "${prefix}${builtins.substring 0 suffixLength digest}";

  deriveWireguardFwMark =
    interfaceName:
    let
      digest = builtins.hashString "sha256" interfaceName;
      raw = lib.fromHexString (builtins.substring 0 8 digest);
    in
    lib.mod raw 4294967294 + 1;

  systemdWords =
    value:
    lib.concatMap (
      item:
      builtins.filter (word: builtins.isString word && word != "") (builtins.split "[[:space:]]+" item)
    ) (lib.toList value);

  privilegedCommand =
    command:
    let
      plain = builtins.match "^[[:space:]]*[-@:|]*[/A-Za-z0-9_][A-Za-z0-9_./-]*([[:space:]].*)?$" command;
      multiple = builtins.match ".*[[:space:]];([[:space:]].*)?$" command != null;
    in
    builtins.match "^[[:space:]]*$" command == null
    && (plain == null || multiple || lib.hasInfix "\n" command || lib.hasInfix "\r" command);

  selectedNamespace =
    cfg: unit: if unit.vpn.namespace != null then unit.vpn.namespace else cfg.defaultNamespace;

  socketTarget =
    name: socket:
    let
      values = lib.toList (socket.socketConfig.Service or null);
      configured = if values == [ ] then null else lib.last values;
      acceptValues = lib.toList (socket.socketConfig.Accept or false);
      accept = if acceptValues == [ ] then false else lib.last acceptValues;
      accepting = builtins.elem accept [
        true
        1
        "1"
        "yes"
        "true"
        "on"
      ];
      knownAccept =
        accepting
        || builtins.elem accept [
          false
          0
          "0"
          "no"
          "false"
          "off"
          ""
        ];
    in
    if configured != null && configured != "" then
      configured
    else if !knownAccept then
      "<unknown-socket-target>"
    else
      "${name}${lib.optionalString accepting "@"}.service";

  serviceMatches =
    name: service: target:
    target == "${name}.service"
    || builtins.elem target (service.aliases or [ ])
    || (lib.hasSuffix "@" name && lib.hasPrefix (lib.removeSuffix "@" name + "@") target)
    || (lib.hasInfix "@" name && target == "${builtins.head (lib.splitString "@" name)}@.service");
in
{
  inherit systemdWords selectedNamespace socketTarget;

  privilegedCommandPhases =
    serviceConfig:
    builtins.filter (field: builtins.any privilegedCommand (lib.toList (serviceConfig.${field} or [ ])))
      [
        "ExecCondition"
        "ExecStartPre"
        "ExecStart"
        "ExecStartPost"
        "ExecReload"
        "ExecStop"
        "ExecStopPost"
      ];

  unconfinedSockets =
    cfg: services: sockets: name:
    let
      service = services.${name};
      nsName = selectedNamespace cfg service;
      explicit = systemdWords (service.serviceConfig.Sockets or [ ]);
      associated = lib.attrNames (
        lib.filterAttrs (
          socketName: socket:
          (socket.enable or true)
          && (
            serviceMatches name service (socketTarget socketName socket)
            || builtins.match "[A-Za-z0-9_.@:-]+[.]service" (socketTarget socketName socket) == null
            || builtins.elem "${socketName}.socket" explicit
            || builtins.any (alias: builtins.elem alias explicit) (socket.aliases or [ ])
          )
        ) sockets
      );
      resolve =
        unit:
        lib.findFirst (
          socketName:
          unit == "${socketName}.socket" || builtins.elem unit (sockets.${socketName}.aliases or [ ])
        ) null (lib.attrNames sockets);
      unresolved = builtins.filter (unit: resolve unit == null) explicit;
      confined =
        socketName:
        let
          socket = sockets.${socketName};
        in
        nsName != null
        && (socket.vpn.enable or false)
        && selectedNamespace cfg socket == nsName
        && (socket.socketConfig.NetworkNamespacePath or null) == "/run/netns/${nsName}";
    in
    unique ((map (n: "${n}.socket") (builtins.filter (n: !confined n) associated)) ++ unresolved);

  unsafeCapabilities =
    serviceConfig:
    let
      caps = map (lib.replaceStrings [ "\"" "'" ] [ "" "" ]) (
        systemdWords (serviceConfig.CapabilityBoundingSet or "")
        ++ systemdWords (serviceConfig.AmbientCapabilities or [ ])
      );
    in
    builtins.any (
      cap:
      builtins.elem cap [
        "CAP_NET_ADMIN"
        "CAP_SYS_ADMIN"
        "CAP_NET_RAW"
      ]
      # Numeric, inverted and escaped forms require an explicit exception.
      || builtins.match "CAP_[A-Z0-9_]+" cap == null
    ) caps;

  endpointTableName = name: "vpnc_endpoint_pin_${builtins.hashString "sha256" name}";

  effectiveNamespace =
    name: ns:
    let
      withHostLink = ns.hostLink.enable || ns.publishToHost.tcp != [ ];
      subnet =
        if ns.hostLink.subnetIPv4 != null then ns.hostLink.subnetIPv4 else hostLinkSubnetFromNamespace name;
      pair = deriveHostLinkPair subnet;
    in
    {
      inherit withHostLink;
      fromHostTcp = unique ns.publishToHost.tcp;
      hostLink = {
        subnetIPv4 = subnet;
        hostAddressIPv4 = if pair == null then null else pair.hostAddressIPv4;
        nsAddressIPv4 = if pair == null then null else pair.nsAddressIPv4;
      };
    };

  uniquePorts = unique;

  renderNftSetElements = values: "{ ${concatMapStringsSep ", " toString values} }";

  renderPortSet = values: "{ ${concatMapStringsSep ", " toString values} }";

  splitDns = dnsSplit;

  isLiteralIp = value: isLiteralIpv4 value || isLiteralIpv6 value;

  inherit isLiteralIpv4;

  inherit isLiteralIpv4Slash30;

  inherit deriveHostLinkInterfaceName;

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

  inherit parseLiteralEndpoint;

  inherit isSupportedEndpoint;

  endpointIsHostname = isHostnameEndpoint;

  inherit deriveHostLinkPair;

  inherit hostLinkSubnetFromNamespace;

  inherit deriveWireguardFwMark;

  inherit isValidInterfaceName;

  inherit isValidNamespaceName;

  inherit isSearchDomain;

  splitIpv4 = ip: splitString "." ip;
}
