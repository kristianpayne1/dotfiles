#!/usr/bin/env bash
# Set up this machine like the others (macOS, Linux, WSL; x86 or ARM).
#   - system basics (git, curl, unzip, C compiler) via the OS package manager, only if sudo works
#   - mise, downloaded at a pinned version and checked against its published checksum
#   - everything else per user via mise, no sudo, pinned and checksum-locked, in one of two
#     profiles:
#       editor  Neovim + LazyVim and its configs, lazygit, delta, ripgrep, fd, fzf, tree-sitter
#               and every language server/formatter. Changes nothing else: Node is installed
#               only for the language servers and stays off your PATH.
#       full    editor, plus Node, pnpm, Python, uv and Rust on your PATH. Any of those already
#               on the machine is kept unless you choose mise's (asked per runtime).
#   - configs symlinked from this repo; anything in the way is moved to
#     ~/.local/state/dotfiles/backups/<timestamp>/
#   - Nerd Font on machines with a screen (skipped over SSH and on WSL)
# Safe to re-run.
#
# Usage: install.sh [--editor | --full [--use-mise-runtimes]] [--no-sudo] [--ca-cert FILE]
#   --editor         editor profile (asked if no profile is given; remembered for re-runs)
#   --full           full profile
#   --use-mise-runtimes   with --full, use mise's Node/Python/uv/pnpm/Rust even where the machine
#                    already has one (default: keep the existing one; asked when interactive)
#   --no-sudo        never touch system packages (e.g. on a shared box); zig and 7-Zip stand in
#                    for a missing C compiler and unzip. Same as DOTFILES_NO_SUDO=1.
#   --ca-cert FILE   trust this extra CA certificate (PEM), for networks whose proxy inspects
#                    HTTPS. Kept for future shells too. Same as DOTFILES_CA_CERT=FILE.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/pins.sh
. "$DOTFILES/scripts/pins.sh"

NO_SUDO="${DOTFILES_NO_SUDO:-0}"
CA_CERT="${DOTFILES_CA_CERT:-}"
PROFILE=""
USE_MISE_RUNTIMES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --editor) PROFILE=editor ;;
    --full) PROFILE=full ;;
    --use-mise-runtimes) USE_MISE_RUNTIMES=1 ;;
    --no-sudo) NO_SUDO=1 ;;
    --ca-cert) CA_CERT="${2:?--ca-cert needs a file}"; shift ;;
    --ca-cert=*) CA_CERT="${1#--ca-cert=}" ;;
    -h | --help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (try --help)"; exit 1 ;;
  esac
  shift
done

STAMP="$(date +%Y%m%d%H%M%S)"
OS="$(uname -s)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
NOTES=()

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
note() { NOTES+=("$*"); }
has() { command -v "$1" >/dev/null 2>&1; }
die() { echo "error: $*" >&2; exit 1; }

sha256() {
  if has sha256sum; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{ print $1 }'
}

# fetch URL FILE SHA256: download and refuse it unless the checksum matches
fetch() {
  curl -fsSL "$1" -o "$2"
  local got
  got="$(sha256 "$2")"
  [ "$got" = "$3" ] || die "checksum mismatch for $1 (expected $3, got $got)"
}

# link SRC DEST: point DEST at SRC, moving whatever was there into this run's backup folder
link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    local backup="$STATE_DIR/backups/$STAMP$dest"
    mkdir -p "$(dirname "$backup")"
    mv "$dest" "$backup"
    info "moved existing $dest to $backup"
  fi
  ln -s "$src" "$dest"
  info "linked $dest -> $src"
}

# write_block FILE NAME CONTENT: put CONTENT between "# >>> NAME >>>" markers in FILE, replacing
# the previous block in place (or appending the first time) so re-runs and changes stay tidy
write_block() {
  local file="$1" tmp
  touch "$file"
  tmp="$(mktemp)"
  BEGIN_MARK="# >>> $2 >>>" END_MARK="# <<< $2 <<<" BLOCK="$3" awk '
    function block() { print ENVIRON["BEGIN_MARK"]; print ENVIRON["BLOCK"]; print ENVIRON["END_MARK"] }
    $0 == ENVIRON["BEGIN_MARK"] { block(); skip = 1; done = 1; next }
    skip { if ($0 == ENVIRON["END_MARK"]) skip = 0; next }
    { print }
    END { if (!done) block() }
  ' "$file" >"$tmp"
  if ! cmp -s "$tmp" "$file"; then
    cat "$tmp" >"$file"
    info "updated $2 block in $file"
  fi
  rm -f "$tmp"
}

is_wsl() { [ "$OS" = Linux ] && grep -qi microsoft /proc/version 2>/dev/null; }

# root, passwordless sudo, or a sudo password typed now (never with --no-sudo)
can_sudo() {
  [ "$NO_SUDO" = 1 ] && return 1
  [ "$(id -u)" = 0 ] && return 0
  has sudo || return 1
  sudo -n true 2>/dev/null && return 0
  [ -t 0 ] && sudo -v
}

# 1. Extra CA certificate (before anything downloads) ------------------------------------------
ENV_FILE="$CONFIG_HOME/dotfiles/env.sh"
if [ -n "$CA_CERT" ]; then
  [ -f "$CA_CERT" ] || die "CA certificate not found: $CA_CERT"
  system_bundle=""
  for f in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
    [ -f "$f" ] && system_bundle="$f" && break
  done
  [ -n "$system_bundle" ] || die "couldn't find the system CA bundle to add $CA_CERT to"
  cert_dir="$HOME/.local/share/dotfiles"
  mkdir -p "$cert_dir" "$(dirname "$ENV_FILE")"
  cp "$CA_CERT" "$cert_dir/extra-ca.pem"
  cat "$system_bundle" "$cert_dir/extra-ca.pem" >"$cert_dir/ca-bundle.pem"
  cat >"$ENV_FILE" <<EOF
# Written by install.sh --ca-cert: trust the extra CA in $cert_dir/extra-ca.pem everywhere.
export SSL_CERT_FILE="$cert_dir/ca-bundle.pem"
export CURL_CA_BUNDLE="$cert_dir/ca-bundle.pem"
export GIT_SSL_CAINFO="$cert_dir/ca-bundle.pem"
export REQUESTS_CA_BUNDLE="$cert_dir/ca-bundle.pem"
export NODE_EXTRA_CA_CERTS="$cert_dir/extra-ca.pem"
EOF
  info "trusting extra CA certificate $CA_CERT (settings in $ENV_FILE)"
fi
# shellcheck source=/dev/null
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

# 2. System basics -----------------------------------------------------------------------------
if [ "$OS" = Darwin ]; then
  if ! xcode-select -p >/dev/null 2>&1; then
    info "installing the Xcode command line tools (git, compiler); re-run this script when it finishes"
    xcode-select --install
    exit 1
  fi
else
  missing=()
  for c in git curl tar unzip xz gzip make cc; do has "$c" || missing+=("$c"); done
  if [ ${#missing[@]} -gt 0 ]; then
    info "missing system tools: ${missing[*]}"
    SUDO=""
    [ "$(id -u)" != 0 ] && SUDO=sudo
    if can_sudo; then
      if has apt-get; then
        $SUDO apt-get update -q
        $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -yq build-essential git curl tar unzip xz-utils gzip ca-certificates
      elif has dnf; then
        $SUDO dnf install -yq gcc gcc-c++ make git curl tar unzip xz gzip
      elif has yum; then
        $SUDO yum install -yq gcc gcc-c++ make git curl tar unzip xz gzip
      elif has pacman; then
        $SUDO pacman -Sy --needed --noconfirm base-devel git curl tar unzip xz gzip
      elif has zypper; then
        $SUDO zypper -nq install gcc gcc-c++ make git curl tar unzip xz gzip
      elif has apk; then
        $SUDO apk add -q build-base git curl tar unzip xz gzip
      else
        note "unknown package manager; install these yourself: ${missing[*]}"
      fi
    else
      note "system packages not installed (no sudo): ${missing[*]} (zig and 7-Zip stand in for cc and unzip)"
      if ! { has curl && has tar && has gzip; }; then die "curl, tar and gzip are required to continue"; fi
    fi
  fi
fi

# 3. mise, verified ----------------------------------------------------------------------------
MISE="$HOME/.local/bin/mise"
if [ ! -x "$MISE" ] || [ "$("$MISE" --version 2>/dev/null | awk '{ print $1 }')" != "${MISE_VERSION#v}" ]; then
  case "$OS" in Linux) os=linux ;; Darwin) os=macos ;; *) die "unsupported OS: $OS" ;; esac
  case "$(uname -m)" in x86_64 | amd64) arch=x64 ;; aarch64 | arm64) arch=arm64 ;; *) die "unsupported CPU: $(uname -m)" ;; esac
  platform="$os-$arch"
  if [ "$os" = linux ] && { ldd --version 2>&1 | grep -qi musl || compgen -G '/lib/ld-musl-*' >/dev/null; }; then
    platform="$platform-musl"
  fi
  sum_var="MISE_SHA256_${platform//-/_}"
  info "installing mise $MISE_VERSION ($platform)"
  tmp="$(mktemp -d)"
  fetch "https://github.com/jdx/mise/releases/download/$MISE_VERSION/mise-$MISE_VERSION-$platform.tar.gz" "$tmp/mise.tar.gz" "${!sum_var}"
  tar -xzf "$tmp/mise.tar.gz" -C "$tmp"
  mkdir -p "$(dirname "$MISE")"
  mv "$tmp/mise/bin/mise" "$MISE"
  rm -rf "$tmp"
fi

# 4. Profile ------------------------------------------------------------------------------------
# Choices are remembered in profile.sh (also sourced by the shell blocks: the mise shims need
# MISE_ENV and MISE_DISABLE_TOOLS at run time). Passing --editor/--full asks again.
PROFILE_FILE="$CONFIG_HOME/dotfiles/profile.sh"
BIN_DIR="$HOME/.local/share/dotfiles/bin"
RUNTIMES="node pnpm python uv rust"
KEEP=""
if [ -z "$PROFILE" ] && [ -f "$PROFILE_FILE" ]; then
  # shellcheck source=/dev/null
  . "$PROFILE_FILE"
  PROFILE="$DOTFILES_PROFILE"
  KEEP="$DOTFILES_KEEP"
  REASK=0
else
  REASK=1
fi

ask() { # ask QUESTION DEFAULT(y/n): yes/no, or DEFAULT when not interactive
  local answer
  if [ ! -t 0 ]; then [ "$2" = y ]; return; fi
  read -r -p "$1 " answer
  case "${answer:-$2}" in [yY]*) return 0 ;; *) return 1 ;; esac
}

if [ -z "$PROFILE" ]; then
  echo "Which profile?"
  echo "  editor  Neovim/LazyVim, its tools and configs only; leaves Node/Python/Rust alone"
  echo "  full    editor, plus Node, pnpm, Python, uv and Rust managed by mise"
  if ask "Install the full profile? [y/N]" n; then PROFILE=full; else PROFILE=editor; fi
fi
info "profile: $PROFILE"

# the first COMMAND on PATH that isn't ours or mise's: a runtime the machine already has
system_which() {
  local d IFS=:
  for d in $PATH; do
    case "$d" in "$BIN_DIR" | "$HOME/.local/share/mise"*) continue ;; esac
    if [ -x "$d/$1" ]; then echo "$d/$1"; return 0; fi
  done
  return 1
}
runtime_cmd() { case "$1" in python) echo python3 ;; rust) echo cargo ;; *) echo "$1" ;; esac; }
pinned_version() { sed -n "s/^$1 = \"\(.*\)\"$/\1/p" "$DOTFILES"/mise-global/config*.toml | head -1; }

if [ "$PROFILE" = full ] && [ "$REASK" = 1 ]; then
  for rt in $RUNTIMES; do
    existing="$(system_which "$(runtime_cmd "$rt")")" || continue
    version="$("$existing" --version 2>&1 | head -1)"
    if [ "$USE_MISE_RUNTIMES" = 1 ] || ask "Found $rt ($version) at $existing. Use mise's $rt $(pinned_version "$rt") instead? [y/N]" n; then
      info "$rt: using mise's, ahead of $existing"
    else
      info "$rt: keeping $existing"
      KEEP="$KEEP $rt"
    fi
  done
fi

# Node stays installed even when kept: the npm-based language servers run on mise's Node
disable=""
for rt in $KEEP; do [ "$rt" = node ] || disable="${disable:+$disable,}$rt"; done
mkdir -p "$(dirname "$PROFILE_FILE")"
{
  echo "# Written by install.sh: this machine's profile and the runtimes mise leaves alone."
  echo "DOTFILES_PROFILE=$PROFILE"
  echo "DOTFILES_KEEP=\"${KEEP# }\""
  if [ "$PROFILE" = full ]; then echo "export MISE_ENV=full"; fi
  if [ -n "$disable" ]; then echo "export MISE_DISABLE_TOOLS=$disable"; fi
} >"$PROFILE_FILE"
unset MISE_ENV MISE_DISABLE_TOOLS
# shellcheck source=/dev/null
. "$PROFILE_FILE"

# 5. Tools, from the lockfile ------------------------------------------------------------------
link "$DOTFILES/mise-global" "$CONFIG_HOME/mise"
info "installing tools with mise"
"$MISE" install
"$MISE" reshim

# Expose commands through BIN_DIR, which goes first on PATH: every editor tool, plus the runtimes
# mise owns in the full profile. Kept runtimes (and all runtimes in the editor profile) aren't
# linked, so the machine's own versions keep winning; the language servers still find mise's Node
# because mise's shims set up each tool's own environment.
owned=""
if [ "$PROFILE" = full ]; then
  for rt in $RUNTIMES; do case " $KEEP " in *" $rt "*) ;; *) owned="$owned $rt" ;; esac; done
fi
new_bin="$(mktemp -d)"
for shim in "$HOME/.local/share/mise/shims"/*; do
  name="$(basename "$shim")"
  tool="$("$MISE" which --plugin "$name" 2>/dev/null)" || continue
  case " $RUNTIMES " in
    *" $tool "*) case " $owned " in *" $tool "*) ;; *) continue ;; esac ;;
  esac
  ln -s "$shim" "$new_bin/$name"
done
if [ "$(ls "$new_bin")" != "$(ls "$BIN_DIR" 2>/dev/null)" ]; then
  rm -rf "$BIN_DIR"
  mkdir -p "$(dirname "$BIN_DIR")"
  mv "$new_bin" "$BIN_DIR"
  info "linked $(find "$BIN_DIR" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ') commands into $BIN_DIR"
else
  rm -rf "$new_bin"
fi
export PATH="$BIN_DIR:$HOME/.local/bin:$PATH"

FALLBACK="$DOTFILES/mise-fallback"
fallback() {
  "$MISE" trust --quiet "$FALLBACK/mise.toml"
  "$MISE" install --cd "$FALLBACK" "$1"
  "$MISE" where --cd "$FALLBACK" "$1"
}

# no C compiler and no sudo to get one: use zig's, so treesitter parsers can still be built
if ! has cc; then
  info "no C compiler; installing zig to provide cc"
  zig_dir="$(fallback zig)"
  # tree-sitter passes Rust-style targets (aarch64-unknown-linux-gnu) that zig can't parse;
  # dropping them is fine since zig builds for this machine by default
  cat >"$HOME/.local/bin/cc" <<EOF
#!/bin/sh
skip=0
for a; do
  shift
  if [ \$skip = 1 ]; then skip=0; continue; fi
  case "\$a" in
    -target) skip=1; continue ;;
    --target=*) continue ;;
  esac
  set -- "\$@" "\$a"
done
exec "$zig_dir/zig" cc "\$@"
EOF
  chmod +x "$HOME/.local/bin/cc"
fi

# no unzip and no sudo to get one: tools only run `unzip [-o] -d DIR FILE`, so 7-Zip stands in
if ! has unzip; then
  info "no unzip; installing 7-Zip to provide it"
  sevenzip_dir="$(fallback 7zip)"
  cat >"$HOME/.local/bin/unzip" <<EOF
#!/bin/sh
dir=.
while [ \$# -gt 1 ]; do
  case "\$1" in
    -d) dir="\$2"; shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
exec "$sevenzip_dir/7zz" x -y -bso0 -bsp0 "-o\$dir" "\$@"
EOF
  chmod +x "$HOME/.local/bin/unzip"
fi

# 6. Shell startup -----------------------------------------------------------------------------
# The same block in login shells (so GUI apps, cron and scripts see it too) and interactive ones.
# No `mise activate`: only BIN_DIR goes first. The full profile also puts mise's shims last on
# PATH, so tools a project's own mise.toml asks for are reachable without shadowing anything.
shell_name="$(basename "${SHELL:-bash}")"
case "$shell_name" in
  zsh) profile="$HOME/.zprofile" rc="$HOME/.zshrc" ;;
  bash)
    if [ "$OS" = Darwin ] || [ -f "$HOME/.bash_profile" ]; then profile="$HOME/.bash_profile"; else profile="$HOME/.profile"; fi
    if [ "$OS" = Darwin ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi
    ;;
  *) profile="" rc="" ;;
esac
# profile.sh: this machine's profile; env.sh: written by --ca-cert; local.sh: yours, for
# machine-only settings (proxy, tokens), never in the repo
block="export PATH=\"\$HOME/.local/share/dotfiles/bin:\$HOME/.local/bin:\$PATH\"
for _dotfiles_f in profile env local; do
  [ -f \"$CONFIG_HOME/dotfiles/\$_dotfiles_f.sh\" ] && . \"$CONFIG_HOME/dotfiles/\$_dotfiles_f.sh\"
done
unset _dotfiles_f"
if [ "$PROFILE" = full ]; then
  block="$block
export PATH=\"\$PATH:\$HOME/.local/share/mise/shims\""
fi
if [ -n "$rc" ]; then
  write_block "$profile" "dotfiles (login)" "$block"
  write_block "$rc" "dotfiles" "$block"
else
  note "add this to your shell's startup files: $block"
fi

# 7. Configs -----------------------------------------------------------------------------------
link "$DOTFILES/nvim" "$CONFIG_HOME/nvim"
link "$DOTFILES/lazygit/config.yml" "$(lazygit --print-config-dir)/config.yml"

# git: include the shared delta/pager settings; name and email stay per machine in ~/.gitconfig
if ! git config --global --type=path --get-all include.path | grep -qx "$DOTFILES/git/delta.gitconfig"; then
  git config --global --add include.path "$DOTFILES/git/delta.gitconfig"
  info "added $DOTFILES/git/delta.gitconfig to ~/.gitconfig"
fi
# scan this repo's commits for secrets
[ -d "$DOTFILES/.git" ] && git -C "$DOTFILES" config core.hooksPath scripts/hooks
git config --global user.name >/dev/null || note "set your git name and email: git config --global user.name ...; git config --global user.email ..."

# 8. Font and terminal (only where there's a screen) -------------------------------------------
FONT_GLOB="JetBrainsMonoNLNerdFont-*.ttf"
install_font() {
  local dir="$1" tmp
  if compgen -G "$dir/$FONT_GLOB" >/dev/null; then
    return
  fi
  info "installing JetBrains Mono NL Nerd Font $NERD_FONTS_VERSION"
  tmp="$(mktemp -d)"
  fetch "https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_FONTS_VERSION/JetBrainsMono.tar.xz" "$tmp/font.tar.xz" "$NERD_FONTS_SHA256"
  tar -xJf "$tmp/font.tar.xz" -C "$tmp"
  mkdir -p "$dir"
  # shellcheck disable=SC2086 # the glob should expand
  cp "$tmp"/$FONT_GLOB "$dir/"
  rm -rf "$tmp"
  if has fc-cache; then fc-cache -f "$dir" >/dev/null; fi
}
if [ "$OS" = Darwin ]; then
  install_font "$HOME/Library/Fonts"
  if [ ! -d /Applications/Ghostty.app ]; then
    if has brew; then
      brew install --cask ghostty
    else
      note "install Ghostty from https://ghostty.org"
    fi
  fi
elif is_wsl; then
  note "WSL: install JetBrains Mono NL Nerd Font on Windows and pick it in your terminal (https://www.nerdfonts.com/font-downloads)"
elif [ -n "${SSH_CONNECTION:-}" ] || ! has fc-cache; then
  : # remote/headless: the font lives on the machine you connect from
else
  install_font "${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
fi

# 9. Neovim plugins (and treesitter parsers) at the versions in lazy-lock.json -----------------
info "installing Neovim plugins and treesitter parsers"
# Two passes. A fresh install can't fully honour the lockfile: plugins that only appear once LazyVim
# itself is installed get cloned at their latest commit, and lazy writes that back over the pin.
# So: install everything, put the committed lockfile back, and restore again, which now checks out
# exactly the pinned commits (and retries any fetch that failed, e.g. behind a proxy).
# Each pass runs nvim-setup.lua, which builds the treesitter parsers and waits for them; quitting
# mid-build can leave a language half-installed.
lock="$DOTFILES/nvim/lazy-lock.json"
saved_lock="$(mktemp)"
cp "$lock" "$saved_lock"
nvim --headless "+Lazy! restore" "+luafile $DOTFILES/scripts/nvim-setup.lua" "+qa!" || true
cp "$saved_lock" "$lock"
rm -f "$saved_lock"
nvim --headless "+Lazy! restore" "+luafile $DOTFILES/scripts/nvim-setup.lua" "+qa!" ||
  note "Neovim setup reported errors; open nvim to finish"

info "done; open a new terminal (or run: exec \$SHELL -l)"
for n in "${NOTES[@]+"${NOTES[@]}"}"; do echo "note: $n"; done
