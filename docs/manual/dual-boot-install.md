---
title: Dual boot install
---

# Dual boot install

There is no nixarchy installer, so there is no dual-boot installer either.

Omarchy ships an ISO whose installer offers a **Free space install** next to
Windows, encrypts the partition with LUKS, and then runs `limine-scan` to add
the other operating systems to its bootloader.

**nixarchy has the ISO now, but not the free-space install.** Its installer
formats a whole disk — that and nothing else. Installing alongside Windows is
[issue #47](https://github.com/olafkfreund/nixarchy/issues/47), and it is the
one piece of this work whose failure mode is destroying data that is not ours,
so it is being done carefully rather than quickly. Until it lands, this page
cannot honestly say more than the following.

## What to do instead

1. **Make room on the Windows side** exactly as upstream describes — Disk
   Management, *Shrink Volume*, and turn BitLocker off first, since it encrypts
   the whole drive rather than a partition. That half of
   [the upstream page](https://omarchy.org/manual/dual-boot-install/) is about
   Windows, not Omarchy, and applies unchanged.

2. **Install NixOS into the free space** by whichever method you prefer. The
   NixOS installer supports installing alongside an existing operating system;
   partitioning and bootloader setup for that are covered by the NixOS manual,
   and this manual does not repeat them.

3. **Add nixarchy as a flake input** to the resulting configuration and
   rebuild. That is the whole of the nixarchy-specific work, and it is
   described on [the getting-started page](getting-started).

Dual boot is therefore a NixOS question, and the NixOS manual and wiki are the
right references for it. Once the machine boots into NixOS, nothing about
adding nixarchy is different for having Windows on the next partition.
