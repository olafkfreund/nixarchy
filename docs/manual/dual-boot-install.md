---
title: Dual boot install
---

# Dual boot install

The nixarchy installer offers two disk modes, the way Omarchy's does:

- **Full disk install** — the disk is nixarchy's, and everything on it is gone.
- **Free space install** — nixarchy goes into the largest unpartitioned region
  on the disk, and every partition already there is left exactly as it was.

The second screen only appears when it can. On a disk with no partitions there
is nothing to install beside, so the question is not asked at all.

## Before you start

**Shrink Windows from inside Windows.** Disk Management, *Shrink Volume*, and
leave at least 32 GiB unallocated — that is the floor the installer enforces,
and it is a floor rather than a recommendation: a desktop with a Nix store in
it is not comfortable below it. That half of
[the upstream page](https://omarchy.org/manual/dual-boot-install/) is about
Windows, not Omarchy, and applies unchanged here.

**Turn BitLocker off first.** The installer refuses a free-space install on a
disk BitLocker is holding, and the reason is worth knowing rather than working
around: nothing nixarchy does would touch the encrypted volume, but the install
adds an EFI boot entry and changes the boot order, and BitLocker measures the
boot chain. The next boot of Windows asks for a recovery key. If you have it,
you lost an afternoon. If you do not — and most people do not — the data is
gone as surely as if the disk had been formatted.

**Back up anyway.** This is a partitioning operation on a disk holding somebody
else's operating system. It is tested — `nix build .#checks.x86_64-linux.free-space`
installs onto a disk carrying a Windows-shaped ESP and data partition and
asserts both come out byte-identical — but a tested operation and a safe one
are different claims, and the second one is not available.

## What it does

1. Finds the largest unpartitioned region with `sgdisk`, and requires 32 GiB.
2. Cuts two partitions out of it with `sgdisk --new=0:`, where `0` is sgdisk's
   own *next free partition number* — so a new partition can never be given a
   number that is already in use.
3. Formats **only those two**, mounts them and installs, exactly as the
   whole-disk mode does.

nixarchy gets its own 2 GiB ESP. It does not adopt the ESP Windows is using,
even when there is one and it would technically work, which is also what
Omarchy does. An ESP nixarchy created is one it is allowed to write to; an ESP
somebody else created is not.

## What it does not do

**It does not add Windows to the boot menu.** Omarchy runs `limine-scan` for
this; nixarchy's bootloader is systemd-boot, which does not scan. Both
operating systems are installed and bootable, and you choose between them from
your firmware's boot menu (usually F12, F11 or Esc at power-on). Adding a
systemd-boot entry for Windows by hand is a few lines in your configuration and
is a NixOS question rather than a nixarchy one.

**It does not shrink anything.** The free space has to be free before you
start. The installer will not resize a partition, and that is deliberate: a
resize is the operation in this whole area most likely to lose data, and it has
a much better tool on the Windows side.

**It does not describe your partition table.** The `disk-config.nix` in the
flake it writes addresses two partitions by label — `nixarchy-esp` and
`nixarchy-root` — and declares no partition table at all. That is what keeps
disko from ever reaching a partition nixarchy did not create, and the cost is
that the file cannot rebuild your disk. Running disko against it on a wiped
disk produces nothing. The file says so at the top; read it before assuming
otherwise.
