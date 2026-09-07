---
title: VPN confinement design research
description: Primary-source research and proposed improvements for security, privacy, performance, and setup
---

Historical review of commit `8a519f1`. Subsequent fixes and current behavior are
documented in the architecture, setup, and diagnostic guides.

Research date: 2026-09-06. This note separates documented upstream behavior from project
recommendations. It is design research, not a completed security audit or a claim that proposed
changes have been implemented. Provider features and upstream `main` documentation can change;
implementation work should check the versions in `flake.lock`.

## Keep the namespace architecture

WireGuard retains its encrypted UDP socket in the namespace where the interface was created, even
after the interface moves elsewhere. Its official namespace guide demonstrates a container with only
loopback and WireGuard, with ordinary traffic able to leave only through WireGuard.
[WireGuard namespace guide](https://www.wireguard.com/netns/)

Recommendation: retain this architecture. For the simplest deployment, keep the encrypted socket in
the host namespace, put the WireGuard interface in the service namespace, and add no host link until
an application needs it. This matches the existing project's design and avoids building another
routing subsystem. Keep nftables as an additional boundary, especially when a host link exists.

A practical privacy promise is that selected services' Internet traffic and DNS travel through the
configured VPN, with no ordinary Internet route when the tunnel fails. This promise still depends on
excluding alternate channels such as host sockets and privileged host helpers.

## State the privacy promise accurately

WireGuard explicitly does not aim to disguise its protocol. Its authors also describe endpoint
roaming and recommend firewall restrictions when the operator needs fixed remote addresses.
[WireGuard known limitations](https://www.wireguard.com/known-limitations/)

A VPN moves trust toward the VPN operator and does not provide anonymity against application
accounts, tracking, or the operator itself. Encryption used by the application still matters after
traffic leaves the tunnel.
[EFF VPN guidance](https://ssd.eff.org/module/choosing-vpn-thats-right-you)

Inference: the ISP can observe the outer VPN connection, including its destination, timing, and
volume. The project should not promise that the ISP has "no chance" of inferring activity. It can
aim to prevent direct destination and content leakage from confined services. Endpoint pinning
constrains the encrypted transport destination; it does not remove these observable properties.

Recommendation: put this short explanation beside the first setup example. Show which services are
confined, whether host communication is enabled, and which VPN endpoint carries their traffic.
Document that a tunnel terminating on another machine using the same ISP does not automatically move
the final Internet egress beyond that ISP.

## Treat host sockets as explicit exceptions

systemd permits host-created activation sockets to be passed into services in another network
namespace. Such sockets retain host connectivity; sockets created by the service use its own
namespace.
[systemd socket documentation](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.socket.xml)

The upstream execution documentation explicitly supports `NetworkNamespacePath=` on socket units. It
also states that filesystem Unix sockets remain accessible across network namespaces, and that
`RestrictAddressFamilies=` does not restrict sockets received from elsewhere. `PrivateIPC=` does not
isolate Unix sockets.
[systemd execution documentation](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.exec.xml)

Recommendations:

- Keep `socketConfig.NetworkNamespacePath`; it is supported. Add a runtime test that proves the
  listener exists in the intended namespace and is absent from the host.
- Describe host socket activation as an intentional host networking exception. Distinguish a stream
  listener from a datagram socket, which merits a dedicated arbitrary-destination send test before
  making a broad confinement claim.
- Prefer a host reverse proxy reaching a narrowly permitted application port for the beginner Web UI
  recipe. Make the ingress choice visible and test that unsolicited connections back toward host
  services fail.
- Extend hostile-process tests to filesystem Unix sockets, descriptor passing, runtime control
  sockets, and resolver helpers. Blocking familiar resolver paths is not a general prohibition on
  delegating network work to another host process.
- Keep a separate UID and narrow filesystem access for each application. A network namespace alone
  is not a complete application sandbox.

## Fix custom endpoint pinning without broadening the helper

The current custom birthplace path in `modules/vpn-confinement/default.nix` invokes `ip netns exec`,
while the endpoint-pinning unit's capability bounding set contains only `CAP_NET_ADMIN`.

`ip netns exec` calls `setns` for the target network namespace, creates a mount namespace, and
mounts the matching `/sys`.
[iproute2 namespace implementation](https://raw.githubusercontent.com/iproute2/iproute2/main/lib/namespace.c)

Entering another network namespace through `setns` requires `CAP_SYS_ADMIN` in both the caller's
user namespace and the user namespace owning the destination.
[Linux setns manual](https://man7.org/linux/man-pages/man2/setns.2.html)

Inference: the custom birthplace command cannot succeed with only `CAP_NET_ADMIN`. This is a
source-supported incompatibility; this research did not reproduce it in a VM.

Recommendation: have systemd enter the existing namespace with `NetworkNamespacePath=` and run plain
`nft` there. Retain the small capability set for the actual firewall process. Verify startup,
shutdown, and restart in a custom birthplace using a runtime test, including the required netlink
address family and unit ordering.

## Separate tunnel privacy from resolver selection

DNS-over-HTTPS carries DNS requests using HTTPS. Blocking traditional DNS ports does not identify
every such request. [RFC 8484](https://www.rfc-editor.org/info/rfc8484/)

DNS-over-TLS and DNS-over-QUIC both use port 853 by default, with TCP and UDP respectively. Their
specifications permit alternatives in defined circumstances.
[RFC 7858](https://www.rfc-editor.org/rfc/rfc7858.html),
[RFC 9250](https://www.rfc-editor.org/rfc/rfc9250.html)

Inference: an application reaching another resolver through WireGuard bypasses the configured
resolver policy, but that alone does not expose plaintext DNS to the ISP. A host resolver IPC call
is a different case because the host can perform DNS outside the tunnel.

Recommendation: explain these two properties separately in `dns.mode` documentation. Keep strict
resolver defaults, but describe port filtering as common-protocol enforcement rather than universal
DNS detection. Do not make HTTPS inspection a prerequisite for a usable torrent setup.

IPv6 PMTU discovery relies on ICMPv6 Packet Too Big messages; blocking them can prevent successful
communication. [RFC 8201](https://www.rfc-editor.org/rfc/rfc8201.html)

Recommendation: retain disabled IPv6 as the beginner default. Offer a tested dual-stack recipe with
a provider-assigned address, IPv6 peer routes, resolver support, and narrowly allowed control
traffic. Test an IPv6-capable uplink with an IPv4-only VPN, and repeat leak checks after interface
recreation and tunnel loss.

## Make failures visible without confusing them with connectivity

`BindsTo=` with `After=` ties a unit's active state to its dependency. This is a unit lifecycle
relationship.
[systemd unit documentation](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.unit.xml)

WireGuard offers separate queries for handshake timestamps and transfer counters. Its
script-oriented `dump` output includes private and preshared keys, so that output is unsuitable for
an unredacted support bundle.
[WireGuard wg manual](https://git.zx2c4.com/wireguard-tools/about/src/man/wg.8)

WireGuard can remain quiet when idle. Persistent keepalive is optional and primarily maintains NAT
mappings for inbound traffic. [WireGuard quick start](https://www.wireguard.com/quickstart/)

Recommendations:

- Add a local `doctor` command that reports namespace attachment, routes, firewall installation,
  resolver configuration, dependencies, and recent handshake status. Query only the WireGuard fields
  needed.
- Distinguish "policy installed" from "VPN reachable". A stopped unit, removed interface, blocked
  outer UDP path, and unreachable remote peer are different test cases.
- Make active Internet checks explicit and run them within the same service restrictions where
  possible. A root `ip netns exec` probe does not exercise service-specific mounts, credentials, or
  inherited descriptors.
- Avoid treating a stale handshake on an idle connection as proof of failure. Do not restart
  applications continuously based on handshake age alone.
- Test recovery as well as shutdown. Verify whether applications resume after the VPN returns, and
  document any deliberate manual restart requirement.

## Keep firewall changes atomic and measure performance

nftables supports atomic changes when a replacement transaction is loaded with `nft -f`. Its
official example places the removal of previous rules inside that same input.
[nftables atomic rule replacement](https://wiki.nftables.org/wiki-nftables/index.php/Atomic_rule_replacement)

The current setup scripts delete a table in one invocation and load it in another. Recommendation:
use one transaction scoped to the project's table. Do not flush unrelated host rules. This removes
an avoidable intermediate state; its present exploitability depends on the lifecycle and is not
established by this research. Test invalid replacement input and repeated starts while traffic runs.

nftables named sets support typed elements, intervals, and policies that let the kernel select an
appropriate representation. [nftables manual](https://netfilter.org/projects/nftables/manpage.html)

Recommendation: retain named sets. First measure the existing implementation against native
WireGuard on the same host using TCP throughput, UDP throughput and loss, latency, CPU use, many
concurrent connections, and several MTUs. A large download and a torrent with many peers stress
different resources. Publish the measurement procedure and hardware instead of asserting an
unmeasured speed advantage.

Kernel flowtables accelerate forwarded traffic and bypass later Netfilter hooks for matching
packets.
[Linux flowtable documentation](https://www.kernel.org/doc/html/latest/networking/nf_flowtable.html)

Inference: flowtable offload is not an obvious optimization for applications originating traffic
inside this namespace. Keep it out of the default design until a measured forwarding bottleneck
warrants the extra policy complexity. Preserve PMTU behavior and avoid per-packet logging by
default.

## Give torrent users one complete recipe

Proton's manual forwarding instructions use renewable NAT-PMP mappings, with a 60-second lease
renewed every 45 seconds in their example. They direct users to assign the returned public port to
the torrent client and disable the client's router UPnP/NAT-PMP option.
[Proton manual port forwarding](https://protonvpn.com/support/port-forwarding-manual-setup)

Provider support is not universal. Mullvad announced removal of forwarded ports in 2023.
[Mullvad forwarding announcement](https://mullvad.net/en/blog/removing-the-support-for-forwarded-ports)

Recommendations:

- Add a complete, tested Transmission or qBittorrent example with runtime secrets, persistent
  download storage, service permissions, DNS, and authenticated Web UI access. Show the flake input
  declaration as well as the module import.
- Explain two independent ingress choices: host access to the Web UI and VPN-side incoming peer
  connections. `publishToHost` does not request a port from the VPN provider.
- Keep provider port forwarding optional. First document static forwarded ports; add
  provider-specific lease adapters only behind a small interface for the allocated TCP/UDP port and
  expiry.
- Run any lease client through the confined VPN path. Update the application and firewall together
  when the assigned port changes, and remove stale allowances on expiry. Test renewal failure and
  VPN reconnect.
- Keep strong service hardening available for torrents even when their changing peer addresses
  require broad tunnel egress. Do not encourage a catch-all CIDR merely to satisfy a stronger
  profile's non-empty allowlist assertion.

## Suggested order

First fix the custom pinning startup mismatch and expand runtime coverage of namespace attachment,
host communication, lifecycle recovery, and failed firewall replacement. Next deliver one working
torrent recipe and a secrets-safe diagnostic command. Then simplify the public options around that
experience. Add provider forwarding adapters and performance changes only when the baseline works
and measurements justify them.

## Implementation follow-up: established connections

The implementation tests also exposed a route-change leak through the blanket
`ct state established,related accept` rule. A persistent UDP socket first exchanged
traffic through WireGuard, then leaked packets onto the host veth after the test
installed a route through that interface. New-connection probes had stayed blocked.

Connection state tracks a flow's history; it does not constrain its output interface.
[Netfilter's connection-tracking reference](https://wiki.iptables.org/wiki-nftables/index.php/Matching_connection_tracking_stateful_metainformation)
explains state and direction matching.

The fix requires WireGuard for established Internet traffic. The host-link exception
permits established TCP replies to the host endpoint on published ports. The runtime
test keeps the persistent socket open while changing routes and captures the host
link to check for both new and established traffic leakage.
