---
status: draft
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
- When the installer exits before installing, for any reason, its last
  message stays readable on tty1, and the user has a way to a shell.

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

## Open questions

1. Default size: 32 (the floor), or 64 (what the tester used)? The qcow2 is
   sparse, but the launcher's preflight asks for the full size free.
2. Keeping the message: hold the screen in the installer (a "press Return
   for a shell" prompt on every early exit), or change the unit (drop
   `TTYVTDisallocate`, or start a getty on tty1 when the installer stops)?
3. Should this one PR also cover `installer/vm.nix` (`diskSize = 32768`,
   exactly at the floor) in the new check, or only the launcher?
