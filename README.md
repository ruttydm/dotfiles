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
| Omarchy / Arch | `stow`, `pipewire-zeroconf`, `ghostty`, Zen Browser | `hypr`, `pipewire`, `ghostty-linux`, `wallpaper`, `tailscale`, `omarchy` |

On Linux, pick **Office** in the volume mixer to play through the HomePod stereo pair. Do not pick **Office (2)**; that is the pair member, not the leader. The installer also clones [Pierre-Aoki Netrunner](https://github.com/Pierre-Aoki/omarchy-netrunner-theme) into `~/.config/omarchy/themes/netrunner` if it is missing (`omarchy theme install`, not Stow).

You can re-run `./install.sh` any time. It is safe if things are already installed. If a file already exists (for example Omarchy already wrote a Herdr config), the script skips that package instead of overwriting it.

## Packages

- `ghostty` — macOS Ghostty config. Follows macOS Automatic appearance (Vesper in Dark, Gruvbox Light in Light). Do not Stow this on Linux.
- `ghostty-linux` — Omarchy Ghostty config at `~/.config/ghostty/config`. Includes Omarchy theme colors so `omarchy theme set` still works. Click-to-open links work (unlike Foot).
- `herdr` — Mac Herdr config. Do not Stow this on Omarchy: that machine keeps Omarchy's local Herdr keymap.
- `hypr` — Omarchy-only Hyprland overrides: agent/Ghostty touchpad scroll, plus the X1 Carbon dock layout (HDMI Philips left, USB-C Dell primary in the middle, laptop right at scale 1.25).
- `pipewire` — Linux only. Turns on AirPlay discovery so HomePods appear as audio outputs.
- `wallpaper` — Linux only. A user systemd timer that rotates the current Omarchy theme's still wallpapers every 15 minutes. The next image is chosen by pushing CSPRNG noise through Lorenz, logistic, Ikeda, Weyl, Arnold, and Blum–Blum–Shub maps, then taking the orbit modulo the wallpaper count (skipping the current still). Preview with `omarchy-wallpaper-orbit --dry-run`. Stop with `systemctl --user disable --now omarchy-wallpaper-orbit.timer`.
- `tailscale` — Linux only. Turns on Tailscale SSH so other devices on the tailnet can `ssh` in, and opens TCP/22 on `tailscale0` only (not public Wi-Fi). `install.sh` runs `enable-tailscale-ssh` when Tailscale is already logged in. A post-boot hook re-asserts `tailscale set --ssh`. Re-run with `enable-tailscale-ssh`.
- `omarchy` — Linux only. Status bar: battery percentage next to the icon, CPU and memory just left of the battery, and a clock with seconds (`Wednesday HH:mm:ss`). Away from home the same clock adds Brussels time (`· BRU 08:20`); open it for both clocks and how many hours apart they are. The local side is the system timezone. `omarchy-timezone-auto` sets that from the public IP when a physical network comes up, so it follows travel, and ignores Tailscale and other tunnels. `install.sh` installs the NetworkManager dispatcher that runs it (needs sudo once). Middle-click the clock still opens the manual timezone list. The clock is a local clone of the built-in widget (`ruttydm.clock`) because the stock clock only updates once a minute. Herdr uses the dashboard icon so it is not the same robot as Agents. Right-click the battery still toggles the percentage. Right-click the clock still cycles formats, which drops the seconds until you cycle back.

Netrunner is not a Stow package. On Omarchy, `install.sh` runs `omarchy theme install https://github.com/Pierre-Aoki/omarchy-netrunner-theme` if `~/.config/omarchy/themes/netrunner` is missing. That clone is Omarchy-managed so theme updates stay `omarchy theme update`.

Third-party Omarchy plugins are not Stow packages. On Omarchy, `install.sh` clones [Which Key](https://github.com/huacnlee/omarchy-which-key) and [Omaherdr](https://github.com/njpatel/omaherdr) with `omarchy plugin add --enable --yes` if they are missing, turns on Which Key Super-hold integration, places Which Key after the tray, the first-party Tailscale bar widget after that, and Omaherdr after Tailscale. Plugin updates stay `omarchy plugin update`. The seconds clock is the exception: `omarchy` stows a local clone of the built-in clock, because that widget has to tick every second. If Omarchy has already written `~/.config/omarchy/shell.json`, move that file aside before Stow can link this one.

The CPU and memory figures are a local widget, `ruttydm.tailnet`. The bar label reads `/proc` every two seconds without starting any process. Click it for a dropdown of every device on the tailnet. Phones, tablets and Mullvad exit nodes are left out. Devices are grouped as servers (Tailscale tag `tag:server`), dev boxes (every box in ginger-dev's `boxes.toml`, matched by Tailscale IP) and other devices. Each online dev box shows CPU, memory, load, disk, temperature and uptime from its `https://<box>/stats.json`, which ginger-dev serves on the tailnet only. This machine reads `/proc` directly. Offline devices are greyed out with when they were last seen. The data comes from `omarchy-tailnet-stats`, which runs once when the dropdown opens and every 15 seconds while it stays open (`refreshSeconds` in `shell.json`), never while it is closed. Click a dev box to open its dashboard, or this machine to open btop. Right-click the bar label also opens btop. In the dropdown, arrow keys move, Enter opens and `r` refreshes. A new dev box shows up by itself: add it to `boxes.toml` and run `dev setup` on it. Tests: `node --test tests/` and `python3 -m unittest discover -s tests`.

The Agents bar stays the built-in `omarchy.agents` panel. Fireworks is turned off. [omarchy-spacexai-usage](https://github.com/jexmarc/omarchy-spacexai-usage) is a service plugin (no second icon) that adds SuperGrok and Cursor tabs from the logins already on the machine. The GLM Coding Plan tab comes from the Z.AI collector in [agent-usage-plus](https://github.com/viganogabriele/agent-usage-plus), installed under `~/.local/share/agent-usage-plus-collectors` and refreshed by the `omarchy-zai-usage` user timer. Only `zai` is collected, so it does not overwrite the Cursor record. The API key is not in this repo: `omarchy-zai-usage-auth` copies a working key into `~/.config/omarchy/agent-usage-plus/collectors.json` (mode 600) from the environment, `~/Projects/kosmokrator/.env`, or `~/Projects/opencompany/.env`.

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
stow --simulate --verbose=2 --target="$HOME" hypr pipewire ghostty-linux wallpaper tailscale omarchy   # Linux
stow --simulate --verbose=2 --target="$HOME" ghostty herdr                 # macOS
```

## Remove links

```sh
cd ~/Projects/dotfiles
stow --delete --target="$HOME" ghostty herdr                      # macOS
stow --delete --target="$HOME" hypr pipewire ghostty-linux wallpaper tailscale omarchy  # Omarchy / Arch
```

Deleting Stow links does not delete the tracked files in this repository.
