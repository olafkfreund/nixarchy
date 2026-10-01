---
status: draft
issue: 1120
spec: spec/2026-09-30-1120-installer-keymaps.md
---

# Plan: Offer only available installer console keymaps

The pinned `kbd` 2.9.0 package contains 43 of the 45 keymaps in
`installer/brand/keymaps.txt`; `ara` and `th-tis` are absent. The owner chose
to remove those two menu rows without a Latin fallback. The wizard reads
that file at `installer/install.sh:24,621-627`, ignores a failed `loadkeys`,
and writes the choice to `console.keyMap` through
`installer/install.sh:1486` and `installer/template/host/configuration.nix:15`.
The unattended path's `validate_keymap` at `installer/install.sh:681-688`
already accepts real and symlinked maps and stays unchanged. The console
menu and Hyprland XKB configuration are separate; upstream Omarchy's menu
also omits Arabic and Thai. Do not remap labels, add custom maps, or change
desktop input settings. A file-existence check cannot prove a physical
keyboard layout, but it catches a missing map before installation.

## Steps

1. `tests/installer-keymaps.nix`: add a cheap `pkgs.runCommand` that reads
   every nonempty tab-separated row of the shipped menu, rejects malformed
   rows and an empty menu, and requires a non-dangling regular or symlinked
   `<name>.map.gz` under the passed `kbd/share/keymaps` -> verify by a
   missing-map error naming both label and name. Use the package tree rather
   than a second list of valid names. A failed `find` must fail the check;
   capture output and status rather than masking them with process
   substitution. Avoid `producer | grep -q` under `pipefail`.
2. `flake.nix:2024-2027`: register `checks.installer-keymaps` beside the
   installer checks and pass `./installer/brand/keymaps.txt` plus
   `pkgsFor.${system}.kbd`, the same package substituted into the installer
   at `flake.nix:965-987` -> verify by building the check against the
   *unfixed* menu; it must fail for `Arabic/ara` and `Thai/th-tis`. Stage the
   new test file with `git add` first, because a flake cannot see an
   untracked file. Build under `flock /mnt/data/vmtest/codex-build.lock`.
   This runCommand is cheap under the owner waiver; before any later
   non-cheap build, require
   `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
   to print exactly `0`.
3. `installer/brand/keymaps.txt:6,43`: delete the two unsupported rows;
   leave the other 43 choices intact -> verify by rebuilding
   `checks.installer-keymaps` green, with a count of 43 resolved rows.
   `installer/install.sh` and the generated host remain unchanged.
4. `installer/brand/keymaps.txt` and `tests/installer-keymaps.nix`: prove
   the finished check can fail independently of the original two rows ->
   verify by copying the good menu to
   `/mnt/data/vmtest/1120-keymaps.good`, appending a row such as
   `Missing proof<TAB>surely-no-such-keymap`, and rebuilding the check red.
   Confirm the log names that label and keymap, restore with
   `cp /mnt/data/vmtest/1120-keymaps.good installer/brand/keymaps.txt`
   (never `git checkout`), then rebuild green. Keep logs outside the
   worktree and paste the key red and green lines into the PR. Use a shell
   `trap` to restore the file even if a proof command fails.
5. `flake.nix` and `tests/installer-keymaps.nix`: format and lint the Nix
   edits -> verify by `nix fmt`, `git diff --stat`,
   `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and
   `nix run nixpkgs#deadnix -- --fail .`. Commit each implementation step
   with its step number in the subject. Record any deviation in this plan
   in the same commit as the code.

## Tests

- The original 45-row menu makes `checks.installer-keymaps` red for exactly
  `ara` and `th-tis`; the corrected 43-row menu makes it green. The fake
  row makes it red again, and restoring the menu returns it to green.
- Use `flock /mnt/data/vmtest/codex-build.lock nix build --no-link
  .#checks.x86_64-linux.installer-keymaps` for each build, one at a time.
  The check is a cheap runCommand; do not run a VM or `checks.options`
  locally. Check CI load before any non-cheap build if scope expands.
- `nix fmt -- --ci`, statix, deadnix, `git diff --check`, and a final clean
  `git status` must pass. After each `.nix` edit run `nix fmt` and inspect
  `git diff --stat` before the check.
- This scope changes no `writeShellApplication` source. If it changes one,
  build the package itself as well as any extracted-function check:
  `tests/AGENTS.md` records that function checks skip package ShellCheck.
- Put the red and green output in the PR, link intent/spec/plan, and use
  `Closes #1120`. Do not change workflows or merge the PR.

## Rollback

Revert the implementation commits to restore the menu and remove the
check. Any proof-time menu edit is restored from the copy in
`/mnt/data/vmtest`; it is never discarded with `git checkout`.
