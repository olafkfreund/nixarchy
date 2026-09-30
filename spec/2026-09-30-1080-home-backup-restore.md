---
status: approved
issue: 1080
intent: intent/2026-09-30-1080-home-backup-restore.md
---

# Spec: Restore home backups safely

## Design

**Owner review decision (supersedes the two-run design below):** Never restore the repository's `backup.list`; keep the local list byte-identical, print repository-only entries, and tell the user to add wanted paths to local `~/.config/omarchy/backup.list` before rerunning.

In `pkgs/omarchy/nix-bin/nixarchy-home-backup:111-119`, `resolved_list` already combines the shipped list with the installed user's local `backup.list`; it never needs to read the repository's copy. Reuse that same include and exclude policy for restore, walking regular files under the backup repository instead of the live home. Snapshot the resulting file list before copying anything, so restoring `backup.list` cannot authorize more files midway through the first run. On a fresh machine its new entries authorize custom files only on a second run. Tell the user to rerun when the list was restored. Reject absolute and `..` paths before a restore can use them.

Replace the unrestricted repository walk at `pkgs/omarchy/nix-bin/nixarchy-home-backup:352`. A repository file outside the local allowlist must never reach the copy loop. Preserve exclusions, including clipboard history, and the current per-file behavior that leaves unrelated home files alone. The ownership gate at `:193` still applies before restore.

At `pkgs/omarchy/nix-bin/nixarchy-home-backup:330-355`, refuse destination symlinks and symlinked directories below `$HOME` before comparing, saving, or copying a file. `--force` only skips saving the previous regular file; it cannot bypass this refusal. Check creation of parent directories, preservation of a differing file, and the restore copy. On any failure, print the affected relative path, exit nonzero, and omit the success message. Increment `kept` and `restored` only after their respective copies succeed. Keep executable-mode preservation and the existing no-directory-swap behavior.

Add a cheap restore regression check under `tests/`, registered in `flake.nix` beside the other package-script checks. It should run the actual restore script with a temporary home, local ownership marker, and local git backup, avoiding network and a VM. Its cases must show: an extra repository file is ignored; shipped exclusions stay excluded; a locally authorized custom file restores while a repository-only custom list needs a second run; destination and parent symlinks do not lead to writes; and failed preservation or restore copies return nonzero without a false success count. Check the rendered user message for the required rerun instruction.

## Alternatives rejected

- Trust the repository's `backup.list` on the first run: a wrong or malicious repository could authorize every extra file it carries.
- Restore every repository file because backup creation already filters: restores can clone a different repository, and existing repositories can gain files outside the current allowlist.
- Replace a destination symlink automatically: the user may have deliberately managed that path elsewhere, so refuse and explain instead.
- Rely on `set -e` for copy failures: restore also runs commands whose failure is handled deliberately; explicit checks give a path-specific error and keep the counters accurate.

## Risks

- Existing backups with custom paths need two restore runs on a fresh machine. The command must explain that after restoring `backup.list`.
- A home that intentionally uses symlinked configuration directories will get a clear refusal for those files and require user action, including under `--force`.
- Restore still trusts file contents in a chosen repository; the allowlist limits destinations, not what those files contain.

## Verification

- Run the cheap restore check and prove it fails against the original unrestricted walk, then passes after the change. With the fixed script saved outside the worktree via `cp`, temporarily reintroduce each relevant bug (unrestricted walk, destination symlink copy, ignored copy failure), confirm the check goes red with its diagnostic, and restore the saved file with `cp`. Record the red output in the eventual PR.
- Run `bash -n` on the script; run the check, formatter, statix, and deadnix. Check `git diff --check` and the final diff. No VM is needed for this behavior.
