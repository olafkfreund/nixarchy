---
title: Updating NixOS
---

# Updating NixOS

## The short way

```sh
omarchy update
```

Omarchy's own update command, replaced here. Upstream's drives pacman — it
prunes packages, takes a snapper snapshot, refreshes the keyring and demands
10 GiB free before it will start. None of that exists on NixOS, so this one does
what updating a NixOS host actually means:

```sh
nh os switch --update /etc/nixos    # move every input forward, then rebuild
```

`nh` is a front end to nixos-rebuild, so nothing about the result differs; it
reports the build as it happens and diffs the packages that changed at the end.

It asks before doing either, and it tells you afterwards that the previous
generation is still in the boot menu. No snapshot is taken because none is
needed — see [rollback](#when-it-goes-wrong).

Your flake is wherever `programs.nixarchy.flake` points, which is often *not*
`/etc/nixos` — many people keep theirs in a git repo under `~`.

## The long way, and when you want it

`omarchy update` moves **every** input. Sometimes that is more than you want.

```sh
nix flake update nixpkgs --flake <flake>   # move one input
nix flake update --flake <flake>           # move all of them
sudo nixos-rebuild switch --flake <flake>
```

Updating a single input is the better habit when you are chasing a specific fix.
Moving everything to solve one problem changes far more than the problem, and
when something breaks you have no idea which input did it.

`nix flake update` rewrites `flake.lock`, so the flake directory has to be
writable by you. A root-owned `/etc/nixos` fails on the lock file.

## switch, boot, test — pick the right one

| | |
|---|---|
| `nixos-rebuild switch` | build, activate now, and make it the boot default |
| `nixos-rebuild boot` | build and make it the boot default, but **do not** activate now |
| `nixos-rebuild test` | build and activate now, but **do not** touch the boot default |
| `nixos-rebuild build` | build only — no `sudo`, no activation |

`build` is free to run and catches every evaluation and build error, so use it
while iterating.

**`boot` is the one to reach for when a change could cost you the screen** — a
display manager, a GPU driver, a greeter. The running system stays up; you test
by rebooting, and if it fails the previous generation is one boot-menu entry
away.

## When it goes wrong

Every previous system is still on disk.

```sh
sudo nixos-rebuild --rollback switch      # back one generation, now
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

Or pick an older generation from the boot menu — which is how you recover when
the machine will not reach a desktop at all. Keep a TTY in mind too:
`Ctrl+Alt+F2` gets you a login even when the graphical session is broken.

To see what an update actually changed:

```sh
nix profile diff-closures --profile /nix/var/nix/profiles/system
```

That is the honest answer to "what did that update do", and better evidence than
any package log.

## A rebuild does not update the session you are sitting in

This one costs people an evening, so it is worth stating plainly.

`OMARCHY_PATH` and `PATH` are set **at login** and keep pointing at whichever
store path was current then. A rebuild installs a new package at a *new* path and
cannot reach into a session that is already running. So every `omarchy-*` command
your desktop executes — every keybinding, every menu row — comes from the old
build until you log out and back in.

```sh
echo "$OMARCHY_PATH"
readlink -f /run/current-system/sw/bin/omarchy | sed 's|/bin/omarchy$||'
```

If those differ, log out and back in. `nixarchy-doctor` reports it under
**Session**.

On Arch this cannot happen: the tree lives at a fixed `/usr/share/omarchy`
overwritten in place, and a running session picks up a new version at once. Here
the path itself changes. It is the single most misleading failure on this system,
because testing a fix by running the script at its full installed path *works*
while the keybinding still does not.

The same applies to Hyprland config deployed by Home Manager: a store **symlink
swap** is not a content change, so Hyprland's auto-reload does not notice it. Run
`hyprctl reload` after a rebuild that touched `~/.config/hypr/`.

## Keeping Omarchy itself current

nixarchy tracks Omarchy releases as a source bump. `nix flake update` moves the
`nixarchy` input like any other, and a new Omarchy version arrives with it — the
menus, themes and commands come along, because the port vendors upstream's real
tree rather than reimplementing it.

Your app selection is untouched by any of this. It lives in a file you own.
