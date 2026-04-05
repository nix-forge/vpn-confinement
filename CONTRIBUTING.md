# Contributing

Thanks for your interest in improving `vpn-confinement`.

## Development Setup

- Install Nix with flakes enabled.
- Clone the repository.
- Enter the development environment:

```bash
nix develop
```

## Before Opening a Pull Request

Run these checks locally:

```bash
nix fmt
nix flake check --show-trace --system x86_64-linux
```

If you have access to additional platforms, also run:

```bash
nix flake check --show-trace --system aarch64-linux
```

If your change affects options or docs, regenerate the options reference and
rebuild the docs site:

```bash
bash scripts/generate-options-doc.sh x86_64-linux
bun install --cwd site
bun run --cwd site build
```

Canonical project docs live in `site/src/content/docs/`.

## Contribution Guidelines

- Keep changes focused and easy to review.
- Prefer secure defaults and fail-closed behavior.
- Document user-visible option or behavior changes.
- Include tests for behavior and assertions where practical.
- Avoid introducing compatibility escape hatches unless there is a clear
  operational need.

## Pull Request Expectations

- Describe what changed and why.
- Document security impact when network, DNS, namespace, or lifecycle behavior
  changes.
- Note migration impact if defaults or assertions change.

## Reporting Security Issues

Do not open public issues for vulnerabilities. Follow
`site/src/content/docs/security.md` and use GitHub private vulnerability
reporting for this repository.

## Code of Conduct

By participating in this project, you agree to follow `CODE_OF_CONDUCT.md`.
