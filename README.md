# dotfiles

Public, deliberately small dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## New machine

Clone, then run the installer. It installs missing system packages, links the right configs for this OS, and on Linux restarts PipeWire so HomePods show up as speakers.

```sh
git clone https://github.com/ruttydm/dotfiles.git ~/Projects/dotfiles
~/Projects/dotfiles/install.sh
```

| Machine | What the script installs | What it links |
|---|---|---|
| macOS | `stow` (Homebrew) | `ghostty`, `herdr` |
| Omarchy / Arch | `stow`, `pipewire-zeroconf` | `herdr`, `pipewire` |

On Linux, pick **Office** in the volume mixer to play through the HomePod stereo pair. Do not pick **Office (2)**; that is the pair member, not the leader.

You can re-run `./install.sh` any time. It is safe if things are already installed. If a file already exists (for example Omarchy already wrote a Herdr config), the script skips that package instead of overwriting it.

## Packages

- `ghostty` — macOS Ghostty config. Follows macOS Automatic appearance (Vesper in Dark, Gruvbox Light in Light). Do not Stow this on Linux: Omarchy owns `~/.config/ghostty/config` so it can theme the terminal.
- `herdr` — shared Herdr config. Follows the terminal's light/dark appearance.
- `pipewire` — Linux only. Turns on AirPlay discovery so HomePods appear as audio outputs.

The repository contains configuration only. Runtime state, logs, sockets, credentials, session data, and machine-local backups are not included. `install.sh` is what installs the extra Arch/Homebrew packages a new machine needs.

## Daily workflow

On the machine where you make a change:

```sh
cd ~/Projects/dotfiles
git pull --ff-only
$EDITOR herdr/.config/herdr/config.toml
herdr config check
git diff
git add herdr/.config/herdr/config.toml
git commit -m "chore: update herdr config"
git push
```

Then on another machine:

```sh
cd ~/Projects/dotfiles
git pull --ff-only
./install.sh
```

Editing a file that is already linked usually does not need a re-run, because the live path is a symlink into this repo. Re-run `install.sh` after files are added, removed, or moved, and after cloning onto a new machine. Ghostty reloads on macOS with `Cmd+Shift+,`; Herdr reloads with `Ctrl+B`, then `Shift+R`.

## How Stow works

Each top-level directory is a package whose contents mirror paths below your home directory. Stow creates symlinks from those home-directory paths back into this repository:

```text
~/Projects/dotfiles/herdr/.config/herdr/config.toml
                         ↓ stow herdr
~/.config/herdr/config.toml
```

The live file and the repository file are therefore the same configuration.

The repository uses `--no-folding` in `.stowrc`, so Stow creates file-level links instead of replacing whole configuration directories. That leaves application-owned runtime files alongside the managed configuration.

Stow refuses conflicting real files rather than silently overwriting them. If `install.sh` stops on a conflict, review or back up the existing file, then re-run. Avoid `stow --adopt` unless you intentionally want the machine's current file copied into the repository.

Preview without changing anything:

```sh
cd ~/Projects/dotfiles
stow --simulate --verbose=2 --target="$HOME" herdr pipewire   # Linux
stow --simulate --verbose=2 --target="$HOME" ghostty herdr    # macOS
```

## Remove links

```sh
cd ~/Projects/dotfiles
stow --delete --target="$HOME" ghostty herdr     # macOS
stow --delete --target="$HOME" herdr pipewire    # Omarchy / Arch
```

Deleting Stow links does not delete the tracked files in this repository.
