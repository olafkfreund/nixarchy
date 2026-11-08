---
status: draft
issue: 1686
intent: intent/2026-11-08-1686-try-disk-minimum.md
---

# Spec: the try-it launcher's disk meets the installer's minimum, and a refusal stays on screen

## Design

### 1. The default (intent decision 1)

`installer/try-nixarchy.sh:25` becomes `DISK_GB=${NIXARCHY_TRY_DISK:-64}`.
The usage text (line 46) already prints `$DISK_GB`, so it follows. The space
preflight (lines 145-147) already asks for `DISK_GB + image_gb` and needs no
edit.

A `NIXARCHY_TRY_DISK` below the installer's floor is refused before
`qemu-img create`, with the floor named: `NIXARCHY_TRY_DISK=$DISK_GB is under
the installer's 32 GB minimum`. The floor is a literal in the launcher with
a comment naming `MIN_DISK_GIB`; the check in section 3 is what keeps the
two equal. The launcher is a standalone download (the release asset), so it
cannot source `install.sh`.

### 2. An existing undersized disk (decision 4)

Where the launcher refuses an existing `$DISK` (lines 200-203), it first
reads the image's virtual size (`qemu-img info --output=json`,
`.["virtual-size"]`). When that is under the floor, the refusal says so:
`$DISK is 24 GB, under the installer's 32 GB minimum. --fresh wipes it and
creates a 64 GB disk.` `--boot` stays offered, because a disk that already
holds an install boots whatever its size. A `qemu-img info` failure falls
back to today's message.

### 3. The check (decision 3)

`tests/try-nixarchy.nix` gains a block that extracts three numbers and
fails when either VM number is under the floor:

- `MIN_DISK_GIB` from `installer/install.sh` (`^MIN_DISK_GIB=`),
- the launcher's default from `try-nixarchy.sh` (`NIXARCHY_TRY_DISK:-N`),
- the launcher's own floor literal from section 1, which must equal
  `MIN_DISK_GIB`,
- `installer/vm.nix`'s install target, read by evaluation rather than by
  grep: `emptyDiskImages`'s first `size` in MiB, divided by 1024.

Each number that cannot be extracted fails the check by name ("could not
read MIN_DISK_GIB"). A failed extraction must not read as zero, and zero
must not read as a pass (§4, `mapfile` and empty lists). The `vm.nix`
number is passed into the derivation from `flake.nix`, where the VM
configuration is already in scope, rather than grepped.

### 4. Holding the screen on an early exit (decision 2)

`installer/install.sh` gets one EXIT trap, set right after the greeter and
cleared where the dashboard's own failure handling takes over (the first
`ui_dashboard_start`). On a non-zero exit, and only when `ui_interactive`
is true, it prints:

```text
The installer stopped before changing anything.
Press Return for a root shell.
```

It then reads one line and `exec`s `bash --login` on the same TTY. An
unattended run (`--answers`, `nixarchy.answers=`) or a non-TTY stdin skips
the hold and exits as today, so no automated install can stall on it.

The trap uses a global and expands nothing late (§5, an EXIT trap reads its
variables at exit). The unit in `installer/cd.nix` is not changed: the
`conflicts` line and the TTY settings stay load-bearing as documented, and
`Restart = "no"` still holds because the shell is the same process.

The installer already prints its refusals to stderr before exiting. The
hold keeps them on screen, because nothing clears the VT until the unit
stops, and the unit does not stop while the shell runs.

## Alternatives rejected

- **32 GB default.** It is the floor, and an install writes about 16 GiB, so
  the user's first rebuild could fill it. 64 is what the reporter proved,
  and it is sparse on disk.
- **Sourcing `MIN_DISK_GIB` from `install.sh` in the launcher.** The
  launcher is downloaded on its own and has no tree to source from.
- **Changing the unit** (dropping `TTYVTDisallocate`, or starting a getty
  when the installer stops). That reaches every exit, the successful one
  included, and it reopens the getty-over-TUI race the `conflicts` line
  closed three times.
- **Holding on every exit, success included.** Success already reboots or
  says so through the dashboard.

## Risks

- **Host space:** a 64 GB default asks for 64 GB plus the image free under
  the launcher's work directory, on a laptop that had room for 24. The
  preflight already refuses with the number, and `NIXARCHY_TRY_DISK=32`
  still works.
- **A trap firing in the wrong phase.** If it were left set into the
  dashboard, a failure would show two screens. It is cleared at
  `ui_dashboard_start`, and the probe asserts both sides.
- No effect on an installed system. Only the ISO's installer and the
  launcher change.

## Verification

- `checks.try-nixarchy`, built locally (cheap tier): passes. §1 break:
  default back to 24 fails it, naming the launcher. Floor literal 30 fails
  it. `emptyDiskImages` size 24576 fails it. Each break is shown with
  `git diff`, and the failing output goes in the PR.
- `checks.installer-disk-list` (or a sibling stubbed `runCommand`) runs
  `ask_device` under `script -qc` (a pty, so `-t 0` is true) with a stubbed
  `lsblk` listing only a 24 GiB disk, and asserts the output carries "no disk
  large enough" **and** the hold prompt. The same run with `--answers` set
  asserts there is no prompt. §1 break: the trap removed fails the first
  assertion.
- A launcher stub run (`tests/try-nixarchy.nix` already stubs qemu) with an
  existing 24 GB `$DISK` asserts the undersized-disk message.
- VM tier when the gate is free: `checks.installer-refusal`, because it
  exercises an early refusal on a real ISO and must stay green.
- `nix fmt -- --ci`, statix, deadnix, `checks.grep-q-pipefail`.
