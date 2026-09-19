---
status: draft
issue: 783
spec: spec/2026-09-19-783-plugin-layout-wait.md
---

# Plan: Wait for the default plugin's persisted bar placement

The shell updates its in-memory configuration before its asynchronous disk
write completes. Enabled IPC is therefore insufficient evidence that
`shell.json` contains the new layout. Add a bounded wait on the persisted
condition in `tests/plugin.nix`'s defaults node, immediately before its
existing layout read.

Use the driver's existing `machine.wait_until_succeeds`, a 60-second timeout,
and `${pkgs.jq}/bin/jq -e --arg id` with the existing `tele` value. Read
`/home/omarchy/.config/omarchy/shell.json` and require
`any(.bar.layout.right[]?; .id == $id)`. The `-e` is essential: printing false
without a nonzero exit code would turn the wait into an immediate success.
Missing files, malformed JSON, missing sections and an absent id must remain
unsuccessful until corrected or timed out.

Keep the enabled-IPC wait, Python layout assertion and diagnostic,
enable-once marker assertion, and disable/re-login assertions unchanged.
Include only a short explanatory comment beside the new wait. Reuse jq and
the driver; add no dependencies, checks, workflows or production edits.
Fixed sleeps, memory-only IPC layout checks, and retrying whole VM runs
until green do not establish the required persisted condition.

## Steps

1. Check `git status --short --branch` in `/mnt/data/vmtest/codex-783` and
   review the current defaults-node block. Refresh the base before final
   integration validation if main moved. Preserve Claude's #780/#782
   machine-node setup changes near the earlier `defaultPlugins.pkg` setting;
   the implementation belongs only at the later layout read.
   → Verify the diff stays within the approved scope.
2. Save the original layout-read/assert block outside the repository under
   `/mnt/data/vmtest/`. Prepare a temporary Python-stdlib replay that executes
   that block against a fixture file. Start with enabled IPC already true
   and valid JSON lacking `tele` in the right section. A producer atomically
   publishes correct JSON only after an explicit handshake reports that the
   reader saw the old contents. Release and join it even after an assertion
   raises. → Capture the old assertion failing before changing the test.
3. Add the specified jq wait immediately before the layout read. Replay the
   corrected block and its actual jq command against the same controlled
   write ordering, redirecting the fixture path and resolving the existing
   jq executable without changing its predicate. The temporary adapter may
   shorten the timeout for fixture cases; the committed wait remains 60 s.
   → Capture a failed initial probe followed by success after publication.
4. Replay no-update and wrong-section cases, with the id missing entirely
   or present only in `bar.layout.left`. Assert the jq exit codes are
   nonzero and both waits expire. Assert an already-correct right section
   returns zero and passes immediately. Temporarily remove `-e` from the
   replayed command and prove these exit-code checks fail, then restore it.
   → Capture negative-case failures and the deliberate `-e` break.
5. Run formatting and whitespace checks, review the scoped diff, and commit
   the implementation. Keep temporary replay files outside the repository.
   When CI capacity permits, run the existing plugin integration check from
   the committed worktree. → Require a successful exit and the retained
   marker/disable assertions; a replay alone does not exercise QML.
6. Prepare the PR with `Closes #783`, links to all three artifacts, the
   touched-file scope, and captured old/new/negative verification output.
   Identify the replay as a controlled persisted-file test, not a QML run.
   If main advances, rebase and rerun integration validation before merge.
   → Check the PR describes the tested final head and preserves nearby work.

## Tests

- `python3 /mnt/data/vmtest/codex-783-replay.py`: temporary replay described
  above; expected old assertion failure, corrected delayed-write success,
  missing-id/wrong-section timeouts, immediate correct-layout success, and
  a detected failure when `-e` is removed. Capture output for the PR.
- Before any build, run
  `gh run list --repo olafkfreund/nixarchy --workflow install-check.yml --status in_progress --limit 100 --json databaseId,status`
  and inspect the returned runs' jobs. If the result reaches the limit,
  paginate rather than assuming older runs are idle. Do not infer inactivity
  from the latest few runs across all workflows. Do not start local builds
  or VM tests while CI installs run; report pending verification honestly.
- `nix fmt -- --ci`: formatting passes when build capacity permits.
- `git diff --check`: no whitespace errors.
- `/mnt/data/vmtest/heavy-build.sh /mnt/data/vmtest/codex-783-plugin.log .#checks.x86_64-linux.plugin --print-build-logs`:
  runs the approved `nix build` through the team's shared lock
  `/mnt/data/vmtest/.nixarchy-heavy.lock`. Require exit zero from the committed
  worktree when capacity permits; the lock does not waive the no-active-install
  condition above. Do not pipe away the build's exit status. Include its
  result and retained assertions in the PR.

The added bounded wait is the lasting runnable check. Temporary replay assets
are not committed. Do not discard unrelated failures or retry until green;
diagnose and report them under the repository's existing rules.

## Rollback

Revert the implementation commit to remove only the added wait and its
comment; leave Claude's setup changes intact. This restores the previous
flaky assertion, so reopen or retain #783 if rollback becomes necessary.
No host deployment or runtime configuration rollback is required. Remove
only this task's temporary replay files after saving the verification output.
