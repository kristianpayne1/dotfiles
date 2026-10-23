#!/usr/bin/env bash
# Set up this machine like the others (macOS, Linux, WSL; x86 or ARM).
#   - system basics (git, curl, unzip, C compiler) via the OS package manager, only if sudo is available
#   - everything else per user via mise, no sudo: nvim, lazygit, delta, ripgrep, fd, fzf, tree-sitter, node, pnpm
#   - configs symlinked from this repo; anything already in the way is moved to <name>.bak.<timestamp>
#   - Nerd Font on machines with a screen (skipped over SSH and on WSL)
# Safe to re-run.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d%H%M%S)"
OS="$(uname -s)"
NOTES=()

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
note() { NOTES+=("$*"); }
has() { command -v "$1" >/dev/null 2>&1; }

# link SRC DEST: point DEST at SRC, backing up whatever was there
link() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    mv "$dest" "$dest.bak.$STAMP"
    info "moved existing $dest to $dest.bak.$STAMP"
  fi
  ln -s "$src" "$dest"
  info "linked $dest -> $src"
}

is_wsl() { [ "$OS" = Linux ] && grep -qi microsoft /proc/version 2>/dev/null; }

# root, passwordless sudo, or a sudo password typed now
can_sudo() {
  [ "$(id -u)" = 0 ] && return 0
  has sudo || return 1
  sudo -n true 2>/dev/null && return 0
  [ -t 0 ] && sudo -v
}

# 1. System basics -----------------------------------------------------------------------------
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
      note "no sudo, so these system tools weren't installed: ${missing[*]} (zig and 7-Zip stand in for cc and unzip)"
      has curl && has tar || { echo "curl and tar are required to continue"; exit 1; }
    fi
  fi
fi

# 2. mise and the tools ------------------------------------------------------------------------
if has mise; then
  MISE="$(command -v mise)"
elif [ -x "$HOME/.local/bin/mise" ]; then
  MISE="$HOME/.local/bin/mise"
else
  info "installing mise"
  curl -fsSL https://mise.run | sh
  MISE="$HOME/.local/bin/mise"
fi

link "$DOTFILES/mise/config.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml"
"$MISE" trust -q "$DOTFILES/mise/config.toml" 2>/dev/null || true
info "installing tools with mise"
"$MISE" install
eval "$("$MISE" activate bash --shims)"
export PATH="$HOME/.local/bin:$PATH"

# no C compiler and no sudo to get one: use zig's, so treesitter parsers can still be built
if ! has cc; then
  info "no C compiler; installing zig to provide cc"
  "$MISE" install zig@latest
  mkdir -p "$HOME/.local/bin"
  # tree-sitter passes Rust-style targets (aarch64-unknown-linux-gnu) that zig can't parse;
  # dropping them is fine since zig builds for this machine by default
  cat > "$HOME/.local/bin/cc" <<EOF
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
exec "$("$MISE" where zig@latest)/zig" cc "\$@"
EOF
  chmod +x "$HOME/.local/bin/cc"
fi

# no unzip and no sudo to get one: Mason only runs `unzip -d DIR FILE`, so 7-Zip can stand in
if ! has unzip; then
  info "no unzip; installing 7-Zip to provide it"
  "$MISE" install 7zip@latest
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/unzip" <<EOF
#!/bin/sh
dir=.
while [ \$# -gt 1 ]; do
  case "\$1" in
    -d) dir="\$2"; shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
exec "$("$MISE" where 7zip@latest)/7zz" x -y -bso0 -bsp0 "-o\$dir" "\$@"
EOF
  chmod +x "$HOME/.local/bin/unzip"
fi

# activate mise (and ~/.local/bin) in future shells
case "$(basename "${SHELL:-bash}")" in
  zsh) rc="$HOME/.zshrc" ;;
  bash) [ "$OS" = Darwin ] && rc="$HOME/.bash_profile" || rc="$HOME/.bashrc" ;;
  *) rc="" ;;
esac
shell_name="$(basename "${SHELL:-bash}")"
if [ -n "$rc" ]; then
  if ! grep -qs "mise activate" "$rc"; then
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\neval "$(%s activate %s)"\n' "$MISE" "$shell_name" >> "$rc"
    info "added mise to $rc"
  fi
else
  note "add 'eval \"\$($MISE activate <your shell>)\"' to your shell's startup file"
fi

# 3. Configs -----------------------------------------------------------------------------------
link "$DOTFILES/nvim" "${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
link "$DOTFILES/lazygit/config.yml" "$(lazygit --print-config-dir)/config.yml"

# git: include the shared delta/pager settings; name and email stay per machine in ~/.gitconfig
if ! git config --global --type=path --get-all include.path | grep -qx "$DOTFILES/git/delta.gitconfig"; then
  git config --global --add include.path "$DOTFILES/git/delta.gitconfig"
  info "added $DOTFILES/git/delta.gitconfig to ~/.gitconfig"
fi
git config --global user.name >/dev/null || note "set your git name and email: git config --global user.name ...; git config --global user.email ..."

# 4. Font and terminal (only where there's a screen) -------------------------------------------
FONT_GLOB="JetBrainsMonoNLNerdFont-*.ttf"
install_font() {
  local dir="$1" tmp
  if compgen -G "$dir/$FONT_GLOB" >/dev/null; then
    return
  fi
  info "installing JetBrains Mono NL Nerd Font"
  tmp="$(mktemp -d)"
  curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz | tar -xJ -C "$tmp"
  mkdir -p "$dir"
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

# 5. Neovim plugins and Mason tools ------------------------------------------------------------
info "installing Neovim plugins and Mason tools (first run takes a few minutes)"
nvim --headless "+Lazy! restore" "+luafile $DOTFILES/scripts/nvim-bootstrap.lua" "+qa!" || note "Neovim setup reported errors; open nvim to finish (Lazy and Mason retry)"

info "done; open a new terminal (or run: exec \$SHELL -l)"
for n in "${NOTES[@]+"${NOTES[@]}"}"; do echo "note: $n"; done
