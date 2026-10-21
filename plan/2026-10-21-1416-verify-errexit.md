---
status: approved
issue: 1416
spec: spec/2026-10-21-1416-verify-errexit.md
---

# Plan: nixarchy-verify runs every check on every machine, and leftover guests and prompting Bluetooth agents stop reading as failures

Pre-approved by the owner, 2026-10-21. Covers #1416, #1417 and #1418. The
coder implements it: five files, four steps. The lead commits each step.

## Decisions (approved spec)

- **#1416:** guard the 12 lines in the spec's table with the script's own
  `|| true` (or `|| rc=$?`). Line 689 becomes
  `{ exec 8<"$dir/.lock"; } 2>/dev/null || continue`.
- **#1417:** a guest is declared if `install-microvm-$name.service` exists
  (`systemctl cat`) **or** `/nix/var/nix/gcroots/microvm/$name` exists.
  Otherwise a dangling one is `hmm "no longer declared"`.
- **#1418:** `pgrep -x blueman-applet|bluedevil|gnome-shell` before the
  pairable ✗ gives `hmm "<name> holds a prompting agent"`.
- **Checks:**
  - `checks.verify-runs`: the packaged binary, asserting the summary line,
    never the exit code;
  - `checks.verify-sections`: the `verify-boxes.nix` pattern, with both
    shapes for #1417 and #1418.

## Repo traps

- **Run the packaged binary** (`self.packages.${system}.verify`), not
  `bash pkgs/verify.sh`. The errexit lives in the wrapper.
- **Stubbing:**
  - declared runtimeInputs beat PATH stubs, so use exported bash functions
    for direct calls;
  - nothing can intercept `timeout <declared cmd>` in the packaged run.
    Those probes fail naturally with no bus or daemon, which is the
    condition being tested.
- `writeShellApplication` stubs in a `runCommand` need
  `#!${pkgs.bash}/bin/bash`. A variable named `out` clobbers `$out`.
- No `grep -q` on a pipe (`checks.grep-q-pipefail`).
- `printf`, not heredocs, inside Nix strings (§5). `nix fmt`.
- Cheap tier only, under the flock. Before any build heavier than a
  runCommand, check that no install or edge `verify` is in flight.

## Steps (coder, one at a time; stage, report, stop)

1. **`pkgs/verify.sh`: the 12 guards.**
   - No check exists yet. Verify by running the packaged
     binary in the step-2 harness environment by hand: it reaches the
     summary.
2. **`tests/verify-runs.nix` and its `flake.nix` entry** (after `explain`,
   ~:2265, passing `inherit (self.packages.${system}) verify`).
   - Red: line 472's guard reverted in a scratch copy (prove the revert
     landed), so there is no summary.
   - Green: the summary line is printed.
3. **`pkgs/verify.sh` #1417 and #1418, plus `tests/verify-sections.nix`
   and its `flake.nix` entry.**
   - The check refuses an empty `sed` extraction.
   - Reds: the declared test removed (the leftover gives ✗); the agent
     probe removed (the blueman case gives ✗).
   - Green: both shapes of each.
4. **`modules/AGENTS.md:599-600`:** the confirmation sentence (#1418).

## Lead

- The full generated list, with CI idle, then the PR (`Closes #1416`,
  `closes #1417`, `closes #1418`, each keyword repeated, §8).
- After merge, the owner re-runs `nixarchy-verify` on p620 (hardware row).

## Rollback

Revert the PR. verify aborts again, and misreports p1 and Bluetooth.
