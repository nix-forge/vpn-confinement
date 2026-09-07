{ lib }:
let
  inherit (lib) optionalString concatMapStringsSep unique;
  vpnLib = import ./lib.nix { inherit lib; };
  blockedDnsPorts = [
    53
    853
    5353
    5355
  ];
  mkNftSet =
    name: typeName: withInterval: elements:
    if elements == [ ] then
      ""
    else
      ''
        set ${name} {
          type ${typeName};
          ${optionalString withInterval "flags interval; auto-merge;"}
          elements = ${vpnLib.renderNftSetElements elements};
        }
      '';

  mkDnsSetDefinitions =
    ns:
    let
      dns = vpnLib.splitDns ns.dns.servers;
    in
    ''
      ${mkNftSet "dns_servers_v4" "ipv4_addr" false dns.ipv4}
      ${optionalString (ns.ipv6.mode == "tunnel") (mkNftSet "dns_servers_v6" "ipv6_addr" false dns.ipv6)}
      ${mkNftSet "dns_blocked_ports" "inet_service" false blockedDnsPorts}
    '';

  mkDnsBlockedPortRules = ns: ''
    oifname "${ns.wireguard.interface}" udp dport @dns_blocked_ports drop
    oifname "${ns.wireguard.interface}" tcp dport @dns_blocked_ports drop
  '';

  mkDnsOutputRules =
    ns:
    let
      dns = vpnLib.splitDns ns.dns.servers;
      hasV4 = dns.ipv4 != [ ];
      hasV6 = dns.ipv6 != [ ] && ns.ipv6.mode == "tunnel";
    in
    ''
      ${optionalString hasV4 ''
        oifname "${ns.wireguard.interface}" ip daddr @dns_servers_v4 udp dport 53 accept
        oifname "${ns.wireguard.interface}" ip daddr @dns_servers_v4 tcp dport 53 accept
      ''}
      ${optionalString hasV6 ''
        oifname "${ns.wireguard.interface}" ip6 daddr @dns_servers_v6 udp dport 53 accept
        oifname "${ns.wireguard.interface}" ip6 daddr @dns_servers_v6 tcp dport 53 accept
      ''}
      oifname "${ns.wireguard.interface}" udp dport 53 drop
      oifname "${ns.wireguard.interface}" tcp dport 53 drop
    '';

  mkEgressSetDefinitions =
    ns:
    let
      allowedTcp = unique ns.egress.allowedTcpPorts;
      allowedUdp = unique ns.egress.allowedUdpPorts;
      allowedCidrs = unique ns.egress.allowedCidrs;
      cidrs = vpnLib.splitCidrs allowedCidrs;
    in
    ''
      ${mkNftSet "allowed_tcp_ports" "inet_service" false allowedTcp}
      ${mkNftSet "allowed_udp_ports" "inet_service" false allowedUdp}
      ${mkNftSet "allowed_ipv4_cidrs" "ipv4_addr" true cidrs.ipv4}
      ${optionalString (ns.ipv6.mode == "tunnel") (
        mkNftSet "allowed_ipv6_cidrs" "ipv6_addr" true cidrs.ipv6
      )}
    '';

  mkEgressRules =
    ns:
    let
      allowedTcp = unique ns.egress.allowedTcpPorts;
      allowedUdp = unique ns.egress.allowedUdpPorts;
      allowedCidrs = unique ns.egress.allowedCidrs;
      cidrs = vpnLib.splitCidrs allowedCidrs;

      essentialIcmpRules =
        if !(ns.egress.allowEssentialIcmp && allowedCidrs != [ ]) then
          ""
        else
          concatMapStringsSep "\n" (rule: rule) (
            lib.optionals (cidrs.ipv4 != [ ]) [
              ''oifname "${ns.wireguard.interface}" ip daddr @allowed_ipv4_cidrs icmp type { destination-unreachable, time-exceeded, parameter-problem } accept''
            ]
            ++ lib.optionals (cidrs.ipv6 != [ ]) [
              ''oifname "${ns.wireguard.interface}" ip6 daddr @allowed_ipv6_cidrs icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem } accept''
            ]
          );

      mkPortRule =
        proto: ports:
        if ports == [ ] then
          ""
        else if allowedCidrs == [ ] then
          "oifname \"${ns.wireguard.interface}\" ${proto} dport @allowed_${proto}_ports accept"
        else
          concatMapStringsSep "\n" (rule: rule) (
            lib.optionals (cidrs.ipv4 != [ ]) [
              "oifname \"${ns.wireguard.interface}\" ip daddr @allowed_ipv4_cidrs ${proto} dport @allowed_${proto}_ports accept"
            ]
            ++ lib.optionals (cidrs.ipv6 != [ ]) [
              "oifname \"${ns.wireguard.interface}\" ip6 daddr @allowed_ipv6_cidrs ${proto} dport @allowed_${proto}_ports accept"
            ]
          );

      cidrOnlyRules =
        if allowedCidrs == [ ] || allowedTcp != [ ] || allowedUdp != [ ] then
          ""
        else
          concatMapStringsSep "\n" (rule: rule) (
            lib.optionals (cidrs.ipv4 != [ ]) [
              "oifname \"${ns.wireguard.interface}\" ip daddr @allowed_ipv4_cidrs accept"
            ]
            ++ lib.optionals (cidrs.ipv6 != [ ]) [
              "oifname \"${ns.wireguard.interface}\" ip6 daddr @allowed_ipv6_cidrs accept"
            ]
          );
    in
    ''
      ${essentialIcmpRules}
      ${mkPortRule "tcp" allowedTcp}
      ${mkPortRule "udp" allowedUdp}
      ${cidrOnlyRules}
    '';

  mkNftRules =
    nsName: ns:
    let
      policy = vpnLib.effectiveNamespace nsName ns;
      hostIngressTcp = policy.fromHostTcp;
      inboundTcp = unique ns.ingress.fromTunnel.tcp;
      inboundUdp = unique ns.ingress.fromTunnel.udp;
      inherit (policy) withHostLink;
      strictDns = ns.dns.mode == "strict";
    in
    ''
      destroy table inet vpnc
      table inet vpnc {
        ${optionalString strictDns (mkDnsSetDefinitions ns)}
        ${optionalString (ns.egress.mode == "allowList") (mkEgressSetDefinitions ns)}

        chain input {
          type filter hook input priority filter; policy drop;
          iifname "lo" accept
          ct state invalid drop
          ${optionalString (ns.ipv6.mode == "disable") "meta nfproto ipv6 drop"}
          iifname "${ns.wireguard.interface}" ct state established,related accept
          ${optionalString (withHostLink && hostIngressTcp != [ ])
            "iifname \"${ns.hostLink.nsIf}\" ip saddr ${policy.hostLink.hostAddressIPv4} tcp dport ${vpnLib.renderPortSet hostIngressTcp} accept"
          }
          ${optionalString (
            inboundTcp != [ ]
          ) "iifname \"${ns.wireguard.interface}\" tcp dport ${vpnLib.renderPortSet inboundTcp} accept"}
          ${optionalString (
            inboundUdp != [ ]
          ) "iifname \"${ns.wireguard.interface}\" udp dport ${vpnLib.renderPortSet inboundUdp} accept"}
        }

        chain forward {
          type filter hook forward priority filter; policy drop;
        }

        chain output {
          type filter hook output priority filter; policy drop;
          oifname "lo" accept
          ct state invalid drop
          ${optionalString (ns.ipv6.mode == "disable") "meta nfproto ipv6 drop"}
          oifname "${ns.wireguard.interface}" ct state established,related accept
          ${optionalString (withHostLink && hostIngressTcp != [ ])
            "oifname \"${ns.hostLink.nsIf}\" ip daddr ${policy.hostLink.hostAddressIPv4} tcp sport ${vpnLib.renderPortSet hostIngressTcp} ct direction reply ct state established accept"
          }
          ${optionalString strictDns (mkDnsOutputRules ns)}
          ${optionalString strictDns (mkDnsBlockedPortRules ns)}
          ${optionalString (ns.egress.mode == "allowList") (mkEgressRules ns)}
          ${optionalString (
            ns.egress.mode == "allowAllTunnel"
          ) "oifname \"${ns.wireguard.interface}\" accept"}
        }
      }
    '';

in
{
  inherit mkNftRules;
}
