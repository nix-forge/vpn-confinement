---
title: Review implementation
description: Changes following the September 7 security and usability review
---

This implementation follows the [repository review](../2026-09-07-review-followup/) and
[upstream research](../2026-09-07-primary-source-followup/). Those pages record the earlier
working tree and its verification results. This page records the subsequent changes.

## Security checks

High-assurance services now require explicit exceptions for raw/admin capabilities,
privileged lifecycle commands, and unverified activation sockets. Capability checks handle
systemd whitespace and reject noncanonical representations without an exception. Command
checks cover every lifecycle phase and conservatively reject quoted or escaped executable
names and command separators. Ordinary quoted arguments remain supported.

Socket checks cover structured declarations, explicit targets, aliases, templates, and
`Sockets`. String boolean values for `Accept` remain supported. Raw and packaged unit files
require deployment review; the doctor also checks the loaded activation relationships.

Both profiles reject inline WireGuard secrets and Nix-store key paths by default. Balanced
mode has an explicit compatibility exception. High assurance rejects that exception.

## Local diagnostics

The namespace and endpoint-pinning helpers save root-only policy snapshots after applying
their nftables transactions. The doctor compares installed rules with those snapshots,
ignoring handles and counters while preserving verdicts and rule order. Changed configuration
selects a new snapshot filename. Missing snapshots fail verification.

The doctor also checks base-chain hooks, usable tunnel routes, configured peers and allowed
IPs, process attachment, resolver files, and loaded activation sockets. It prints configured
exceptions and dangerous effective capabilities. Reads through application mount views are
bounded and reject non-regular files. Resolver reads use Linux `openat2` with
`RESOLVE_IN_ROOT` and `RESOLVE_NO_MAGICLINKS`, so absolute symlinks remain in the
application's filesystem view. The previous `/proc/<pid>/root/etc/resolv.conf` read
could follow an absolute symlink back into the doctor's host root and report the
host resolver instead. There is no unsafe fallback on unsupported kernels or ABIs.
[Linux path-resolution guarantees](https://man7.org/linux/man-pages/man2/openat2.2.html)

These checks trust host root and the policy installation helpers. They do not contact a
provider, certify reachability, or treat an old handshake as a failure.

The libc DNS VM exposed a compatibility failure on systemd-resolved hosts. Blocking
the resolver directory also blocked non-root traversal to a bind-mounted `resolv.conf`.
Strict mode now blocks resolver IPC sockets instead of that directory, and tolerates
missing helper paths. The application test reads the resolver file as its service user.
[systemd filesystem restrictions](https://github.com/systemd/systemd/blob/main/man/systemd.exec.xml)

## Setup and maintenance

The [Transmission recipe](../../guides/transmission/) now includes persistent root-owned
secrets, permissions, rotation, missing-file recovery, and a reboot check. The ordinary path
needs no extra secret-manager dependency. Existing secret managers can supply runtime paths.

`publishToHost.tcp` is the common host-access option. `ingress.fromHost.tcp` remains an alias.
Neither setting creates a host listener or a provider port mapping.

Assertions, lifecycle units, shared context, and generated policy now have separate modules.
The firewall is installed before host links are brought up. Runtime tests share a small local
WireGuard peer fixture.

The benchmark supports longer samples and 32 parallel connections, and records total guest
CPU and latency during load. No kernel or firewall performance tuning was justified by the
existing measurements. The earlier published numbers remain historical.

## Verification

The new application privacy VM passed a fresh run. It transferred and verified a
16 MiB private test torrent, interrupted an established download by blocking the
VPN endpoint, and recovered across a WireGuard restart. Captures started before
application startup, included positive controls, and found no plaintext DNS,
tracker, or peer packets on the simulated ISP link or host interfaces. It also
verified non-root libc resolution, blocked resolver IPC, and doctor failures after
an injected accept rule and a removed WireGuard peer.

The final x86_64 flake check passed all 69 registered checks. All 12 VM scenarios
executed freshly in that run. The 17 repository lint hooks passed, the options
reference was regenerated, and Astro checks plus the 21-page documentation build
passed. These results supersede the earlier review's cached baseline results.

All 13 Python diagnostic tests passed locally and in the Nix build sandbox. The instrumented short benchmark
completed 18 samples; its [results and limits](../../guides/performance/) are saved
alongside the earlier measurements.

## Scope

The ISP can still observe the VPN endpoint, timing, and traffic volume. These changes target
ordinary service traffic and DNS containment, including failures. They do not hide VPN use or
provide anonymity against the provider, host root, or application identities.

Commercial-provider integration, qBittorrent/DHT/uTP coverage, ARM runtime tests, and stable
NixOS release validation remain separate work. The tested setup continues to target the
repository's pinned NixOS unstable input.
