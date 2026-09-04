# dotfiles

Public, deliberately small dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Packages

- `ghostty` manages the macOS Ghostty config at `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`.
- `herdr` manages the cross-platform config at `~/.config/herdr/config.toml`.
- `pipewire` enables AirPlay/RAOP discovery on Linux at `~/.config/pipewire/pipewire.conf.d/50-raop.conf`, so HomePods and other AirPlay speakers show up as audio outputs.

The repository contains configuration only. Runtime state, logs, sockets, credentials, session data, and machine-local backups are not included. Arch packages required by a Stow package are listed next to the install steps, not installed by Stow itself.

## How Stow works

Each top-level directory is a package whose contents mirror paths below your home directory. Stow creates symlinks from those home-directory paths back into this repository. For example:

```text
~/Projects/dotfiles/herdr/.config/herdr/config.toml
                         ↓ stow herdr
~/.config/herdr/config.toml
```

The live file and the repository file are therefore the same configuration. You can edit either path, review the change with Git, commit it, and pull it onto another machine.

The repository uses `--no-folding` in `.stowrc`, so Stow creates file-level links instead of replacing whole configuration directories with links. This leaves application-owned runtime files alongside the managed configuration safely.

## Install on macOS

Install Stow:

```sh
brew install stow
```

Clone and link the packages:

```sh
git clone https://github.com/ruttydm/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
stow --target="$HOME" ghostty herdr
```

The Ghostty config follows macOS Automatic appearance: Vesper in Dark mode and warm, outdoor-readable Gruvbox Light in Light mode. Herdr follows the host terminal's reported light/dark appearance and uses the matching built-in theme.

## Install on Omarchy / Arch

Install GNU Stow and the AirPlay sender module with `omarchy pkg add stow pipewire-zeroconf` on Omarchy (or `sudo pacman -S stow pipewire-zeroconf` on plain Arch), clone the same repository, then link the portable Linux packages:

```sh
git clone https://github.com/ruttydm/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
stow --target="$HOME" herdr pipewire
systemctl --user restart wireplumber pipewire pipewire-pulse
```

`pipewire-zeroconf` is the Arch package that actually contains PipeWire's RAOP discover module. Stow only links the config that loads it. After restarting PipeWire, HomePods on the LAN appear as sinks in the volume mixer; pick the stereo-pair leader (here, **Office**) rather than the member speaker.

Do not Stow the `ghostty` package on Linux: it targets Ghostty's macOS Application Support path. On Omarchy, keep `~/.config/ghostty/config` under Omarchy's control because Omarchy generates terminal colors from the selected desktop theme. The shared Herdr configuration still works on Linux; automatic switching occurs when the host terminal reports a light/dark appearance change.

Before the first Stow on an existing machine, preview it:

```sh
stow --simulate --verbose=2 --target="$HOME" herdr pipewire
```

Stow refuses conflicting real files rather than silently overwriting them. Review and merge or back up an existing config before retrying; avoid `stow --adopt` unless you intentionally want the machine's current file copied into the repository.

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

Then sync another machine:

```sh
cd ~/Projects/dotfiles
git pull --ff-only
stow --restow --target="$HOME" herdr pipewire   # omit pipewire on macOS
```

Editing a file usually does not require re-Stowing because the symlink already points into the repository. `--restow` is useful after files are added, removed, or moved. Ghostty reloads its configuration on macOS with `Cmd+Shift+,`; Herdr reloads with `Ctrl+B`, then `Shift+R`.

## Remove links

macOS:

```sh
stow --delete --target="$HOME" ghostty herdr
```

Omarchy / Arch:

```sh
stow --delete --target="$HOME" herdr pipewire
```

Deleting Stow links does not delete the tracked files in this repository.
