# dotfiles

Public, deliberately small dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Packages

- `ghostty` manages the macOS Ghostty config at `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`.
- `herdr` manages `~/.config/herdr/config.toml`.

The repository contains configuration only. Runtime state, logs, sockets, credentials, session data, and machine-local backups are not included.

## Install

Install Stow on macOS:

```sh
brew install stow
```

Clone and link the packages:

```sh
git clone https://github.com/ruttydm/dotfiles.git ~/Projects/dotfiles
cd ~/Projects/dotfiles
stow --target="$HOME" ghostty herdr
```

The repository uses `--no-folding` in `.stowrc`, so Stow creates file-level links instead of replacing whole configuration directories with links. This leaves application-owned runtime files alongside the managed configuration safely.

## Update

Edit files in this repository, then reload the relevant application. Ghostty reloads its configuration with `Cmd+Shift+,`; Herdr reloads with `Ctrl+B`, then `Shift+R`.

## Remove links

```sh
stow --delete --target="$HOME" ghostty herdr
```
