#!/usr/bin/env bash
# Set up this machine like the others: tools via Homebrew, configs symlinked from this repo.
# Safe to re-run; anything already in the way is moved aside to <name>.bak.<timestamp>.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d%H%M%S)"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

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

find_brew() {
  command -v brew && return
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -x "$b" ] && echo "$b" && return
  done
  return 1
}

# 1. Homebrew + packages
BREW="$(find_brew || true)"
if [ -z "$BREW" ]; then
  info "installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  BREW="$(find_brew)"
fi
if ! command -v brew >/dev/null 2>&1; then
  # brew isn't on PATH yet: use it now, and put it on PATH for future shells
  eval "$("$BREW" shellenv)"
  case "$(basename "${SHELL:-}")" in
    zsh) rc="$HOME/.zprofile" ;;
    bash) [ "$(uname)" = Darwin ] && rc="$HOME/.bash_profile" || rc="$HOME/.bashrc" ;;
    *) rc="" ;;
  esac
  if [ -n "$rc" ] && ! grep -qs "$BREW shellenv" "$rc"; then
    printf '\neval "$(%s shellenv)"\n' "$BREW" >> "$rc"
    info "added Homebrew to PATH in $rc"
  elif [ -z "$rc" ]; then
    echo "note: add 'eval \"\$($BREW shellenv)\"' to your shell's startup file"
  fi
fi
info "installing packages from Brewfile"
brew bundle --file="$DOTFILES/Brewfile"

# 2. Configs
link "$DOTFILES/nvim" "${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
link "$DOTFILES/lazygit/config.yml" "$(lazygit --print-config-dir)/config.yml"

# git: include the shared delta/pager settings; name and email stay per machine in ~/.gitconfig
if ! git config --global --type=path --get-all include.path | grep -qx "$DOTFILES/git/delta.gitconfig"; then
  git config --global --add include.path "$DOTFILES/git/delta.gitconfig"
  info "added $DOTFILES/git/delta.gitconfig to ~/.gitconfig"
fi
git config --global user.name >/dev/null || echo "note: set git user.name and user.email in ~/.gitconfig"

# 3. Neovim plugins at the versions pinned in lazy-lock.json
info "installing Neovim plugins"
nvim --headless "+Lazy! restore" +qa

if ! command -v npm >/dev/null 2>&1; then
  echo "note: npm not found; Mason needs Node for prettier, eslint and the TypeScript server"
fi
info "done"
