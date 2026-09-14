# Dependency management policy

This policy applies to Nix flake inputs, the Bun documentation site, generated
option documentation, GitHub Actions, and test tooling in vpn-confinement.
Dependency changes are reviewed as changes to the network and deployment trust
boundary.

## Inventory and provenance

The authoritative dependency records are `flake.lock`, nested development
lockfiles, `site/bun.lock`, generated documentation inputs, and immutable
action references in `.github/workflows/`. Each update identifies its upstream
source, revision or archive, expected hash where applicable, and material
transitive changes.

Dependabot keeps supported ecosystems visible. Dependency-review, CodeQL,
flake-lock health, documentation checks, runtime tests, and Nix flake checks
run in CI. These checks cover known vulnerabilities, supported source
languages, lockfile freshness, generated output, and the isolation behavior
exercised by the repository.

## Selection and review

Maintainers review upstream provenance, maintenance status, security
advisories, licensing, platform compatibility, and network behavior. Lockfiles
are updated with their declarations. Action updates use immutable commit SHAs.
Changes that affect namespace, DNS, firewall, credentials, or service
lifecycle include a focused test and migration guidance.

## Release gate and exceptions

Before a future release, applicable dependency-review, CodeQL, lock-health,
flake, documentation, and runtime checks must pass. A high- or
critical-severity finding, an unreviewed license problem, or a failed
provenance check blocks the release. The only exception is a reviewed,
time-bounded pull-request record that names the component, explains why it is
not exploitable here, assigns an owner, and gives a remediation date.
`security/vex.json` records reviewed non-affectability statements in OpenVEX
form; it does not waive an affectable finding.

## Update and rollback

Updates are evaluated on the supported systems and representative VM or
runtime tests. A regression is rolled back by reverting the lockfile or
declaration change, then tracked with a follow-up issue. Emergency security
updates use the smallest safe change and receive normal review retrospectively
if immediate action is required.
