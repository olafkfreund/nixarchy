---
name: nixarchy
description: >
  REQUIRED for end-user customization of the Nixarchy desktop, window manager, or
  desktop config on NixOS. Use when editing ~/.config/hypr/, ~/.config/omarchy/,
  ~/.config/alacritty/, ~/.config/foot/, ~/.config/kitty/, or ~/.config/ghostty/.
  Triggers: Hyprland, window rules, animations, keybindings, monitors, gaps, borders,
  blur, opacity, omarchy-shell, bar, terminal config, themes, background,
  night light, idle, lock screen, screenshots, reminders, layer rules, workspace
  settings, display config, and user-facing omarchy commands. For installing
  packages or changing anything outside ~/.config, use the `nixos` skill instead.
---

# Nixarchy Skill

Manage [Nixarchy](https://github.com/olafkfreund/nixarchy) systems — the
[Omarchy](https://omarchy.org/) desktop vendored for NixOS, with its menus rewired
to Nix instead of pacman.

This skill is for end-user customization of the **desktop** on an installed system.
For installing packages or editing the system configuration, use the `nixos` skill.
This skill is not for contributing to Nixarchy or Omarchy source code.

## Read This First: How Nixarchy Differs From Omarchy

Nixarchy runs Omarchy's real tree, unmodified where it can be. The commands, menus,
themes, keybindings and shell are upstream's. What changes is everything that
assumed Arch:

| Upstream Omarchy | Here |
|---|---|
| Files live in `/usr/share/omarchy/` | Files live in `$OMARCHY_PATH`, a `/nix/store` path |
| `omarchy pkg add <pkg>` installs via pacman | Prints the declarative route and **exits non-zero**; nothing is installed imperatively |
| Install menu runs `pacman -S` | Install menu edits `~/.config/nixarchy/apps.nix`; nothing is built until you apply |
| `omarchy update` runs a pacman upgrade | Runs `nix flake update` then `nixos-rebuild switch` |
| Rollback via snapper snapshots | Rollback via NixOS generations (`nixos-rebuild --rollback`, or the boot menu) |
| AUR | No equivalent. `omarchy pkg aur add` explains rather than installs |

**The most important consequence:** nothing you install imperatively survives a
rebuild. If a task involves adding a package, it is a `nixos` skill task, not this
one. Do not reach for `omarchy pkg add` to "just install" something — it is a
replacement script that deliberately refuses, so that a caller which would go on to
configure what it thinks it installed stops there instead of half-completing.

## When This Skill MUST Be Used

**ALWAYS invoke this skill for end-user requests involving ANY of these:**

- Editing ANY file in `~/.config/hypr/` (window rules, animations, keybindings, monitors, etc.)
- Editing `~/.config/omarchy/shell.json` (status bar layout, widgets)
- Editing terminal configs (alacritty, foot, kitty, ghostty)
- Editing ANY file in `~/.config/omarchy/`
- Window behavior, animations, opacity, blur, gaps, borders
- Layer rules, workspace settings, display/monitor configuration
- Themes, backgrounds, fonts, appearance changes
- User-facing `omarchy` commands (`omarchy theme ...`, `omarchy refresh ...`, `omarchy restart ...`, etc.)
- Screenshots, screen recording, reminders, night light, idle behavior, lock screen

**If you're about to edit a config file in ~/.config/ on this system, STOP and use this skill first.**

**Do NOT use this skill for:**
- Installing packages or changing system configuration — use the `nixos` skill
- Nixarchy or Omarchy source development

## Topic Guides

Deeper instructions for common areas live next to this file. Read the
matching guide before starting:

- [`hyprland.md`](hyprland.md) - keybindings, monitors, window rules, and other Hyprland config
- [`plugins.md`](plugins.md) - the Omarchy shell: bar layout, widgets, plugins, idle behavior
- [`theming.md`](theming.md) - themes, backgrounds, and fonts
- [`hooks.md`](hooks.md) - automation hooks that run on system events
- [`capture.md`](capture.md) - screenshots, screen recordings, OCR text capture, and file sharing
- [`contributing.md`](contributing.md) - reporting Nixarchy and Omarchy bugs

## Critical Safety Rules

For privileged commands, follow the Privilege Escalation rules below: `sudo` when a
terminal is available for the password prompt, `pkexec` when it is not. Do not wrap
commands that already manage privilege elevation themselves.

**`$OMARCHY_PATH` is a read-only `/nix/store` path. Reading it is safe and
encouraged; writing to it is impossible.**

This is stronger than upstream's rule. On Arch the package directory is merely
overwritten on update; here the store is mounted read-only and a write fails
outright. If a command or an edit is trying to write there, the approach is wrong —
find the `~/.config/` equivalent.

```
$OMARCHY_PATH/            # READ-ONLY /nix/store path (reading is OK)
├── bin/                    # Command source (packaged binaries are on PATH)
├── config/                 # Default config templates
├── themes/                 # Stock themes
├── default/                # System defaults
├── shell/                  # Omarchy shell source and defaults
├── migrations/             # Update migrations
└── install/                # Installation scripts
```

**Reading `$OMARCHY_PATH` is SAFE and useful** - do it freely to:
- Understand how omarchy commands work: `omarchy theme set --help` or `cat $(which omarchy-theme-set)`
- See default configs before customizing: `cat "$OMARCHY_PATH/config/omarchy/shell.json"`
- Check stock theme files to copy for customization
- Reference default hyprland settings: `cat "$OMARCHY_PATH"/default/hypr/*`

Always resolve it through the variable. Never hardcode a store hash: it changes on
every Omarchy or nixpkgs bump, and a path written down today is wrong after the next
rebuild.

**Always use these safe locations instead:**
- `~/.config/` - User configuration (safe to edit)
- `~/.config/omarchy/themes/<custom-name>/` - Custom themes
- `~/.config/omarchy/hooks/` - Custom automation hooks

If the request is to develop Nixarchy itself, this skill is out of scope.

## Privilege Escalation

For an interactive script or command run in a visible terminal, use `sudo` for
privileged work. The terminal is the appropriate place to request a password when
one is needed.

Use `pkexec` only when the caller cannot interact with a terminal or cannot
enter a password there, such as a command launched by an agent or a graphical
background process. Do not replace `sudo` with `pkexec` merely because a
command changes system state.

## System Architecture

Nixarchy is built on:

| Component | Purpose | Config Location |
|-----------|---------|-----------------|
| **NixOS** | Base OS | The flake (see the `nixos` skill), `~/.config/` |
| **Hyprland** | Wayland compositor/WM | `~/.config/hypr/` |
| **Omarchy shell** | Status bar + notifications (Quickshell) | `~/.config/omarchy/shell.json` |
| **Launcher/menus** | Quickshell menu | `programs.nixarchy.menu.extraEntries` — the jsonc is generated, see below |
| **Alacritty/Foot/Kitty/Ghostty** | Terminals | `~/.config/<terminal>/` |
| **Omarchy OSD** | On-screen display | Quickshell plugin |

Two config systems coexist and the boundary matters: **anything under `~/.config/` is
yours, imperative, and edited in place. Anything else is declared in the flake and
only changes at a rebuild.** Getting this backwards is the most common way to do
something on this system that silently does not last.

## Command Discovery

Nixarchy ships Omarchy's single `omarchy` CLI, which dispatches to all `omarchy-*`
binaries via `omarchy <group> <action>`. Always prefer this form — it is
self-documenting and stable. The underlying `omarchy-*` binaries still exist on
`PATH` and remain safe to read for source.

```bash
# List every documented command and its summary (--all includes hidden commands)
omarchy commands

# Show the commands inside a group
omarchy theme --help
omarchy refresh --help
omarchy restart --help

# Show help for a specific command (does not execute it)
omarchy theme set --help

# Machine-readable listing (binary, route, summary, args, aliases)
omarchy commands --json

# Read a command's source to understand it
cat $(which omarchy-theme-set)
```

Some `omarchy-*` commands are Nixarchy replacements rather than upstream's. They
keep upstream's name and contract; reading the source is the quickest way to see
which is which — a replacement says so in its header comment.

### Command Groups

Run `omarchy --help` for the full list. The most common groups:

| Group | Purpose | Example |
|-------|---------|---------|
| `omarchy refresh` | Reset config to defaults (backs up first) | `omarchy refresh shell` |
| `omarchy restart` | Restart a service/app | `omarchy restart shell` |
| `omarchy toggle` | Toggle feature on/off | `omarchy toggle nightlight` |
| `omarchy theme` | Theme management | `omarchy theme set <name>` |
| `omarchy bar` | Bar layout and widgets | `omarchy bar move omarchy.clock --section right` |
| `omarchy plugin` | Manage/clone shell plugins | `omarchy plugin clone omarchy.clock` |
| `omarchy hook` | Install automation hooks | `omarchy hook install theme-set <script>` |
| `omarchy install` | Queue an app into the Nix selection (see the `nixos` skill) | `omarchy install docker dbs` |
| `omarchy launch` | Launch apps | `omarchy launch browser` |
| `omarchy capture` | Screenshots and recordings | `omarchy capture screenshot` |
| `omarchy reminder` | Desktop notification reminders | `omarchy reminder 15 "Pickup Jack"` |
| `omarchy pkg` | **Explains the declarative route; installs nothing** | `omarchy pkg add <pkg>` |
| `omarchy setup` | Interactive setup wizards | `omarchy setup security fingerprint` |
| `omarchy update` | `nix flake update` + `nixos-rebuild switch` | `omarchy update` |

## Configuration Locations

Hyprland config lives in `~/.config/hypr/` — see [`hyprland.md`](hyprland.md).
The Omarchy shell (bar, notifications, plugins, idle) is configured in
`~/.config/omarchy/shell.json` — see [`plugins.md`](plugins.md).

### Terminals

```
~/.config/alacritty/alacritty.toml
~/.config/foot/foot.ini
~/.config/kitty/kitty.conf
~/.config/ghostty/config
```

**Command:** `omarchy restart terminal`

### Other Configs

| App | Location |
|-----|----------|
| btop | `~/.config/btop/btop.conf` |
| fastfetch | `/etc/fastfetch/config.jsonc` default; `~/.config/fastfetch/config.jsonc` user override |
| lazygit | `~/.config/lazygit/config.yml` |
| starship | `~/.config/starship.toml` |
| git | `~/.config/git/config` |

Note that `/etc` on NixOS is generated from the system configuration. A file there
may be a symlink into the store, in which case it is not editable and its content
belongs in the flake — see the `nixos` skill.

## Safe Customization Patterns

### Edit User Config Directly

For simple changes, edit files in `~/.config/`:

```bash
# 1. Read current config
cat ~/.config/hypr/bindings.lua

# 2. Backup before changes
cp ~/.config/hypr/bindings.lua ~/.config/hypr/bindings.lua.bak.$(date +%s)

# 3. Make changes with Edit tool

# 4. Apply changes
# - Hyprland: auto-reloads on save, but MUST validate with `hyprctl reload` and `hyprctl configerrors`
# - Omarchy shell: shell.json and user plugin code under ~/.config/omarchy/plugins/ hot-reload on save
# - Menus/launcher: NOT editable here -- see "The menu is generated" below
# - Terminals: apply with `omarchy restart terminal` (reloads running terminals; foot picks changes up in new windows)
```

None of this needs a rebuild. That is the point of the boundary: desktop
customization is immediate, and only the flake half requires `nixos-rebuild`.

### The menu is generated, not yours to edit

`~/.config/omarchy/extensions/omarchy-menu.jsonc` is the one file under
`~/.config/omarchy/` that is **not** editable. It is a symlink to a read-only
`/nix/store` path:

```
~/.config/omarchy/extensions/omarchy-menu.jsonc -> /etc/nixarchy/omarchy-menu.jsonc -> /nix/store/...
```

That is deliberate. This file carries the rewrite that points every `install.*`
row at the Nix app selection instead of pacman, so it has to track the package.
A copy would go stale the moment the package moved and leave the Install menu
driving commands that no longer match.

Upstream's documentation says this file hot-reloads on save. It does — but you
cannot save it, and trying is worse than failing: replacing the symlink with a
real file silently stops the menu tracking the package, and the next rebuild
overwrites it anyway.

Add rows declaratively instead:

```nix
programs.nixarchy.menu.extraEntries = {
  "personal.notes" = {
    icon = "󰎞";
    label = "Notes";
    action = "omarchy-launch-editor ~/notes";
  };
};
```

Nothing else in `~/.config/omarchy/` works this way — `shell.json`, the themes
and the plugins directory are all real, writable, and yours.

If a file under `~/.config/` turns out to be a symlink into `/nix/store`, it is
managed by Home Manager and editing it is not possible. Change it in your Home
Manager configuration instead — that is a `nixos` skill task.

### Reset to Defaults -- ALWAYS SEEK USER CONFIRMATION BEFORE RUNNING

When customizations go wrong:

```bash
# Reset specific config (creates backup automatically)
omarchy refresh shell
omarchy refresh hyprland

# The refresh command:
# 1. Backs up current config with timestamp
# 2. Copies default from $OMARCHY_PATH/config/
# 3. Restarts the component where the refresh needs it (e.g. `refresh shell`)
```

## System Commands

```bash
omarchy update                  # nix flake update + nixos-rebuild switch
omarchy version                 # Show Omarchy version
omarchy debug --no-sudo --print # Debug info (ALWAYS use these flags)
omarchy system lock             # Lock screen
omarchy system shutdown         # Shutdown
omarchy system reboot           # Reboot
```

**IMPORTANT:** Always run `omarchy debug` with `--no-sudo --print` flags to avoid
interactive sudo prompts that will hang the terminal.

## Troubleshooting

```bash
# Get debug information (ALWAYS use these flags to avoid interactive prompts)
omarchy debug --no-sudo --print

# Reset specific config to defaults
omarchy refresh <app>

# Refresh specific config file
# config-file path is relative to ~/.config/
# eg. `omarchy refresh config hypr/hyprland.lua` will refresh ~/.config/hypr/hyprland.lua
omarchy refresh config <config-file>
```

**`omarchy reinstall` exists but cannot finish here.** Its first act is
`omarchy-reinstall-pkgs`, which runs `pacman -Suu`. The shim refuses, `set -e` aborts
the script, and `omarchy-reinstall-configs` never runs. The ordering is safe — it
fails before touching anything — but it does mean the command is not a recovery
route, despite prompting as though it were.

To reset configs, use `omarchy refresh <app>` above. For anything else, the previous
working system is still on disk as a generation:

```bash
sudo nixos-rebuild --rollback switch    # back to the previous generation
```

Or pick an older generation from the boot menu. See the `nixos` skill.

## Decision Framework

When user requests system changes:

1. **Is it a stock omarchy command?** Use it directly
2. **Is it a config edit under `~/.config/`?** Edit it there, never `$OMARCHY_PATH`
3. **Is it a theme customization?** Follow [`theming.md`](theming.md); create a NEW custom theme directory
4. **Is it automation?** Follow [`hooks.md`](hooks.md); use `omarchy hook install` and the hook `.d` directories
5. **Is it a package install, or any change outside `~/.config/`?** **Use the `nixos` skill.** Do not run `omarchy pkg add` expecting an install, and never install imperatively — it will not survive the next rebuild
6. **Is it built-in shell/plugin code?** Follow [`plugins.md`](plugins.md); clone it with `omarchy plugin clone`, never edit the packaged copy
7. **Unsure if command exists?** Run `omarchy commands` (or `omarchy <group> --help` for one group)

### Reminder Requests

When the user asks to set a reminder, use `omarchy reminder <minutes> [message]` directly. Convert natural language durations to minutes and title-case short reminder labels when appropriate.

```bash
omarchy reminder 15 "Pickup Jack"
omarchy reminder 60 "Check laundry"
omarchy reminder show
omarchy reminder clear
```

## Out of Scope

This skill intentionally does not cover:
- Package installation or system configuration — use the `nixos` skill
- Nixarchy or Omarchy source development
- Editing anything under `$OMARCHY_PATH` (`bin/`, `config/`, `default/`, `shell/`, `themes/`, `migrations/`) — which is read-only anyway
- Creating or editing migrations

## Example Requests

- "Change my theme to catppuccin" -> `omarchy theme set catppuccin`
- "Add a keybinding for Super+E to open file manager" -> Check existing bindings first, call `hl.unbind` if needed, then `o.bind` in `~/.config/hypr/bindings.lua`
- "Configure my external monitor" -> Edit `~/.config/hypr/monitors.lua`
- "Make the window gaps smaller" -> Edit `~/.config/hypr/looknfeel.lua`
- "Turn on night light" -> `omarchy toggle nightlight` (for time-based schedules, edit `~/.config/hypr/hyprsunset.conf` profiles, then `omarchy restart hyprsunset`)
- "Set a reminder to pickup jack in 15 minutes" -> `omarchy reminder 15 "Pickup Jack"`
- "Customize the catppuccin theme colors" -> Overlay: put an edited `colors.toml` in `~/.config/omarchy/themes/catppuccin/`, then re-apply the theme (see `theming.md`)
- "Run a script every time I change themes" -> Install it with `omarchy hook install theme-set <script>`
- "Lock after ten minutes" -> Set `idle.lock` to `600` in `~/.config/omarchy/shell.json`
- "Reset shell/bar to defaults" -> `omarchy refresh shell`
- "Record my screen" -> `omarchy screenrecord --fullscreen`, then `omarchy screenrecord --stop-recording` (see `capture.md`)
- **"Install Ghostty" -> NOT this skill. Use the `nixos` skill: it is a declarative change, not a command**
- **"My change disappeared after a reboot" -> it was installed imperatively. Use the `nixos` skill to declare it**
- "Report this bug" -> Work out whether it is Nixarchy's or Omarchy's first (see `contributing.md`)
