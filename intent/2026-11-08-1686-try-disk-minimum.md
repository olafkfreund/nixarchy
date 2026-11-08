---
status: approved
issue: 1686
author: olafkfreund
---

# Intent: the try-it launcher's disk meets the installer's minimum, and a refusal stays on screen

## Problem

`installer/try-nixarchy.sh` creates a 24 GB virtual disk by default
(`DISK_GB=${NIXARCHY_TRY_DISK:-24}`, line 25). The installer refuses any disk
under `MIN_DISK_GIB=32` (`installer/install.sh:962`, from #708), so the
launcher's own default can never install. A tester on v4.5.0-1 hit exactly
that.

The refusal itself is invisible. `ask_device` prints "no disk large enough"
to stderr and exits 1 (`installer/install.sh:849-856`). The unit that runs it
(`installer/cd.nix:312-350`) has `Restart = "no"`, `TTYVTDisallocate = true`
and conflicts with `getty@tty1`, so the VT is cleared on exit and nothing
takes the screen back. The tester saw a blank screen with a blinking cursor
and could report only that.

Two constants that must agree live in two files with nothing comparing them
(CLAUDE.md §4, "a hand-maintained list fails open").

## Proposed outcome

- The launcher's default disk installs: it is at least the installer's
  minimum, with headroom for the store.
- A check fails if the launcher's default (or any other VM launcher default
  in the tree) drops below `MIN_DISK_GIB`.
- When the installer exits before its own failure screen can run
  (`ui_failed` already covers failures during the install, `install.sh`
  ~3042), its last message stays readable on tty1, and the user has a way to
  a shell. `ask_device`'s refusal is the known case.
- A tester who already has a 24 GB disk is told why it cannot install.
  Today the launcher refuses an existing disk and offers `--boot` or
  `--fresh` (`try-nixarchy.sh:194-203`), and neither says the disk is too
  small.

## Affected users and systems

- Anyone using `try-nixarchy.sh` with its default, i.e. first-time testers.
- Everyone booting the ISO on a machine where the installer exits early
  (small disk, no disk, a refusal), not only VMs.
- `installer/try-nixarchy.sh`, `installer/cd.nix`, `tests/try-nixarchy.nix`
  or a sibling check.

## Constraints

- The installer must keep owning tty1 while it runs; the `conflicts` line
  exists because a getty drew over the TUI three times (`cd.nix:308-311`).
- A finished, aborted or crashed installer must not respawn the TUI in a
  loop (`Restart = "no"`'s reason).
- The launcher's space preflight (`try-nixarchy.sh:145-147`) grows with the
  default, so a larger default asks for more free space on the host.
- §1: the new check is proven to fail with the default set back to 24.
- §3: the screen fix needs a probe that can see it, at the cheapest layer
  that can (the refusal path in a VM, or a stubbed run).

## Decisions (owner, 2026-11-08)

1. The launcher defaults to 64 GB: what the tester proved installs, with room for a first rebuild. The space preflight asks for it, and `NIXARCHY_TRY_DISK` still lowers it to the floor.
2. The installer holds its own screen on an early exit (a "press Return for a shell" prompt), only when interactive (`ui_interactive`). The unit's `conflicts` and TTY settings stay as they are.
3. The new check covers the launcher default and `installer/vm.nix`'s install target (`emptyDiskImages`), both against `MIN_DISK_GIB`.
4. An existing undersized disk gets a refusal that names its size and the minimum.

## Open questions (as drafted)

1. Default size: 32 (the floor), or 64 (what the tester used)? The qcow2 is
   sparse, but the launcher's preflight asks for the full size free. An
   install writes a 2G ESP and about 14 GiB of closure (`vm.nix:140-143`),
   so 32 fits with little room for the user's first rebuild.
2. Keeping the message: hold the screen in the installer (a "press Return
   for a shell" prompt on every early exit), or change the unit (drop
   `TTYVTDisallocate`, or start a getty on tty1 when the installer stops)?
3. Should the new check also cover `installer/vm.nix`'s install target
   (`emptyDiskImages[0].size = 32768`, line 147; `diskSize` sizes the VM's
   own disk, not the target), or only the launcher?
4. A screen hold must not stall an unattended install: the ISO takes
   `nixarchy.answers=` on the kernel command line (`cd.nix:81-87`). Hold only
   when interactive?
