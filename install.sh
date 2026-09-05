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
    echo "Setting up Linux packages: hypr pipewire ghostty-linux wallpaper tailscale"
    install_linux_packages
    stow_packages hypr pipewire ghostty-linux wallpaper tailscale || stow_status=$?
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
