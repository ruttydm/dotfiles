# dotfiles

Public, deliberately small dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## New machine

Clone, then run the installer. It installs missing system packages, links the right configs for this OS, and on Linux installs Zen as the default browser, sets Ghostty as the terminal, and restarts PipeWire so HomePods show up as speakers.

```sh
git clone https://github.com/ruttydm/dotfiles.git ~/Projects/dotfiles
~/Projects/dotfiles/install.sh
```

| Machine | What the script installs | What it links |
|---|---|---|
| macOS | `stow` (Homebrew) | `ghostty`, `herdr` |
| Omarchy / Arch | `stow`, `pipewire-zeroconf`, `ghostty`, Zen Browser | `hypr`, `pipewire`, `ghostty-linux`, `wallpaper` |

On Linux, pick **Office** in the volume mixer to play through the HomePod stereo pair. Do not pick **Office (2)**; that is the pair member, not the leader. The installer also clones [Pierre-Aoki Netrunner](https://github.com/Pierre-Aoki/omarchy-netrunner-theme) into `~/.config/omarchy/themes/netrunner` if it is missing (`omarchy theme install`, not Stow).

You can re-run `./install.sh` any time. It is safe if things are already installed. If a file already exists (for example Omarchy already wrote a Herdr config), the script skips that package instead of overwriting it.

## Packages

- `ghostty` — macOS Ghostty config. Follows macOS Automatic appearance (Vesper in Dark, Gruvbox Light in Light). Do not Stow this on Linux.
- `ghostty-linux` — Omarchy Ghostty config at `~/.config/ghostty/config`. Includes Omarchy theme colors so `omarchy theme set` still works. Click-to-open links work (unlike Foot).
- `herdr` — Mac Herdr config. Do not Stow this on Omarchy: that machine keeps Omarchy's local Herdr keymap.
- `hypr` — Omarchy-only Hyprland input overrides (agent/Ghostty touchpad scroll).
- `pipewire` — Linux only. Turns on AirPlay discovery so HomePods appear as audio outputs.
- `wallpaper` — Linux only. A user systemd timer that rotates the current Omarchy theme's still wallpapers every 15 minutes. The next image is chosen by pushing CSPRNG noise through Lorenz, logistic, Ikeda, Weyl, Arnold, and Blum–Blum–Shub maps, then taking the orbit modulo the wallpaper count (skipping the current still). Preview with `omarchy-wallpaper-orbit --dry-run`. Stop with `systemctl --user disable --now omarchy-wallpaper-orbit.timer`.

Netrunner is not a Stow package. On Omarchy, `install.sh` runs `omarchy theme install https://github.com/Pierre-Aoki/omarchy-netrunner-theme` if `~/.config/omarchy/themes/netrunner` is missing. That clone is Omarchy-managed so theme updates stay `omarchy theme update`.

Zen is not a Stow package. On Omarchy, `install.sh` runs `omarchy install browser zen` and `omarchy default browser zen` so new machines get the same keyboard-first browser with vertical tabs and Spaces. Chromium stays installed for Omarchy web apps.

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
stow --simulate --verbose=2 --target="$HOME" hypr pipewire ghostty-linux wallpaper   # Linux
stow --simulate --verbose=2 --target="$HOME" ghostty herdr                 # macOS
```

## Remove links

```sh
cd ~/Projects/dotfiles
stow --delete --target="$HOME" ghostty herdr                      # macOS
stow --delete --target="$HOME" hypr pipewire ghostty-linux wallpaper  # Omarchy / Arch
```

Deleting Stow links does not delete the tracked files in this repository.
