# Secret management policy

This policy covers NixOS examples, runtime VPN credentials, GitHub Actions,
documentation, and test fixtures. Provider credentials and private network
details are deployment inputs, not repository content.

## Storage and handling

WireGuard private keys, provider credentials, tokens, and private host data
must stay in the consumer's protected secret store. They must not be committed,
placed in the Nix store, passed as command-line arguments, copied into site
artifacts, or printed in logs and test output. Pull-request and fork workflows
receive no repository secrets; runtime tests use disposable public fixtures.

The Pages workflow only builds public documentation. It uses job-scoped read
permissions and GitHub's Pages OIDC deployment token, not a long-lived site
credential.

## Access, rotation, and response

Maintainers review Actions secrets, environments, Pages, and any future release
access before granting it. Access is individual, least-privilege, and removed
when responsibility ends. Credentials have an owner and review date; rotate
them at least annually and immediately after suspected exposure, maintainer or
provider changes, or a trust-boundary change.

Suspected exposure triggers revocation, replacement, log and artifact review,
and a private report through [SECURITY.md](../SECURITY.md). Never put secret
values or private incident details in `security/vex.json`.
