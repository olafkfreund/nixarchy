---
status: draft
issue: 1080
spec: spec/2026-09-30-1080-home-backup-restore.md
---

# Plan: Restore home backups safely

The approved design limits restore to the shipped allowlist plus the installed user's local `backup.list`. The repository cannot authorize its own files. Snapshot eligible files before copying: a newly restored `backup.list` takes effect only on a second run, which the command explains. Refuse unsafe relative paths, destination symlinks and symlinked parent directories; `--force` does not bypass that refusal. Preserve existing files before replacing them, preserve executable mode, leave unrelated home files alone, and report any failed copy as an error with accurate counts.

## Steps

1. `pkgs/omarchy/nix-bin/nixarchy-home-backup:111-119,241-261`: let the existing allowlist walker inspect a chosen root while always reading the installed user's local list; reject absolute and `..` entries for restore, preserve prefix exclusions, and snapshot the repository's eligible regular files before writes -> verify by the new restore check's extra-file, excluded-file, and two-run custom-list cases. Traps: a repo-supplied `backup.list` must never broaden the first run; do not turn backup creation into a whole-home walk.
2. `pkgs/omarchy/nix-bin/nixarchy-home-backup:303-358`: replace the unrestricted `find` loop with the snapshot; refuse symlinks at the destination or in parent directories below `$HOME`, even under `--force`; check directory creation, backup copy, and restore copy before incrementing counters; stop nonzero with the relative path on failure and suppress `Done.`; explain a required rerun if `backup.list` was restored -> verify by the new check's symlink, copy-failure, mode, count, and rerun-message cases. Traps: retain the ownership gate, existing files' backup unless `--force`, and per-file copying that never deletes unrelated files.
3. `tests/home-backup-restore.nix`: add a cheap `runCommand` that executes the changed source script in a temporary home with a local ownership marker and a local git repository; cover all step 1 and 2 cases without network or a VM -> verify by `nix build .#checks.x86_64-linux.home-backup-restore --no-link --print-build-logs`. Traps: make assertions on effects and exit codes, with readable failure messages; avoid a `grep -q` pipeline under `pipefail`.
4. `flake.nix:2230-2285`: register `checks.home-backup-restore` beside package-script checks, passing `./pkgs/omarchy/nix-bin/nixarchy-home-backup` to the test -> verify the check attribute builds and `tests/test-registration.nix` sees the new test. Traps: a test file without a `checks` entry is not coverage; stage new files before Nix evaluation.

## Tests

- Before a Nix build, check CI load with `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`; do not build alongside an install job. Do not run VM checks.
- Prove the check fails by copying the fixed script aside to `/mnt/data/vmtest/1080-home-backup.saved`, then separately reintroducing (a) the unrestricted repository walk, (b) symlink-following destination copy, and (c) unchecked restore copy. For each break, inspect `git diff` to prove it landed, run `nix build .#checks.x86_64-linux.home-backup-restore --no-link --print-build-logs`, save the failing output outside the worktree, and restore with `cp /mnt/data/vmtest/1080-home-backup.saved pkgs/omarchy/nix-bin/nixarchy-home-backup` before the next break. Never use `git checkout` to restore a break. Include the red output in the PR; then run the fixed check and show green.
- Run `bash -n pkgs/omarchy/nix-bin/nixarchy-home-backup`, `nix fmt` after editing `.nix`, inspect `git diff --stat`, and require `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, `nix run nixpkgs#deadnix -- --fail .`, and `git diff --check` to pass. Stage new files before flake checks.
- Commit each implementation step with the step number in its subject. If implementation must deviate, update this plan in the same commit. Open a PR against `main` with `Closes #1080`, links to intent/spec/plan, and the red outputs. Do not merge.

## Rollback

Revert the implementation commits on the task branch and rebuild. Existing home files and backup repositories are not migrated or deleted by this change.
