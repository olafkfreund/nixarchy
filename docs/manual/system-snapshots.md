---
title: System snapshots
---

# System snapshots

Omarchy takes a Btrfs snapshot with snapper before every update, and you boot
into one from the Limine menu to undo a bad update. **None of that machinery
exists here, and none of it is missing.** NixOS keeps every previous system on
disk as a *generation*, and generations do everything the snapshot did.

`omarchy-snapshot` still exists in the tree, but it checks for snapper and
exits 127 when it is not there, which is always. `omarchy update` treats that
exit code as "no snapshot available" and carries on.

## What a generation is

Every `nixos-rebuild switch` (which is what `omarchy update` runs) builds a
complete new system in `/nix/store` and points
`/nix/var/nix/profiles/system` at it. The old one is not overwritten; it is
still there, complete, and it is still listed in the boot menu.

```sh
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

No snapshot is taken before an update because there is nothing to snapshot:
the previous system was never modified in the first place.

## Rolling back

From a running desktop:

```sh
sudo nixos-rebuild --rollback switch   # back one generation, now
```

From a machine that will not reach a desktop: reboot, and pick the previous
generation from the boot menu. Every generation is an entry there, labelled
with its date and number.

This is the one way generations are better than snapper, and it matters.
Upstream's restore is a command you run from inside the booted snapshot, and
a broken update that keeps the machine from booting at all leaves you with
the Limine menu only if you are not using direct boot. Here the boot menu is
where the generations live, so the recovery route works precisely when it is
needed most: when the update cost you the screen, the GPU driver, or the
login manager.

To see what an update actually changed, before deciding whether to roll it
back:

```sh
nix profile diff-closures --profile /nix/var/nix/profiles/system
```

## What a rollback does and does not touch

The same boundary upstream describes for snapshots holds here, for the same
reason:

| | |
|---|---|
| Packages, services, kernel, drivers, the Omarchy tree | Rolled back with the generation |
| `/home`, `~/.config`, your app selection file | Left exactly as they are |

So a rollback fixes a broken system update and does not recover a deleted
file. And if an application rewrote its config in a new format before you
rolled back, the config stays in the new format; sort that out by hand, as
upstream says.

Rolling back also does not edit your flake. `flake.lock` still names the
inputs that produced the broken generation, so the next `omarchy update` or
`nixos-rebuild switch` builds it again. To make the rollback stick, revert the
lock file too, most simply with `git checkout flake.lock` in your flake if it
is under version control, or by updating only the input that did not break.

## Testing a change without committing to it

Snapshots exist to make an update safe to try. Generations make that a
first-class option instead:

```sh
sudo nixos-rebuild boot --flake <flake>   # becomes the default at next boot, running system untouched
sudo nixos-rebuild test --flake <flake>   # activates now, boot default untouched
```

`boot` is the one for anything that could cost you the screen; the previous
generation stays one menu entry away. See
[updating NixOS](updating-nixos.md).

## The one command that deletes the safety net

```sh
nix-collect-garbage -d
```

`-d` deletes every generation but the current one. The disk space it frees is
exactly the rollback history. Run it when you mean to, after the current
system has been good for a while, and not as a reflex to free space. Without
`-d`, `nix-collect-garbage` removes only store paths no generation references,
which is safe.

Direct boot, upstream's *Setup > Direct Boot*, is a Limine feature and has no
meaning here; your boot loader's own timeout setting is the equivalent.
