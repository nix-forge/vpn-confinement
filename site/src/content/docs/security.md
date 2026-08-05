---
title: Security
description: Supported versions and vulnerability reporting
---

## Supported versions

This project supports:

- the latest `main` branch
- NixOS `unstable`

Security fixes are developed on `main`. If needed, supported stable-targeted
fixes are documented in release notes or security advisories.

## Reporting a vulnerability

Do not open a public issue. Submit a report through
[GitHub private vulnerability reporting](https://github.com/nix-forge/vpn-confinement/security/advisories/new).
If that form is unavailable, contact the maintainer through the private address
listed on the GitHub profile and request an encrypted channel.

Include:

- affected version or commit
- relevant namespace/service configuration
- impact summary (what guarantee is bypassed)
- minimal reproduction steps

We aim to acknowledge reports within 3 business days, provide an initial
assessment within 7 business days, and publish a remediation timeline after
triage. Coordinated disclosure timing is agreed with the reporter. Good-faith
research that avoids privacy violations, persistence, destructive actions, and
third-party systems is welcome.
