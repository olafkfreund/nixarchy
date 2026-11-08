---
status: approved
issue: 1686
spec: spec/2026-11-08-1686-try-disk-minimum.md
coders:
  1: codex  # launcher argument order: a size check placed after --fresh would wipe a disk
  2: codex  # a number-extraction check that must fail loudly on every miss, in a Nix '' string
  3: codex  # an EXIT trap in a set -e script, with a phase boundary
  4: codex  # a pty-driven stub harness whose breaks must really fail
reviewers:
  - codex  # small, tricky shell where an off-by-one is a wiped disk
  - agy    # an independent read of the same diff
---

# Plan: the try-it launcher's disk meets the installer's minimum, and a refusal stays on screen

## Decisions carried from the approved spec

1. `installer/try-nixarchy.sh` defaults to 64 GB
   (`DISK_GB=${NIXARCHY_TRY_DISK:-64}`). The usage text and the space
   preflight already follow `$DISK_GB`.
2. A `NIXARCHY_TRY_DISK` under the floor is refused right after argument
   parsing, before `--fresh` deletes anything. The launcher carries the
   floor as a literal (`MIN_DISK_GB=32`), with a comment naming
   `installer/install.sh`'s `MIN_DISK_GIB`. It is a standalone download and
   cannot source the installer.
3. An existing undersized `$DISK` gets a refusal naming its size and the
   floor, and still offers `--boot` and `--fresh`. The size comes from
   `qemu-img info`'s plain `virtual size: ... (N bytes)` line, via `sed`;
   no jq. Unreadable output falls back to today's message.
4. A check compares, by number: `MIN_DISK_GIB`, the launcher default (which
   must equal 64), the launcher's floor literal (which must equal
   `MIN_DISK_GIB`), `installer/try.sh`'s `DISK_MB`, and `installer/vm.nix`'s
   `emptyDiskImages` size (passed in by evaluation, not grepped). Any value
   that cannot be read fails by name.
5. `install.sh` sets one EXIT trap after the greeter and clears it at
   `ui_dashboard_start`. On a non-zero exit, and only if `ui_interactive`,
   it prints "The installer stopped before writing to any disk." and "Press
   Return for a root shell.", reads a line, and `exec bash --login`. The
   systemd unit in `installer/cd.nix` is untouched.

## Steps

1. **Launcher** — `installer/try-nixarchy.sh`:
   - line 25: default 24 → 64; add `MIN_DISK_GB=32` beside it, with a
     one-line comment naming `MIN_DISK_GIB` in `installer/install.sh` and
     the check that keeps them equal.
   - After the argument loop ends (line 51), before anything at line 194
     touches `$DISK`: refuse `DISK_GB < MIN_DISK_GB` with
     "NIXARCHY_TRY_DISK=$DISK_GB is under the installer's $MIN_DISK_GB GB
     minimum." Also refuse a non-integer value.
   - Lines 200-203, the existing-disk refusal: when
     `qemu-img info "$DISK"` yields a byte count under the floor, prefix
     "$DISK is N GB, under the installer's 32 GB minimum. --fresh wipes it
     and creates a 64 GB disk.". Otherwise print today's text.

   Verify: `shellcheck installer/try-nixarchy.sh`, and step 4's launcher
   cases.
   Traps: `set -u` holds in this script, so test the parse with
   `[[ $DISK_GB =~ ^[0-9]+$ ]]` before any arithmetic. `qemu-img` may be
   absent before the dependency check runs, so place the existing-disk read
   after that check.

2. **The number check** — `tests/try-nixarchy.nix` gains an argument
   `vmTargetMiB`, and `flake.nix` (near line 1931, where the check is
   wired) passes `nixosConfigurations`' VM `virtualisation.emptyDiskImages`
   head `size` from `installer/vm.nix:147`. The check body:
   - reads `MIN_DISK_GIB` from `${../installer/install.sh}` (`^MIN_DISK_GIB=`),
     the default and `MIN_DISK_GB` from the launcher, and `DISK_MB` from
     `${../installer/try.sh}`;
   - fails by name on any empty read ("could not read MIN_DISK_GIB from
     install.sh") before comparing;
   - asserts the default is 64, `MIN_DISK_GB` equals `MIN_DISK_GIB`,
     `DISK_MB / 1024 >= MIN_DISK_GIB`, and `vmTargetMiB / 1024 >= MIN_DISK_GIB`.

   Verify: build passes. Four §1 breaks, one at a time: the default set to
   32, `MIN_DISK_GB=30`, `DISK_MB=24576`, and `vm.nix` size 24576. Each
   fails naming its file. Capture all four.
   Traps: §5, a heredoc inside the `''` string reindents the file, so use
   `printf`. `out=$(cmd) || exit` and never `mapfile < <(...)` (§4). Find
   where `flake.nix` already reaches the VM configuration (the
   `installer-*` checks do); do not evaluate a second machine for one
   number.

3. **The hold** — `installer/install.sh`:
   - a function `early_exit_hold` (global state only; §5 says an EXIT trap
     reads its variables at exit time): when `$?` is non-zero and
     `ui_interactive`, print the two lines from decision 5 to stdout, then
     `read -r _ || true` and `exec bash --login`;
   - `trap early_exit_hold EXIT` immediately after each `ui_greeter` call
     (lines 2964 and 2970), and `trap - EXIT` as the first line before
     `ui_dashboard_start "$log"` (line 3091), whose own EXIT trap (line 3079
     comment) takes over.

   Verify: step 4's installer cases.
   Traps: the EXIT trap must capture `$?` on its first line, before any
   other command resets it. `set -e` is on, so the trap body must not fail
   (`|| true` on the read). Grep for any other `trap ... EXIT` between the
   greeter and line 3091 (line 1243 sets one inside a function, for
   `answers_fetched`). If a trap there replaces ours, chain it rather than
   lose either.

4. **Probes**:
   - `tests/try-nixarchy.nix`: the `qemu-img` stub answers `info` with a
     `virtual size: 24 GiB (25769803776 bytes)` line when a marker file
     says so, and fails otherwise. Three cases: an existing 24 GB disk
     gets the undersized message; an unreadable `info` gets today's
     message; `NIXARCHY_TRY_DISK=24 ... --fresh` is refused and
     `test -f "$DISK"` still holds.
   - A new `tests/installer-early-exit.nix`, wired in `flake.nix` beside
     `installer-disk-list` (line 2265). It runs the **real** `install.sh`
     entry under `script -qec` (util-linux, so stdin is a pty), with
     the greeter's Return on stdin and stubs from `installer-disk-list.nix`'s
     `lsblk` pattern listing only a 24 GiB disk. It asserts "no disk large
     enough" and the hold prompt both appear. Three more runs: `--answers`
     set gives no prompt; stdin from `/dev/null` gives no prompt; a stubbed
     failure after `ui_dashboard_start` gives no hold prompt.

   Verify: both build. §1: delete the `trap early_exit_hold EXIT` lines, and
   the first assertion fails. Move the `trap - EXIT` below
   `ui_dashboard_start`, and the boundary case fails. Capture both.
   Traps: the sandbox has no `/usr/bin/env`, so `patchShebangs` the stubs
   (#1670). Whatever `install.sh` calls before `ask_device` (network probe,
   `nix config show`) needs a stub. Read the real call order first rather
   than stubbing by guess.

5. **Run, commit, PR** (session): `nix fmt -- --ci`, statix, deadnix,
   `checks.grep-q-pipefail`, `checks.try-nixarchy`,
   `checks.installer-early-exit`, `checks.installer-disk-list` (cheap,
   under the build lock). Then `checks.installer-refusal` (VM tier, when no
   runner is busy). Commit each step separately. Open the PR with
   `Closes #1686` and a "@codex review" comment, merged with
   `--auto --merge --delete-branch`.

## Tests

| check | tier | expect |
|---|---|---|
| `try-nixarchy` | cheap | pass; four §1 breaks fail by name |
| `installer-early-exit` (new) | cheap | pass; trap removal and boundary breaks fail |
| `installer-disk-list` | cheap | unchanged, pass |
| `installer-refusal` | VM | pass (an early refusal on a real ISO; it runs with `--answers`, so no hold) |
| fmt, statix, deadnix, `grep-q-pipefail` | cheap | pass |

Not run locally: the `install` job (CI only, an install slot).

## Rollback

Revert the PR. The launcher's old default comes back, the trap goes, and
nothing installed is affected: only the ISO and the launcher change.
