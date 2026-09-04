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
    echo "Setting up Linux packages: hypr pipewire ghostty-linux"
    install_linux_packages
    stow_packages hypr pipewire ghostty-linux || stow_status=$?
    echo "Restarting PipeWire so AirPlay speakers (HomePods) show up as outputs"
    systemctl --user restart wireplumber pipewire pipewire-pulse
    if need_cmd omarchy; then
      omarchy default terminal ghostty
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
