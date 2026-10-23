# dotfiles

Neovim (LazyVim), lazygit and git/delta, all in One Dark Pro.

## Install

```sh
git clone https://github.com/kristianpayne1/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

The script installs Homebrew if missing, the packages in `Brewfile`, symlinks the configs into
place (backing up anything already there) and installs Neovim plugins at the versions in
`nvim/lazy-lock.json`. Re-running it is safe. Node (for Mason's prettier/eslint/TypeScript
tools) is not installed by it.

## What's here

| Path | Linked to |
|---|---|
| `nvim/` | `~/.config/nvim` |
| `lazygit/config.yml` | lazygit's config dir (`lazygit --print-config-dir`) |
| `git/delta.gitconfig` | included from `~/.gitconfig` (name/email stay per machine) |

## Notable tweaks

- **Theme:** One Dark Pro (`onedarkpro.nvim`), with matching delta and lazygit colours.
- **Explorer:** mini.files opens on `nvim <dir>` and on `<leader>e`; file previews stretch to
  the screen edge.
- **Surround:** vim-surround keys: `ys{motion}{char}`, `ds{char}`, `cs{old}{new}`, visual `S`,
  `yss` for the line.
- **Buffers:** `Q` closes the current buffer.
- **Diffs:** delta in git and lazygit; lazygit opens side by side, `|` switches to unified.
