---
status: approved
issue: 1093
spec: spec/2026-09-30-1093-rollback-kernel-identity.md
---

# Plan: Warn when rollback changes kernel or module builds

The rollback warning must compare the selected generation with the **booted** system before any activation. Resolve both `kernel` and `kernel-modules` under `/run/booted-system` and `$profile-$target-link` with `readlink -e`; warn when either pair differs or any path cannot be resolved. Version strings remain in the generation list but do not decide safety. A module-only NVIDIA rebuild therefore warns even when the kernel store path and version stay the same. Keep selection, `--list`, cancellation, confirmation, and switching intact. Warn rather than refuse: the user may boot the generation from the boot menu or switch and reboot promptly.

The source command is `pkgs/omarchy/nix-bin/nixarchy-rollback`, installed by `pkgs/omarchy/default.nix:1012-1019`. The current comparison is at script lines 119-133; `profile` is defined at line 28 and switching occurs at lines 135-154. `tests/options.nix:3904-3928` tests a different post-switch warning and is owned by the unpushed criticals PR. Do not edit or build it for this work; if a later integration needs it, wait until that PR merges and rebase first. No workflow changes, VM runs, or host deploys are part of this plan.

## Steps

1. `tests/rollback-kernel.nix` (new): add a cheap `runCommand` that executes the rollback source after copying it into a sandbox and replacing only the absolute booted-system and profile roots with fixture roots -> verify by `nix-instantiate --parse tests/rollback-kernel.nix`; run its behavioral red proof after step 2 registers it. Use two JSON generations with equal `kernelVersion`; stub `nixos-rebuild`, `gum`, `sudo`, and closure-diff commands, with no real profile switch. Cases: different kernel path; same kernel but different `kernel-modules` path; one unresolved path; both paths matching. Require a warning before confirmation in the first three and no warning in the matching case; refuse confirmation and assert no `sudo` call. Match behavior, not the presence of `readlink` in source. Traps: git-add the new file before flake evaluation; avoid pipelines into `grep -q`; do not write `omarchy/shell.json`.
2. `flake.nix:2264-2283`: register the new test as `checks.<system>.rollback-kernel`, passing `pkgsFor.${system}` and `./pkgs/omarchy/nix-bin/nixarchy-rollback` -> verify by `nix eval .#checks.x86_64-linux.rollback-kernel.drvPath` after staging the new test, then build that named check against the unfixed script and capture the expected same-version missing-warning failure. Traps: `nix fmt` after the `.nix` edit and inspect `git diff --stat`; the generated-checks CI step runs new checks without workflow edits.
3. `pkgs/omarchy/nix-bin/nixarchy-rollback:110-133`: replace `kernelVersion` versus truncated `uname -r` with `readlink -e` identities for booted and selected `kernel` and `kernel-modules`; treat resolution failure as a warning, not equality -> verify by `checks.x86_64-linux.rollback-kernel` passing all four fixture cases. Reword the warning so it is accurate for same-version kernels and module-only changes while retaining its reboot advice. Traps: compare `$profile-$target-link`, not `/run/current-system`; handle expected `readlink` failures under `set -euo pipefail`; coreutils `readlink` is already used by the package; keep the warning before the diff, confirmation and switch.
4. `tests/rollback-kernel.nix` and `pkgs/omarchy/nix-bin/nixarchy-rollback`: prove the check can fail twice with cp-aside restores -> verify by copying the fixed script outside the repository, replacing its comparison with the old version comparison, and building the check under the shared flock lock to capture the same-version kernel failure; restore with `cp`, then remove only the module comparison and build again to capture the module-only failure; restore with `cp` again and build a green check. Inspect the diff before each red run to ensure the break landed. Never use `git checkout` for restoration. Put both red lines and the green line in the eventual PR; remove scratch files and logs from the worktree before committing. Traps: build one at a time under `/mnt/data/vmtest/codex-build.lock`, and never pipe `nix build` to a command that masks its status.
5. `plan/2026-09-30-1093-rollback-kernel-identity.md` and changed code: commit each implementation step naming the plan step; update this plan in the same commit as any deviation -> verify by `git show --stat` and `git diff --check`. After approval and checks, open a PR against `main` using the template, link intent/spec/plan, include the captured red and green output, and say `Closes #1093`; do not merge.

## Tests

- Before any build, stage new files so the flake sees them. Use `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.rollback-kernel --print-build-logs --no-link`, once per deliberate red break and once after restoration. Capture exit statuses directly.
- After `.nix` edits run `nix fmt`, inspect `git diff --stat`, then require `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, `nix run nixpkgs#deadnix -- --fail .`, and `git diff --check` to pass.
- Confirm the check's output names the same-version kernel mismatch, module-only mismatch, unresolved-path warning, and equal-path no-warning case. The script must not call the real `sudo` or switch a host.

## Rollback

Revert this branch's implementation commits to restore the version-based warning and remove `checks.rollback-kernel`. Rollback of the code does not switch an installed machine; a user who already selected a generation can choose the previous generation from the boot menu.
