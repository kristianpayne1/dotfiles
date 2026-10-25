#!/usr/bin/env bash
# Rewrite the lockfiles (mise-global/mise.lock, mise-global/mise.full.lock, mise-fallback/mise.lock)
# for every platform these dotfiles support.
# Run after changing a version in mise-global/config*.toml or mise-fallback/mise.toml.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORMS="linux-x64,linux-arm64,macos-x64,macos-arm64"

# lock the main config as mise sees it on a real machine, as the global config in
# ~/.config/mise, so the npm lock paths match; a temporary config dir makes this work from any
# checkout, linked in or not
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ln -s "$DOTFILES/mise-global" "$tmp/mise"
# MISE_ENV=full includes config.full.toml, so this writes both mise.lock and mise.full.lock
XDG_CONFIG_HOME="$tmp" MISE_ENV=full mise lock --global --platform "$PLATFORMS"

mise trust --quiet "$DOTFILES/mise-fallback/mise.toml"
mise lock --cd "$DOTFILES/mise-fallback" --platform "$PLATFORMS"
