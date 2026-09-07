---
title: Repository review and improvement plan
description: Code-backed findings and priorities for VPN privacy, reliability, setup, and performance
---

Historical review of commit `8a519f1`. Subsequent fixes and current behavior are
documented in the architecture, setup, and diagnostic guides.

Reviewed on 2026-09-06 at commit `8a519f12a99827f33237afce023a05e8bf870004`.

Keep the WireGuard network namespace architecture. The main work should be closing configuration
traps, proving failure and recovery behavior, and making one real application easy to deploy. Adding
more networking backends would increase the maintenance burden before those basics are settled. The
architecture follows [WireGuard's own namespace design](https://www.wireguard.com/netns/).

The companion [primary-source research note](../2026-09-vpn-design-sources/) explains upstream
behavior and provider considerations. This review records current code behavior and proposed
changes. Runtime implementation files were not changed.

## Findings to fix first

Priorities below describe implementation order, not CVSS severity. Configuration mistakes are
relevant to this project's privacy promise even where they do not constitute an attacker exploiting
a software vulnerability.

| Priority | Finding | Evidence | Consequence |
| --- | --- | --- | --- |
| P1 | Top-level disable silently removes service confinement | Nix evaluation | A service can retain `vpn.enable = true` and run with ordinary host networking |
| P1 | Endpoint-pinning table names collide | Nix evaluation and isolated nftables replay | One namespace replaces or removes another namespace's outer endpoint restrictions |
| P2 | Inactive allowlist settings generate invalid rules | Nix evaluation and kernel nftables validation | Switching to broad tunnel egress can prevent namespace startup |
| P2 | Custom socket birthplace pinning lacks required capabilities | Source trace and isolated capability check | The advertised custom-namespace pinning helper cannot enter its namespace |
| P2 | Explicit root plus `DynamicUser` passes non-root enforcement | Nix evaluation and systemd documentation | The high-assurance root opt-out is bypassed by an accepted configuration |

### 1. Make contradictory enable settings fail evaluation

`modules/vpn-confinement/service-extension.nix:147` applies all service confinement only when the
global switch is enabled. The corresponding socket guard is at `socket-extension.nix:38`. All module
assertions are themselves inside `mkIf cfg.enable` at `default.nix:1242`.

Evaluating an otherwise valid confined service with the following override produces no failed
assertions and no `NetworkNamespacePath`:

```nix
services.vpnConfinement.enable = false;
systemd.services.probe.vpn = {
  enable = true;
  namespace = "vpnapps";
};
```

This is an operator mistake with a fail-open outcome. An already-enabled application remains
eligible to run on host networking. The module cannot protect against someone removing its import
entirely, but it can reject a contradiction while the import is present.

Put an assertion outside the global enable guard requiring the global switch whenever any service or
socket opts in. Alternatively, derive global enablement from use, with an explicit global disable
still producing an error. Add rejection tests for services and sockets.

### 2. Give endpoint-pinning tables unique identities

`default.nix:481` replaces both dots and hyphens with underscores. Valid namespace names `vpn-a`,
`vpn.a`, and `vpn_a` therefore produce the same table name, `vpnc_endpoint_pin_vpn_a`.

Two such namespaces with different WireGuard interfaces and marks pass all assertions. Replaying the
generated delete-and-load operations in a disposable network namespace confirms that loading the
second policy removes the first policy's mark rules. Stopping either helper also deletes the shared
table at `default.nix:514`.

This removes the optional restriction on encrypted WireGuard endpoint destinations. It does not, by
itself, decrypt traffic or give applications a direct Internet route. The namespace and tunnel
boundary still matter.

Use an injective encoding or a deterministic hash of the full namespace name, with an assertion over
final generated table names. Test both startup orders and each namespace's independent teardown.
Distinct WireGuard marks do not solve a collision in table ownership.

### 3. Gate allowlist rules and sets together

`default.nix:259` emits allowlist set definitions only in `allowList` mode, but `default.nix:292`
calls `mkEgressRules` in every mode.

This accepted configuration generates a reference to an undefined set:

```nix
egress = {
  mode = "allowAllTunnel";
  allowedTcpPorts = [ 443 ];
};
```

The baseline generated rules passed `nft -c -f`. The configuration above failed with
`No such file or directory` at `@allowed_tcp_ports`. Both checks ran in disposable user and network
namespaces using nftables 1.1.6, without touching host firewall rules.

Render allowlist rules only in allowlist mode. Either ignore inactive settings consistently or
reject them with a clear evaluation error. Cover TCP ports, UDP ports, CIDRs, and switching modes.
This currently causes an availability failure, not evidence of plaintext fallback.

### 4. Let systemd enter the custom birthplace namespace

`default.nix:121` limits the endpoint-pinning helper to `CAP_NET_ADMIN`, but `default.nix:480`
invokes `ip netns exec` for a custom birthplace. That command needs namespace-entry and mount
privileges. The source trace is documented in the research note. A separate disposable-namespace
check also confirmed that removing `CAP_SYS_ADMIN` makes network namespace reassociation fail with
`Operation not permitted`.

Prefer `NetworkNamespacePath` on the helper and plain `nft` execution, letting systemd perform
namespace attachment before dropping process capabilities. Verify that all lifecycle commands run in
the intended namespace. This keeps the firewall process's capability set small.

The existing custom birthplace test only evaluates configuration. It does not start the helper. Add
a VM case with a working uplink, start and restart the helper, and inspect the policy in both host
and custom namespaces. No full custom-birthplace VM reproduction was performed during this review.

### 5. Check explicit root before accepting `DynamicUser`

`default.nix:843` accepts `dynamicUser || !rootLike`. A service with `User = "root"` and
`DynamicUser = true` passes the high-assurance assertion without `allowRootInHighAssurance`.
Evaluation confirmed both effective settings and zero failed assertions.

systemd reuses an existing account when dynamic user allocation is requested with an existing user
name. An explicit root account therefore needs rejection regardless of `DynamicUser`. See the
[systemd execution documentation](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.exec.xml).

Keep the intentional root opt-out, but require it for explicit root values. Add a test for the
combination and a runtime effective-UID assertion. Other hardening remains in place, so this finding
is a non-root policy violation, not proof of a network escape.

## Privacy and failure behavior

The public promise should be prevention of direct Internet and DNS leakage from selected services
under documented assumptions. It should not promise that an ISP has no chance of inferring activity.
WireGuard intentionally does not conceal its protocol; the outer endpoint and traffic patterns
remain observable. See [WireGuard's limitations](https://www.wireguard.com/known-limitations/).

Separate these properties in the documentation:

- Confinement determines where application traffic can leave.
- Resolver policy determines which DNS services an application may use.
- Service hardening limits a compromised application's access to the host.
- VPN availability determines whether useful traffic currently passes.

An application using another DNS-over-HTTPS resolver through WireGuard bypasses resolver selection.
That alone is not plaintext DNS leakage to the ISP. Host resolver IPC is a different concern because
another host process can resolve outside the tunnel.

The current `BindsTo` wiring concerns systemd unit state. The pinned NixOS WireGuard interface
service is a oneshot with `RemainAfterExit = true`. An unreachable peer does not automatically stop
that service. Likewise, deleting the interface or namespace name outside systemd is different from
stopping the managed unit.
[systemd unit semantics](https://raw.githubusercontent.com/systemd/systemd/main/man/systemd.unit.xml)
support this distinction.

`runtime-fail-closed-tunnel-drop.nix:71` tests `systemctl stop wireguard-wg0.service`. It does not
test an outer UDP blackhole, a remote peer outage, or automatic recovery. The expected outage
behavior can be that the application stays running but cannot communicate. That is still private if
no alternate route is available. Document shutdown and reachability separately, then define whether
managed restarts should restore applications automatically.

Host activation sockets and accessible filesystem Unix sockets deserve explicit treatment as
exceptions. Namespace confinement does not revoke a socket created elsewhere. Keep host Web UI
access intentional and narrow, and distinguish permission to answer an incoming connection from
permission to initiate arbitrary host-side traffic. `NetworkNamespacePath` is supported for socket
units; the missing piece here is runtime evidence, not a need to remove socket support.

## Tests that would increase confidence most

There are seven VM checks in `flake/checks.nix:42`, enabled only on x86_64 Linux at line 219. The
ARM CI job supplies evaluation coverage, but does not run those VM checks. Both socket namespace
attachment and custom birthplace pinning are currently evaluation-only scenarios.

Build on the local WireGuard peer fixture and use a controlled service beyond it. Run probes as an
actual confined non-root service so they exercise resolver mounts, address-family restrictions,
capabilities, and socket inheritance. The existing root `ip netns exec` probes are useful firewall
tests but do not exercise the complete service boundary.

| Scenario | Required evidence |
| --- | --- |
| Normal operation | Application reaches controlled destination through the VPN; non-confined host traffic retains its normal path |
| Remote peer outage | Continuous TCP, UDP, and DNS attempts produce no plaintext on the simulated ISP link |
| Interface deletion and namespace-name deletion | No fallback; observed service and namespace lifetime matches documentation |
| Failed rule replacement | Previous deny policy survives an invalid replacement transaction |
| Restart and rebuild | Existing streams cannot escape; services recover according to the documented policy |
| IPv6-capable uplink | No IPv6 bypass with an IPv4-only VPN; a separate dual-stack case succeeds through the tunnel |
| Socket activation | Listener is in the intended namespace and absent from the host unless deliberately host-facing |
| Resolver and host IPC | Confined service cannot delegate ordinary DNS to blocked host helpers |
| Multiple namespaces | Starting or stopping one leaves another's routes, rules, and services intact |

Use packet-capture positive controls so an empty capture cannot silently pass because the observer
was broken. Retain evaluation rejection tests for unsafe inputs. Add ARM runtime coverage when
supported infrastructure is available, and label architecture coverage accurately until then.

Load table replacement in one nftables transaction. The separate delete and load calls at
`default.nix:363` and `default.nix:509` introduce an intermediate state. Current ordering mitigates
normal startup exposure, so this review does not claim a demonstrated startup leak from that gap.
Atomic replacement is a simpler invariant to maintain as reload support evolves.

## Make the first deployment complete

The quick start is a useful module example, but `my-service` does not provide a runnable
application, and the input declaration and key provisioning are left to the reader. The
reverse-proxy guide stops before a complete proxy configuration. These gaps make the user solve
integration details before verifying privacy.

Add one tested Transmission or qBittorrent recipe containing the flake input, import,
provider-supplied WireGuard values, runtime key file, application UID, writable download directory,
DNS, and authenticated Web UI access. Show which upstream application options open the host firewall
and why they should remain disabled when only VPN peer ingress is wanted. Use a fixed test fixture
for CI and clearly mark provider values users must replace.

Explain that `publishToHost.tcp` creates a veth path and permits ingress to the namespace address.
It does not create a localhost listener, configure a reverse proxy, or obtain a provider port
forward. The current name invites a Docker-style port-publishing interpretation. Clarify it
immediately; consider a more precise name with an alias in a later API cleanup.

Torrent users need broad tunnel egress because peer destinations change. They can already request
`vpn.hardeningProfile = "strict"` independently of the namespace's `balanced` profile. Show that
combination, with tested application-specific adjustments. Do not teach people to add `0.0.0.0/0`
merely to satisfy the `highAssurance` non-empty CIDR check. A non-empty list does not prove
meaningful destination restriction.

Provider forwarding should remain optional. Separate Web UI access from incoming TCP/UDP peer ports.
Start with a static forwarded-port recipe; add lease renewal adapters only after defining how an
allocated port, its expiry, the app setting, and firewall state are updated together.
Provider-specific facts and primary sources are in the companion research note.

Add a local diagnostic command before more public options. It should identify selected services,
namespace attachment, installed policy, routes, DNS configuration, host ingress, and handshake
information. Distinguish installed isolation from verified reachability. External probes should be
explicit and use the same service restrictions where practical. Avoid unredacted `wg show ... dump`,
which includes secrets, and avoid public-IP polling as a default background dependency.

## Simplification and performance

The four module files contain 2,024 lines, with 1,286 in `default.nix`. Split that file by
responsibility into option declarations, effective policy calculation, rule rendering, lifecycle
units, and assertions. Preserve the public API while doing it. Compute effective ingress, host-link
addresses, and endpoint identities once, then have services, firewall generation, and diagnostics
consume them.

Treat hardening defaults as defaults when explaining assurance. Most service restrictions use
`mkDefault`, so an existing NixOS service or user override can change the effective capability and
sandbox settings. Diagnostics should show those effective values. Warn about dangerous capability
grants and require a named exception for controls the stronger profile intends to guarantee.

Keep the strict literal input validation. Replacing it with permissive strings would reduce code
while weakening the boundary between configuration and shell or nftables syntax. Add table-driven
parser cases, including equivalent and overlapping CIDRs, before attempting a parser cleanup.

Reduce repeated documentation claims and examples. Keep one canonical minimal recipe, one
application recipe, the threat model, and generated options. Reconcile the `IanHollow` URLs in the
README and site configuration with the `nix-forge` URLs and repository guards in security reporting
and automation. The review establishes inconsistent references, not whether GitHub currently
redirects each URL.

Measure before optimizing. Compare native WireGuard with confinement on the same machine and peer,
recording CPU, TCP throughput, UDP loss, latency, concurrent connections, MTU, and kernel versions.
Exercise sustained transfer and many torrent-like connections. Include PMTU failure cases,
especially IPv6. Retain named nftables sets and avoid per-packet logging by default. Flowtable
offload targets forwarding and is not an obvious improvement for service-originated input/output
traffic; its primary-source explanation is in the research note.

Keep the NixOS/WireGuard scope for the next release. A stable NixOS release matrix and clear
compatibility policy would help users more than adding Docker, OpenVPN, or another orchestration
layer now.

## Suggested delivery sequence

1. Fix the five policy issues and add regression tests. Make firewall replacement atomic.
2. Test outage, recovery, sockets, and IPv6. Rewrite guarantees to match measured behavior.
3. Ship a complete torrent deployment and diagnostics, with runtime secrets and a usable Web UI.
4. Refactor policy generation, remove repeated documentation, and clarify host publishing.
5. Publish benchmarks and a NixOS support matrix before adding provider port-forwarding adapters.

## Verification and limits

All four module files were read, along with the test registration, relevant fixtures, CI, setup
documentation, and the pinned upstream WireGuard integration. This was a focused repository review,
not an exhaustive audit of all dependencies or deployed hosts.

The 26 existing non-VM, non-doc check predicates evaluated true by directly importing
`flake/checks.nix` with the root lock's nixpkgs revision,
`b0aa699cd56b87a41d3e66d89f827c7fbc35ed8d`. This evaluated their pass/fail expressions; it did not
execute their derivation builders. Additional evaluations confirmed the contradictory enable state,
root plus DynamicUser state, and colliding table definitions. Disposable namespace checks validated
the normal rules, reproduced the missing-set failure, replayed the table collision, and checked the
namespace capability requirement.

The full flake check could not finish evaluation because the development partition resolved an
invalid store path, `/nix/store/vp33skrf4zpp72majb3dkwx98ymvsbz3-dev`. Both the offline repository
invocation and an explicit path invocation encountered it. Its underlying cause was not diagnosed,
so it is not classified here as a product defect. VM tests and performance benchmarks were not run.

The packaged Codex Security scanner could not start because its bundled generic-Linux Python
executable failed on NixOS. No completed scanner report or security certification is claimed. The
findings above come from direct code review, primary-source research, and the stated bounded checks.
