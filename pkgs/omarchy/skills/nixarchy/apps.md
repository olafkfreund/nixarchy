# Apps: Defaults, Launchers, and Installing

Read this before changing which app opens something, adding a web app or TUI launcher, or installing or removing software.

## Default Applications

| Role | Default | Change it with |
|------|---------|----------------|
| Terminal | foot | `omarchy default terminal <alacritty\|foot\|ghostty\|kitty>` |
| Browser | Chromium | `omarchy default browser <chromium\|chrome\|brave\|brave-origin\|edge\|firefox\|zen>` |
| Editor (GUI and `$EDITOR`) | Plain | `omarchy default editor <plain\|code\|cursor\|zed\|sublime_text\|helix\|vim\|emacs\|nvim>` |
| Dictation | Superwhisper (or Voxtype) | `omarchy default dictation <superwhisper\|voxtype\|hex>` |
| Coding agent | chosen at first use | `omarchy default agent <claude\|codex\|opencode\|pi\|...>` |
| Files | Folio | `xdg-mime default <app>.desktop inode/directory`, and rebind Super+Shift+F, which always opens Folio |
| Images, video, music | Omaview | `xdg-mime default <app>.desktop <mimetype>` |
| PDF | Papers | `xdg-mime default <app>.desktop application/pdf` |
| Markdown | Omawrite | `xdg-mime default <app>.desktop text/markdown` |
| Email links | HEY web app | `xdg-mime default <app>.desktop x-scheme-handler/mailto` |

Each `omarchy default` command prints the current choice when run without an argument, and the same choices are in the menu under Setup > Defaults. For browser, editor, and coding agent, choosing one that is not installed yet enables it in `~/.config/nixarchy/apps.nix` and runs `nixarchy-apply` to build it, then sets the default once the rebuild finishes (`programs.nixarchy.defaultAgent` declares the coding agent in the flake). For another terminal (`alacritty`, `ghostty`, `kitty`), enable it in `~/.config/nixarchy/apps.nix` and apply with `nixarchy-apply` first, then run `omarchy default terminal <name>`. The terminal is reached through `xdg-terminal-exec` (`$TERMINAL`), and every editor through `omarchy-launch-editor` (`$EDITOR`), so bindings and scripts that use those follow the choice.

`xdg-mime default` writes `~/.config/mimeapps.list`, which overrides the system defaults in `/etc/xdg/mimeapps.list` (or declare associations in Home Manager with `xdg.mimeApps.defaultApplications`). Leave `~/.config/hyprland-mimeapps.list` alone: it routes web links through `omarchy-browser.desktop`, which opens them in whichever browser is the default.

Omarchy also ships Omacalc, Omacut (video trimming), Hype (presentations), Monologue (webcam recording), Signed (PDF signing), LibreOffice, Pinta, LocalSend, Fantasi (image and media models), btop (Activity), and the HEY, ChatGPT and Grok web apps (`obsidian` is in the app selection). `omarchy menu keybindings --print` shows which of them have hotkeys.

## Web Apps and TUIs

A web app opens a site in its own browser window with its own launcher entry; a TUI launcher opens a terminal program in its own window. Both write a `.desktop` file to `~/.local/share/applications/`, so they show in the app launcher:

```bash
omarchy webapp install "YouTube" https://youtube.com https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/youtube.png
omarchy webapp remove YouTube
omarchy tui install "Disk Usage" "dust" float <icon-url-or-name>   # window style: float or tile
omarchy tui remove "Disk Usage"
```

Run either without arguments for an interactive prompt. To put one on a key, use the `{ webapp = ... }` or `{ tui = ... }` binding forms in [`hyprland.md`](hyprland.md).

## Installing and Removing Software

On NixOS, software is declared rather than installed imperatively — use the `nixos` skill for full details.

The curated apps Omarchy's Install menu offers live in `~/.config/nixarchy/apps.nix` (and services in `~/.config/nixarchy/services.nix`), applied with `nixarchy-apply` (Install > Apply changes). Picking an app in the Install menu or running `nixarchy-app-enable` queues it into that selection; nothing is built until you apply:

```bash
nixarchy-app-enable firefox            # Queue a curated app in ~/.config/nixarchy/apps.nix
nixarchy-app-disable firefox           # Remove a curated app from the selection
nixarchy-pkg-add ripgrep               # Append a nixpkgs attribute to the same selection
nixarchy-search                        # Fuzzy picker over nixpkgs, NixOS options, and curated apps
nixarchy-app-remove                    # Fuzzy picker to remove items from your selection
nixarchy-apply                         # Copy the selection into the flake and rebuild
```

For language toolchains (Node, Python, Go, Rust, Ruby, and so on) in a project, use a per-project `devenv.nix` (`nixarchy dev init`, see the `devenv` skill) rather than a global install.

Non-package helpers that work in place:

```bash
omarchy install docker dbs             # A database in Docker
omarchy remove preinstalls             # Drop the preinstalled web apps and TUIs
omarchy install preinstalls            # Bring them back
```

To drop the preinstalled desktop packages declaratively, set `programs.nixarchy.preinstalls = false;` or list individual packages in `programs.nixarchy.preinstallsExclude`.
