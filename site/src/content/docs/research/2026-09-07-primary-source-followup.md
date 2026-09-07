---
title: VPN isolation primary-source follow-up
description: Upstream evidence and proposed security, privacy, performance, and setup improvements
---

Research date: 2026-09-07 UTC. This note is research, not a code audit. It preserves the earlier
research notes. Statements headed "Proposal" are design recommendations, not claims about what this
repository currently implements. Upstream development branches and provider features can change;
validate implementation details against the project's pinned versions.

## Keep WireGuard as the only Internet path

WireGuard keeps its encrypted UDP socket in the network namespace where its interface was created.
Moving that interface to another namespace does not move the socket. The official guide uses this to
separate cleartext application traffic from the physical Internet interfaces.
[WireGuard namespace architecture](https://www.wireguard.com/netns/)

Proposal: keep the encrypted socket on the host and expose only loopback and WireGuard to a service
by default. Make host access an explicit addition. Without an alternate interface, route changes on
the host cannot directly give the service a cleartext Internet route. A host veth link creates
another possible path, so it needs its own narrowly scoped policy and tests.

The TunnelVision researchers demonstrate how DHCP option 121 installs more specific routes that
bypass affected routing-based VPNs. They identify Linux network namespaces as a mitigation. This is
a routing-policy attack, not a break of WireGuard encryption.
[Original disclosure and reproduction](https://github.com/leviathansecurity/TunnelVision)

Proposal: test injected host routes while the service continuously sends traffic. Namespace
architecture addresses this attack only if host connectivity, socket passing, and privileged helpers
do not reintroduce a bypass.

## Treat host sockets as separate exits

systemd documents that network namespaces isolate abstract Unix sockets, while filesystem Unix
sockets remain subject to filesystem access. `RestrictAddressFamilies=` restricts socket creation;
already supplied sockets are not covered.
[Upstream systemd execution documentation](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.exec.xml)

By default, systemd socket units create network sockets in the host namespace and may pass them to a
service running in another namespace.
[Upstream systemd socket documentation](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.socket.xml)

Proposal: for a service advertised as strictly confined, review its activation sockets, inherited
descriptors, accessible host proxies, container engines, and privileged helper APIs. Reject
unsupported socket activation at evaluation time or explicitly confine its socket units. A pathname
denylist is useful for common integrations, but cannot promise isolation from every host helper.
Offer a stricter filesystem profile with an explicit list of allowed paths for applications that
support it.

## Keep raw packet privileges outside ordinary service profiles

Linux packet sockets require `CAP_NET_RAW` in the user namespace governing the network namespace.
They send frames to the selected interface driver and bypass the ordinary input/output firewall
chains. [Linux packet socket documentation](https://man7.org/linux/man-pages/man7/packet.7.html)

The resulting design concern is specific. A service with both `CAP_NET_RAW` and access to
`AF_PACKET` can send through an available veth without obeying that namespace's `inet` output
policy. Host ingress and forwarding rules still apply. This does not by itself prove an Internet
leak, but it invalidates reliance on the namespace's output filter for host access control.

Proposal: reject this combination in a strict service profile and include `CAP_NET_RAW` in the
capabilities that require an explicit unsafe configuration. If raw packet workloads are supported,
enforce the host boundary independently and test crafted frames. Keep that advanced mode separate
from a torrent-client recipe.

## Check privileged command prefixes without overstating their effects

systemd's `+` command prefix bypasses user/group and capability restrictions. Its execution
documentation also exempts these commands from `RestrictAddressFamilies`.
[systemd command-prefix documentation](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.service.xml),
[systemd execution documentation](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.exec.xml)

The inspected pinned nixpkgs revision `b0aa699cd56b87a41d3e66d89f827c7fbc35ed8d` specifies systemd
261.2. In that release, `needs_sandboxing` is false for fully privileged commands, which disables
`InaccessiblePaths` handling. However, the network namespace setup branch does not depend on that
variable. The source therefore does not support claiming that `+` automatically ignores
`NetworkNamespacePath`.
[Pinned package definition](https://raw.githubusercontent.com/NixOS/nixpkgs/b0aa699cd56b87a41d3e66d89f827c7fbc35ed8d/pkgs/os-specific/linux/systemd/default.nix),
[systemd 261.2 execution implementation](https://raw.githubusercontent.com/systemd/systemd/v261.2/src/core/exec-invoke.c)

Proposal: inspect all `Exec*` commands, including setup and shutdown hooks, before labeling a
service strictly confined. Either reject privileged prefixes in that profile or report exactly which
privileged commands require a separate trust assumption. Validate their actual namespace and
effective capabilities in a VM. A command can retain its VPN namespace while still regaining access
that defeats other protection layers.

## Test the resolver applications actually use

`nss-resolve` talks to systemd-resolved using `/run/systemd/resolve/io.systemd.Resolve`, an
`AF_UNIX` socket. Changing the service's `resolv.conf` alone therefore does not cover every resolver
path.
[Upstream nss-resolve documentation](https://github.com/systemd/systemd/blob/main/man/nss-resolve.xml)

The `ip netns exec` helper creates a mount namespace and binds `/etc/netns/NAME/` configuration into
ordinary `/etc/` locations. Simply entering the network namespace is a different operation.
[iproute2 ip-netns manual](https://www.man7.org/linux/man-pages/man8/ip-netns.8.html)

Proposal: supply a service-local resolver configuration, choose a resolver reachable through the
VPN, and prevent access to the host resolver socket and name-service cache where applicable.
Validate libc lookups such as `getaddrinfo`, direct UDP and TCP DNS, and the real application's
resolver. Run tests with host systemd-resolved enabled and with the VPN unavailable. Prefer packet
capture on a controlled simulated ISP link to relying exclusively on a public DNS-leak page.

Endpoint hostname resolution is a separate bootstrap decision. Proposal: document whether the host
resolves it outside the tunnel. A literal endpoint IP avoids that lookup but requires a clear update
workflow when the provider changes endpoints. Do not claim that bootstrap DNS reveals application
domains; identify exactly which hostname it exposes.

## Make lifecycle safety a release requirement

nftables supports atomic ruleset replacement with `nft -f`. Separate commands can leave a partially
configured firewall between operations.
[nftables atomic replacement documentation](https://wiki.nftables.org/wiki-nftables/index.php/Atomic_rule_replacement)

Proposal: generate one transaction per owned ruleset update. Install restrictions before enabling a
host link or starting consumers. During teardown, remove alternate connectivity before removing its
firewall protection. Keep ownership limited to this module's tables so host firewall management
remains predictable.

Proposed release tests should transmit continuously during startup failure, service restart, tunnel
removal, endpoint outage, failed reload, and shutdown. Include an existing connection as well as new
attempts. A successful WireGuard handshake and a changed public IP show connectivity; they do not
establish that failure paths cannot leak.

## Give IPv6 and MTU an explicit policy

WireGuard's Linux `wg-quick` implementation derives an MTU from endpoint/default routes and
subtracts 80 bytes. It also allows an explicit MTU. That provides a useful baseline, not proof that
1420 fits every path.
[Upstream wg-quick implementation](https://github.com/WireGuard/wireguard-tools/blob/master/src/wg-quick/linux.bash)

IPv6 path MTU discovery uses ICMPv6 Packet Too Big messages. Filtering these messages can prevent
the sender from learning the usable path MTU.
[RFC 8201](https://www.rfc-editor.org/rfc/rfc8201.html)

Proposal: offer a clear choice between IPv6 through the VPN and IPv6 blocked within confinement.
Test both address families even on a deployment marketed as IPv4-only. Avoid globally changing the
host's IPv6 settings. Expose one documented MTU override, preserve necessary error messages, and
test bulk transfer on a reduced-MTU underlay. For performance, measure throughput, CPU, packet loss,
and latency under torrent-like connection counts before adding tuning knobs.

WireGuard recommends persistent keepalive only when needed to preserve NAT/firewall mappings, with
25 seconds as a broadly useful interval. It defaults to disabled.
[WireGuard quick start](https://www.wireguard.com/quickstart/)

Proposal: retain the upstream default unless a provider or inbound-service use case needs
keepalives. Avoid a constant polling daemon as the basic isolation mechanism.

## Separate torrent connectivity from privacy

qBittorrent exposes a network-interface binding option. libtorrent separately documents outgoing TCP
binding and listening-interface settings, with other traffic such as DHT, trackers, and uTP tied to
listening sockets.
[qBittorrent options](https://github.com/qbittorrent/qBittorrent/wiki/Explanation-of-Options-in-qBittorrent),
[libtorrent settings](https://libtorrent.org/reference-Settings.html)

Proposal: provide one tested qBittorrent recipe with interface binding as another safeguard. Verify
TCP peers, UDP trackers, DHT, uTP, and DNS, rather than checking only the peer listener. Do not
present application binding as the entire confinement mechanism.

Provider port forwarding is distinct from publishing a Web UI on the host. For example, Proton's
manual configuration renews short-lived TCP and UDP NAT-PMP mappings and tells users to disable
router UPnP/NAT-PMP in the torrent client.
[Proton's first-party port-forwarding instructions](https://protonvpn.com/support/port-forwarding-manual-setup)

Proposal: use separate configuration names for host UI access and VPN peer ingress. Keep provider
forwarding optional and isolated in an adapter that reports its allocated port and lease state.
Provide a copyable configuration for a working basic client before introducing forwarding. Default
UI access to loopback or a documented authenticated reverse proxy, with LAN exposure an explicit
choice.

## Promise protection that can be verified

WireGuard explicitly does not aim to obfuscate its protocol. Its transport format encrypts
encapsulated packets and includes padding; it does not make the outer connection disappear.
[WireGuard limitations](https://www.wireguard.com/known-limitations/),
[WireGuard protocol](https://www.wireguard.com/protocol/)

The practical inference is that an ISP can still observe the VPN endpoint, connection timing, and
traffic volume. These observations can support guesses about activity. Encryption cannot justify a
promise that the ISP has no chance of inferring anything.

A VPN also transfers trust to its operator and does not provide complete anonymity. Application
encryption still matters after traffic leaves the VPN.
[EFF's VPN threat-model guidance](https://ssd.eff.org/module/vpn.html)

Proposal: state the product promise as "selected services' Internet traffic and DNS use the
configured VPN, and lose Internet connectivity when that path is unavailable." State assumptions
about the host administrator, kernel, provider, and explicitly allowed host access alongside that
promise. A setup check should report confinement, tunnel reachability, resolver behavior, and UI
exposure separately. Those states give a new user a useful next action without asking them to
understand routing tables first.
