---
title: Repository review follow-up
description: Validated policy gaps and a practical roadmap for secure, usable VPN confinement
---

Reviewed on 2026-09-07 UTC against the working tree based on commit
`8a519f12a998`. The tree already contained substantial implementation and documentation changes.
This review preserves those changes and the earlier review. It adds research, not product fixes.

Subsequent changes are recorded in the [implementation follow-up](../2026-09-07-implementation/).

## Recommendation

Keep the NixOS and WireGuard namespace architecture. Concentrate the next release on closing
privilege exceptions, proving real application behavior, and making the first deployment survive a
reboot. Another VPN backend or orchestration layer would add complexity before solving these needs.

The ISP privacy promise needs a precise boundary. Selected services' ordinary Internet traffic and
DNS should use the VPN and fail closed when it is unavailable. The ISP still observes the VPN
endpoint, timing, and traffic volume, and may infer activity. The provider and application identities
remain separate trust concerns. WireGuard does not aim to hide its protocol.
[WireGuard limitations](https://www.wireguard.com/known-limitations/)

The [companion research](../2026-09-07-primary-source-followup/) cites upstream evidence for the
architecture, host sockets, DNS, lifecycle, MTU, torrent integration, and privacy limits.

## What the current edits already improve

The earlier review's five principal implementation findings have corresponding changes in this tree:
global enable contradictions are rejected; inactive allowlists no longer render missing-set
references; endpoint tables use distinct hashes; custom birthplace policy uses namespace attachment;
and explicit root with `DynamicUser` is rejected. Regression checks cover those cases.

The tree also adds atomic nftables replacement, an authenticated Transmission recipe, diagnostics,
more runtime tests, and a measured local benchmark. Options and firewall rendering now have separate
modules. Those changes are useful progress and should not be proposed again as missing features.

## Validated security findings

### P1: raw packet access bypasses the host-link policy

`modules/vpn-confinement/lib.nix:414` checks capability grants for `CAP_NET_ADMIN`, `CAP_SYS_ADMIN`,
and inverted lists. It does not flag `CAP_NET_RAW`. A service can request `AF_PACKET` through
`vpn.extraAddressFamilies`, while an explicit capability setting overrides the empty default.

A fresh disposable NixOS VM accepted this combination without either unsafe/root exception:

```nix
services.vpnConfinement.namespaces.vpnapps = {
  securityProfile = "highAssurance";
  egress.allowedCidrs = [ "10.71.216.232/32" ];
  hostLink.enable = true;
};
systemd.services.probe = {
  vpn = {
    enable = true;
    namespace = "vpnapps";
    extraAddressFamilies = [ "AF_PACKET" ];
  };
  serviceConfig = {
    DynamicUser = true;
    CapabilityBoundingSet = [ "CAP_NET_RAW" ];
    AmbientCapabilities = [ "CAP_NET_RAW" ];
  };
};
```

The test ran the sender as a non-root service with strict hardening and confirmed a default-drop
output chain. A host UDP listener nevertheless received its crafted plaintext packet through the
veth. No host ingress ports were declared. Linux packet sockets bypass ordinary input/output
firewall chains, which explains the observed result.
[Linux packet socket documentation](https://man7.org/linux/man-pages/man7/packet.7.html)

This is a demonstrated namespace-to-host policy bypass. Internet leakage additionally requires a
host forwarding, relay, or helper path; that downstream step was not tested. The default Transmission
recipe does not grant the capabilities/address family used in this reproduction.

Require an explicit unsafe exception for `CAP_NET_RAW` in `highAssurance`, and warn in `balanced`.
Keep raw-packet access out of ordinary recipes. If supporting it is necessary, enforce and test an
independent host-side boundary rather than relying on the namespace's `inet` output chain.

The same parser splits only on literal spaces. A direct Nix evaluation returned `true` for
`"CAP_NET_BIND_SERVICE CAP_NET_ADMIN"` and `false` for the same string separated by a tab. Normalize
systemd whitespace before checking capability names. The tab case was evaluated, not runtime-tested.

### P2: privileged command prefixes evade the non-root check

`modules/vpn-confinement/default.nix:629` determines non-root status from `User` and `DynamicUser`.
It does not inspect command prefixes. A second fresh VM test accepted a high-assurance service with
`DynamicUser = true` and `ExecStart = "+..."`, then confirmed that its command ran with UID 0 without
`allowRootInHighAssurance`.

The command retained the VPN network namespace. This finding is a privilege-policy violation, not
evidence that the prefix directly selects the host network. systemd gives `+` commands exemptions
from several other sandbox controls, so configuration-level capability and resolver checks are also
insufficient to describe their effective restrictions.
[systemd command prefixes](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.service.xml),
[systemd 261.2 execution source](https://raw.githubusercontent.com/systemd/systemd/v261.2/src/core/exec-invoke.c)

Validate all effective `Exec*` commands, including preparation and shutdown hooks, for privileged
prefixes. Require a named exception in the stronger profile and report the affected command phase.
Use small, separately trusted setup units where an application needs privileged preparation.

## Security and diagnostic improvements

The doctor command is a useful starting point, but its successful exit means limited structural
checks passed. At `doctor.py:53`, it checks chain names and policies without checking their hook
attachment or accepting rules. A mocked observation with an unconditional output accept, empty
route tables, and no WireGuard peers produced `issues = []`. This matches the documented limitation,
but it is too weak to become a beginner's sole readiness check.

Extend the existing diagnostic manifest to include expected peers, policy details, and declared
exceptions. Compare normalized installed rules, ignoring counters and handles. Report confinement,
tunnel configuration, application state, and untested reachability separately. Show dangerous
capabilities and host activation sockets in normal text output, not only raw JSON properties.
Keep external probes opt-in and avoid treating idle handshake age as failure.

`socketAssertions` only examines sockets that opt into VPN confinement. A host socket can still
activate a confined service, as the threat model acknowledges. Detect that association in the
stronger profile and require an explicit host-socket exception. Keep localhost UI proxies supported,
but ensure a deliberate UI exception does not silently permit unrelated activation sockets.

Keep blocking common host resolver IPC. The next DNS test should call `getaddrinfo` from the actual
non-root service with systemd-resolved enabled on the host. The current strict/compat test inspects
unit properties and sends direct namespace probes; the runtime-safety fixture echoes bytes on port
53. Neither demonstrates the complete libc resolver path under a host resolver configuration.

## Make the first deployment durable and easier to understand

The Transmission recipe already includes a local authenticated UI and correct separation of host
publication from provider peer forwarding. Its largest remaining setup gap is secret persistence.
The manual instructions create files in `/run`, then ask users to configure their existing secret
manager. A new user still has to solve reboot provisioning and startup ordering.

Provide one complete persistent setup, preferably a tested secret-manager example. Also document a
root-owned persistent file option for people without one. Show ownership, permissions, service
ordering, rotation, and recovery from a missing file. Test a reboot with those secrets restored.
Reject inline keys and Nix-store key paths by default in the ordinary recipe as well as the stronger
profile; any compatibility exception should be explicit.

Use one short path through the docs: provider values, secret provisioning, application declaration,
apply, local checks, open UI, reboot check. Keep the current reference pages for advanced use.
Add a qBittorrent recipe only after this path is reliable. Its optional interface binding is another
safeguard, and still needs tests for UDP trackers, DHT, uTP, and DNS.

Treat profile names as presets over independent controls. Explain `balanced` as broad VPN egress,
with strict application hardening available independently. Over time, prefer names that describe
the policy, such as unrestricted VPN destinations versus restricted destinations. Preserve aliases
and avoid forcing a migration just to rename options.

For host access, consolidate the common path around one declarative API. `publishToHost.tcp`,
`ingress.fromHost.tcp`, and `hostLink.enable` currently offer overlapping ways to request it. Keep
addresses and interface names as advanced overrides. If adding automatic localhost proxying, give
that behavior a clear name and explicit bind address; do not silently change existing semantics.

## Simplify implementation and focus performance work

`default.nix` remains 847 lines, mostly lifecycle assembly and validation. Extract assertions and
unit construction into focused helpers. Expand the existing `effectiveNamespace` calculation so
firewall rendering, unit wiring, and diagnostics consume one normalized policy. Preserve the strict
IP and name validation that protects generated shell and nftables syntax.

Share the controlled WireGuard peer and application-probe fixtures across tests. Keep failure
scenarios separate enough that a failing test names the broken guarantee. Avoid adding a generic
framework that hides the network topology or observation point.

The recorded benchmark's confined TCP medians are about 1.6% and 2.4% below its comparison modes,
with overlapping ranges. It measures incremental firewall cost in a short local tunnel test, not
the whole service sandbox or an Internet torrent workload. That evidence supports keeping the
current packet path until a representative workload shows a bottleneck.

Extend measurement to sustained transfers, many concurrent connections, total guest CPU, latency
under load, and a genuinely smaller underlay MTU. The current IPv6 test demonstrates a 256 KiB
transfer with tunnel MTU 1280; it does not exercise an intermediate router generating Packet Too Big
or a PMTU blackhole. Keep provider forwarding adapters optional and outside the core module.

## Delivery order and acceptance evidence

| Order | Work | Evidence before release |
| --- | --- | --- |
| 1 | Capability and privileged-command checks | Both reproduced cases require explicit exceptions; tab-separated grants are recognized |
| 2 | Stronger diagnostics and host-socket checks | Altered policy, missing peers, and undeclared host activation are reported |
| 3 | Real application privacy tests | libc DNS and a local seeded torrent complete through a controlled VPN; captures stay clean during failure |
| 4 | Persistent setup recipe | A fresh machine reaches the authenticated UI and recovers after reboot without manual key copying |
| 5 | Internal simplification | Same public configurations and failure tests pass after extracting policy and lifecycle helpers |
| 6 | Support and performance evidence | Documented stable-release evaluation plus runtime coverage where available; sustained workload measurements |

Use a simulated ISP link with a working capture positive control for the application tests. Exercise
new and established TCP/UDP flows during endpoint outage, WireGuard restart, route injection,
namespace/interface removal, and failed policy replacement. Existing tests cover several of these
individually; the next gain is checking the complete application and resolver boundary together.

## Verification and limits

- `nix flake check --no-build --system x86_64-linux` passed.
- `nix flake check --system x86_64-linux --keep-going` passed all 48 registered checks, including
  11 VM checks. Nix reused existing build results; those VM tests were not freshly executed here.
- All five Python doctor unit tests ran and passed.
- The documentation build and Astro checks passed with both new research pages included.
- Fresh disposable VM builds reproduced the raw-packet bypass and the privileged-command UID
  mismatch. The reproduction used local test endpoints and did not alter the host firewall.
- Direct Nix evaluation confirmed the capability whitespace gap. Mocked doctor inputs confirmed
  the limited success criteria described above.

The local reproduction is `/tmp/vpnc-review-raw.nix`; its combined run log is
`/tmp/vpnc-review-raw-plus.log`. These temporary artifacts are available in this review environment,
not portable repository tests. Product fixes should add permanent regression coverage.

The formal Codex Security scanner failed to launch because its bundled generic-Linux Python cannot
run directly on this NixOS host. This is a manual source review with the stated checks, not a
completed scanner audit or a guarantee of zero leaks. No new ARM runtime, real provider, or real
torrent transfer was tested during this review. Earlier research remains historical context;
current implementation claims above refer to this working tree.
