#!/usr/bin/env bash
# Check that install.sh produced a working setup. Run it in a new shell after installing, the way
# you'd use the machine: bash -lic ~/dotfiles/scripts/verify.sh
# Exits non-zero on the first failed check.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ok() { printf '  \033[32mok\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; exit 1; }

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN_DIR="$HOME/.local/share/dotfiles/bin"
# shellcheck source=/dev/null
. "$CONFIG_HOME/dotfiles/profile.sh"
echo "tools ($DOTFILES_PROFILE profile${DOTFILES_KEEP:+, keeping: $DOTFILES_KEEP})"
missing="$(mise ls --missing 2>&1 || true)"
[ -z "$missing" ] || fail "mise tools not installed: $missing"
ok "every tool for this profile is installed"
for c in nvim lazygit delta rg fd fzf tree-sitter gitleaks \
  lua-language-server marksman rust-analyzer ruff taplo shfmt stylua prettier markdownlint-cli2 \
  markdown-toc vtsls yaml-language-server vscode-eslint-language-server \
  vscode-json-language-server basedpyright tailwindcss-language-server; do
  [ "$(command -v "$c")" = "$BIN_DIR/$c" ] || fail "$c doesn't come from $BIN_DIR (got: $(command -v "$c" || echo nothing))"
done
ok "editor tools come from mise"

# runtimes: from mise only where this profile lets mise own them; otherwise never from mise
for rt in node:node pnpm:pnpm python:python3 uv:uv rust:cargo; do
  tool="${rt%%:*}" cmd="${rt#*:}" path="$(command -v "$cmd" || true)"
  if [ "$DOTFILES_PROFILE" = full ] && [[ " $DOTFILES_KEEP " != *" $tool "* ]]; then
    [ "$path" = "$BIN_DIR/$cmd" ] || fail "$cmd should come from mise (got: ${path:-nothing})"
    "$cmd" --version >/dev/null 2>&1 || fail "$cmd from mise doesn't run"
  else
    [ "$path" != "$BIN_DIR/$cmd" ] || fail "$cmd comes from mise, but this profile leaves it alone"
  fi
done
ok "runtimes follow the profile ($(for c in node python3 cargo; do printf '%s=%s ' "$c" "$(command -v "$c" || echo none)"; done))"
[ "$(git config --get core.pager)" = delta ] || fail "git doesn't use delta"
ok "git uses delta"

echo "neovim"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'local x = 1\nreturn x\n' >"$tmp/test.lua"
printf '# Title\n\nText.\n' >"$tmp/test.md"
printf 'const x: number = 1;\nexport default x;\n' >"$tmp/test.ts"
printf 'key: value\n' >"$tmp/test.yaml"
printf 'def add(a: int, b: int) -> int:\n    return a + b\n' >"$tmp/test.py"
printf '{ "key": "value" }\n' >"$tmp/test.json"
printf '[package]\nname = "x"\n' >"$tmp/test.toml"
mkdir -p "$tmp/tailwind"
printf 'module.exports = { content: ["./*.html"] };\n' >"$tmp/tailwind/tailwind.config.js"
printf '<div class="flex p-4"></div>\n' >"$tmp/tailwind/index.html"
TEST_DIR="$tmp" nvim --headless "+luafile $DOTFILES/scripts/verify-nvim.lua"
