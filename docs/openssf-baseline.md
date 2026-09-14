# OpenSSF baseline policy

This repository follows the [OSPS Baseline](https://baseline.openssf.org/versions/2026-08-28)
version 2026.08.28. The policy covers the NixOS modules, scripts, examples,
documentation site, CI, and source history.

## Project scope and releases

vpn-confinement provides fail-closed network namespaces, WireGuard routing,
nftables policy, and DNS controls for selected NixOS services. It does not
currently publish compiled GitHub release assets or official GitHub releases.
The documentation site is the public release surface. A future source release
must use a unique immutable tag, a scoped change log, integrity evidence,
security review, and a support window.

## Change and build controls

Every commit must carry a matching Signed-off-by trailer. The DCO file defines
the certificate and .github/workflows/dco.yml checks proposed non-merge commits
on pull requests and merge-group refs.

All workflows start with empty default permissions. Jobs grant only the scopes
they need, checkout does not persist credentials, and actions use full commit
SHAs. Pull requests and merge groups run flake checks, dependency review,
CodeQL, documentation builds, runtime tests, and repository checks before
protected main can advance.

Use the commands in [CONTRIBUTING.md](../CONTRIBUTING.md):

    nix fmt
    nix flake check --show-trace --system x86_64-linux
    bun install --cwd site --frozen-lockfile
    bun run --cwd site build

Changes to namespace, DNS, firewall, credential, or service lifecycle behavior
include a VM or focused test and a migration note. Never commit provider keys
or plaintext credentials.

## Release and dependency controls

Flake inputs, the Bun lockfile, and generated option documentation are reviewed
with their security and compatibility impact. Dependency review blocks new
low-or-higher severity vulnerabilities. CodeQL and SCA findings must be fixed
before a future release unless a reviewed suppression records why the finding
is not exploitable.

A future release will tag reviewed main, publish the source commit and scoped
change log, publish checksums and a signed manifest, identify the release actor
and workflow, explain verification, record the threat-model review, and state
when support ends. Releases will not contain provider credentials.

## Governance and vulnerability response

The maintainers listed in [GOVERNANCE.md](../GOVERNANCE.md) own repository
administration, Actions secrets, Pages, dependency policy, and future releases.
Sensitive access is granted after review of the contributor's history and
intended responsibility. New maintainers receive the narrowest role needed.

Report vulnerabilities through [SECURITY.md](../SECURITY.md) or GitHub private
vulnerability reporting. The maintainer acknowledges reports within three
business days and provides an initial assessment within seven days. Public
disclosure follows a fix or documented mitigation. [security/vex.json](../security/vex.json)
records reviewed non-affectability statements. Support rules are in
[SUPPORT.md](../SUPPORT.md).

## Control evidence

| Control area | Evidence |
| --- | --- |
| Least-privilege CI and trusted inputs | Empty default permissions, job scopes, pinned actions, quoted inputs, and no fork secrets |
| Releases and change logs | This release policy and the documentation site |
| Dependencies | flake.lock, site/bun.lock, dependency review, and CodeQL |
| Build and test instructions | [CONTRIBUTING.md](../CONTRIBUTING.md) |
| Governance | [GOVERNANCE.md](../GOVERNANCE.md) |
| Contributor legal agreement | [DCO](../DCO) and .github/workflows/dco.yml |
| Security assessment | [THREAT_MODEL.md](../THREAT_MODEL.md) and the site threat-model page |
| Vulnerability response | [SECURITY.md](../SECURITY.md), private reporting, advisories, and [security/vex.json](../security/vex.json) |
| Public interfaces and release identity | Module options, docs, reviewed commits, and future signed manifests |
| Support lifecycle | [SUPPORT.md](../SUPPORT.md) |

Review this policy when network, credential, service lifecycle, CI, or release
behavior changes.
