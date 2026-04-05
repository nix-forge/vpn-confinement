#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
target="$repo_root/site/src/content/docs/reference/options-generated.md"

if [ $# -gt 1 ]; then
  echo "Usage: $0 [system]" >&2
  exit 1
fi

if [ $# -eq 1 ]; then
  system="$1"
else
  system="$(nix eval --raw --impure --expr builtins.currentSystem)"
fi

mkdir -p "$(dirname "$target")"
if ! nix eval ".#packages.${system}.options-doc-markdown.outPath" >/dev/null 2>&1; then
  cat <<EOF >&2
No options-doc package is available for system '${system}'.
This flake currently exposes per-system outputs for Linux targets.
Run this command with an explicit supported target, for example:

  bash scripts/generate-options-doc.sh x86_64-linux
EOF
  exit 1
fi

out_path="$(nix build ".#packages.${system}.options-doc-markdown" --print-out-paths --no-link)"
cp "$out_path" "$target"

echo "Wrote $target"
