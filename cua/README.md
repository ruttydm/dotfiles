# Cua on Omarchy

Last verified: 2026-11-16 on the ThinkPad, Hyprland 0.56.2-4, Omarchy 4.5.0 (stable repository).

This Stow package wires Cua into the desktop: the user service, the Hyprland Lua include, the load
guard, the MCP wrapper and the setup script. **The driver and the Hyprland plugin themselves are
Omarchy's packages**, not vendor installs or local builds. Account settings are merged locally;
credentials, screenshots, browser state and binaries are never stored here.

```sh
stow --target="$HOME" cua
cua-setup          # pacman packages (no -Sy), skills, MCP entries, Hyprland include, user service
# log out and back in: the plugin loads at Hyprland start
```

## Packages

| Package (repository `omarchy`) | Provides |
| --- | --- |
| `cua-driver-bin` | `/usr/bin/cua-driver` (tree in `/usr/lib/cua-driver`). Omarchy holds upstream updates and bumps them by hand; the binary's own updater is rewritten to refuse and name pacman, so `cua-driver update --apply` cannot install a second copy around pacman. |
| `cua-hyprland-plugin` | `/usr/lib/cua/hyprland/cua-hyprland-plugin.so`, built by Omarchy from Cua's published profile kit (with Omarchy's downstream patch: keyboard remaps, Num Lock, input-method popup guard) and pinned to the exact `hyprland` build and ABI libraries in the same repository. Provenance files in `/usr/share/cua-hyprland-plugin/`. |

**Updates come with the system update** (`omarchy-update`), never from `cua-driver update` or a local
build. `cua-setup` installs from the synced package database only (`pacman -S --needed`, no `-Sy`), so it
never makes a partial upgrade. After an update that changes either package: `cua-driver skills install`
(the skill pack follows the driver), `systemctl --user restart cua-driver`, then log out and back in
for a new plugin. Agent sessions must reconnect to see MCP changes.

## What this package manages

| File | Role |
| --- | --- |
| `.config/systemd/user/cua-driver.service` | `/usr/bin/cua-driver serve` in the graphical session, native Wayland on (`CUA_DRIVER_RS_ENABLE_WAYLAND=1`), normal Cua permission mode. No TCP listener, no browser-debugging port. |
| `.local/bin/cua-mcp` | What Codex, Claude and Grok run for MCP: starts the service and connects to its socket. One controller at a time: the agents share one desktop. |
| `.config/hypr/cua.lua` | Included from `hyprland.lua`; loads the plugin only when `cua-hyprland-check` passes. |
| `.local/bin/cua-hyprland-check` | Load guard: the plugin file exists and every version the package pins is installed now (`pacman -T`). A half-finished update therefore never loads a plugin built against other headers. |
| `.local/bin/cua-setup` | Installs both packages if missing, refuses while a vendor-installed driver shadows `/usr/bin` in `~/.local/bin`, installs the skill pack, links the Grok skill, merges only the Cua MCP entry into Codex, Claude and Grok, adds the optional include to `hyprland.lua`, enables the service. |
| `.local/bin/cua-build-hyprland` | Retired stub (exits 0) for older `install.sh` copies; the plugin is no longer built here. |

Never hot-unload or replace a loaded plugin in a live desktop: log out (or exit to a TTY) and start a
fresh graphical session. To disable: remove the Cua include from `hyprland.lua`, log out, then
`systemctl --user disable --now cua-driver` and remove the Cua MCP entries if needed.

## Checks

```sh
cua-driver --version                 # the packaged version
command -v cua-driver                # /usr/bin/cua-driver; anything in ~/.local/bin shadows it
cua-driver doctor
systemctl --user status cua-driver
cua-hyprland-check && echo ok
hyprctl plugin list                  # cua-hyprland-plugin listed after a fresh login
hyprctl configerrors
cua-driver call list_windows '{}'
```

Use the installed `cua-driver` skill: choose the exact PID and window, observe, act, verify. Repeat a
named `session` on related CLI calls and end only that session. A result of `unverifiable` needs fresh
UI verification; never blindly replay partial input. Cua is experimental on Hyprland; these checks do
not certify every application.

## History

- **2026-10-10:** first setup with the vendor installer (driver 0.34.1 in `~/.cua-driver`) and a local
  plugin build (0.32.0, Cua's `omarchy-stable-20260910` kit plus Omarchy's patch) for Hyprland
  0.56.2-2. Kit checks, 20/20 CTest and 5/5 downstream tests passed; typing into a Foot window was
  verified by screenshot.
- **2026-10-22:** the system update brought Hyprland 0.56.2-4. The old guard correctly refused the local
  build, so the plugin stopped loading.
- **2026-11-16:** moved to Omarchy's packages (`cua-driver-bin` 0.33.4-2, `cua-hyprland-plugin`
  0.33.2-3, both matching Hyprland 0.56.2-4 and its ABI libraries exactly). The vendor driver tree,
  its skill pack and the local plugin build were moved aside, not deleted:
  `~/.cua-driver/packages.upstream-0.34.1.retired`, `~/.cua-driver/skills.upstream-0.34.1.retired`,
  `~/.local/lib/cua-hyprland.local-build.retired`; remove them once the packaged setup has been used
  for a while. `cua-driver skills install` from the packaged driver re-linked the skill for the
  installed agents.

## Known limitation: Zen

At the first setup, exact-window foreground clicks and shortcuts in Zen returned
`foreground_primary_binding` / `primary_target_busy`: the plugin requires one unambiguous primary
Wayland seat binding, and that Zen instance did not satisfy it. Accessibility actions (pressing
buttons, reading the tree) worked. Do not substitute global keystroke tools to conceal this refusal.

### Zen follow-up (2026-10-10)

Current upstream `input_experiment.cpp` still requires a unique primary seat
binding. Mozilla bug [2075886](https://bugzilla.mozilla.org/show_bug.cgi?id=2075886)
reports a related, distinct Zen/Firefox tab-drag problem with Cua's extra seats;
it does not by itself prove the cause of this foreground-input refusal.
A disposable Zen profile under XWayland, paired with a separate X11 Cua service,
avoided the original refusal and advanced one onboarding screen. Later actions
were not visibly verified, so XWayland is not established as a reliable workaround.
The temporary browser and test service were stopped; the user's profile was
not changed. A native fix needs verified primary-seat/resource selection for
Gecko, preserving exact-window targeting and input interruption checks.

Sources: [Omarchy packaging](https://github.com/omacom/omarchy-pkgs/tree/master/pkgbuilds) (`cua-driver-bin`,
`cua-hyprland-plugin`), [Cua Hyprland source](https://github.com/trycua/cua/tree/main/libs/cua-driver/hyprland-plugin).
