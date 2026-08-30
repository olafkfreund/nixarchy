---
title: The NixOS philosophy, and what it changes
---

# The NixOS philosophy, and what it changes

Omarchy assumes Arch. Arch installs software by running a command that changes
the machine. NixOS does not work that way, and almost every difference in this
manual falls out of that one fact.

## The machine is described, not modified

On Arch, `pacman -S ghostty` *changes your system*. The record that it happened
is a log file.

On NixOS, you write a line in a file:

```nix
environment.systemPackages = with pkgs; [ ghostty ];
```

and then build the machine that file describes. **The file is the system.** If
the file does not say Ghostty, the next rebuild does not have Ghostty — no
matter what you ran last week.

That has one consequence worth putting in bold, because it is the single most
common way to waste an afternoon here:

> **Nothing you install imperatively survives.** Not `nix-env -i`, not
> `nix profile install`, not a binary you drop in `~/.local/bin` and forget. The
> first two create state no file records; the third survives, but nobody
> including you will remember it is there.

If you find yourself typing `nix-env`, the answer is a line in your
configuration instead.

## What this does to the Install menu

Omarchy's Install menu runs `pacman -S`. Here it cannot, so it does the
declarative equivalent: **it edits a file and stops.**

```
Install ▸ Brave          →  "brave queued — not installed yet"
Install ▸ VSCode         →  "2 app(s) selected"
Install ▸ Apply changes  →  nh os switch <flake>
```

Pick as many as you like; nothing is built until you apply. That is not a
limitation being worked around — it is the point. You get to see everything you
are about to change before any of it happens.

`omarchy pkg add <pkg>` therefore **refuses**, deliberately, and exits non-zero.
It prints the declarative route instead. It is a replacement script rather than
a broken one: if it silently did nothing, a caller that went on to configure what
it thought it had installed would half-complete. Failing loudly stops that.

## The boundary: `~/.config` is yours, everything else is declared

Two configuration systems coexist on a nixarchy machine, and knowing which one
you are in is most of knowing what to do.

| | |
|---|---|
| `~/.config/hypr/`, `~/.config/omarchy/shell.json`, themes, plugins | **Yours.** Imperative, edited in place, effective immediately. No rebuild. |
| Packages, services, users, fonts, hardware, the firewall | **Declared** in your flake. Only changes at a rebuild. |

Getting this backwards is the usual way to do something that silently does not
last. Changing a keybinding is a text edit and takes effect on save. Installing
the program that keybinding launches is a rebuild.

Two exceptions worth knowing:

- **A file under `~/.config/` that is a symlink into `/nix/store` is not
  editable.** Home Manager owns it. Change it where it is declared.
- **`~/.config/omarchy/extensions/omarchy-menu.jsonc`** is generated, and is the
  one file under `~/.config/omarchy/` you cannot edit. It carries the rewrite
  that points every `install.*` row at the Nix selection, so it has to track the
  package. Add rows with `programs.nixarchy.menu.extraEntries` instead.

## Rollback replaces the snapshot

Omarchy takes a snapper snapshot before an update so you can undo it. NixOS does
not need one: **every previous system is still on disk**, as a generation.

```sh
sudo nixos-rebuild --rollback switch   # back one generation, now
```

Or pick an older one from the boot menu. Nothing is lost by trying a change,
which is why this manual keeps suggesting you try one.

The corollary: `nix-collect-garbage -d` deletes those generations. It is the one
command that removes your safety net, so do not run it to free space without
meaning to.

## The store is read-only, and that is stronger than "do not edit"

Omarchy's manual says never to modify `/usr/share/omarchy/` because an update
overwrites it. Here the equivalent is `$OMARCHY_PATH`, a `/nix/store` path, and
the rule is not advice — **the filesystem is mounted read-only and the write
fails**.

Read it freely; it is the best documentation of how the commands work:

```sh
cat "$OMARCHY_PATH"/default/hypr/windows.lua
cat $(which omarchy-theme-set)
```

Never write down the path itself. It changes on every Omarchy or nixpkgs bump,
so a store hash copied into a config today is wrong after the next rebuild.
Always resolve it through `$OMARCHY_PATH`.

## Reproducibility is the point of all of it

The reason to accept "edit a file and rebuild" over "run a command" is that at
the end you have a machine you can rebuild from scratch, and a second machine
that is genuinely the same. Your flake plus its lock file is the whole
description. That is worth more than the convenience of `pacman -S`, and it is
the trade nixarchy is asking you to make.
