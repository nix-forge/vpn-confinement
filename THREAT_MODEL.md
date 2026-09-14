# Threat model

## Scope

This model covers the vpn-confinement NixOS modules, scripts, examples, test
VMs, documentation site, and repository automation. It does not cover a
consumer's VPN provider, host kernel, or credentials.

## Assets and actors

Assets include routing and firewall policy, service credentials, WireGuard
configuration, generated options, dependency pins, and CI access. Contributors
and pull requests are untrusted. Maintainers approve changes and control
repository, Pages, Actions, and future release settings. The consumer supplies
provider credentials and chooses the service namespace.

## Trust boundaries

The Nix evaluator, generated systemd units, network namespace, host network,
VPN provider, and GitHub Actions are separate boundaries. Provider keys remain
outside the Nix store and CI. A host socket published through the veth is
explicitly different from a localhost listener.

## Main threats and controls

| Threat | Control |
| --- | --- |
| A service falls back to the clearnet | Default-drop nftables, namespace routing, DNS policy, and runtime tests |
| A provider key reaches the store or logs | Secret-path validation, documentation, and no credentials in CI |
| A pull request weakens isolation unnoticed | VM tests, CodeQL, dependency review, DCO, review, and protected main |
| CI token reaches untrusted code | Empty default permissions, job scopes, pinned actions, and no fork secrets |

Review this model when changing namespace, firewall, DNS, socket, credential,
service lifecycle, CI, or release behavior.

## Review cadence

The maintainers review this model before each release and whenever network
isolation, service behavior, dependencies, CI permissions, Pages, or secret
handling changes. A release candidate includes an explicit attack-surface
review and records new trust boundaries and residual risk in its release
notes. Incidents trigger an out-of-cycle review and a dated follow-up issue.
