---
title: Architecture
description: How namespace policy, WireGuard, and service lifecycle fit together
---

Each namespace is a shared network trust domain. Its services share DNS and
firewall policy. Use separate namespaces for mutually untrusted applications.

## Traffic path

The module uses `networking.wireguard.interfaces`. NixOS creates the WireGuard
interface in the host namespace and moves it into `/run/netns/<name>`. WireGuard
retains its encrypted UDP socket in its birthplace namespace. A confined service
creates ordinary network sockets inside the confinement namespace.

With no host link, that namespace contains loopback and WireGuard. A host link
adds a veth pair for explicitly permitted host ingress. Namespace nftables uses
default-drop input, output, and forward chains. Internet traffic is accepted
only through the WireGuard interface, subject to DNS and egress policy. Established
connections remain bound to that interface even if a route changes. Host-link
replies are limited to established TCP connections on published ports, directed
to the host endpoint. Connection state alone does not authorize another interface.

The renderer lives in `modules/vpn-confinement/firewall.nix`. It generates one
transaction that destroys the previous project table and installs the new one.
A rejected transaction leaves the previous rules intact. CIDR sets merge
overlapping intervals. Inactive allowlist settings do not generate rules.

`lib.nix` centralizes effective host ingress and address calculation. Option
schema lives in `options.nix`, configuration checks in `assertions.nix`, lifecycle
units in `lifecycle.nix`, and shared selection in `context.nix`. `policy.nix`
provides the applied rules and root-only snapshots used by the doctor. Runtime
diagnostics live in `diagnostics.nix` and `doctor.py`. Service/socket integration
lives in the extension modules.

## Service attachment and DNS

Services opt in using `systemd.services.<name>.vpn`. The module owns
`NetworkNamespacePath` and rejects conflicting manual namespace settings.
Opted-in services and sockets are rejected if the global module is disabled.

Strict DNS bind-mounts generated resolver and NSS files into each service. It
blocks access to common host resolver helpers unless explicitly opted out, and
limits conventional DNS ports before general tunnel egress. Arbitrary encrypted
DNS through permitted tunnel destinations is a resolver-policy limitation, not
in itself plaintext DNS leakage to the ISP.

Service hardening drops capabilities by default and provides a strict preset.
The module does not set `RestrictNetworkInterfaces`: systemd resolves those
names in the manager's namespace, where the moved WireGuard interface is absent.
That filter blocked real confined applications in VM tests. Namespace nftables
is the network enforcement mechanism.

## Lifecycle

The namespace preparation unit installs the firewall before bringing up host links
and must finish before WireGuard starts. Confined
services and sockets use `BindsTo` and `After` for both dependencies. Stopping a
managed dependency stops its consumers. `PartOf` propagates a managed WireGuard
restart to previously active consumers.

The upstream WireGuard target normally starts at boot. Namespace creation is
therefore not guaranteed to be on-demand. Stopping an application alone does not
necessarily stop WireGuard or remove its namespace.

A remote outage is different from a stopped unit. WireGuard can remain active
while its peer is unreachable; applications can remain running with traffic
stalled. Deleting an interface or removing a namespace name outside systemd is
also different. An existing process may retain the namespace inode. The module
leaves its firewall intact until the namespace itself is destroyed.

Socket units use explicit shutdown ordering instead of their usual early
`sockets.target` ordering, avoiding a cycle while waiting for namespace services.
A separate stop followed by a start does not automatically revive every stopped
application. Start the application explicitly in that case.

## Host communication

`publishToHost.tcp` enables a veth pair and permits those ports from its host
endpoint. It does not bind localhost, configure NAT, create a reverse proxy, or
request VPN-provider forwarding. Derived addresses are exported under
`namespaces.<name>.derived.hostLink`.

Host network managers are told to leave the module's veths unmanaged. Their
addresses and routes belong to the confinement module.

A socket opted into confinement binds inside the namespace. A socket deliberately
left on the host can pass a host-network file descriptor into a confined service.
That is an explicit networking exception. Prefer the complete
[Transmission reverse-proxy recipe](../guides/transmission/) for a first setup.

## Endpoint pinning

Optional endpoint pinning restricts marked, encrypted WireGuard UDP traffic to
literal configured endpoint tuples. Each namespace has a table name derived from
a full hash of its name. Different punctuation does not produce shared tables.

For a custom socket birthplace, systemd enters that namespace before launching
the pinning helper. The nftables process retains only `CAP_NET_ADMIN`. An external
birthplace must exist before the helper starts; managed birthplace namespaces
receive dependency wiring automatically.

Endpoint pinning is not a defense against host root, and it does not hide the VPN
endpoint or traffic patterns. Hostname endpoints require explicit opt-in and
refresh, and cannot be combined with endpoint pinning.

## Validation

The checks include real non-root service traffic, outage and recovery, host-link
packet capture with a positive control, IPv6 disable and tunneled transfer,
namespace socket activation, colliding names, custom birthplace lifecycle,
invalid firewall replacement, and the Transmission example. The VM suite runs on
x86_64 Linux. ARM checks currently evaluate configuration only.

Use [Diagnostics](../guides/diagnostics/) to inspect a deployment and
[Performance](../guides/performance/) for the optional local benchmark.
