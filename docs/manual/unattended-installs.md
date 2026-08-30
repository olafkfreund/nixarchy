---
title: Unattended installs
---

# Unattended installs

There is no nixarchy installer, so there is no unattended installer either.

Omarchy's ISO watches for a second drive labelled `cidata`, reads the wizard's
answers off it, and installs with nobody at the keyboard — which makes it a
good base image for disposable VMs.

**nixarchy has the answers file but not yet the drive.** `nixarchy-install
--answers <file>` takes every answer the wizard asks for and installs with
nobody at the keyboard — one `key=value` per line, parsed rather than sourced,
and it names every missing key in one go instead of one per attempt:

```ini
device=/dev/vda
encrypt=yes
luks_passphrase=correct horse
hostname=nixarchy
username=alice
password_hash=$6$...        # from `mkpasswd -m sha-512`; or
password=hunter2            # plaintext, hashed by the installer
timezone=Europe/London
keymap=us
```

What is missing is the `cidata` half: the ISO does not yet look for a labelled
drive and feed itself from it. That is
[issue #14's follow-up](https://github.com/olafkfreund/nixarchy/issues/14) —
the code path exists and only the detection is absent.

## What to do instead

The honest answer is that unattended provisioning is a NixOS problem with
mature NixOS solutions, and nixarchy sits on top of whichever you pick:

- **[disko](https://github.com/nix-community/disko)** describes the disk
  layout declaratively, so partitioning and formatting are part of the
  configuration rather than a wizard step.
- **[nixos-anywhere](https://github.com/nix-community/nixos-anywhere)**
  installs a NixOS flake configuration onto a remote machine over SSH, using
  disko for the disks. Point it at a VM or a bare host booted into any Linux
  with SSH, and it comes back as the system your flake describes.

Add nixarchy as an input to that flake before the first install and the
machine arrives with the desktop already declared — there is no second step
to automate, because the flake is the whole description. How to add the input
is on [the getting-started page](getting-started).

This is also why the gap is smaller than it looks. Upstream's `cidata` drive
exists to feed answers to an imperative wizard: a disk, a hostname, a user, a
password hash, SSH keys. In a NixOS flake every one of those is already a line
in a file, and the file is what nixos-anywhere ships. What nixarchy is missing
is the boot medium, not the unattended part.
