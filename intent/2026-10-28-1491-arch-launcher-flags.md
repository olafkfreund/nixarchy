---
status: approved
issue: 1491
author: x
---

# Intent: the browser flags Omarchy seeds reach the browser

## Problem

Omarchy configures Chromium through `~/.config/chromium-flags.conf`, and
nixarchy seeds that file verbatim (`modules/home.nix:1172`). On Arch,
`/usr/bin/chromium` reads it. nixpkgs' wrapper reads no flags file, so none
of its six flags reach Chromium:

- `--load-extension=` for copy-url, yt-dlp and whatsapp-slim, so
  `chrome://extensions` is empty, Alt+Shift+L does nothing and the yt-dlp
  button is missing;
- `--password-store=gnome-libsecret`, and the Wayland and feature flags.

The extension paths are also wrong where they stand: `/usr/share/omarchy/...`
does not exist on NixOS.

Two more gaps sit beside it:

- **The native messaging hosts are never registered.** Upstream runs
  `omarchy-install-chromium-copy-url` and `-ytdlp` from
  `install/user/chromium.sh`, and nothing in nixarchy does. Run by hand, they
  write `$OMARCHY_PATH/bin/...` into `~/.config/chromium/NativeMessagingHosts/*.json`.
  That is a store path, and garbage collection removes it after the next
  Omarchy update.
- **Upstream's managed policy** `default/chromium/policies/omarchy.json`
  (`DefaultBrowserSettingEnabled: false`) is not installed.

#1493 reports the same class of bug for Obsidian: `config/obsidian/user-flags.conf`
is read by Arch's launcher and not by nixpkgs' wrapper. Its other half, the
Xournal++ `/usr/share` template path, no longer applies: Omarchy 4.5.0-rc2,
which `main` and `release` pin, ships no `config/xournalpp/`.

Reported, with a working workaround, by eyadsibai on v4.0.6-1.

## Proposed outcome

On a fresh install, and on an existing home after a switch:

- Chromium starts with Omarchy's three extensions loaded and uses
  gnome-libsecret. Alt+Shift+L copies the URL, and the yt-dlp button is
  present.
- Both native hosts are registered with a path that survives garbage
  collection, and they still work after an Omarchy update.
- Omarchy's Chromium policy is in force.
- Obsidian gets the flags from its `user-flags.conf`.
- A check fails if any of these regresses.

## Affected users and systems

Every nixarchy desktop that uses the Chromium nixarchy installs, which is
Omarchy's default browser. Obsidian users through `apps.obsidian`. The
Omarchy package (`pkgs/omarchy/default.nix`), the home seeding
(`modules/home.nix`), the NixOS module (`modules/nixos.nix`), and the
session check.

## Constraints

- Mode A: someone importing the module into their own config, with their
  own `programs.chromium` settings, keeps them. Coexistence (§14) needs a
  fixture if this touches `programs.chromium` or `/etc/chromium/policies`,
  where nixarchy already writes `color.json`.
- The user's own edits to `~/.config/chromium-flags.conf` keep working. The
  seed never overwrites it (`cp --update=none`), so existing homes hold the
  `/usr` paths today.
- No `/usr` paths in what ships. The session check's `/usr` scan must stay
  green without a new exception.
- Brave reads `~/.config/brave-flags.conf` through upstream's
  `omarchy-install-browser`. That is out of scope unless it falls out for
  free.

## Open questions

1. **Read the user's flags file at launch, or bake upstream's flags into
   the package?** A launcher that reads `~/.config/chromium-flags.conf` the
   way Arch's does keeps the file editable and handles existing homes. That
   needs `/usr/share/omarchy` mapped to a store-independent path at read
   time. Baking the flags in (`chromium.override { commandLineArgs }`) is
   simpler, but it ignores the user's file. My lean: the launcher.
2. **Obsidian:** nixpkgs' wrapper already adds `--enable-wayland-ime`, so
   the only flag missing is upstream's `-disable-gpu`. Do the same launcher
   treatment, or leave Obsidian alone and close #1493 with a note?

## Decisions (owner, 2026-10-28)

1. **A launcher** that reads `~/.config/chromium-flags.conf` at every start,
   the way Arch's does.
2. **Obsidian is left alone.** #1493 closes with a note: its Xournal++ half
   is gone upstream in 4.5.0-rc2, and Obsidian is missing only
   `-disable-gpu`.
