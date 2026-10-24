#!/usr/bin/env bash
# Check that install.sh produced a working setup. Run it in a new shell after installing, the way
# you'd use the machine: bash -lic ~/dotfiles/scripts/verify.sh
# Exits non-zero on the first failed check.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ok() { printf '  \033[32mok\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; exit 1; }

echo "tools"
missing="$(mise ls --missing 2>&1 || true)"
[ -z "$missing" ] || fail "mise tools not installed: $missing"
ok "every tool in mise-global/config.toml is installed"
for c in nvim lazygit delta rg fd fzf tree-sitter node npm pnpm \
  lua-language-server marksman shfmt stylua prettier markdownlint-cli2 markdown-toc \
  vtsls yaml-language-server vscode-eslint-language-server gitleaks; do
  command -v "$c" >/dev/null || fail "$c not on PATH"
done
ok "all commands on PATH"
[ "$(git config --get core.pager)" = delta ] || fail "git doesn't use delta"
ok "git uses delta"

echo "neovim"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'local x = 1\nreturn x\n' >"$tmp/test.lua"
printf '# Title\n\nText.\n' >"$tmp/test.md"
printf 'const x: number = 1;\nexport default x;\n' >"$tmp/test.ts"
printf 'key: value\n' >"$tmp/test.yaml"
TEST_DIR="$tmp" nvim --headless "+luafile $DOTFILES/scripts/verify-nvim.lua"
