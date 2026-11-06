---
title: A reinstall image of this machine
---

# A reinstall image of this machine

**Not available right now.** The command runs its checks and then refuses to
build, because the image would install a stock system rather than this machine
([#1649](https://github.com/olafkfreund/nixarchy/issues/1649)). To get a machine
back today, boot the published network image with `nixarchy.from=<your config
repo> nixarchy.host=<name>` on its kernel command line. The rest of this page
describes the command once that is fixed.

`nixarchy reinstall iso` builds a bootable image **from this machine's own
configuration**. Boot it on new hardware and you get this system back: the same
packages, the same desktop, the same services, the same settings.

It is the last of the five ways back, and the only one that survives losing the
disk:

| what went wrong | what gets you back |
|---|---|
| a bad change | a previous [generation](system-snapshots) |
| a deleted file, same disk | a [snapshot](system-snapshots#snapshots-of-your-home-directory) |
| your dotfiles | [the home backup](dotfiles) |
| your configuration | [the config repo](many-machines) |
| **the disk itself, or the whole machine** | **this image** |

## It is not a backup, and that distinction is the whole page

**The image carries your configuration and fetches your system. It does not
carry your files.**

No `/home`. No browser profiles. No service state, no databases, no
photographs. And **booting it erases the target disk**.

That is why the menu row is called *Build reinstall image* and not *Backup*.
The trap it avoids is a specific one: somebody loses a disk, boots the thing
they were calling a backup, and ends up with a clean machine and none of their
files. Your files come back from your backups. This brings back the machine
they go on.

## Making one

From the menu: **System ▸ Backup and recovery ▸ Build reinstall image**. Or in
a terminal:

```
nixarchy reinstall iso
```

Before building, it checks:

- **Committed.** The flake embedded in the image pins by commit, so an
  uncommitted tree cannot be baked. `git add` is not enough — it has to be
  committed.
- **Drift.** If what is running differs from what `/etc/nixos` evaluates to —
  edits you have not switched to yet — it says so and asks. It does not refuse:
  building an image of what the configuration *says*, rather than what happens
  to be running, is a legitimate thing to want. It just should not happen
  without being told.
- **Cache availability.** It asks your store what a fresh machine could fetch
  and lists packages no configured cache holds, with their sizes, before you
  choose whether to build the image.

Then it asks before building, because the build takes tens of minutes —
compression is most of it.

The image lands at `~/.local/share/nixarchy/reinstall-iso/`, and the command
prints the exact path and size.

## What the image needs to reinstall

The image is about 1.5 GB because it carries your configuration and fetches
the system as it installs. Reinstalling needs a network and caches holding
this machine's packages. `--net` is still accepted and builds the same image.

They often do not hold all of it. `cache.nixos.org` carries **no unfree
packages** — vscode, zoom, every IDE with a licence — and anything built on
your machine (an overlay, a patched package) is in no cache anywhere. A
target must *compile* those during installation, or the install fails. The
command warns about them before building the image. The installer checks again
on the target, before anything is formatted.

## Writing it to a USB stick

```
sudo dd if=<the path it printed> of=/dev/sdX bs=4M status=progress oflag=sync
```

`/dev/sdX` is the stick, not a partition on it, and **this erases the stick**.
Check the device name with `lsblk` first.

Two things to do with the image once you have it:

**Keep it off this machine.** An image stored on the disk it exists to replace
protects nothing.

**Keep it private.** It contains your `/etc/nixos` — hostnames, options, and
the shape of your network. Those are yours to keep and not yours to publish.

## Using it: a new machine

Boot the stick. There is no boot menu and no login prompt — the installer is
what comes up, the same one the [normal ISO](getting-started) runs, and it asks
the same questions.

The difference is what it installs. A normal ISO installs a fresh nixarchy. This
one installs **the system that built it**. The target needs a network to fetch
that system from caches. A package no cache holds is compiled during the
install, or the install fails.

After it finishes, the machine has your system and `/etc/nixos` is your
repository. What it does not have is your files — bring those back with
[`nixarchy home backup restore`](dotfiles) and your own backups.

## Using it: a machine that already has something on it

**The installer erases the disk you point it at.** There is no in-place upgrade
here and no merge with what is already there.

If the target has something you want, you have two honest options:

1. **Move the data off first**, then install and bring it back.
2. **Install beside it** rather than over it — that is a different flow, and
   [dual boot](dual-boot-install) covers installing into free space next to an
   existing system.

If what you actually want is *this configuration on a machine that already runs
NixOS*, do not use the image at all. Add the nixarchy module to the
configuration that machine already has — it touches neither the partitions nor
the bootloader, and a bad result is one `nixos-rebuild --rollback` away.
[Many machines, one repo](many-machines) is the page for that.

## What is checked, and what is not

No automated check installs a personal image end to end. The stock network
image is installed in a VM, and the personal image's cache preflights are
tested with stubs. Your hardware is also untested: if the new machine differs
from the old one, expect to edit `hosts/<name>/hardware-configuration.nix`
after the first boot and rebuild.

The cache prediction is tested against real `nix path-info` shapes, but no
automated check watches a personal image fetch its system on a new machine.
If the preflight predicted "all fetchable" and installation still had to
build something, please report it.

## Related

- [Getting started](getting-started) — the normal installer
- [Many machines, one repo](many-machines) — one configuration, several machines
- [Your dotfiles](dotfiles) — the half this image does not carry
- [System snapshots](system-snapshots) — generations, and undoing a bad change
