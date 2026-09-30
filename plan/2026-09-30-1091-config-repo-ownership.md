---
status: approved
issue: 1091
spec: spec/2026-09-30-1091-config-repo-ownership.md
---

# Plan: Keep generated config repo files owned by the repository user

The installer gives the installed user ownership of `/etc/nixos` (`installer/install.sh:2021-2062`). `nixarchy-config-repo` already elevates git writes only when needed, but unconditionally uses `sudo tee` for `.gitignore` and both CI templates and `sudo mkdir` for a CI parent. On a user-owned flake these writes must run as the user without a sudo prompt. Detect a legacy unwritable flake with `! -w "$FLAKE"`, matching the existing `wgit` writability model at `pkgs/omarchy/nix-bin/nixarchy-config-repo:88`; only that state permits sudo when a destination needs it. A writable flake with an unwritable, previously root-owned subdirectory fails with a clear ownership diagnosis; do not silently elevate or chown it. Preserve the managed-install refusal, the existing `wgit`/`wcommit` flow, all prompts, and the exact generated GitHub/GitLab CI content.

## Steps

1. `pkgs/omarchy/nix-bin/nixarchy-config-repo:80-103,570-598,725-766`: add the smallest write and directory helpers. For each target, use the actual destination or nearest existing parent to decide whether the caller can write. Write directly when possible; if not, use sudo only when `! -w "$FLAKE"`. Otherwise report the unwritable path and stop. Replace only the three `sudo tee` calls and the CI `sudo mkdir`; do not chown anything or change the generated heredocs, managed gate, git helper, or prompts. -> Verify by `checks.config-repo-ownership` writable-flake, legacy-unwritable-flake and mixed-ownership fixtures. Traps: this script is installed unwrapped with `install -Dm755`, so there is no `writeShellApplication` runtimeInputs change; test nested `.github/workflows` independently of `.git`.
2. `tests/config-repo-ownership.nix`: add a cheap `runCommand` that runs a copy of the actual script in sandbox repositories. Replace only its fixed `/etc/nixarchy/managed` marker path in the test copy; set a sandbox `HOME` and git identity, stub `omarchy-done`, `gum`, and `sudo`, and push only to a local bare remote whose path contains `github.com` or `gitlab` so the script chooses each existing template. Fail if sudo is called for a writable flake; check the generated files and parent are caller-owned, contents are unchanged, and a pre-existing file stays byte-identical. Simulate the legacy case with `chmod a-w` on the flake (the build sandbox cannot create actual root ownership), and record necessary elevation; make a writable flake's existing CI parent unwritable and require an actionable refusal with no chown. -> Verify by `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.config-repo-ownership --print-build-logs --no-link`. Traps: no network push, no `/etc/nixos` write, no producer piped into `grep -q`, and no `omarchy/shell.json` fixture.
3. `flake.nix:2275-2305`: register `checks.config-repo-ownership` with `pkgs` and the source script passed explicitly. -> Verify that the check derivation evaluates, then build only that check. Traps: stage the new test before flake evaluation; generated CI check registration needs no workflow edit.
4. `pkgs/omarchy/nix-bin/nixarchy-config-repo`, `tests/config-repo-ownership.nix`: prove the check fails. Copy the fixed script aside under `/mnt/data/vmtest/`, temporarily restore the old unconditional `sudo tee`/`sudo mkdir` calls, inspect the diff to confirm the break landed, run the check and capture its explicit user-owned-fixture failure. Restore the script with `cp`, never `git checkout`, and run the check again to capture green output. -> Verify by one red and one green `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.config-repo-ownership --print-build-logs --no-link`; include the red line in the PR. Traps: do not pipe build status through `tail`; keep proof logs outside the repo and remove them before committing.
5. `pkgs/omarchy/nix-bin/nixarchy-config-repo`, `tests/config-repo-ownership.nix`, `flake.nix`: review the final diff and run `nix fmt`, `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and `nix run nixpkgs#deadnix -- --fail .`. -> Verify by clean formatter/linter exits and `git diff --check`; inspect `git diff --stat` after the `.nix` edits. Traps: do not run local VM checks or `checks.options`; do not edit `tests/options.nix` or the criticals PR's installer/microVM files. Name the plan step in implementation commits; if implementation must differ, update this plan in the same commit as the code.

## Tests

- `checks.config-repo-ownership` fails on the deliberately restored unconditional sudo path and passes on the fix, with separate writable-flake GitHub, GitLab, pre-existing-file, chmod-unwritable legacy, and mixed-ownership cases.
- `nix fmt -- --ci`, statix, deadnix, and `git diff --check` pass after the `.nix` changes.
- No VM run or local `checks.options`. The new check is a cheap `runCommand` registered in `flake.nix`, so the existing generated-checks CI path picks it up without a workflow change.

## Rollback

Revert the implementation commits on the branch. That restores the original unconditional sudo writes; it does not change files or ownership in any user's existing flake. Leave the intent, spec, and plan history as the audit trail.
