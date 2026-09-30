---
status: draft
issue: 1109
spec: spec/2026-09-30-1109-config-repo-git-hint.md
---

# Plan: Show Git commands that match repository ownership

`nixarchy-config-repo` already uses `wgit` for its own writes. Its closing manual hint alone always says `sudo git`, risking root-owned `.git` objects in a user-owned repository. Use precisely `-w "$FLAKE/.git"`, the `wgit` predicate, to choose plain `git` or `sudo git` for the printed add, commit, and push commands. Keep the manual workflow, menu backup text, `--drift`, and actual Git operations unchanged. Do not substitute `$FLAKE` writability: the metadata is the write target. Extend the existing cheap ownership check; do not add a new check or change `flake.nix` or `tests/options.nix`.

## Steps

1. `pkgs/omarchy/nix-bin/nixarchy-config-repo:827-836`: choose one display prefix from `[ -w "$FLAKE/.git" ]` and use it in the existing add/commit and push hints -> verify by `bash -n pkgs/omarchy/nix-bin/nixarchy-config-repo` and Step 2's output assertions. Preserve the menu and `--drift` text. Name Step 1 in the implementation commit.
2. `tests/config-repo-ownership.nix:16-28,49-65,82-90`: reuse the built script and existing writable/legacy fixtures. Strip ANSI styling from each saved output file, then match the **whole** indented add/commit and push command lines exactly: plain `git` in the writable case, `sudo git` in the legacy case. Also assert no `sudo git` appears anywhere in the writable output. A substring search for `git push` would incorrectly pass on `sudo git push`. Make the legacy fixture's `.git` directory non-writable as well as `$FLAKE`, and let its sudo stub temporarily enable writes to both -> verify by `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.config-repo-ownership --print-build-logs`. Name Step 2 in the implementation commit. After the `.nix` edit, run `nix fmt`, inspect `git diff --stat`, and stage it so the flake sees the edit. Avoid `producer | grep -q` under pipefail; inspect the saved output file directly.
3. `tests/config-repo-ownership.nix` and `pkgs/omarchy/nix-bin/nixarchy-config-repo`: prove the new assertions fail -> verify by copying the good script to `/mnt/data/vmtest/1109-config-repo-good`, temporarily restoring the old unconditional `sudo git` hint, and building the same check under the shared lock. Require a nonzero exit and an explicit writable-hint failure; capture that line for the PR. Restore with `cp /mnt/data/vmtest/1109-config-repo-good pkgs/omarchy/nix-bin/nixarchy-config-repo` (never `git checkout`) and rebuild under the lock to green. Also break the legacy branch by temporarily printing plain `git` there, require the legacy assertion to fail, then restore by `cp` and recheck green. Remove the saved copy. Name Step 3 in the implementation commit if it changes tracked files; otherwise record the proof in the PR.

## Tests

- Run `bash -n` on the script.
- The locked `config-repo-ownership` check must show a red result for each deliberately broken hint and green after restoration. Exact whole-line matches must prove plain add/commit and push guidance in the writable fixture and their `sudo` forms in the legacy fixture; the writable output must have no `sudo git` anywhere. Existing setup and ownership assertions must stay green.
- Run `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, `nix run nixpkgs#deadnix -- --fail .`, and `git diff --check` before publishing. Scan the changed lines for `| grep -q` and writes to `omarchy/shell.json`.
- No VM or `checks.options` run. No change to the criticals PR's forbidden files.

## Rollback

Revert the script and check commits together. This restores the prior closing hint and the prior ownership fixture; it does not change any user's Git repository. Remove any leftover `/mnt/data/vmtest/1109-config-repo-good` proof copy.
