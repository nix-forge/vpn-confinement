---
title: Diagnose a confined service
description: Inspect effective VPN confinement without exposing keys or sending external probes
---

Enabling the module installs `vpn-confinement-doctor`:

```bash
sudo vpn-confinement-doctor
sudo vpn-confinement-doctor downloads
sudo vpn-confinement-doctor downloads --json
```

It reads the local system and reports namespace existence, default-drop firewall
chains and their hook attachment, routes, installed peers, configured host ingress, and
handshake ages. For running services it compares the process's actual namespace
with the configured namespace and reads its resolver file through the process's
mount view. The JSON output also includes effective capabilities and systemd
sandbox settings. Text and JSON report unsafe capabilities, privileged lifecycle commands, host
sockets, and named exceptions as warnings. An intentional exception stays visible without making
the exit status fail.

After applying a generated firewall transaction, the lifecycle unit records the installed policy in
a root-owned runtime directory. The doctor compares current rules with this snapshot, ignoring
handles and counters but preserving rule order, sets, hooks, and verdicts. The snapshot filename
includes the generated policy's digest, so a changed configuration cannot reuse an older snapshot.
Missing snapshots, added accepting rules, missing peers, and missing tunnel routes are issues.
Endpoint-pinning rules use the same comparison in the socket's birthplace namespace.

Exit status `0` means these local checks found no issue. Status `1` reports
missing or unexpected state. Status `2` indicates invalid arguments or missing
root access. An inactive service can have valid unit configuration without a
running process to inspect; the report makes that distinction explicit.

The command never reads private keys, queries WireGuard's secret-bearing `dump`
output, contacts a public IP checker, changes firewall rules, or restarts a unit.
Its output still contains local network configuration and service names. Review
it before sharing it publicly.

## Interpret results

An old handshake is not enough to declare a failed VPN. WireGuard can be quiet
when idle. The report says `reachability: not probed` because it has not tried an
application connection.

A missing namespace or firewall table deserves investigation before starting an
application. A wrong process namespace is an error. A wrong resolver file in
strict mode is also an error. Read unit status for the underlying startup failure:

```bash
systemctl status wireguard-wg0.service vpn-confinement-netns@vpnapps.service
journalctl -u wireguard-wg0.service -u vpn-confinement-netns@vpnapps.service -b
```

Use your application to test a destination you control. A root `ip netns exec`
probe tests namespace routing, but does not reproduce the application's UID,
resolver mounts, sandbox, or inherited sockets.

These diagnostics are not a security certification. A matching snapshot verifies that the
installed rules still match the rules captured after application; it does not prove that the
generated policy is correct or protect against a compromised host administrator. A host socket, a privileged
helper, or an application-specific communication path can require separate review.

Resolver-file inspection uses Linux `openat2` to keep absolute symlinks inside the
application's root. It requires Linux 5.6 or newer on the supported x86_64/aarch64
ABIs and fails verification if that operation is unavailable. It reads configuration
as root; use application-level tests to establish that the service user can read
and use it. The libc DNS VM exercises that distinction on a systemd-resolved host.
