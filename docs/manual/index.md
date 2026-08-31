---
title: The nixarchy manual
---

# The nixarchy manual

nixarchy is [Omarchy](https://omarchy.org) vendored for NixOS. It runs Omarchy's
real tree — the same commands, menus, themes, keybindings and shell — and
replaces only what assumed Arch.

**So this manual only covers what is different.** Of Omarchy's 51 manual pages,
38 are word-for-word true here and are linked straight through to
[omarchy.org/manual](https://omarchy.org/manual/). The 13 that are not are
rewritten below, plus two that Omarchy has no reason to have.

That is the same decision the port itself makes. Forking a manual you do not
change means maintaining a copy that goes stale at every upstream release, and
Omarchy releases often. Tracking upstream is a source bump, not a re-port — for
the documentation as much as the code.

## Start here if you are new to NixOS

| | |
|---|---|
| [Getting Started](getting-started) | Two ways in: the ISO for a blank machine, the flake for NixOS you already run |
| [The NixOS philosophy, and what it changes](philosophy) | Why the Install menu *queues* instead of installing, where the line between `~/.config` and your flake falls, and why nothing installed imperatively survives |
| [Updating NixOS](updating-nixos) | `omarchy update`, what it does underneath, generations, rollback, and why a rebuild does not change the session you are sitting in |

## Every topic

| topic | |
|---|---|
| Welcome to omarchy | same as Omarchy — [read there](https://omarchy.org/manual/welcome-to-omarchy/) |
| **Getting started** | **differs on NixOS** — [read here](getting-started) |
| Coming from mac or windows | same as Omarchy — [read there](https://omarchy.org/manual/coming-from-mac-or-windows/) |
| Navigation | same as Omarchy — [read there](https://omarchy.org/manual/navigation/) |
| The top bar | same as Omarchy — [read there](https://omarchy.org/manual/the-top-bar/) |
| Themes | same as Omarchy — [read there](https://omarchy.org/manual/themes/) |
| Hotkeys | same as Omarchy — [read there](https://omarchy.org/manual/hotkeys/) |
| Unified clipboard history | same as Omarchy — [read there](https://omarchy.org/manual/unified-clipboard-history/) |
| Reminders | same as Omarchy — [read there](https://omarchy.org/manual/reminders/) |
| Notices | same as Omarchy — [read there](https://omarchy.org/manual/notices/) |
| Text extraction dictation | same as Omarchy — [read there](https://omarchy.org/manual/text-extraction-dictation/) |
| Screenshots recording | same as Omarchy — [read there](https://omarchy.org/manual/screenshots-recording/) |
| Toggles idle screensaver | same as Omarchy — [read there](https://omarchy.org/manual/toggles-idle-screensaver/) |
| Omarchy cli | same as Omarchy — [read there](https://omarchy.org/manual/omarchy-cli/) |
| Terminal | same as Omarchy — [read there](https://omarchy.org/manual/terminal/) |
| Neovim | same as Omarchy — [read there](https://omarchy.org/manual/neovim/) |
| **Ai** | **differs on NixOS** — [read here](ai) |
| **Development tools** | **differs on NixOS** — [read here](development-tools) |
| Shell tools | same as Omarchy — [read there](https://omarchy.org/manual/shell-tools/) |
| Shell functions | same as Omarchy — [read there](https://omarchy.org/manual/shell-functions/) |
| Tuis | same as Omarchy — [read there](https://omarchy.org/manual/tuis/) |
| Guis | same as Omarchy — [read there](https://omarchy.org/manual/guis/) |
| Browsers | same as Omarchy — [read there](https://omarchy.org/manual/browsers/) |
| Commercial apps services | same as Omarchy — [read there](https://omarchy.org/manual/commercial-apps-services/) |
| Web apps | same as Omarchy — [read there](https://omarchy.org/manual/web-apps/) |
| **Gaming** | **differs on NixOS** — [read here](gaming) |
| Filling out pdfs | same as Omarchy — [read there](https://omarchy.org/manual/filling-out-pdfs/) |
| Windows vm | same as Omarchy — [read there](https://omarchy.org/manual/windows-vm/) |
| **Other packages** | **differs on NixOS** — [read here](other-packages) |
| **Updates** | **differs on NixOS** — [read here](updates) |
| **Dotfiles** | **differs on NixOS** — [read here](dotfiles) |
| Shell plugins | same as Omarchy — [read there](https://omarchy.org/manual/shell-plugins/) |
| Monitors | same as Omarchy — [read there](https://omarchy.org/manual/monitors/) |
| Keyboard mouse trackpad | same as Omarchy — [read there](https://omarchy.org/manual/keyboard-mouse-trackpad/) |
| Networking | same as Omarchy — [read there](https://omarchy.org/manual/networking/) |
| System sleep | same as Omarchy — [read there](https://omarchy.org/manual/system-sleep/) |
| Hardware authentication | same as Omarchy — [read there](https://omarchy.org/manual/hardware-authentication/) |
| Fonts | same as Omarchy — [read there](https://omarchy.org/manual/fonts/) |
| Backgrounds | same as Omarchy — [read there](https://omarchy.org/manual/backgrounds/) |
| Prompt | same as Omarchy — [read there](https://omarchy.org/manual/prompt/) |
| Branding | same as Omarchy — [read there](https://omarchy.org/manual/branding/) |
| Common tweaks | same as Omarchy — [read there](https://omarchy.org/manual/common-tweaks/) |
| **Making your own theme** | **differs on NixOS** — [read here](making-your-own-theme) |
| Mac support | same as Omarchy — [read there](https://omarchy.org/manual/mac-support/) |
| **Troubleshooting** | **differs on NixOS** — [read here](troubleshooting) |
| Faq | same as Omarchy — [read there](https://omarchy.org/manual/faq/) |
| **System snapshots** | **differs on NixOS** — [read here](system-snapshots) |
| **Security** | **differs on NixOS** — [read here](security) |
| Omarchy on | same as Omarchy — [read there](https://omarchy.org/manual/omarchy-on/) |
| **Dual boot install** | **differs on NixOS** — [read here](dual-boot-install) |
| **Unattended installs** | **differs on NixOS** — [read here](unattended-installs) |

## The short version of the difference

| Omarchy on Arch | nixarchy on NixOS |
|---|---|
| `pacman -S foo` | a line in a file you own, then a rebuild |
| Install menu installs | Install menu *queues*; nothing is built until you apply |
| `omarchy update` runs a pacman upgrade | `nix flake update` then `nixos-rebuild switch` |
| Files in `/usr/share/omarchy/` | files in `$OMARCHY_PATH`, a read-only `/nix/store` path |
| snapper snapshots | NixOS generations, in the boot menu |
| AUR | no equivalent; `omarchy pkg aur add` explains instead of installing |
| `ufw allow` | `networking.firewall.allowedTCPPorts` |
