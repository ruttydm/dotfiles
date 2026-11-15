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
| Omarchy / Arch | `stow`, `pipewire-zeroconf`, `ghostty`, `mosh`, Zen Browser | `hypr`, `pipewire`, `ghostty-linux`, `wallpaper`, `tailscale`, `omarchy`, `ginger` |

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
- `omarchy` — Linux only. Status bar: battery percentage next to the icon, CPU and memory just left of the battery, and a clock with seconds (`Wednesday HH:mm:ss`). Away from home the same clock adds Brussels time (`· BRU 08:20`); open it for both clocks and how many hours apart they are. The local side is the system timezone. `omarchy-timezone-auto` sets that from the public IP when a physical network comes up, so it follows travel, and ignores Tailscale and other tunnels. `install.sh` installs the NetworkManager dispatcher that runs it (needs sudo once). Middle-click the clock still opens the manual timezone list. The clock is a local clone of the built-in widget (`ruttydm.clock`) because the stock clock only updates once a minute. Right-click the battery still toggles the percentage. Right-click the clock still cycles formats, which drops the seconds until you cycle back.

Netrunner is not a Stow package. On Omarchy, `install.sh` runs `omarchy theme install https://github.com/Pierre-Aoki/omarchy-netrunner-theme` if `~/.config/omarchy/themes/netrunner` is missing. That clone is Omarchy-managed so theme updates stay `omarchy theme update`.

Third-party Omarchy plugins are not Stow packages. On Omarchy, `install.sh` clones [Which Key](https://github.com/huacnlee/omarchy-which-key) with `omarchy plugin add --enable --yes` if it is missing, turns on Which Key Super-hold integration, and places Which Key after the tray and the first-party Tailscale bar widget after that. The Omaherdr bar widget is no longer installed: herdr sessions are not used on the laptop, and agent activity is on the tailnet widget instead. On a machine that still has it, `omarchy plugin disable njpatel.omaherdr` takes it off the bar. Plugin updates stay `omarchy plugin update`. The seconds clock is the exception: `omarchy` stows a local clone of the built-in clock, because that widget has to tick every second. If Omarchy has already written `~/.config/omarchy/shell.json`, move that file aside before Stow can link this one.

The CPU and memory figures are a local widget, `ruttydm.tailnet`. This machine's CPU and memory come from `/proc` every two seconds without starting any process. After them the bar shows one pill per fleet box (servers, tag `tag:server`, and every box in ginger-dev's `boxes.toml` other than this one): `rz 3󰐊 1󰏤  pi`. A pill is the box name, then its T3 agents working (󰐊) and waiting for you (󰏤, accent colour), and `✗1` for a linked pull request with failing checks. A quiet box is just its dimmed name; a busy one is bold. A box turns urgent (the theme's urgent colour) when it is offline, its disk is at 90% or more, swap at 80% or more, or memory at 95% or more, and then the reason replaces the name: `rz swap 98%`, `pi off`. This machine gets a pill only when it has agents or a problem. Hover the label for the CPU, memory, every problem and every box's agents. The numbers come from each box's `https://<box>/stats.json`, which ginger-dev serves on the tailnet only and which carries `agents: {working, waiting, done}` and `ci: {failing}` from that box's T3 (refreshed every 2 minutes by `dev refresh`). This machine reads `/proc` and ginger-dev's `~/.local/state/ginger-dev/agents.json` directly. `omarchy-tailnet-stats` gathers it all: once a minute (`pollSeconds` in `shell.json`), and every 15 seconds while the dropdown is open (`refreshSeconds`). Each poll is `tailscale status` plus one ~400-byte request per online box, run side by side with a 5-second timeout.

Click the label for a dropdown of every device on the tailnet. Phones, tablets and Mullvad exit nodes are left out. Devices are grouped as servers, dev boxes (matched by Tailscale IP) and other devices. Each online dev box shows CPU, memory and swap meters, load, disk, temperature and uptime, and a line with its agents (`3 working · 1 waiting · 2 done · 1 PR failing`); a red line under the title lists every problem, and the number that breaks a limit is red. Done means a T3 turn finished in the last hour in a thread nobody has opened since. Offline devices are greyed out with when they were last seen; an offline fleet box stays readable and red. Click a dev box to open its dashboard, a meter to open that chart, the agents line to open the box's T3 (`https://t3.<box>.afai.cc`), or this machine to open btop. Right-click the bar label also opens btop. In the dropdown, arrow keys move, Enter opens, `t` opens the selected box's T3 and `r` refreshes. A new dev box shows up by itself: add it to `boxes.toml` and run `dev setup` on it. Tests: `node --test tests/*.test.js` and `python3 -m unittest discover -s tests`.

The Agents bar stays the built-in `omarchy.agents` panel. Fireworks is turned off. [omarchy-spacexai-usage](https://github.com/jexmarc/omarchy-spacexai-usage) is a service plugin (no second icon) that adds SuperGrok and Cursor tabs from the logins already on the machine. The GLM Coding Plan tab comes from the Z.AI collector in [agent-usage-plus](https://github.com/viganogabriele/agent-usage-plus), installed under `~/.local/share/agent-usage-plus-collectors` and refreshed by the `omarchy-zai-usage` user timer. Only `zai` is collected, so it does not overwrite the Cursor record. The API key is not in this repo: `omarchy-zai-usage-auth` copies a working key into `~/.config/omarchy/agent-usage-plus/collectors.json` (mode 600) from the environment, `~/Projects/kosmokrator/.env`, or `~/Projects/opencompany/.env`.

Zen is not a Stow package. On Omarchy, `install.sh` runs `omarchy install browser zen` and `omarchy default browser zen` so new machines get the same keyboard-first browser with vertical tabs and Spaces. Chromium stays installed for Omarchy web apps.

The repository contains configuration only. Runtime state, logs, sockets, credentials, session data, and machine-local backups are not included. `install.sh` is what installs the extra Arch/Homebrew packages a new machine needs.

## Ginger dev boxes

The `ginger` package (Linux only) is for working on Ginger's dev boxes from this laptop. Agent sessions and projects live on rz and pi; this machine is the screen.

| Key or command | What it does |
|---|---|
| `Super+Alt+R`, `rz` | Terminal on rz, attached to its persistent herdr session. Uses mosh when rz has `mosh-server`, so typing echoes locally on a slow link and the session survives sleep and network changes. Without herdr it falls back to `tmux new -A -s main`, then a login shell. |
| `Super+Alt+P`, `rpi` | The same on pi, over SSH. The command is `rpi` because `pi` is the pi coding agent. |
| `rz CMD…`, `rpi CMD…` | Run one command there in a login shell, for example `rz dev ls`. |
| `Super+Alt+T`, `t3o [box]` | Open T3 on rz (or the named box) in the default browser. |
| `Super+Alt+D` | The Ginger menu, also at Omarchy menu → Ginger: terminals, T3 on each box, and every served project per box. Type to search; Enter opens the project's URL. |
| `ssh rz`, `ssh pi` | One shared connection per box for 10 minutes (`~/.ssh/config`): later `ssh`, `scp`, `git` and mosh skip the handshake. Keepalive every 30 s, compression on. Host keys come from ginger-dev's `~/.config/ginger-dev/known_hosts`. |

The project list comes from `dev ls --all --json`, run on rz over SSH because it takes about 15 seconds, plus this machine's own `dev ls --json`. `ginger-menu refresh` fetches it, caches it in `~/.cache/ginger-menu/projects.json` and writes the rows into `~/.config/omarchy/extensions/omarchy-menu.jsonc` between two `ginger-menu` marker comments. Omarchy's menu cannot run custom providers, so the rows are written into the file. Anything you add outside the markers stays. The `ginger-menu-refresh` timer refreshes every 30 minutes; the menu's last row refreshes on demand.

Pushes sent with `dev notify` from any box show up as desktop notifications. `ginger-ntfy-desktop` (a user service) follows the `rutger` topic on `https://ntfy.rz.afai.cc` and hands each message to `notify-send`: priority 5 stays until dismissed, 1 and 2 are low. Clicking a notification that carries a link opens it. The service reconnects by itself; after sleep it shows pushes from the last hour it missed. Logs: `journalctl --user -u ginger-ntfy-desktop`.

`install.sh` also sets `git config --global init.defaultBranch main`, appends `require("hypr.ginger")` to `~/.config/hypr/bindings.lua`, and links `dev` into `/usr/local/bin` (sudo), because Tailscale SSH runs remote commands with a bare `PATH` and no shell setup.

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
stow --simulate --verbose=2 --target="$HOME" hypr pipewire ghostty-linux wallpaper tailscale omarchy ginger   # Linux
stow --simulate --verbose=2 --target="$HOME" ghostty herdr                 # macOS
```

## Remove links

```sh
cd ~/Projects/dotfiles
stow --delete --target="$HOME" ghostty herdr                      # macOS
stow --delete --target="$HOME" hypr pipewire ghostty-linux wallpaper tailscale omarchy ginger  # Omarchy / Arch
```

Deleting Stow links does not delete the tracked files in this repository.
