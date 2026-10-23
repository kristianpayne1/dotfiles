# dotfiles

Neovim (LazyVim), lazygit and git/delta in One Dark Pro, set up the same way on macOS, Linux
(any distro, x86 or ARM) and WSL, including boxes where you don't have sudo.

## Install

```sh
git clone https://github.com/kristianpayne1/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

Then open a new terminal. Re-running the script is safe.

Only `git` is needed to start. On a new Mac, running `git` offers to install the Xcode command
line tools, which include it.

## What the script does

1. **System basics.** On Linux it installs a C compiler, make, curl, unzip and xz with the
   system package manager (apt, dnf, yum, pacman, zypper or apk), but only when something is
   missing and sudo works. Without sudo it uses zig as the C compiler and 7-Zip for unzip
   (both installed per user by mise). On macOS it checks for the Xcode command line tools.
2. **Tools, per user, no sudo.** It installs [mise](https://mise.jdx.dev) into `~/.local/bin`,
   which installs everything in `mise/config.toml`: Neovim, lazygit, delta, ripgrep, fd, fzf,
   tree-sitter, Node LTS (with npm) and pnpm. It also adds mise to `~/.zshrc` or `~/.bashrc`.
   `mise up` updates them later.
3. **Configs.** Symlinks them into place, moving anything already there to `<name>.bak.<time>`.
4. **Font and terminal.** On macOS it installs JetBrains Mono NL Nerd Font, and Ghostty too if
   Homebrew is present. On desktop Linux it installs the font into `~/.local/share/fonts`. Over
   SSH it skips the font, because your local terminal draws the text. On WSL, install the font
   on Windows.
5. **Neovim.** Installs the plugins at the versions in `nvim/lazy-lock.json` and waits for Mason
   to install the language servers and formatters.

## What's here

| Path | Linked to |
|---|---|
| `nvim/` | `~/.config/nvim` |
| `lazygit/config.yml` | lazygit's config dir (`lazygit --print-config-dir`) |
| `mise/config.toml` | `~/.config/mise/config.toml` |
| `git/delta.gitconfig` | included from `~/.gitconfig` (name and email stay per machine) |

## Notable tweaks

- **Theme:** One Dark Pro (`onedarkpro.nvim`), with matching delta and lazygit colours.
- **Explorer:** mini.files opens on `nvim <dir>` and on `<leader>e`; file previews stretch to
  the screen edge.
- **Surround:** vim-surround keys: `ys{motion}{char}`, `ds{char}`, `cs{old}{new}`, visual `S`,
  `yss` for the line.
- **Buffers:** `Q` closes the current buffer.
- **Diffs:** delta in git and lazygit; lazygit opens side by side, `|` switches to unified.
