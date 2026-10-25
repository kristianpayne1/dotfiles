# dotfiles

Neovim (LazyVim), lazygit and git/delta in One Dark Pro, set up the same way on macOS, Linux
(any distro, x86 or ARM) and WSL, including boxes where you don't have sudo. Every download is
pinned to an exact version and checked against a recorded checksum.

## Install

```sh
git clone https://github.com/kristianpayne1/dotfiles.git ~/dotfiles | ~/dotfiles/install.sh            # asks which profile; or pass --editor / --full
```

Then open a new terminal. Re-running the script is safe and remembers the profile.

### Profiles

| | `--editor` | `--full` |
|---|---|---|
| Neovim + LazyVim, its configs, lazygit, delta, ripgrep, fd, fzf | ✓ | ✓ |
| Language servers, formatters, linters, Rust debugger | ✓ | ✓ |
| Node, pnpm, Python, uv, Rust toolchain on your PATH | – | ✓ |
| Touches the machine's existing Node/Python/Rust | never | only where you say so |

- **`--editor`** is for machines you don't own, like a work box. The language servers run on
  a Node that mise installs just for them; `node`, `python3` and `cargo` stay whatever the
  machine already had.
- **`--full`** is for your own machines. For each runtime the machine already has, it asks
  whether to keep it (the default) or use mise's. `--use-mise-runtimes` answers "use mise's"
  to all.

Choices are saved in `~/.config/dotfiles/profile.sh`; run with `--editor` or `--full` again to
change them.

Only `git` is needed to start. On a new Mac, running `git` offers to install the Xcode command
line tools, which include it.

Options:

- `--no-sudo`: for shared boxes. Never installs system packages, even when sudo works; zig and
  7-Zip stand in for a missing C compiler and unzip.
- `--ca-cert FILE`: for networks whose proxy inspects HTTPS. Trusts that extra CA certificate
  for this run and future shells. Behind a plain proxy, just have `HTTPS_PROXY` set.

## What the script does

1. **System basics.** On Linux it installs a C compiler, make, curl, unzip and xz with the
   system package manager (apt, dnf, yum, pacman, zypper or apk), but only when something is
   missing and sudo works. On macOS it checks for the Xcode command line tools.
2. **mise.** Downloads [mise](https://mise.jdx.dev) at a pinned version into `~/.local/bin` and
   checks it against its published SHA-256.
3. **Tools, per user, no sudo.** mise installs everything in `mise-global/config.toml` (and,
   for `--full`, `config.full.toml`). The lockfiles record each download's URL and checksum for
   every platform, and mise refuses anything that doesn't match. Commands are exposed through
   `~/.local/share/dotfiles/bin`: every editor tool, plus the runtimes mise owns.
4. **Shell startup.** Adds the same marked block to `~/.zshrc`/`~/.bashrc` and
   `~/.zprofile`/`~/.profile` (so GUI apps, cron and scripts see it too): that `bin` folder
   first on PATH, and your saved settings.
5. **Configs.** Symlinks them into place. Anything already there is moved to
   `~/.local/state/dotfiles/backups/<timestamp>/`.
6. **Font and terminal.** On macOS: JetBrains Mono NL Nerd Font (checksum-verified), and Ghostty
   if Homebrew is present. On desktop Linux the font goes in `~/.local/share/fonts`. Skipped over
   SSH (your local terminal draws the text) and on WSL (install it on Windows).
7. **Neovim.** Installs the plugins at the commits in `nvim/lazy-lock.json` and builds the
   treesitter parsers.

## Secrets and machine-only settings

Nothing secret belongs in this repo (it's public). Put machine-only settings, such as proxy
variables or tokens, in `~/.config/dotfiles/local.sh`: the shell startup blocks load it, and it
never lives in the repo. Your git name and email stay in `~/.gitconfig` for the same reason.

As a backstop, [gitleaks](https://github.com/gitleaks/gitleaks) checks every commit: a
pre-commit hook (switched on by `install.sh`) refuses commits containing anything that looks
like a key or token, and CI scans the whole history.

## Changing things

Configs are symlinks into `~/dotfiles`, so edits land in the repo; commit and push them. Then:

- **Tool versions:** change `mise-global/config*.toml` (or `mise upgrade --bump`), then run
  `scripts/lock.sh` and commit the lockfiles with it.
- **Plugins:** after `:Lazy update` or adding a plugin, commit `nvim/lazy-lock.json`.
- **A new config file:** move it into the repo and add a `link` line to `install.sh`.
- **On other machines:** `git pull`, then `install.sh` (or just `mise install`).

You rarely need to bump things by hand: every Monday the **Update pins** workflow bumps every
version to the newest release that's at least a week old (Node to the newest LTS), refreshes the
lockfiles and plugins, and opens a pull request. CI installs that branch on fresh Linux and
macOS, and you merge it if it's green.

## Testing

- `scripts/test-linux.sh full` / `scripts/test-linux.sh editor`: install on a fresh Ubuntu box in
  Docker, verify, re-run, and check the repo wasn't modified. The editor test runs without sudo
  on a box that already has Node and Python, and checks they're untouched.
- `scripts/verify.sh`: check an installed machine (tools, theme, parsers, language servers
  attaching, formatters, debugger).
- CI runs shellcheck, a gitleaks scan, both Linux profiles, and macOS (full profile on a runner
  that already has Node, Python and Rust) on every push to `main`, every pull
  request and weekly.

## What's here

| Path | What it is |
|---|---|
| `nvim/` | Neovim config, linked to `~/.config/nvim` |
| `mise-global/` | tool versions and lockfiles (`config.toml` editor, `config.full.toml` runtimes), linked to `~/.config/mise` |
| `mise-fallback/` | zig and 7-Zip, only for boxes without a compiler or unzip and no sudo |
| `lazygit/config.yml` | linked into lazygit's config dir |
| `git/delta.gitconfig` | included from `~/.gitconfig` (name and email stay per machine) |
| `scripts/` | pins, lockfile, test and verify scripts |
| `CLAUDE.md` | how it works and the rules for changing it, for AI agents and future you |

## Notable tweaks

- **Theme:** One Dark Pro (`onedarkpro.nvim`), with matching delta and lazygit colours.
- **Explorer:** mini.files opens on `nvim <dir>` and on `<leader>e`; file previews stretch to
  the screen edge.
- **Surround:** vim-surround keys: `ys{motion}{char}`, `ds{char}`, `cs{old}{new}`, visual `S`,
  `yss` for the line.
- **Buffers:** `Q` closes the current buffer.
- **Diffs:** delta in git and lazygit; lazygit opens side by side, `|` switches to unified.
- **Languages:** TypeScript/React (+ Tailwind), Rust, Python (basedpyright + ruff), Markdown,
  JSON, YAML, TOML and Lua, with tools from mise instead of Mason so they're pinned and locked
  like everything else.
