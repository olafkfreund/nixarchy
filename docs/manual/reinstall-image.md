---
title: A reinstall image of this machine
---

# A reinstall image of this machine

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

**The image carries your system. It does not carry your files.**

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

It checks three things before it starts, and each refusal says what to do:

- **Disk space.** The image is 6–10 GB and the build wants roughly twice the
  closure in transient space. Checked first, because running out of disk
  mid-build fails several levels away from the cause.
- **Committed.** The flake embedded in the image pins by commit, so an
  uncommitted tree cannot be baked. `git add` is not enough — it has to be
  committed.
- **Drift.** If what is running differs from what `/etc/nixos` evaluates to —
  edits you have not switched to yet — it says so and asks. It does not refuse:
  building an image of what the configuration *says*, rather than what happens
  to be running, is a legitimate thing to want. It just should not happen
  without being told.

Then it asks before building, because the build takes tens of minutes —
compression is most of it.

The image lands at `~/.local/share/nixarchy/reinstall-iso/`, and the command
prints the exact path and size.

## Writing it to a USB stick

```
sudo dd if=<the path it printed> of=/dev/sdX bs=4M status=progress oflag=sync
```

`/dev/sdX` is the stick, not a partition on it, and **this erases the stick**.
Check the device name with `lsblk` first.

Two things to do with the image once you have it:

**Keep it off this machine.** An image stored on the disk it exists to replace
protects nothing.

**Keep it private.** It contains your `/etc/nixos` — hostnames, options, the
shape of your network — and the unfree packages your system uses. Those are
yours to keep and not yours to publish.

## Using it: a new machine

Boot the stick. There is no boot menu and no login prompt — the installer is
what comes up, the same one the [normal ISO](getting-started) runs, and it asks
the same questions.

The difference is what it installs. A normal ISO installs a fresh nixarchy. This
one installs **the system that built it** — the closure is on the medium, so
nothing is downloaded and nothing is compiled. That means it works on a machine
with no network at all: no wifi driver loaded, no cable to hand.

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

The image is built and reinstalled from, in a VM, on a machine that is
deliberately *not* this project's reference system — and the assertion is not
"the install worked" but that **nothing was built and nothing was fetched**:
every path came off the medium. That check runs nightly rather than on every
change, because it builds a second full image and installs from it.

What no check covers is your particular hardware. A green check says the image
reinstalls correctly in a VM; it says nothing about whether your new laptop's
wifi chip has a driver in the closure you baked. If the new machine's hardware
differs from the old one, expect to edit `hosts/<name>/hardware-configuration.nix`
after the first boot, and to rebuild — which needs a network.

## Related

- [Getting started](getting-started) — the normal installer
- [Many machines, one repo](many-machines) — one configuration, several machines
- [Your dotfiles](dotfiles) — the half this image does not carry
- [System snapshots](system-snapshots) — generations, and undoing a bad change
