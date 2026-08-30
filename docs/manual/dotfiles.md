---
title: Dotfiles
---

# Dotfiles

Upstream draws one line: `~/.config` is yours, `/usr/share/omarchy` is
Omarchy's. The same line exists here, and it is enforced harder than upstream
can enforce it.

| | Who owns it | How it changes |
|---|---|---|
| `~/.config/hypr/*.lua`, `~/.config/omarchy/shell.json`, `~/.config/foot/foot.ini`, `~/.XCompose`, `~/.bashrc` | You | Edit in place, effective on save. No rebuild. |
| `$OMARCHY_PATH` (Omarchy's own tree, a `/nix/store` path) | The package | Read-only filesystem. The write fails; it is not merely discouraged. |
| Packages, services, fonts, the firewall | Your flake | Only at a rebuild. |

Getting the row wrong is the usual way to make a change that silently does
not last: a keybinding is a text edit, but the program it launches is a
rebuild.

Upstream's table of key files and what each controls is unchanged and is not
repeated here; see [the upstream page](https://omarchy.org/manual/dotfiles/).
The menu editing routes (*Setup > Monitors*, *Setup > Keybindings*, *Setup >
Input*, *Setup > Config > [file]*) work the same, including the automatic
restart of whatever needs restarting when you quit the editor.

## Two files under `~/.config` that are not yours

**A symlink into `/nix/store`.** If you declared a config through Home
Manager, `~/.config/<that file>` is a link to a read-only store path, and
editing it fails. It is not a nixarchy file and not an upstream file; it is
yours, declared in the other place. Change it where you declared it and
rebuild. `ls -l ~/.config/hypr/` tells you at a glance which files are links.
The doctor reports this for the Hyprland configs and for `mimeapps.list`,
where a store-managed file makes *Setup > Default browser* a silent no-op.

Note that a rebuild swaps the symlink rather than rewriting the file, and
Hyprland's auto-reload does not notice a swap. Run `hyprctl reload`.

**`~/.config/omarchy/extensions/omarchy-menu.jsonc`.** Upstream says to edit
this to add menu rows. Here it is generated on every rebuild and your edit is
overwritten by the next one. It has to be generated: it carries the rewrite
that points every `install.*` and `remove.*` row at the Nix app selection, and
upstream's merge copies every key of an override rather than filling in the
ones you omit, so a hand-written row that leaves out `label` renders its raw
id and one that leaves out `action` does nothing. Add rows in your flake
instead:

```nix
programs.nixarchy.menu.extraEntries = {
  "personal"       = { icon = ""; label = "Personal"; };
  "personal.notes" = { icon = "󰎞"; label = "Notes"; action = "omarchy-launch-editor ~/notes"; };
};
```

Same dotted ids as upstream, so `personal` lands on the root menu and
`personal.notes` inside it; reuse an existing id to override that row. Give
every row a `label`, and every leaf an `action`.

## Starting your own apps with the session

Unchanged: `o.launch_on_start("my-service")` in `~/.config/hypr/autostart.lua`.
The command has to be on `PATH`, which on NixOS means it is in your flake or
your app selection; a binary dropped in `~/.local/bin` works too, but nothing
records that it is there.

## Running scripts on system events

The hook directories under `~/.config/omarchy/hooks/<event>.d/` are as
upstream ships them, and `omarchy hook install <event> <script>` copies a
script in. One row of upstream's table changes:

| Event | Here |
|---|---|
| `post-boot`, `theme-set`, `font-set`, `battery-low` | Unchanged |
| `post-update` | Runs during `omarchy update`, after the rebuild |
| `pre-refresh-pacman` | Never runs. There is no pacman; the shipped README in that directory says so. |

## Shell exports, functions, and aliases

`~/.bashrc` is yours and is not touched by a rebuild. Omarchy's aliases and
functions load from `/etc/bashrc`, *before* `~/.bashrc`, so anything you
define wins. If you bring your own shell setup entirely, turn the chain off
in your flake with `programs.nixarchy.bashIntegration = false;`.

## Changing internal Omarchy files

Upstream's advice is "don't, an update overwrites them". Here you cannot:
`$OMARCHY_PATH` is in `/nix/store` and mounted read-only. Read it freely,
because it is the best documentation of what each command does:

```sh
cat "$OMARCHY_PATH"/default/hypr/windows.lua
cat "$(which omarchy-theme-set)"
```

Never write the path itself into a config. It changes with every Omarchy or
nixpkgs bump; always go through `$OMARCHY_PATH`.

Overriding still works the way upstream shows, in your files. Replacing a
keybinding in `~/.config/hypr/bindings.lua`:

```lua
hl.unbind("SUPER + SHIFT + O")
o.bind("SUPER + SHIFT + O", "Joplin", "joplin-desktop")
```

except that `omarchy-pkg-add joplin-bin` is not how Joplin gets installed;
pick it from the Install menu or add it to your flake, and rebuild. Stock
themes are read-only in the same way; put a custom theme in
`~/.config/omarchy/themes/<slug>/` rather than editing one under
`$OMARCHY_PATH/themes/`.

Upstream's dev channel (*Update > Channel > Dev*, a git checkout in
`~/omarchy`) is a pacman concept. The equivalent is pointing the `nixarchy`
flake input at your own fork or a local path and rebuilding.

## Resetting your changes

`omarchy refresh config <path>` copies one shipped file back over yours and
keeps a timestamped `.bak` of your version, for example
`omarchy refresh config hypr/bindings.lua`. `omarchy reinstall configs` replays
`/etc/skel` over your home, which resets every shipped default at once and is
as destructive as it sounds. Plain `omarchy reinstall` cannot finish here at
all; see [troubleshooting](troubleshooting.md).
