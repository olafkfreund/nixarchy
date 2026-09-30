---
status: draft
issue: 1080
author: olafkfreund
---

# Intent: Restore home backups without writing outside the allowlist

## Problem

`nixarchy-home-backup restore` copies every regular file found in the backup repository into the same relative path under the user's home. Backup creation uses an allowlist, but restore does not. A repository cloned from the wrong URL, or one with extra files, can therefore write files the user did not choose to restore, including SSH and autostart files.

The issue's other two claims also hold. `cp -f "$src" "$dest"` follows an existing destination symlink and can write its target. The script runs without `errexit` and increments `restored` even when that copy fails, then reports completion. The existing `tests/options.nix` assertions check `--list` and the ownership gate, not restore behavior.

## Proposed outcome

Restore writes only files authorized by the restore allowlist and cannot write through a destination symlink. If a file cannot be saved or copied, the command reports the failure, exits unsuccessfully, and does not count that file as restored. Its summary reflects what actually happened.

## Affected users and systems

Users restoring a desktop backup on a new or existing nixarchy installation. The affected command is `pkgs/omarchy/nix-bin/nixarchy-home-backup`; the risk is confined to files reachable from the user's home during restore, including paths outside home if a destination symlink points there.

## Constraints

- Keep backup creation's user-extensible allowlist and the existing ownership gate.
- Preserve the current behavior of saving a user's differing file before overwriting it unless `--force` is set. A failed save must not be treated as permission to overwrite.
- Do not delete other home files to make a restore fit.
- Verify the safety properties with a check that fails when each regression is reintroduced.

## Open questions

- On a fresh installation, should the restore allowlist come only from the installed machine's shipped list and local `backup.list`, so custom entries require restoring that list and rerunning, or may the repository's `backup.list` authorize its other files on the first run? The latter would let a wrong repository expand the restore scope.
