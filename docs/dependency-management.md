# Dependency management policy

This policy covers Nix inputs, the Bun documentation toolchain, source
references, GitHub Actions, and test tooling in `vpn-confinement`.

## Inventory and provenance

The authoritative dependency records are `flake.lock`, `site/bun.lock`,
generated option sources, and immutable action references in
`.github/workflows/`. Updates identify the upstream source, revision or
archive, license, and material transitive changes. Documentation dependencies
are installed from the committed Bun lockfile.

## Automated evaluation

Pull requests and merge groups run dependency review, Bun's audit, CodeQL,
flake checks, documentation builds, runtime tests, and repository checks.
These checks cover the Nix and site dependency surfaces and are required
before protected `main` advances. A dependency or security check failure is a
release blocker, not an advisory-only result.

## Remediation and exceptions

Known exploited vulnerabilities, high or critical SCA findings, malicious
dependencies, and prohibited licenses must be fixed before a future release.
Lower-severity findings are fixed before release unless a reviewed,
time-bounded record names the component, explains non-exploitability, assigns
an owner, and gives a remediation date. `security/vex.json` records reviewed
non-affectability statements only; it does not suppress an affectable finding.

Maintainers review upstream provenance, maintenance status, advisories,
licensing, reproducibility, and platform support. Regressions are rolled back
by reverting the lockfile or declaration and tracking the follow-up issue.
