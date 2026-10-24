#!/usr/bin/env bash
# Set up this machine like the others (macOS, Linux, WSL; x86 or ARM).
#   - system basics (git, curl, unzip, C compiler) via the OS package manager, only if sudo works
#   - mise, downloaded at a pinned version and checked against its published checksum
#   - everything else per user via mise, no sudo, pinned and checksum-locked: nvim, lazygit,
#     delta, ripgrep, fd, fzf, tree-sitter, node, pnpm, and Neovim's language servers and tools
#   - configs symlinked from this repo; anything in the way is moved to
#     ~/.local/state/dotfiles/backups/<timestamp>/
#   - Nerd Font on machines with a screen (skipped over SSH and on WSL)
# Safe to re-run.
#
# Usage: install.sh [--no-sudo] [--ca-cert FILE]
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
while [ $# -gt 0 ]; do
  case "$1" in
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

# write_block FILE NAME CONTENT: put CONTENT between "# >>> NAME >>>" markers in FILE,
# replacing the previous block so re-runs and changes to this script stay tidy
write_block() {
  local file="$1" begin="# >>> $2 >>>" end="# <<< $2 <<<" content="$3" tmp
  touch "$file"
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$file" >"$tmp"
  printf '%s\n%s\n%s\n' "$begin" "$content" "$end" >>"$tmp"
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

# 4. Tools, from the lockfile ------------------------------------------------------------------
link "$DOTFILES/mise-global" "$CONFIG_HOME/mise"
info "installing tools with mise"
"$MISE" install
"$MISE" reshim
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

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

# 5. Shell startup -----------------------------------------------------------------------------
# login shells (and so GUI apps, cron, scripts) get mise's shims; interactive shells activate mise
shell_name="$(basename "${SHELL:-bash}")"
case "$shell_name" in
  zsh) profile="$HOME/.zprofile" rc="$HOME/.zshrc" ;;
  bash)
    if [ "$OS" = Darwin ] || [ -f "$HOME/.bash_profile" ]; then profile="$HOME/.bash_profile"; else profile="$HOME/.profile"; fi
    if [ "$OS" = Darwin ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi
    ;;
  *) profile="" rc="" ;;
esac
if [ -n "$rc" ]; then
  # env.sh is written by --ca-cert; local.sh is yours for machine-only settings (proxy, tokens)
  # and never lives in the repo
  env_line="[ -f \"$ENV_FILE\" ] && . \"$ENV_FILE\"
[ -f \"$CONFIG_HOME/dotfiles/local.sh\" ] && . \"$CONFIG_HOME/dotfiles/local.sh\""
  write_block "$profile" "dotfiles (login)" "export PATH=\"\$HOME/.local/share/mise/shims:\$HOME/.local/bin:\$PATH\"
$env_line"
  write_block "$rc" "dotfiles" "export PATH=\"\$HOME/.local/bin:\$PATH\"
$env_line
eval \"\$(\"\$HOME/.local/bin/mise\" activate $shell_name)\""
else
  note "add ~/.local/share/mise/shims to PATH and 'eval \"\$(~/.local/bin/mise activate <shell>)\"' to your shell's startup files"
fi

# 6. Configs -----------------------------------------------------------------------------------
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

# 7. Font and terminal (only where there's a screen) -------------------------------------------
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

# 8. Neovim plugins (and treesitter parsers) at the versions in lazy-lock.json -----------------
info "installing Neovim plugins and treesitter parsers"
# restore runs twice: the second pass retries fetches that failed (proxies and GitHub sometimes
# reject a burst of parallel git requests) and is nearly free otherwise. nvim-setup.lua then waits
# for the treesitter parsers, which build in the background.
nvim --headless "+Lazy! restore" "+Lazy! restore" "+luafile $DOTFILES/scripts/nvim-setup.lua" "+qa!" || note "Neovim setup reported errors; open nvim to finish"

info "done; open a new terminal (or run: exec \$SHELL -l)"
for n in "${NOTES[@]+"${NOTES[@]}"}"; do echo "note: $n"; done
