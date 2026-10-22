#!/usr/bin/env bash
# New-machine setup. From a clone of this repo:
#   ./install.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"

os="$(uname -s)"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

stow_packages() {
  local pkg status=0
  for pkg in "$@"; do
    echo "Linking $pkg"
    if stow --restow --target="$HOME" "$pkg"; then
      continue
    fi
    echo "Could not link $pkg: an existing file is in the way. Move or merge it, then re-run." >&2
    status=1
  done
  return "$status"
}

install_linux_packages() {
  local pkgs=(stow pipewire-zeroconf ghostty) missing=() pkg
  for pkg in "${pkgs[@]}"; do
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done
  if ((${#missing[@]} == 0)); then
    echo "Arch packages already installed: ${pkgs[*]}"
    return
  fi
  echo "Installing Arch packages: ${missing[*]}"
  if need_cmd omarchy; then
    omarchy pkg add "${missing[@]}"
  else
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  fi
}

# Third-party Omarchy plugins are git clones under ~/.config/omarchy/plugins,
# same as extra themes. Do not Stow them.
ensure_omarchy_git_plugin() {
  local id="$1" url="$2"
  if [[ ! -d "$HOME/.config/omarchy/plugins/$id" ]]; then
    echo "Installing Omarchy plugin $id"
    omarchy plugin add "$url" --enable --yes
  fi
}

ensure_which_key_integration() {
  local dir="$HOME/.config/omarchy/plugins/huacnlee.which-key"
  local status
  [[ -x "$dir/scripts/integration-status" && -x "$dir/scripts/enable-integration" ]] || return 0
  status="$("$dir/scripts/integration-status" || true)"
  if [[ "$status" != "enabled" ]]; then
    echo "Enabling which-key Super-hold integration"
    "$dir/scripts/enable-integration"
  fi
}

install_omarchy_extra_plugins() {
  ensure_omarchy_git_plugin huacnlee.which-key https://github.com/huacnlee/omarchy-which-key.git
  omarchy plugin enable huacnlee.which-key --section right --after omarchy.tray
  ensure_which_key_integration
  omarchy plugin enable omarchy.tailscale --section right --after huacnlee.which-key
  ensure_omarchy_git_plugin njpatel.omaherdr https://github.com/njpatel/omaherdr.git
  omarchy plugin enable njpatel.omaherdr --section right --after omarchy.tailscale
  # Service plugin: Grok and Cursor tabs in the stock Agents panel. shell.json
  # lists it, so do not --enable here (that rewrites the whole bar config).
  if [[ ! -d "$HOME/.config/omarchy/plugins/omarchy-spacexai-usage" ]]; then
    echo "Installing Grok and Cursor usage collector"
    omarchy plugin add https://github.com/jexmarc/omarchy-spacexai-usage.git --yes
  fi
  ensure_glm_usage_collector
}

# Writes zai.json only. The stock updater never sees collectors outside
# /usr/share/omarchy/bin, and the full Agent Usage Plus runner would also
# overwrite the Cursor record owned by omarchy-spacexai-usage.
ensure_glm_usage_collector() {
  local src="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/agent-usage-plus"
  local bin="$HOME/.local/share/agent-usage-plus-collectors/bin/agent-usage-plus-collectors"
  if [[ ! -x "$bin" ]]; then
    echo "Installing GLM Coding Plan usage collector"
    mkdir -p "$(dirname "$src")"
    if [[ ! -d "$src/.git" ]]; then
      git clone --depth 1 https://github.com/viganogabriele/agent-usage-plus.git "$src"
    fi
    "$src/collectors/install.sh"
  fi
  if [[ -x "$HOME/.local/bin/omarchy-zai-usage-auth" ]]; then
    "$HOME/.local/bin/omarchy-zai-usage-auth" || true
  fi
  if [[ -f "$HOME/.config/systemd/user/omarchy-zai-usage.timer" ]]; then
    systemctl --user daemon-reload
    systemctl --user enable --now omarchy-zai-usage.timer
  fi
  if [[ -x "$bin" ]]; then
    "$bin" update zai || echo "GLM quota refresh failed; the timer will retry." >&2
  fi
}

# The clock follows the system zone. This dispatcher re-points that zone when
# a physical network comes up, so travel does not leave the bar on the last city.
install_timezone_autoupdate() {
  local bin="$HOME/.local/bin/omarchy-timezone-auto"
  local dest=/etc/NetworkManager/dispatcher.d/99-omarchy-timezone
  local tmp
  [[ -x "$bin" ]] || return 0
  tmp="$(mktemp)"
  {
    echo '#!/bin/bash'
    printf 'export OMARCHY_TZ_USER=%q\n' "$USER"
    printf 'exec %q "$@"\n' "$bin"
  } >"$tmp"
  if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 0
  fi
  echo "Installing NetworkManager timezone dispatcher"
  if sudo install -m 755 "$tmp" "$dest"; then
    rm -f "$tmp"
  else
    rm -f "$tmp"
    echo "Could not install $dest. Re-run ./install.sh once sudo is available." >&2
  fi
}

stow_status=0

case "$os" in
  Darwin)
    echo "Setting up macOS packages: ghostty herdr"
    if ! need_cmd stow; then
      if ! need_cmd brew; then
        echo "Homebrew is required to install stow. Install it from https://brew.sh then re-run." >&2
        exit 1
      fi
      brew install stow
    fi
    stow_packages ghostty herdr || stow_status=$?
    ;;
  Linux)
    if ! need_cmd pacman; then
      echo "This install script only knows Arch/Omarchy on Linux (needs pacman)." >&2
      exit 1
    fi
    echo "Setting up Linux packages: hypr pipewire ghostty-linux wallpaper tailscale omarchy"
    install_linux_packages
    stow_packages hypr pipewire ghostty-linux wallpaper tailscale omarchy || stow_status=$?
    install_timezone_autoupdate
    echo "Restarting PipeWire so AirPlay speakers (HomePods) show up as outputs"
    systemctl --user restart wireplumber pipewire pipewire-pulse
    if [[ -f "$HOME/.config/systemd/user/omarchy-wallpaper-orbit.timer" ]]; then
      echo "Enabling the Omarchy wallpaper orbit timer"
      systemctl --user daemon-reload
      systemctl --user enable --now omarchy-wallpaper-orbit.timer
    fi
    if need_cmd tailscale && tailscale status >/dev/null 2>&1; then
      echo "Enabling Tailscale SSH so other tailnet devices can log in"
      if ! enable-tailscale-ssh; then
        echo "Could not finish Tailscale SSH (needs sudo for the firewall and tailscaled restart). Re-run: enable-tailscale-ssh" >&2
      fi
    fi
    if need_cmd omarchy; then
      omarchy default terminal ghostty
      echo "Installing Zen Browser and making it the default"
      omarchy install browser zen
      omarchy default browser zen
      if [[ ! -d "$HOME/.config/omarchy/themes/netrunner" ]]; then
        echo "Installing Pierre-Aoki Netrunner theme"
        omarchy theme install https://github.com/Pierre-Aoki/omarchy-netrunner-theme
      fi
      echo "Installing extra Omarchy plugins"
      install_omarchy_extra_plugins
    fi
    ;;
  *)
    echo "Unsupported OS: $os" >&2
    exit 1
    ;;
esac

if ((stow_status == 0)); then
  echo "Done. Configs in $root are now linked into $HOME."
else
  echo "Finished with some packages unlinked. Re-run after resolving the conflicts above." >&2
fi
if [[ "$os" == Linux ]]; then
  echo "To play through the Office HomePods, pick 'Office' in the volume mixer (the stereo-pair leader, not 'Office (2)')."
fi
exit "$stow_status"
